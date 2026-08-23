import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../demo_data.dart';
import '../models.dart';
import '../services/media_picker.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';

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

  app.setGfFlyerArt(picked);
  app.setGfFlyerUploading(true);
  final storageId = await media.uploadFlyerArt(app.bandId, picked);
  if (identical(app.gfFlyerArt, picked)) {
    app.setGfFlyerStorageId(storageId);
  }
  app.setGfFlyerUploading(false);
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
                  Expanded(child: Text('NEW GIG', style: epDisplay(size: 16))),
                  ReadyPill(ready: app.canPublishGig),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 150),
                children: [
                  const _FlyerStudio(),
                  const SizedBox(height: 14),
                  _NameCard(controller: _cardName, focusNode: _cardFocus),
                  const SizedBox(height: 9),
                  const _SlotGrid(),
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
                  app.gfFlyerArt == null ? 'ADD FLYER ART' : 'CHANGE ART',
                ),
              ),
              if (app.gfFlyerArt != null)
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
    final slot = ColoredBox(
      color: base,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (art == null)
            Padding(
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
            )
          else
            Image.memory(art.bytes, fit: BoxFit.cover),
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

/// Card outline states shared by the name card and the four slot cards.
enum _SlotState { done, needed, optional }

class _SlotShell extends StatelessWidget {
  final _SlotState state;
  final Widget child;
  final VoidCallback? onTap;

  const _SlotShell({required this.state, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return EpCard(
      variant: state == _SlotState.done
          ? EpCardVariant.selected
          : EpCardVariant.standard,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      onTap: onTap,
      child: child,
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
        size: 9.5,
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
    return _SlotShell(
      state: filled ? _SlotState.done : _SlotState.needed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SlotTag(
            filled ? 'GIG NAME ✓' : 'GIG NAME · REQUIRED',
            filled ? Ep.accent : Ep.warning,
          ),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: app.setGfName,
            style: epText(size: 15, weight: FontWeight.w800),
            decoration: InputDecoration.collapsed(
              hintText: 'Riptide Release Show',
              hintStyle: epText(
                size: 15,
                weight: FontWeight.w800,
                color: Ep.contentDisabled,
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

    final slots = [
      _SlotCard(
        tag: app.gfDate == null ? 'WHEN · REQUIRED' : 'WHEN ✓',
        tagColor: app.gfDate == null ? Ep.warning : Ep.accent,
        value: app.gfDate == null
            ? 'Pick a date'
            : app.gfDateLabel.toUpperCase(),
        sub: app.gfDate == null ? '' : 'Doors ${app.gfDoorsLabel}',
        state: app.gfDate == null ? _SlotState.needed : _SlotState.done,
        onTap: () => showWhenSheet(context),
      ),
      _SlotCard(
        tag: venue == null ? 'VENUE · REQUIRED' : 'VENUE ✓',
        tagColor: venue == null ? Ep.warning : Ep.accent,
        value: venue?.name ?? 'Where is it',
        sub: venue?.area ?? '',
        state: venue == null ? _SlotState.needed : _SlotState.done,
        onTap: () => showVenueSheet(context),
      ),
      _SlotCard(
        tag: 'PRICE',
        tagColor: Ep.contentSecondary,
        value: app.gfPrice,
        sub: app.gfPrice == 'FREE'
            ? 'Free gigs pull bigger crowds'
            : 'At the door',
        state: _SlotState.optional,
        onTap: () => showPriceSheet(context),
      ),
      _SlotCard(
        tag: 'TICKETS',
        tagColor: Ep.contentSecondary,
        value: app.gfTix == Ticketing.rsvp ? 'In-app RSVP' : 'External link',
        sub: switch (app.gfTix) {
          Ticketing.rsvp when app.gfCap == 'No cap' =>
            'No cap · QR at the door',
          Ticketing.rsvp => 'Cap ${app.gfCap} · QR at the door',
          Ticketing.external => app.gfExt.isEmpty ? 'Add your link' : app.gfExt,
        },
        state: _SlotState.optional,
        onTap: () => showTicketsSheet(context),
      ),
      _SlotCard(
        tag: 'AGE',
        tagColor: Ep.contentSecondary,
        value: app.gfAgeRequirement.label,
        sub: 'Who can come through',
        state: _SlotState.optional,
        onTap: () => showAgeSheet(context),
      ),
    ];

    Widget row(_SlotCard left, _SlotCard right) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: 9),
          Expanded(child: right),
        ],
      ),
    );

    return Column(
      children: [
        row(slots[0], slots[1]),
        const SizedBox(height: 9),
        row(slots[2], slots[3]),
        const SizedBox(height: 9),
        SizedBox(width: double.infinity, child: slots[4]),
      ],
    );
  }
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
  final Color tagColor;
  final String value;
  final String sub;
  final _SlotState state;
  final VoidCallback onTap;

  const _SlotCard({
    required this.tag,
    required this.tagColor,
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
          _SlotTag(tag, tagColor),
          const SizedBox(height: 4),
          Text(
            value,
            style: epText(
              size: 13,
              weight: FontWeight.w800,
              color: state == _SlotState.needed
                  ? Ep.contentDisabled
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
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        30,
        16,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Ep.background.withValues(alpha: 0), Ep.background],
          stops: const [0, .34],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            missing.isEmpty
                ? 'Ready. Fans nearby see it as soon as you publish.'
                : 'Still needs ${missing.join(' + ')}',
            textAlign: TextAlign.center,
            style: epText(
              size: 11,
              weight: FontWeight.w700,
              letterSpacing: .3,
              color: missing.isEmpty ? Ep.accent : Ep.contentSecondary,
            ),
          ),
          const SizedBox(height: 9),
          EpButton(
            'PUBLISH GIG',
            fontSize: 14,
            kind: app.canPublishGig
                ? EpButtonKind.filled
                : EpButtonKind.disabled,
            padding: const EdgeInsets.symmetric(vertical: 16),
            onTap: app.canPublishGig ? app.publishGig : null,
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
          app.say("Adding venues isn't ready yet. Pick from the list for now.");
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
                  decoration: InputDecoration.collapsed(
                    hintText: 'Other amount',
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
                          decoration: InputDecoration.collapsed(
                            hintText: 'Other cap',
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
              decoration: sheetInput('https://…'),
            ),
          ),
        const SizedBox(height: 14),
        const DoneButton(),
      ],
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
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: 'https://${app.gigUrl}'),
                          );
                          app.say('Link copied: ${app.gigUrl}');
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: EpButton(
                        'DOOR QR',
                        kind: EpButtonKind.ghost,
                        fontSize: 11.5,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        onTap: () => app.say(
                          "Door QR isn't ready yet. RSVPs still count live.",
                        ),
                      ),
                    ),
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
