import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../flyer_styles.dart';
import '../models.dart';
import '../services/flyer_text_extractor.dart';
import '../services/media_picker.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';
import '../widgets/slot_card.dart';
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

/// Gig creation with an upright decorative poster preview and standard fields.
class GigCreateScreen extends StatefulWidget {
  const GigCreateScreen({super.key});

  @override
  State<GigCreateScreen> createState() => _GigCreateScreenState();
}

class _GigCreateScreenState extends State<GigCreateScreen> {
  final _cardName = TextEditingController();
  final _cardFocus = FocusNode();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final name = context.read<AppState>().gfName;
    if (_cardFocus.hasFocus || _cardName.text == name) return;
    _cardName.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
  }

  @override
  void dispose() {
    _cardName.dispose();
    _cardFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.gfPublished) {
      return const GigPublishedView(poster: _Poster(width: 212, height: 280));
    }
    if (app.gfPreviewing) return const GigDraftPreview();

    return Stack(
      children: [
        Column(
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.epColors.border),
                ),
              ),
              child: Row(
                children: [
                  CircleIconButton(
                    icon: Icons.close,
                    onTap: app.closeGigCreate,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.gfProject?.status == GigProjectStatus.published
                              ? 'EDIT GIG'
                              : 'GIG DRAFT',
                          style: epDisplay(size: 16),
                        ),
                        Text(
                          app.gfSaveState,
                          style: epText(
                            size: 11,
                            weight: FontWeight.w800,
                            letterSpacing: .8,
                            color: app.gfSaveState == 'SAVE FAILED'
                                ? context.epColors.warning
                                : context.epColors.contentDisabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: app.saveGigDraft,
                    child: Text('SAVE DRAFT'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 170),
                children: [
                  _NameCard(controller: _cardName, focusNode: _cardFocus),
                  const SizedBox(height: 18),
                  const _SlotGrid(),
                  SectionBar(label: 'Lineup', count: app.gfPerformers.length),
                  const _LineupField(),
                  const SectionBar(label: 'Poster'),
                  const _FlyerStudio(),
                  const SectionBar(label: 'Additional information'),
                  const _AdditionalInfoField(),
                ],
              ),
            ),
          ],
        ),
        const Positioned(left: 0, right: 0, bottom: 0, child: _PublishBar()),
      ],
    );
  }
}

// ============================ the flyer ============================

/// The poster plus its press picker — the hero of the screen.
class _FlyerStudio extends StatelessWidget {
  const _FlyerStudio();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      children: [
        const _Poster(),
        const SizedBox(height: 12),
        const _SwatchRow(),
        if (app.gfCustomFlyer) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _pickGigFlyerArt(context),
                icon: Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  app.gfFlyerArt == null && app.gfFlyerUrl == null
                      ? 'ADD FLYER ART'
                      : 'CHANGE ART',
                ),
              ),
              if (app.gfFlyerArt != null || app.gfFlyerUrl != null)
                TextButton.icon(
                  key: const ValueKey('clear-flyer-art'),
                  onPressed: () => app.setGfFlyerArt(null),
                  icon: Icon(Icons.close),
                  label: Text('REMOVE ART'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const _OverlayToggle(),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: 250,
          child: Text(
            app.gfCustomFlyer
                ? (app.gfShowOverlay
                      ? 'Your flyer art previews with listing details on top.'
                      : 'Overlay off. Your art stays clean, and details still appear below.')
                : 'Use the fields below; the poster previews changes live.',
            textAlign: TextAlign.center,
            style: epText(
              size: 11,
              weight: FontWeight.w600,
              letterSpacing: .3,
              color: context.epColors.contentDisabled,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _Poster extends StatelessWidget {
  final double width;
  final double height;

  const _Poster({this.width = 216, this.height = 284});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final fly = app.flyer(app.gfFly);

    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .55),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (app.gfCustomFlyer)
            _CustomArtSlot(base: fly.base)
          else
            FlyerBox(style: fly, radius: 0, shadow: false),
          // Readability overlay for uploaded artwork.
          if (app.gfCustomFlyer && app.gfShowOverlay)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: .62),
                      Colors.black.withValues(alpha: .12),
                      Colors.black.withValues(alpha: .15),
                      Colors.black.withValues(alpha: .78),
                    ],
                    stops: const [0, .38, .52, 1],
                  ),
                ),
              ),
            ),
          if (app.gfShowOverlay) _PosterOverlay(ink: fly.fg),
        ],
      ),
    );
  }
}

class _CustomArtSlot extends StatelessWidget {
  final Color base;

  const _CustomArtSlot({required this.base});

  @override
  Widget build(BuildContext context) {
    final flyer = context
        .select<
          AppState,
          ({PickedMedia? art, String? persistedUrl, bool uploading})
        >(
          (app) => (
            art: app.gfFlyerArt,
            persistedUrl: app.gfFlyerUrl,
            uploading: app.gfFlyerUploading,
          ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : null;
        final logicalHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : null;
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

        return ColoredBox(
          color: base,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (flyer.art case final art?)
                Image.memory(
                  art.bytes,
                  fit: BoxFit.cover,
                  cacheWidth: logicalWidth == null
                      ? null
                      : (logicalWidth * devicePixelRatio).round(),
                  cacheHeight: logicalHeight == null
                      ? null
                      : (logicalHeight * devicePixelRatio).round(),
                )
              else if (flyer.persistedUrl case final persistedUrl?)
                EpNetworkImage(
                  url: persistedUrl,
                  fit: BoxFit.cover,
                  fallback: _ArtPlaceholder(base: base),
                  cacheWidth: logicalWidth?.round(),
                  cacheHeight: logicalHeight?.round(),
                )
              else
                _ArtPlaceholder(base: base),
              if (flyer.uploading)
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ArtPlaceholder extends StatelessWidget {
  const _ArtPlaceholder({required this.base});

  final Color base;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: base,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: DashedBox(
          padding: const EdgeInsets.all(12),
          color: context.epColors.border,
          radius: 4,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 22,
                  color: context.epColors.contentDisabled,
                ),
                const SizedBox(height: 6),
                Text(
                  'CUSTOM FLYER PREVIEW',
                  style: epText(
                    size: 11,
                    weight: FontWeight.w900,
                    letterSpacing: .8,
                    color: context.epColors.contentDisabled,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Non-interactive listing details printed on the decorative poster.
class _PosterOverlay extends StatelessWidget {
  final Color ink;

  const _PosterOverlay({required this.ink});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final venue = app.gfVenueId == null ? null : app.venue(app.gfVenueId!);
    final titleStyle = epDisplay(
      size: 23,
      color: ink,
      height: 1.02,
    ).copyWith(letterSpacing: -.3);

    return Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              app.gfName.trim().isEmpty
                  ? 'YOUR GIG NAME'
                  : app.gfName.toUpperCase(),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _PosterLine(
                label: app.gfDate == null
                    ? '+ DATE & DOORS'
                    : '${app.gfDateLabel.toUpperCase()} · DOORS ${app.gfDoorsLabel}',
                unset: app.gfDate == null,
                ink: ink,
              ),
              const SizedBox(height: 7),
              _PosterLine(
                label: venue == null
                    ? '+ VENUE'
                    : '${venue.name.toUpperCase()} · ${venue.area.toUpperCase()}',
                unset: venue == null,
                ink: ink,
              ),
              const SizedBox(height: 7),
              _PosterLine(
                label: app.gfPrice == 'FREE'
                    ? 'FREE'
                    : '${app.gfPrice} AT THE DOOR',
                unset: false,
                ink: ink,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One detail printed on the flyer — dashed and dimmed until it is filled in.
class _PosterLine extends StatelessWidget {
  final String label;
  final bool unset;
  final Color ink;

  const _PosterLine({
    required this.label,
    required this.unset,
    required this.ink,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: epText(
        size: 10.5,
        weight: FontWeight.w800,
        letterSpacing: .6,
        color: unset ? ink.withValues(alpha: .55) : ink,
      ),
    );
    return unset
        ? DashedBox(
            expand: false,
            radius: 6,
            color: ink.withValues(alpha: .55),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: text,
          )
        : text;
  }
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final key in flyerPicks) ...[
          Swatch(
            key: ValueKey('press-$key'),
            selected: app.gfFly == key,
            onTap: () => app.setGfFly(key),
            child: ClipOval(
              child: FlyerBox(
                style: app.flyer(key),
                radius: 0,
                shadow: false,
                patternScale: .6,
              ),
            ),
          ),
          const SizedBox(width: 9),
        ],
        Swatch(
          key: const ValueKey('press-custom'),
          selected: app.gfCustomFlyer,
          dashed: true,
          onTap: () => app.setGfFly('custom'),
          child: Center(
            child: Icon(
              Icons.arrow_upward,
              size: 15,
              color: context.epColors.accent,
            ),
          ),
        ),
      ],
    );
  }
}

/// Only meaningful over uploaded art: print the details, or leave them off.
class _OverlayToggle extends StatelessWidget {
  const _OverlayToggle();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final on = app.gfShowOverlay;
    return EpCard(
      variant: on ? EpCardVariant.selected : EpCardVariant.standard,
      padding: EdgeInsets.zero,
      child: SwitchListTile.adaptive(
        value: on,
        onChanged: (_) => app.toggleGfOverlay(),
        title: Text('Text overlay'),
        subtitle: Text(
          on
              ? 'Name, date and venue printed on the art'
              : 'Art only. Details appear in the listing.',
        ),
      ),
    );
  }
}

// ============================ form cards ============================

class _NameCard extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _NameCard({required this.controller, required this.focusNode});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final filled = app.gfName.trim().isNotEmpty;
    return EpCard(
      variant: EpCardVariant.raised,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SlotTag(
            filled ? 'YOUR GIG NAME ✓' : 'YOUR GIG NAME · REQUIRED',
            filled ? context.epColors.success : context.epColors.warning,
          ),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: app.setGfName,
            style: epDisplay(size: 18),
            decoration: epCollapsedInputDecoration(
              'Riptide Release Show',
              hintStyle: epDisplay(
                size: 18,
                color: context.epColors.contentDisabled,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final venue = app.gfVenueId == null ? null : app.venue(app.gfVenueId!);
    final slots = <Widget>[
      SlotCard(
        key: const ValueKey('gig-slot-date'),
        tag: 'DATE',
        value: app.gfDate == null ? 'REQUIRED' : app.gfDateLabel.toUpperCase(),
        sub: app.gfDate == null ? 'Choose a date' : 'Calendar date for doors',
        state: app.gfDate == null ? SlotState.needed : SlotState.done,
        onTap: () => showWhenSheet(context),
      ),
      SlotCard(
        key: const ValueKey('gig-slot-times'),
        tag: 'TIMES',
        value: 'Doors ${app.gfDoorsLabel} · Start ${app.gfStartLabel}',
        sub: 'A start earlier than doors is treated as after midnight',
        state: SlotState.done,
        onTap: () => showWhenSheet(context),
      ),
      SlotCard(
        key: const ValueKey('gig-slot-venue'),
        tag: 'VENUE',
        value: venue?.name ?? 'REQUIRED',
        sub: venue?.area ?? 'Choose a venue',
        state: venue == null ? SlotState.needed : SlotState.done,
        onTap: () => showVenueSheet(context),
      ),
      SlotCard(
        key: const ValueKey('gig-slot-cover'),
        tag: 'COVER',
        value: app.gfPrice,
        sub: app.gfPrice == 'FREE' ? 'No cover' : 'At the door',
        state: SlotState.done,
        onTap: () => showPriceSheet(context),
      ),
      SlotCard(
        key: const ValueKey('gig-slot-access'),
        tag: 'ACCESS',
        value: app.gfTix == Ticketing.rsvp ? 'In-app RSVP' : 'External link',
        sub: switch (app.gfTix) {
          Ticketing.rsvp when app.gfCap == 'No cap' => 'No RSVP cap',
          Ticketing.rsvp => 'RSVP cap ${app.gfCap}',
          Ticketing.external =>
            app.gfExt.isEmpty ? 'Add ticket URL' : app.gfExt,
        },
        state: app.gfTix == Ticketing.external && !app.validExternalTicketUrl
            ? SlotState.needed
            : SlotState.done,
        onTap: () => showTicketsSheet(context),
      ),
      SlotCard(
        key: const ValueKey('gig-slot-audience'),
        tag: 'AUDIENCE',
        value: app.gfAgeRequirement.label,
        sub: 'Age requirement',
        state: SlotState.done,
        onTap: () => showAgeSheet(context),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final singleColumn =
            constraints.maxWidth < 330 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.25;
        const gap = 12.0;
        final tileWidth = singleColumn
            ? constraints.maxWidth
            : (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final slot in slots) SizedBox(width: tileWidth, child: slot),
          ],
        );
      },
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
          const DashedBox(
            child: Text(
              'Add at least one performer.',
              textAlign: TextAlign.center,
            ),
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
              return Padding(
                key: ValueKey(performer.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: EpCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          child: Icon(Icons.drag_handle, size: 20),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              performer.name,
                              style: epText(size: 13, weight: FontWeight.w800),
                            ),
                            Text(
                              switch (performer.kind) {
                                GigPerformerKind.band => 'EARPLUG BAND',
                                GigPerformerKind.invited => 'INVITE PENDING',
                                GigPerformerKind.text => 'TEXT-ONLY PERFORMER',
                              },
                              style: epText(
                                size: 11,
                                weight: FontWeight.w800,
                                letterSpacing: .7,
                                color:
                                    performer.kind == GigPerformerKind.invited
                                    ? context.epColors.volt
                                    : context.epColors.contentDisabled,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (performer.inviteUrl != null)
                        IconButton(
                          tooltip: 'Copy invite link',
                          onPressed: () => copyForUser(
                            context,
                            performer.inviteUrl!,
                            successMessage: 'Invite link copied.',
                          ),
                          icon: Icon(Icons.link, size: 18),
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
                              child: Text(role.name.toUpperCase()),
                            ),
                        ],
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: 48,
                            minWidth: 48,
                          ),
                          child: Center(
                            child: DecoratedBox(
                              key: ValueKey(
                                'gig-performer-role-pill-${performer.id}',
                              ),
                              decoration: BoxDecoration(
                                color: context.epColors.surfaceSelected,
                                border: Border.all(
                                  color: context.epColors.accent,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                child: Text(
                                  performer.role.name.toUpperCase(),
                                  style: epText(
                                    size: 11,
                                    weight: FontWeight.w900,
                                    color: context.epColors.accent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove performer',
                        onPressed: () => app.removeGigPerformer(performer.id),
                        icon: Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: EpChip(
            label: '+ Add band or performer',
            active: false,
            ghost: true,
            onTap: () => showEpSheet(
              context,
              (_) => const EpFormSheet(
                title: 'Add performer',
                child: _AddPerformerBody(),
              ),
            ),
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
          decoration: sheetInput(context, 'Search EarPlug bands'),
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
        TextField(
          controller: _name,
          decoration: sheetInput(context, 'Unlisted band or performer name'),
        ),
        const SizedBox(height: 8),
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
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    focusNode: _focusNode,
    minLines: 4,
    maxLines: 7,
    onChanged: context.read<AppState>().setGfDescription,
    decoration: sheetInput(
      context,
      'Accessibility, set times, parking, or anything fans should know',
    ),
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

class _PublishBar extends StatelessWidget {
  const _PublishBar();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final missing = app.gigMissing;
    return ColoredBox(
      color: context.epColors.tabBarBackground.withValues(alpha: .95),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Semantics(
              liveRegion: true,
              child: Text(
                missing.isEmpty
                    ? 'Ready. Fans nearby see it as soon as you publish.'
                    : 'Still needs ${missing.join(' + ')}',
                textAlign: TextAlign.center,
                style: epText(
                  size: 11,
                  weight: FontWeight.w700,
                  letterSpacing: .3,
                  color: missing.isEmpty
                      ? context.epColors.success
                      : context.epColors.contentSecondary,
                ),
              ),
            ),
          ),
          StickyActionBar(
            secondaryLabel: 'Preview',
            onSecondary: app.previewGigDraft,
            primaryLabel: app.gfProject?.status == GigProjectStatus.published
                ? 'Publish updates'
                : 'Publish gig',
            onPrimary: app.canPublishGig ? app.publishGig : null,
          ),
        ],
      ),
    );
  }
}
