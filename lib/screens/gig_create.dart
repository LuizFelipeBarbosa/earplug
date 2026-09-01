import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../demo_data.dart';
import '../models.dart';
import '../services/flyer_text_extractor.dart';
import '../services/media_picker.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import 'door_mode.dart';

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
      (_) => _Sheet(
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
    if (app.gfPublished) return const _PublishedView();
    if (app.gfPreviewing) return const _DraftPreview();

    return Stack(
      children: [
        Column(
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Ep.border)),
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
                                ? Ep.warning
                                : Ep.contentDisabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: app.saveGigDraft,
                    child: const Text('SAVE DRAFT'),
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
                icon: const Icon(Icons.add_photo_alternate_outlined),
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
                  icon: const Icon(Icons.close),
                  label: const Text('REMOVE ART'),
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
              size: 10.5,
              weight: FontWeight.w600,
              letterSpacing: .3,
              color: Ep.contentDisabled,
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
    final app = context.watch<AppState>();
    final art = app.gfFlyerArt;
    final persistedUrl = app.gfFlyerUrl;
    final slot = ColoredBox(
      color: base,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (art != null)
            Image.memory(art.bytes, fit: BoxFit.cover)
          else if (persistedUrl != null)
            Image.network(
              persistedUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _ArtPlaceholder(base: base),
            )
          else
            _ArtPlaceholder(base: base),
          if (app.gfFlyerUploading)
            const Align(
              alignment: Alignment.bottomCenter,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
    return slot;
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
          color: Ep.border,
          radius: 4,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 22,
                  color: Ep.contentDisabled,
                ),
                const SizedBox(height: 6),
                Text(
                  'CUSTOM FLYER PREVIEW',
                  style: epText(
                    size: 10.5,
                    weight: FontWeight.w900,
                    letterSpacing: .8,
                    color: Ep.contentDisabled,
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
        for (final key in DemoData.flyerPicks) ...[
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
          child: const Center(
            child: Icon(Icons.arrow_upward, size: 15, color: Ep.accent),
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
        title: const Text('Text overlay'),
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

/// Card outline states shared by the six editing slots.
enum _SlotState { done, needed }

class _SlotShell extends StatelessWidget {
  final _SlotState state;
  final Widget child;
  final VoidCallback? onTap;

  const _SlotShell({required this.state, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
    if (state != _SlotState.needed) {
      return EpCard(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        onTap: onTap,
        child: content,
      );
    }

    final radius = BorderRadius.circular(12);
    return Semantics(
      container: true,
      button: onTap != null,
      child: Material(
        color: Ep.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: DashedBox(
            color: Ep.volt,
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _SlotTag extends StatelessWidget {
  final String text;
  final Color color;

  const _SlotTag(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: epText(
        size: 11,
        weight: FontWeight.w900,
        letterSpacing: 1.2,
        color: color,
      ),
    );
  }
}

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
          _SlotTag(
            filled ? 'YOUR GIG NAME ✓' : 'YOUR GIG NAME · REQUIRED',
            filled ? Ep.success : Ep.warning,
          ),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: app.setGfName,
            style: epDisplay(size: 18),
            decoration: epCollapsedInputDecoration(
              'Riptide Release Show',
              hintStyle: epDisplay(size: 18, color: Ep.contentDisabled),
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
      _SlotCard(
        key: const ValueKey('gig-slot-date'),
        tag: 'DATE',
        value: app.gfDate == null ? 'REQUIRED' : app.gfDateLabel.toUpperCase(),
        sub: app.gfDate == null ? 'Choose a date' : 'Calendar date for doors',
        state: app.gfDate == null ? _SlotState.needed : _SlotState.done,
        onTap: () => showWhenSheet(context),
      ),
      _SlotCard(
        key: const ValueKey('gig-slot-times'),
        tag: 'TIMES',
        value: 'Doors ${app.gfDoorsLabel} · Start ${app.gfStartLabel}',
        sub: 'A start earlier than doors is treated as after midnight',
        state: _SlotState.done,
        onTap: () => showWhenSheet(context),
      ),
      _SlotCard(
        key: const ValueKey('gig-slot-venue'),
        tag: 'VENUE',
        value: venue?.name ?? 'REQUIRED',
        sub: venue?.area ?? 'Choose a venue',
        state: venue == null ? _SlotState.needed : _SlotState.done,
        onTap: () => showVenueSheet(context),
      ),
      _SlotCard(
        key: const ValueKey('gig-slot-cover'),
        tag: 'COVER',
        value: app.gfPrice,
        sub: app.gfPrice == 'FREE' ? 'No cover' : 'At the door',
        state: _SlotState.done,
        onTap: () => showPriceSheet(context),
      ),
      _SlotCard(
        key: const ValueKey('gig-slot-access'),
        tag: 'ACCESS',
        value: app.gfTix == Ticketing.rsvp ? 'In-app RSVP' : 'External link',
        sub: switch (app.gfTix) {
          Ticketing.rsvp when app.gfCap == 'No cap' => 'No RSVP cap',
          Ticketing.rsvp => 'RSVP cap ${app.gfCap}',
          Ticketing.external =>
            app.gfExt.isEmpty ? 'Add ticket URL' : app.gfExt,
        },
        state: _SlotState.done,
        onTap: () => showTicketsSheet(context),
      ),
      _SlotCard(
        key: const ValueKey('gig-slot-audience'),
        tag: 'AUDIENCE',
        value: app.gfAgeRequirement.label,
        sub: 'Age requirement',
        state: _SlotState.done,
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
                          child: const Icon(Icons.drag_handle, size: 20),
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
                                    ? Ep.volt
                                    : Ep.contentDisabled,
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
                          icon: const Icon(Icons.link, size: 18),
                        ),
                      PopupMenuButton<GigPerformerRole>(
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
                          constraints: const BoxConstraints(minHeight: 48),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Ep.surfaceSelected,
                              border: Border.all(color: Ep.accent),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 6,
                              ),
                              child: Center(
                                child: Text(
                                  performer.role.name.toUpperCase(),
                                  style: epText(
                                    size: 11,
                                    weight: FontWeight.w900,
                                    color: Ep.accent,
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
                        icon: const Icon(Icons.close, size: 18),
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
              (_) => const _Sheet(
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
          decoration: sheetInput('Search EarPlug bands'),
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
                      trailing: const Icon(Icons.add),
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
        const Divider(),
        TextField(
          controller: _name,
          decoration: sheetInput('Unlisted band or performer name'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _addNamed(invite: false),
                child: const Text('ADD TEXT ONLY'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () => _addNamed(invite: true),
                child: const Text('CREATE INVITE'),
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
          style: epText(size: 11, color: Ep.contentSecondary, height: 1.4),
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
                  title: const Text('VIEW EXTRACTED TEXT'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        proposal.rawText,
                        style: epText(size: 10.5, color: Ep.contentSecondary),
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
    subtitle: Text(label.toUpperCase(), style: epText(size: 9.5)),
    controlAffinity: ListTileControlAffinity.leading,
  );
}

// ---------------------------- age ----------------------------

void showAgeSheet(BuildContext context) {
  showEpSheet(
    context,
    (_) => const _Sheet(title: 'Age requirement', child: _AgeBody()),
  );
}

class _AgeBody extends StatelessWidget {
  const _AgeBody();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final requirement in AgeRequirement.values) ...[
          _OptionCard(
            title: requirement.label,
            subtitle: switch (requirement) {
              AgeRequirement.allAges => 'Everyone is welcome',
              AgeRequirement.eighteenPlus => 'Guests must be 18 or older',
              AgeRequirement.twentyOnePlus => 'Guests must be 21 or older',
            },
            selected: app.gfAgeRequirement == requirement,
            onTap: () {
              app.setGfAgeRequirement(requirement);
              Navigator.pop(context);
            },
          ),
          if (requirement != AgeRequirement.twentyOnePlus)
            const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SlotCard extends StatelessWidget {
  final String tag;
  final String value;
  final String sub;
  final _SlotState state;
  final VoidCallback onTap;

  const _SlotCard({
    super.key,
    required this.tag,
    required this.value,
    required this.sub,
    required this.state,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _SlotShell(
      state: state,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _SlotTag(
                  tag,
                  state == _SlotState.needed ? Ep.warning : Ep.contentSecondary,
                ),
              ),
              if (state == _SlotState.done)
                const Icon(Icons.check, size: 17, color: Ep.success),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: epText(
              size: 13,
              weight: FontWeight.w800,
              color: state == _SlotState.needed
                  ? Ep.warning
                  : Ep.contentPrimary,
            ),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: epText(size: 10.5, color: Ep.contentDisabled),
            ),
          ],
        ],
      ),
    );
  }
}

class _PublishBar extends StatelessWidget {
  const _PublishBar();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final missing = app.gigMissing;
    return ColoredBox(
      color: Ep.tabBarBackground.withValues(alpha: .95),
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
                  color: missing.isEmpty ? Ep.success : Ep.contentSecondary,
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

// ============================ sheets ============================

class _Sheet extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;

  /// Sheets that own their own scrolling (the calendar) lay out their body.
  final bool padBody;

  const _Sheet({
    required this.title,
    required this.child,
    this.trailing,
    this.padBody = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      decoration: const BoxDecoration(
        color: Ep.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(title.toUpperCase(), style: epDisplay(size: 15)),
                ),
                trailing ??
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
              ],
            ),
          ),
          if (padBody)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              child: child,
            )
          else
            Flexible(child: child),
        ],
      ),
    );
  }
}

/// Full-width option row used by the venue and ticketing sheets.
class _OptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool titleCaps;

  const _OptionCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.titleCaps = false,
  });

  @override
  Widget build(BuildContext context) {
    return EpCard(
      variant: selected ? EpCardVariant.selected : EpCardVariant.standard,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titleCaps ? title.toUpperCase() : title,
            style: epText(size: 12.5, weight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: epText(size: 10.5, color: Ep.contentSecondary)),
        ],
      ),
    );
  }
}

// ---------------------------- when ----------------------------

void showWhenSheet(BuildContext context) {
  showEpSheet(context, (ctx) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * .82,
      ),
      child: const _Sheet(
        title: 'When is it',
        padBody: false,
        child: _WhenBody(),
      ),
    );
  });
}

class _WhenBody extends StatelessWidget {
  const _WhenBody();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 4,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (_, index) => _Month(
              first: DateTime(today.year, today.month + index, 1),
              today: today,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 34),
          decoration: BoxDecoration(
            border: const Border(top: BorderSide(color: Ep.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'DOORS',
                    style: epText(
                      size: 10.5,
                      weight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: Ep.contentSecondary,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: app.gfDoors,
                      );
                      if (picked != null) app.setGfDoors(picked);
                    },
                    child: Text(app.gfDoorsLabel),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'START',
                    style: epText(
                      size: 10.5,
                      weight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: Ep.contentSecondary,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: app.gfStart,
                      );
                      if (picked != null) app.setGfStart(picked);
                    },
                    child: Text(app.gfStartLabel),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final hour in const [18, 19, 20, 21, 22]) ...[
                      EpChip(
                        label:
                            'DOORS ${timeLabel(TimeOfDay(hour: hour, minute: 0))}',
                        active: app.gfDoors == TimeOfDay(hour: hour, minute: 0),
                        onTap: () =>
                            app.setGfDoors(TimeOfDay(hour: hour, minute: 0)),
                      ),
                      const SizedBox(width: 7),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 11),
              const DoneButton(),
            ],
          ),
        ),
      ],
    );
  }
}

class _Month extends StatelessWidget {
  final DateTime first;
  final DateTime today;

  const _Month({required this.first, required this.today});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // The grid starts on Sunday; Dart weekdays run Mon(1)..Sun(7).
    final lead = first.weekday % 7;
    final days = DateTime(first.year, first.month + 1, 0).day;
    final rows = ((lead + days) / 7).ceil();

    Widget cell(int slot) {
      final day = slot - lead + 1;
      if (day < 1 || day > days) return const SizedBox(height: 48);
      final date = DateTime(first.year, first.month, day);
      final past = date.isBefore(today);
      final selected = date == app.gfDate;

      return Semantics(
        // Keyed by the whole date, not the day number: four months are on
        // screen at once, so '1' alone is ambiguous four times over.
        button: !past,
        selected: selected,
        enabled: !past,
        label: '${date.year}-${date.month}-$day',
        child: Material(
          color: past
              ? Colors.transparent
              : selected
              ? Ep.surfaceSelected
              : Ep.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: past
                  ? Ep.surfaceDisabled
                  : selected || date == today
                  ? Ep.accent
                  : Ep.border,
            ),
          ),
          child: InkWell(
            key: ValueKey('day-${date.year}-${date.month}-${date.day}'),
            onTap: past ? null : () => app.setGfDate(date),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  '$day',
                  style: Theme.of(context).textTheme.epLabel.copyWith(
                    color: past
                        ? Ep.contentDisabled
                        : selected
                        ? Ep.contentPrimary
                        : Ep.contentSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget grid(int row, Widget Function(int) child) => Row(
      children: [
        for (var column = 0; column < 7; column++) ...[
          if (column > 0) const SizedBox(width: 4),
          Expanded(child: child(row * 7 + column)),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          monthLabel(first).toUpperCase(),
          style: epText(
            size: 10.5,
            weight: FontWeight.w900,
            letterSpacing: 1.3,
            color: Ep.contentDisabled,
          ),
        ),
        const SizedBox(height: 8),
        grid(
          0,
          (slot) => Text(
            const ['S', 'M', 'T', 'W', 'T', 'F', 'S'][slot],
            textAlign: TextAlign.center,
            style: epText(
              size: 8.5,
              weight: FontWeight.w900,
              letterSpacing: .5,
              color: Ep.contentDisabled,
            ),
          ),
        ),
        const SizedBox(height: 5),
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) const SizedBox(height: 4),
          grid(row, cell),
        ],
      ],
    );
  }
}

// ---------------------------- venue ----------------------------

void showVenueSheet(BuildContext context) {
  final app = context.read<AppState>();
  showEpSheet(context, (ctx) {
    return _Sheet(
      title: 'Where is it',
      trailing: TextAction(
        '+ NEW VENUE',
        onTap: () {
          Navigator.pop(ctx);
          if (context.mounted) showNewVenueSheet(context);
        },
        size: 11,
        letterSpacing: .6,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * .6,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'Venues are shared records, so the address stays consistent across '
              "every band's listings.",
              style: epText(
                size: 10.5,
                color: Ep.contentDisabled,
                height: 1.45,
              ),
            ),
            for (final venue in app.venues)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Consumer<AppState>(
                  builder: (_, watched, _) => _OptionCard(
                    title: venue.name,
                    titleCaps: true,
                    subtitle: '${venue.addr} · ${venue.area}',
                    selected: watched.gfVenueId == venue.id,
                    onTap: () {
                      watched.setGfVenue(venue.id);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  });
}

void showNewVenueSheet(BuildContext context) {
  showEpSheet(
    context,
    (_) => const _Sheet(title: 'New venue', child: _NewVenueBody()),
  );
}

class _NewVenueBody extends StatefulWidget {
  const _NewVenueBody();

  @override
  State<_NewVenueBody> createState() => _NewVenueBodyState();
}

class _NewVenueBodyState extends State<_NewVenueBody> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _area = TextEditingController();
  LatLng? _pin;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _area.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pin;
    if (_name.text.trim().isEmpty ||
        _address.text.trim().isEmpty ||
        _area.text.trim().isEmpty ||
        pin == null) {
      setState(
        () => _error = 'Name, street address, area, and map pin are required.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await context.read<AppState>().createVenue(
        name: _name.text,
        area: _area.text,
        address: _address.text,
        point: pin,
      );
      if (!mounted) return;
      Navigator.pop(context);
      context.read<AppState>().say(
        result.created
            ? 'Venue created and selected.'
            : 'Existing venue selected.',
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Venue could not be created. Check the details and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const center = LatLng(37.7749, -122.4194);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('new-venue-name'),
          controller: _name,
          maxLength: 120,
          decoration: sheetInput('Venue name'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('new-venue-address'),
          controller: _address,
          maxLength: 240,
          decoration: sheetInput('Street address'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('new-venue-area'),
          controller: _area,
          maxLength: 80,
          decoration: sheetInput('Neighborhood or city'),
        ),
        const SizedBox(height: 10),
        Text(
          _pin == null
              ? 'TAP THE MAP TO PLACE THE REQUIRED PIN'
              : 'MAP PIN SET ✓',
          style: epText(
            size: 10,
            weight: FontWeight.w900,
            color: _pin == null ? Ep.warning : Ep.accent,
          ),
        ),
        const SizedBox(height: 7),
        SizedBox(
          key: const Key('new-venue-map'),
          height: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 11.5,
                onTap: (_, point) => setState(() => _pin = point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'dev.earplug.app',
                ),
                if (_pin case final pin?)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: pin,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_pin,
                          color: Ep.accent,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 8),
          Text(error, style: epText(size: 11, color: Ep.warning)),
        ],
        const SizedBox(height: 12),
        EpButton(
          _saving ? 'CREATING…' : 'CREATE & SELECT VENUE',
          kind: _saving ? EpButtonKind.disabled : EpButtonKind.filled,
          onTap: _saving ? null : _save,
        ),
      ],
    );
  }
}

// ---------------------------- price ----------------------------

const _presetPrices = ['FREE', '\$5', '\$8', '\$10', '\$12', '\$15'];

void showPriceSheet(BuildContext context) {
  showEpSheet(
    context,
    (_) => const _Sheet(title: 'Cover', child: _PriceBody()),
  );
}

class _PriceBody extends StatefulWidget {
  const _PriceBody();

  @override
  State<_PriceBody> createState() => _PriceBodyState();
}

class _PriceBodyState extends State<_PriceBody> {
  late final TextEditingController _custom;

  @override
  void initState() {
    super.initState();
    final price = context.read<AppState>().gfPrice;
    _custom = TextEditingController(
      text: _presetPrices.contains(price) ? '' : price.replaceAll('\$', ''),
    );
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isCustom = !_presetPrices.contains(app.gfPrice);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final price in _presetPrices)
              EpChip(
                label: price,
                active: app.gfPrice == price,
                onTap: () {
                  app.setGfPrice(price);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: isCustom ? Ep.surfaceSelected : Ep.background,
            border: isCustom
                ? Border.all(color: Ep.accent, width: 1.5)
                : Border.all(color: Ep.border),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              Text(
                '\$',
                style: epDisplay(size: 19, color: Ep.contentSecondary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _custom,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (value) {
                    final amount = int.tryParse(value) ?? 0;
                    app.setGfPrice(amount == 0 ? 'FREE' : '\$$amount');
                  },
                  style: epText(size: 16, weight: FontWeight.w800),
                  decoration: epCollapsedInputDecoration(
                    'Other amount',
                    hintStyle: epText(
                      size: 16,
                      weight: FontWeight.w800,
                      color: Ep.contentDisabled,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'AT THE DOOR',
                style: epText(
                  size: 10.5,
                  weight: FontWeight.w800,
                  letterSpacing: .6,
                  color: Ep.contentDisabled,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Free gigs get roughly twice the RSVPs. Sliding scale? Put the range '
          'in the gig name.',
          style: epText(size: 10.5, color: Ep.contentDisabled, height: 1.45),
        ),
      ],
    );
  }
}

// ---------------------------- tickets ----------------------------

const _presetCaps = ['No cap', '50', '100', '150'];

void showTicketsSheet(BuildContext context) {
  showEpSheet(
    context,
    (_) => const _Sheet(title: 'Tickets', child: _TicketsBody()),
  );
}

class _TicketsBody extends StatefulWidget {
  const _TicketsBody();

  @override
  State<_TicketsBody> createState() => _TicketsBodyState();
}

class _TicketsBodyState extends State<_TicketsBody> {
  late final TextEditingController _cap;
  late final TextEditingController _ext;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _cap = TextEditingController(
      text: _presetCaps.contains(app.gfCap) ? '' : app.gfCap,
    );
    _ext = TextEditingController(text: app.gfExt);
  }

  @override
  void dispose() {
    _cap.dispose();
    _ext.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final capIsCustom = !_presetCaps.contains(app.gfCap);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _OptionCard(
          title: 'In-app RSVP',
          subtitle: 'Free headcount, QR at the door, optional cap',
          selected: app.gfTix == Ticketing.rsvp,
          onTap: () => app.setGfTix(Ticketing.rsvp),
        ),
        if (app.gfTix == Ticketing.rsvp)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final cap in _presetCaps)
                      EpChip(
                        label: cap,
                        active: app.gfCap == cap,
                        onTap: () => app.setGfCap(cap),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: capIsCustom ? Ep.surfaceSelected : Ep.background,
                    border: capIsCustom
                        ? Border.all(color: Ep.accent, width: 1.5)
                        : Border.all(color: Ep.border),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cap,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (value) {
                            final spots = int.tryParse(value) ?? 0;
                            app.setGfCap(spots <= 0 ? 'No cap' : '$spots');
                          },
                          style: epText(size: 14, weight: FontWeight.w800),
                          decoration: epCollapsedInputDecoration(
                            'Other cap',
                            hintStyle: epText(
                              size: 14,
                              weight: FontWeight.w800,
                              color: Ep.contentDisabled,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        'SPOTS',
                        style: epText(
                          size: 10.5,
                          weight: FontWeight.w800,
                          letterSpacing: .6,
                          color: Ep.contentDisabled,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        _OptionCard(
          title: 'External ticket link',
          subtitle: 'DICE, Eventbrite, venue box office…',
          selected: app.gfTix == Ticketing.external,
          onTap: () => app.setGfTix(Ticketing.external),
        ),
        if (app.gfTix == Ticketing.external)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextField(
              controller: _ext,
              keyboardType: TextInputType.url,
              onChanged: app.setGfExt,
              style: epText(size: 12.5),
              decoration: sheetInput('https://…').copyWith(
                errorText:
                    app.gfExt.trim().isNotEmpty && !app.validExternalTicketUrl
                    ? 'Enter a complete HTTPS URL.'
                    : null,
              ),
            ),
          ),
        const SizedBox(height: 14),
        const DoneButton(),
      ],
    );
  }
}

// ============================ fan preview ============================

class _DraftPreview extends StatelessWidget {
  const _DraftPreview();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final venue = app.gfVenueId == null ? null : app.venue(app.gfVenueId!);
    return ColoredBox(
      color: Ep.background,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 40),
        children: [
          Row(
            children: [
              CircleIconButton(
                icon: Icons.chevron_left,
                onTap: app.closeGigPreview,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('FAN PREVIEW', style: epDisplay(size: 16))),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Ep.surfaceSelected,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  app.gigPreviewLabel,
                  style: epText(
                    size: 9,
                    weight: FontWeight.w900,
                    letterSpacing: .8,
                    color: Ep.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Center(child: _Poster(width: 250, height: 328)),
          const SizedBox(height: 20),
          Text(
            app.gfName.trim().isEmpty
                ? 'UNTITLED GIG'
                : app.gfName.toUpperCase(),
            style: epDisplay(size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (app.gfDate != null) app.gfDateLabel,
              'Doors ${app.gfDoorsLabel}',
              'Start ${app.gfStartLabel}',
            ].join(' · '),
            style: epText(size: 12, color: Ep.contentSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            venue == null ? 'VENUE NOT SET' : venue.name.toUpperCase(),
            style: epText(size: 12, weight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          const SectionLabel('LINEUP'),
          const SizedBox(height: 8),
          if (app.gfPerformers.isEmpty)
            Text('No performers yet.', style: epText(color: Ep.contentDisabled))
          else
            for (final performer in app.gfPerformers)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: EpCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          performer.name.toUpperCase(),
                          style: epText(size: 13, weight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        performer.role.name.toUpperCase(),
                        style: epText(
                          size: 9,
                          weight: FontWeight.w900,
                          color: Ep.contentDisabled,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          if (app.gfDesc.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              app.gfDesc.trim(),
              style: epText(size: 13, color: Ep.contentSecondary, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================ published ============================

class _PublishedView extends StatelessWidget {
  const _PublishedView();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ColoredBox(
      color: Ep.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'PUBLISHED',
                style: epText(
                  size: 10.5,
                  weight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Ep.accent,
                ),
              ),
              const SizedBox(height: 16),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: .9, end: 1),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: const _Poster(width: 212, height: 280),
              ),
              const SizedBox(height: 16),
              Text("IT'S LIVE.", style: epDisplay(size: 20)),
              const SizedBox(height: 4),
              Text(
                app.gigUrl,
                style: epText(size: 12, color: Ep.contentSecondary),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 300,
                child: Row(
                  children: [
                    Expanded(
                      child: EpButton(
                        'SHARE LINK',
                        fontSize: 11.5,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        onTap: () => copyForUser(
                          context,
                          'https://${app.gigUrl}',
                          successMessage: 'Link copied: ${app.gigUrl}',
                        ),
                      ),
                    ),
                    if (app.gfProject?.ticketing == Ticketing.rsvp) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: EpButton(
                          'DOOR MODE',
                          kind: EpButtonKind.ghost,
                          fontSize: 11.5,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          onTap: () => showDoorMode(
                            context,
                            DoorModeLaunch(
                              projectId: app.gfProject!.id,
                              gigTitle: app.gfName.trim().isEmpty
                                  ? 'Untitled gig'
                                  : app.gfName,
                              venueName: app.gfVenueId == null
                                  ? 'Venue TBD'
                                  : app.venue(app.gfVenueId!).name,
                              doorsTime: app.gfDoorsLabel,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextAction(
                    'KEEP EDITING',
                    onTap: app.editPublishedGig,
                    color: Ep.contentSecondary,
                    size: 11,
                    letterSpacing: .6,
                  ),
                  TextAction(
                    'MAKE ANOTHER',
                    onTap: app.makeAnotherGig,
                    size: 11,
                    letterSpacing: .6,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextAction(
                'BACK TO GIGS',
                onTap: app.closeGigCreate,
                color: Ep.contentDisabled,
                size: 11,
                letterSpacing: .6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
