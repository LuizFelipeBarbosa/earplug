import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../date_names.dart';
import '../flyer_styles.dart';
import '../initials.dart';
import '../models.dart';
import '../money.dart';
import '../services/flyer_text_extractor.dart';
import '../services/media_picker.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/ep_text.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';
import 'gig_create_preview.dart';
import 'gig_create_sheets.dart';

Future<void> _pickGigFlyerArt(BuildContext context) async {
  final app = context.read<AppState>();
  final media = context.read<BandMediaController>();
  final PickedMedia? picked;
  try {
    picked = await media.pickFlyerArt();
  } on MediaPickException catch (error) {
    if (!context.mounted) return;
    app.say(error.message);
    return;
  }
  if (!context.mounted || picked == null) return;

  final extractionFuture = _extractFlyerProposal(app, picked);
  app.setGfFlyerArt(picked);
  app.setGfFlyerUploading(true);
  final storageId = await media.uploadFlyerArt(app.bandId, picked);
  if (identical(app.gfFlyerArt, picked)) {
    app.setGfFlyerStorageId(storageId);
  }
  app.setGfFlyerUploading(false);

  final proposal = await extractionFuture;
  if (!context.mounted || proposal == null) return;
  if (!proposal.hasSuggestions) {
    app.say('Flyer added. Add any details the artwork did not make clear.');
    return;
  }
  unawaited(
    showEpSheet(
      context,
      (_) => EpFormSheet(
        title: 'Review flyer details',
        child: _FlyerReviewBody(proposal: proposal),
      ),
    ),
  );
}

Future<FlyerEntryProposal?> _extractFlyerProposal(
  AppState app,
  PickedMedia picked,
) async {
  const extractor = FlyerTextExtractor();
  if (!extractor.isSupported) return null;
  try {
    final extraction = await extractor.extract(picked.bytes);
    if (extraction == null || extraction.lines.isEmpty) return null;
    final bands = await app.repository.searchBands('');
    return const FlyerEntryParser().parse(
      extraction,
      venues: app.venues,
      bands: bands,
    );
  } on PlatformException catch (error) {
    debugPrint('Flyer OCR failed: ${error.code}: ${error.message}');
    return null;
  }
}

/// A flyer-first editor with autosaved fields and a separate fan preview.
class GigCreateScreen extends StatefulWidget {
  const GigCreateScreen({super.key});

  @override
  State<GigCreateScreen> createState() => _GigCreateScreenState();
}

class _GigCreateScreenState extends State<GigCreateScreen> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  bool? _detailsExpanded;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final name = context.read<AppState>().gfName;
    if (_nameFocus.hasFocus || _name.text == name) return;
    _name.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.gfPublished) {
      _detailsExpanded = null;
      return const GigPublishedView();
    }
    if (app.gfPreviewing) return const GigDraftPreview();

    final palette = context.epColors;
    final venue = app.gfVenueId == null ? null : app.venue(app.gfVenueId!);
    final date = app.gfDate;
    final editingPublished =
        app.gfProject?.status == GigProjectStatus.published;
    final detailsExpanded = _detailsExpanded ?? editingPublished;

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.fromLTRB(
            EpLayout.gutter,
            headerTopPad(context) + 44 + 16,
            EpLayout.gutter,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          children: [
            AspectRatio(
              key: const Key('gig-flyer'),
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const _DraftPoster(),
                  Positioned.fill(
                    child: Semantics(
                      button: true,
                      label: 'Edit flyer',
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(onTap: () => showGigFlyerSheet(context)),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: EpIconPill(
                      key: const Key('gig-flyer-edit'),
                      icon: Icons.edit,
                      semanticLabel: 'Edit flyer',
                      filled: true,
                      onPressed: () => showGigFlyerSheet(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('gig-name-field'),
              controller: _name,
              focusNode: _nameFocus,
              textCapitalization: TextCapitalization.words,
              style: Theme.of(context).textTheme
                  .epDisplayAt(32)
                  .copyWith(color: palette.contentPrimary),
              decoration: InputDecoration(
                hintText: 'Name your gig',
                hintStyle: Theme.of(context).textTheme
                    .epDisplayAt(32)
                    .copyWith(color: palette.contentSecondary),
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                enabledBorder: UnderlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: palette.ink),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: palette.accent, width: 1.5),
                ),
              ),
              onChanged: app.setGfName,
            ),
            const SizedBox(height: 16),
            _SlotRow(
              key: const Key('gig-slot-when'),
              placeholder: 'Pick a date and time',
              value: date == null
                  ? null
                  : '${weekdayNames[date.weekday - 1]}, ${shortDateLabel(date)}',
              display: true,
              sub: date == null
                  ? null
                  : 'Doors ${app.gfDoorsLabel} · Start ${app.gfStartLabel}',
              onTap: () => showGigWhenSheet(context),
            ),
            _SlotRow(
              key: const Key('gig-slot-venue'),
              placeholder: 'Choose a venue',
              value: venue?.name,
              sub: venue?.area,
              onTap: () => showVenueSheet(context),
            ),
            _SlotRow(
              key: const Key('gig-details-toggle'),
              value: 'More details',
              sub: 'Cover · Access · Audience · Lineup · Notes',
              trailingIcon: detailsExpanded
                  ? Icons.expand_less
                  : Icons.expand_more,
              expanded: detailsExpanded,
              onTap: () => setState(() => _detailsExpanded = !detailsExpanded),
            ),
            if (detailsExpanded)
              Column(
                key: const Key('gig-details-body'),
                children: [
                  _SlotRow(
                    key: const Key('gig-slot-cover'),
                    placeholder: 'Set the cover charge',
                    value: app.gfTix == Ticketing.paid
                        ? app.gfTicketPriceMinor == null
                              ? null
                              : 'Tickets · ${Money(app.gfTicketPriceMinor!).label}'
                        : app.gfPrice.isEmpty
                        ? null
                        : app.gfPrice == 'FREE'
                        ? 'Free'
                        : app.gfPrice,
                    sub: app.gfTix == Ticketing.paid
                        ? 'In-app checkout'
                        : app.gfPrice.isEmpty || app.gfPrice == 'FREE'
                        ? null
                        : 'At the door',
                    onTap: () => app.gfTix == Ticketing.paid
                        ? showTicketsSheet(context)
                        : showPriceSheet(context),
                  ),
                  _SlotRow(
                    key: const Key('gig-slot-access'),
                    placeholder: 'Tickets and age access',
                    value: switch (app.gfTix) {
                      Ticketing.rsvp =>
                        'In-app RSVP · ${app.gfCap == 'No cap' ? 'No cap' : 'RSVP cap ${app.gfCap}'}',
                      Ticketing.external =>
                        app.validExternalTicketUrl ? 'External link' : null,
                      Ticketing.paid => 'Paid tickets',
                    },
                    sub: switch (app.gfTix) {
                      Ticketing.rsvp => null,
                      Ticketing.external =>
                        app.gfExt.isEmpty ? 'Add ticket URL' : app.gfExt,
                      Ticketing.paid => 'In-app checkout',
                    },
                    onTap: () => showTicketsSheet(context),
                  ),
                  _SlotRow(
                    key: const Key('gig-slot-audience'),
                    placeholder: 'Who is this for',
                    value: app.gfAgeRequirement.label,
                    semanticHint: 'Age requirement',
                    onTap: () => showAgeSheet(context),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: EpCard(
                      key: Key('gig-slot-lineup'),
                      padding: EdgeInsets.all(16),
                      child: _LineupField(),
                    ),
                  ),
                  _SlotRow(
                    key: const Key('gig-slot-notes'),
                    placeholder: 'Notes for fans',
                    value: app.gfDesc.trim().isEmpty ? null : app.gfDesc,
                    onTap: () => showEpSheet(
                      context,
                      (_) => const EpFormSheet(
                        title: 'Notes for fans',
                        child: _AdditionalInfoField(),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        Positioned(
          top: headerTopPad(context),
          left: EpLayout.gutter,
          right: EpLayout.gutter,
          child: Row(
            children: [
              EpIconPill(
                key: const Key('gig-close'),
                icon: Icons.close,
                semanticLabel: 'Close',
                filled: true,
                onPressed: app.closeGigCreate,
              ),
              Expanded(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.background.withValues(alpha: .72),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Semantics(
                        liveRegion: true,
                        child: EpMonoText(
                          app.gfSaveState,
                          key: const Key('gig-save-state'),
                          color: palette.contentSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: EpPill(
                  key: const Key('gig-save'),
                  label: 'Save',
                  variant: EpPillVariant.primary,
                  onPressed: () async {
                    await app.saveGigDraft();
                    if (context.mounted) app.previewGigDraft();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Label-free picker cards show either their current value or an invitation.
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    super.key,
    this.placeholder = '',
    this.value,
    this.sub,
    this.display = false,
    this.semanticHint,
    this.trailingIcon = Icons.chevron_right,
    this.expanded,
    required this.onTap,
  });

  final String placeholder;
  final String? value;
  final String? sub;
  final bool display;
  final String? semanticHint;
  final IconData trailingIcon;
  final bool? expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        hint: semanticHint,
        expanded: expanded,
        child: EpCard(
          padding: const EdgeInsets.all(16),
          onTap: onTap,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (display && value != null)
                      EpDisplay(value!, size: 24)
                    else
                      Text(
                        value ?? placeholder,
                        style: Theme.of(context).textTheme.epBody.copyWith(
                          color: value == null
                              ? palette.accent
                              : palette.contentPrimary,
                        ),
                      ),
                    if (sub != null) ...[
                      const SizedBox(height: 4),
                      EpMonoText(sub!, color: palette.contentSecondary),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(trailingIcon, size: 16, color: palette.contentSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showGigFlyerSheet(BuildContext context) => showEpSheet(
  context,
  (_) => EpFormSheet(
    title: 'FLYER',
    child: _GigFlyerBody(onPickArt: () => _pickGigFlyerArt(context)),
  ),
);

class _GigFlyerBody extends StatelessWidget {
  const _GigFlyerBody({required this.onPickArt});

  final VoidCallback onPickArt;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final hasArt = app.gfFlyerArt != null || app.gfFlyerUrl != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(
          width: 120,
          height: 158,
          child: _DraftPoster(compact: true),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                children: [
                  for (final key in flyerPicks)
                    Swatch(
                      key: ValueKey('press-$key'),
                      selected: app.gfFly == key,
                      semanticLabel: 'Color swatch · $key',
                      onTap: () => app.setGfFly(key),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: flyerStyles[key]!.base,
                          border: Border.all(color: context.epColors.outline),
                        ),
                      ),
                    ),
                  Swatch(
                    key: const ValueKey('press-custom'),
                    selected: app.gfCustomFlyer,
                    dashed: true,
                    semanticLabel: 'Color swatch · Custom flyer',
                    onTap: () => app.setGfFly('custom'),
                    child: const SizedBox.shrink(),
                  ),
                ],
              ),
              if (app.gfCustomFlyer) ...[
                TextButton(
                  onPressed: onPickArt,
                  child: EpMonoText(hasArt ? 'Change art' : 'Add flyer art'),
                ),
                if (hasArt)
                  TextButton(
                    key: const ValueKey('clear-flyer-art'),
                    onPressed: () => app.setGfFlyerArt(null),
                    child: const EpMonoText('Remove art'),
                  ),
                Semantics(
                  toggled: app.gfShowOverlay,
                  label: 'Text overlay',
                  child: TextButton(
                    onPressed: app.toggleGfOverlay,
                    child: EpMonoText(
                      'Text overlay · ${app.gfShowOverlay ? 'on' : 'off'}',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Shared artwork rendering for the square flyer and its sheet preview.
/// Persisted artwork keeps the app's URL resolution, caching and error fallback.
class _DraftPoster extends StatelessWidget {
  const _DraftPoster({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final palette = context.epColors;
    final style = app.flyer(app.gfFly);
    final showDetails = !app.gfCustomFlyer || app.gfShowOverlay;
    final art = app.gfFlyerArt;
    final placeholder = Semantics(
      label: 'CUSTOM FLYER PREVIEW',
      child: EpPanel(
        color: palette.panel,
        child: Center(
          child: Icon(
            Icons.add_photo_alternate_outlined,
            size: 16,
            color: palette.muted,
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (app.gfCustomFlyer) ...[
              if (art != null)
                Image.memory(
                  art.bytes,
                  fit: BoxFit.cover,
                  cacheWidth:
                      (constraints.maxWidth *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                )
              else
                EpNetworkImage(
                  url: app.gfFlyerUrl,
                  cacheWidth: constraints.maxWidth.round(),
                  fit: BoxFit.cover,
                  fallback: placeholder,
                ),
              if (showDetails)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        palette.background.withValues(alpha: .25),
                        palette.background.withValues(alpha: .85),
                      ],
                    ),
                  ),
                ),
            ],
            if (showDetails)
              EpPoster(
                title: app.gfName.trim().isEmpty ? 'Your gig name' : app.gfName,
                height: constraints.maxHeight,
                titleSize: compact ? 16 : 32,
                padding: EdgeInsets.all(compact ? 10 : 20),
                style: app.gfCustomFlyer
                    ? FlyerStyle(
                        base: palette.background.withValues(alpha: 0),
                        patternColor: palette.background.withValues(alpha: 0),
                        fg: palette.ink,
                      )
                    : style,
              ),
            if (app.gfFlyerUploading)
              const Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _LineupField extends StatelessWidget {
  const _LineupField();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final performers = app.gfPerformers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (performers.isEmpty)
          Text(
            'Add performers',
            style: Theme.of(
              context,
            ).textTheme.epBody.copyWith(color: context.epColors.accent),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: performers.length,
            onReorderItem: app.moveGigPerformer,
            itemBuilder: (context, index) {
              final performer = performers[index];
              final band = performer.bandId == null
                  ? null
                  : app.band(performer.bandId!);
              return Column(
                key: ValueKey(performer.id),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (index > 0) const EpHairline(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: Semantics(
                            label: 'Reorder performer',
                            child: SizedBox(
                              width: 20,
                              height: 48,
                              child: Icon(
                                Icons.drag_handle,
                                size: 16,
                                color: context.epColors.muted,
                              ),
                            ),
                          ),
                        ),
                        PopupMenuButton<GigPerformerRole>(
                          key: ValueKey(
                            'gig-performer-role-target-${performer.id}',
                          ),
                          tooltip: 'Billing role',
                          initialValue: performer.role,
                          onSelected: (role) =>
                              app.setGigPerformerRole(performer.id, role),
                          itemBuilder: (_) => [
                            for (final role in GigPerformerRole.values)
                              PopupMenuItem(
                                value: role,
                                child: EpMonoText(role.name),
                              ),
                          ],
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: 48,
                              minWidth: 48,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: EpPill(
                                key: ValueKey(
                                  'gig-performer-role-pill-${performer.id}',
                                ),
                                label: performer.role.name,
                                onPressed: null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (band != null)
                          BandAvatar(
                            band,
                            key: ValueKey(
                              'gig-performer-avatar-${performer.id}',
                            ),
                            size: 36,
                          )
                        else
                          EpAvatarTile(
                            key: ValueKey(
                              'gig-performer-avatar-${performer.id}',
                            ),
                            initials: initialsFirstLast(performer.name),
                            size: 36,
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            performer.name,
                            style: Theme.of(context).textTheme.epBody,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (performer.inviteUrl != null)
                          EpIconPill(
                            icon: Icons.link,
                            semanticLabel: 'Copy invite link',
                            onPressed: () => copyForUser(
                              context,
                              performer.inviteUrl!,
                              successMessage: 'Invite link copied.',
                            ),
                          ),
                        EpIconPill(
                          key: ValueKey('gig-performer-remove-${performer.id}'),
                          icon: Icons.close,
                          semanticLabel: 'Remove ${performer.name}',
                          onPressed: () => app.removeGigPerformer(performer.id),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => showEpSheet(
              context,
              (_) => const EpFormSheet(
                title: 'Add performer',
                child: _AddPerformerBody(),
              ),
            ),
            child: const EpMonoText('+ Add band or performer'),
          ),
        ),
      ],
    );
  }
}

class _AddPerformerBody extends StatefulWidget {
  const _AddPerformerBody();

  @override
  State<_AddPerformerBody> createState() => _AddPerformerBodyState();
}

class _AddPerformerBodyState extends State<_AddPerformerBody> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  late Future<List<Band>> _results;

  @override
  void initState() {
    super.initState();
    _results = context.read<AppState>().repository.searchBands('');
  }

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  void _runSearch(String value) {
    setState(() {
      _results = context.read<AppState>().repository.searchBands(value.trim());
    });
  }

  Future<void> _addNamed({required bool invite}) async {
    if (_name.text.trim().isEmpty) return;
    await context.read<AppState>().addNamedGigPerformer(
      _name.text,
      invite: invite,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _search,
          onChanged: _runSearch,
          decoration: epInputDecoration(context, 'Search EarPlug bands'),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 170,
          child: FutureBuilder<List<Band>>(
            future: _results,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                children: [
                  for (final band in snapshot.data!)
                    ListTile(
                      title: Text(band.name),
                      subtitle: Text(band.area),
                      trailing: Icon(Icons.add),
                      onTap: () async {
                        await app.addExistingGigPerformer(band.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                ],
              );
            },
          ),
        ),
        const EpHairline(),
        EpLabeledField(
          controller: _name,
          label: 'PERFORMER NAME',
          hint: 'Unlisted band or performer name',
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: EpLayout.fieldGap),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _addNamed(invite: false),
                child: Text('ADD TEXT ONLY'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () => _addNamed(invite: true),
                child: Text('CREATE INVITE'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AdditionalInfoField extends StatefulWidget {
  const _AdditionalInfoField();

  @override
  State<_AdditionalInfoField> createState() => _AdditionalInfoFieldState();
}

class _AdditionalInfoFieldState extends State<_AdditionalInfoField> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: context.read<AppState>().gfDesc);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final description = context.read<AppState>().gfDesc;
    if (_focusNode.hasFocus || _controller.text == description) return;
    _controller.value = TextEditingValue(
      text: description,
      selection: TextSelection.collapsed(offset: description.length),
    );
  }

  @override
  Widget build(BuildContext context) => EpLabeledField(
    controller: _controller,
    focusNode: _focusNode,
    minLines: 4,
    maxLines: 7,
    onChanged: context.read<AppState>().setGfDescription,
    label: 'NOTES FOR FANS',
    hint: 'Accessibility, set times, parking, or anything fans should know',
    textCapitalization: TextCapitalization.sentences,
  );
}

class _FlyerReviewBody extends StatefulWidget {
  const _FlyerReviewBody({required this.proposal});

  final FlyerEntryProposal proposal;

  @override
  State<_FlyerReviewBody> createState() => _FlyerReviewBodyState();
}

class _FlyerReviewBodyState extends State<_FlyerReviewBody> {
  late bool _title = widget.proposal.title != null;
  late bool _date = widget.proposal.date != null;
  late bool _doors = widget.proposal.doors != null;
  late bool _start = widget.proposal.start != null;
  late bool _venue = widget.proposal.venueId != null;
  late bool _price = widget.proposal.price != null;
  late final Set<String> _bands = {
    for (final band in widget.proposal.bands) band.id,
  };
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final proposal = widget.proposal;
    final choices = <Widget>[
      if (proposal.title != null)
        _ReviewChoice(
          label: 'Gig name',
          value: proposal.title!,
          selected: _title,
          onChanged: (value) => setState(() => _title = value),
        ),
      if (proposal.date != null)
        _ReviewChoice(
          label: 'Date',
          value: dateLabel(proposal.date!),
          selected: _date,
          onChanged: (value) => setState(() => _date = value),
        ),
      if (proposal.doors != null)
        _ReviewChoice(
          label: 'Doors',
          value: _proposalTime(proposal.doors!),
          selected: _doors,
          onChanged: (value) => setState(() => _doors = value),
        ),
      if (proposal.start != null)
        _ReviewChoice(
          label: 'Start',
          value: _proposalTime(proposal.start!),
          selected: _start,
          onChanged: (value) => setState(() => _start = value),
        ),
      if (proposal.venueId != null)
        _ReviewChoice(
          label: 'Venue',
          value: proposal.venueName!,
          selected: _venue,
          onChanged: (value) => setState(() => _venue = value),
        ),
      if (proposal.price != null)
        _ReviewChoice(
          label: 'Price',
          value: proposal.price == 0 ? 'FREE' : '\$${proposal.price}',
          selected: _price,
          onChanged: (value) => setState(() => _price = value),
        ),
      for (final band in proposal.bands)
        _ReviewChoice(
          label: 'Performer',
          value: band.name,
          selected: _bands.contains(band.id),
          onChanged: (value) => setState(() {
            if (value) {
              _bands.add(band.id);
            } else {
              _bands.remove(band.id);
            }
          }),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Flyer text can be stylized or incomplete. Check each suggestion before adding it to the draft.',
          style: epText(
            size: 11,
            color: context.epColors.contentSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .48,
          ),
          child: SingleChildScrollView(
            child: Column(
              children: [
                ...choices,
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('VIEW EXTRACTED TEXT'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        proposal.rawText,
                        style: epText(
                          size: 11,
                          color: context.epColors.contentSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _applying ? null : _apply,
          child: Text(_applying ? 'ADDING…' : 'ADD SELECTED TO DRAFT'),
        ),
      ],
    );
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    final source = widget.proposal;
    await context.read<AppState>().applyFlyerProposal(
      FlyerEntryProposal(
        rawText: source.rawText,
        title: _title ? source.title : null,
        date: _date ? source.date : null,
        doors: _doors ? source.doors : null,
        start: _start ? source.start : null,
        venueId: _venue ? source.venueId : null,
        venueName: _venue ? source.venueName : null,
        price: _price ? source.price : null,
        bands: [
          for (final band in source.bands)
            if (_bands.contains(band.id)) band,
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  String _proposalTime(FlyerClockTime value) =>
      timeLabel(TimeOfDay(hour: value.hour, minute: value.minute));
}

class _ReviewChoice extends StatelessWidget {
  const _ReviewChoice({
    required this.label,
    required this.value,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final String value;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    value: selected,
    onChanged: (value) => onChanged(value ?? false),
    title: Text(value, style: epText(size: 12.5, weight: FontWeight.w800)),
    subtitle: Text(label.toUpperCase(), style: epText(size: 11)),
    controlAffinity: ListTileControlAffinity.leading,
  );
}
