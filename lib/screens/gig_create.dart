import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../flyer_styles.dart';
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

/// A live poster dock followed by the draft's editing checklist.
class GigCreateScreen extends StatefulWidget {
  const GigCreateScreen({super.key});

  @override
  State<GigCreateScreen> createState() => _GigCreateScreenState();
}

class _GigCreateScreenState extends State<GigCreateScreen> {
  final _name = TextEditingController();
  final _nameFocus = FocusNode();

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
    if (app.gfPublished) return const GigPublishedView();
    if (app.gfPreviewing) return const GigDraftPreview();

    final venue = app.gfVenueId == null ? null : app.venue(app.gfVenueId!);
    final nameDone = app.gfName.trim().isNotEmpty;
    final dateDone = app.gfDate != null;
    final venueDone = venue != null;
    final coverDone =
        app.gfTix != Ticketing.paid || app.gfTicketPriceMinor != null;
    final accessDone =
        app.gfTix != Ticketing.external || app.validExternalTicketUrl;
    final lineupDone = app.gfPerformers.isNotEmpty;
    // Times and audience always have usable defaults. Notes are optional.
    final readiness = [
      nameDone,
      dateDone,
      true,
      venueDone,
      coverDone,
      accessDone,
      true,
      lineupDone,
    ];
    final done = readiness.where((complete) => complete).length;
    final editingPublished =
        app.gfProject?.status == GigProjectStatus.published;
    final missing = app.gigMissing.join(' + ');

    return Stack(
      children: [
        Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.epColors.line),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  EpLayout.gutter,
                  headerTopPad(context),
                  EpLayout.gutter,
                  16,
                ),
                child: Row(
                  children: [
                    EpIconPill(
                      icon: Icons.close,
                      semanticLabel: 'Close',
                      onPressed: app.closeGigCreate,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          EpDisplay(
                            editingPublished ? 'Edit gig' : 'Gig draft',
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          Semantics(
                            liveRegion: true,
                            child: EpEyebrow(
                              '${app.gfSaveState} · $done of ${readiness.length} done',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: app.previewGigDraft,
                      child: const EpMonoText('Preview'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  EpLayout.gutter,
                  20,
                  EpLayout.gutter,
                  actionBarClearance(context) + 80,
                ),
                children: [
                  const _PosterDock(),
                  const SizedBox(height: 20),
                  _SlotRow(
                    label: 'Name',
                    done: nameDone,
                    required: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (nameDone && !_nameFocus.hasFocus) ...[
                          EpDisplay(app.gfName, size: 24),
                          const SizedBox(height: 8),
                        ],
                        EpUnderlineField(
                          fieldKey: const Key('gig-name-field'),
                          controller: _name,
                          focusNode: _nameFocus,
                          hint: 'Name your gig',
                          onChanged: app.setGfName,
                        ),
                      ],
                    ),
                  ),
                  _SlotRow(
                    key: const ValueKey('gig-slot-date'),
                    label: 'Date',
                    done: dateDone,
                    required: true,
                    value: dateDone ? app.gfDateLabel : 'Choose a date',
                    onTap: () => showWhenSheet(context),
                  ),
                  _SlotRow(
                    key: const ValueKey('gig-slot-times'),
                    label: 'Times',
                    done: true,
                    value:
                        'Doors ${app.gfDoorsLabel} · Start ${app.gfStartLabel}',
                    semanticHint:
                        'A start earlier than doors is treated as after midnight',
                    onTap: () => showWhenSheet(context),
                  ),
                  _SlotRow(
                    key: const ValueKey('gig-slot-venue'),
                    label: 'Venue',
                    done: venueDone,
                    required: true,
                    value: venue?.name ?? 'Choose a venue',
                    sub: venue?.area,
                    onTap: () => showVenueSheet(context),
                  ),
                  _SlotRow(
                    key: const ValueKey('gig-slot-cover'),
                    label: 'Cover',
                    done: coverDone,
                    required: true,
                    value: app.gfTix == Ticketing.paid
                        ? 'Tickets · ${app.gfTicketPriceMinor == null ? 'Set a price' : Money(app.gfTicketPriceMinor!).label}'
                        : app.gfPrice == 'FREE'
                        ? 'Free'
                        : app.gfPrice,
                    sub: app.gfTix == Ticketing.paid
                        ? 'In-app checkout'
                        : app.gfPrice == 'FREE'
                        ? null
                        : 'At the door',
                    onTap: () => app.gfTix == Ticketing.paid
                        ? showTicketsSheet(context)
                        : showPriceSheet(context),
                  ),
                  _SlotRow(
                    key: const ValueKey('gig-slot-access'),
                    label: 'Access',
                    done: accessDone,
                    required: true,
                    value: switch (app.gfTix) {
                      Ticketing.rsvp =>
                        'In-app RSVP · ${app.gfCap == 'No cap' ? 'No cap' : 'RSVP cap ${app.gfCap}'}',
                      Ticketing.external => 'External link',
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
                    key: const ValueKey('gig-slot-audience'),
                    label: 'Audience',
                    done: true,
                    value: app.gfAgeRequirement.label,
                    semanticHint: 'Age requirement',
                    onTap: () => showAgeSheet(context),
                  ),
                  _SlotRow(
                    label: 'Lineup · ${app.gfPerformers.length}',
                    done: lineupDone,
                    required: true,
                    child: const _LineupField(),
                  ),
                  _SlotRow(
                    label: 'Notes for fans · optional',
                    done: app.gfDesc.trim().isNotEmpty,
                    value: app.gfDesc.trim().isEmpty
                        ? 'Accessibility, set times, parking'
                        : app.gfDesc,
                    onTap: () => showEpSheet(
                      context,
                      (_) => const EpFormSheet(
                        title: 'Notes for fans',
                        child: _AdditionalInfoField(),
                      ),
                    ),
                  ),
                  const EpHairline(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: app.saveGigDraft,
                      child: const EpMonoText('Save draft'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(
            // An opaque surface under the shared CTA removes its fading edge.
            decoration: BoxDecoration(
              color: context.epColors.background,
              border: Border(top: BorderSide(color: context.epColors.line)),
            ),
            child: Semantics(
              liveRegion: true,
              child: EpBottomCta(
                hint: missing.isEmpty
                    ? 'Ready. Fans nearby see it as soon as you publish.'
                    : 'Still needs $missing',
                child: EpPill(
                  label: editingPublished ? 'Publish updates' : 'Publish gig',
                  variant: EpPillVariant.primary,
                  size: EpPillSize.large,
                  expand: true,
                  onPressed: app.canPublishGig ? app.publishGig : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Checklist rows can contain an inline field or the complete lineup editor.
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    super.key,
    required this.label,
    required this.done,
    this.required = false,
    this.value,
    this.sub,
    this.semanticHint,
    this.child,
    this.onTap,
  });

  final String label;
  final bool done;
  final bool required;
  final String? value;
  final String? sub;
  final String? semanticHint;
  final Widget? child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    return Semantics(
      button: onTap != null,
      hint: semanticHint,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const EpHairline(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: done
                        ? Icon(Icons.check, size: 16, color: palette.accent)
                        : Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: required
                                    ? palette.accent
                                    : palette.outline,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        EpEyebrow(
                          required && !done ? '$label · required' : label,
                          color: required && !done
                              ? palette.accent
                              : palette.muted,
                        ),
                        const SizedBox(height: 4),
                        if (child != null)
                          child!
                        else
                          Text(
                            value!,
                            style: Theme.of(context).textTheme.epBody.copyWith(
                              color: done ? palette.ink : palette.muted,
                            ),
                          ),
                        if (sub != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            sub!,
                            style: Theme.of(
                              context,
                            ).textTheme.epBody.copyWith(color: palette.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.chevron_right, size: 16, color: palette.muted),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterDock extends StatelessWidget {
  const _PosterDock();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final hasArt = app.gfFlyerArt != null || app.gfFlyerUrl != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DraftPoster(),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EpEyebrow('Poster'),
              const SizedBox(height: 8),
              Text(
                'Previews live as you fill the list. Pick a press or upload your own art.',
                style: Theme.of(
                  context,
                ).textTheme.epBody.copyWith(color: context.epColors.muted),
              ),
              const SizedBox(height: 12),
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
                  onPressed: () => _pickGigFlyerArt(context),
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

/// Compose the small footer locally: EpPoster has no footer size/color options.
/// Persisted artwork keeps the app's URL resolution, caching and error fallback.
class _DraftPoster extends StatelessWidget {
  const _DraftPoster();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final palette = context.epColors;
    final style = app.flyer(app.gfFly);
    final venue = app.gfVenueId == null ? null : app.venue(app.gfVenueId!);
    final footer = [
      app.gfDate == null
          ? '+ Date & doors'
          : '${app.gfDateLabel} · Doors ${app.gfDoorsLabel}',
      venue == null ? '+ Venue' : '${venue.name} · ${venue.area}',
      app.gfTix == Ticketing.paid
          ? 'Tickets · ${app.gfTicketPriceMinor == null ? 'Set a price' : Money(app.gfTicketPriceMinor!).label}'
          : app.gfPrice == 'FREE'
          ? 'Free'
          : '${app.gfPrice} at the door',
    ].join('\n');
    final scaler = MediaQuery.textScalerOf(context);
    final footerPainter = TextPainter(
      text: TextSpan(
        text: footer,
        style: Theme.of(context).textTheme.epChipLabel.copyWith(fontSize: 8),
      ),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout(maxWidth: 100);
    final footerHeight = footerPainter.height;
    footerPainter.dispose();
    // Keep the nominal 120 × 158 thumbnail, growing for long details/large text.
    final height = (footerHeight + scaler.scale(70) + 28).clamp(
      158.0,
      double.infinity,
    );
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
    return SizedBox(
      width: 120,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (app.gfCustomFlyer) ...[
            if (art != null)
              Image.memory(
                art.bytes,
                fit: BoxFit.cover,
                cacheWidth: (120 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
              )
            else
              EpNetworkImage(
                url: app.gfFlyerUrl,
                cacheWidth: 120,
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
          if (showDetails) ...[
            EpPoster(
              title: app.gfName.trim().isEmpty ? 'Your gig name' : app.gfName,
              height: height,
              titleSize: 18,
              padding: EdgeInsets.fromLTRB(10, 10, 10, footerHeight + 18),
              style: app.gfCustomFlyer
                  ? FlyerStyle(
                      base: Colors.transparent,
                      patternColor: Colors.transparent,
                      fg: palette.ink,
                    )
                  : style,
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: EpMonoText(
                footer,
                size: 8,
                color: app.gfCustomFlyer ? palette.ink : style.fg,
              ),
            ),
          ],
          if (app.gfFlyerUploading)
            const Align(
              alignment: Alignment.bottomCenter,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
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
            'Add at least one performer.',
            style: Theme.of(
              context,
            ).textTheme.epBody.copyWith(color: context.epColors.muted),
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
              return Column(
                key: ValueKey(performer.id),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    performer.name,
                    style: Theme.of(context).textTheme.epBody,
                  ),
                  const SizedBox(height: 4),
                  EpMonoText(
                    switch (performer.kind) {
                      GigPerformerKind.band => 'EarPlug band',
                      GigPerformerKind.invited => 'Invite pending',
                      GigPerformerKind.text => 'Text-only performer',
                    },
                    color: context.epColors.muted,
                    keepCase: performer.kind == GigPerformerKind.band,
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: Semantics(
                          label: 'Reorder performer',
                          child: SizedBox.square(
                            dimension: 48,
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
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: EpBadge(
                              key: ValueKey(
                                'gig-performer-role-pill-${performer.id}',
                              ),
                              label: performer.role.name,
                            ),
                          ),
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
                        icon: Icons.close,
                        semanticLabel: 'Remove performer',
                        onPressed: () => app.removeGigPerformer(performer.id),
                      ),
                    ],
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
        Divider(),
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
