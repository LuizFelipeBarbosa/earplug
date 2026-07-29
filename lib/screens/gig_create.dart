import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../demo_data.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _posterTilt = -1.6 * math.pi / 180;

/// Everything on this screen edits one live flyer: the poster is the form.
class GigCreateScreen extends StatefulWidget {
  const GigCreateScreen({super.key});

  @override
  State<GigCreateScreen> createState() => _GigCreateScreenState();
}

class _GigCreateScreenState extends State<GigCreateScreen> {
  final _posterName = TextEditingController();
  final _cardName = TextEditingController();
  final _posterFocus = FocusNode();
  final _cardFocus = FocusNode();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The name is editable in two places — whichever field is idle follows.
    final name = context.read<AppState>().gfName;
    for (final (controller, focus) in [
      (_posterName, _posterFocus),
      (_cardName, _cardFocus),
    ]) {
      if (focus.hasFocus || controller.text == name) continue;
      controller.value = TextEditingValue(
        text: name,
        selection: TextSelection.collapsed(offset: name.length),
      );
    }
  }

  @override
  void dispose() {
    _posterName.dispose();
    _cardName.dispose();
    _posterFocus.dispose();
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
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Ep.whiteA(.09))),
              ),
              child: Row(
                children: [
                  CircleIconButton(
                    icon: Icons.close,
                    onTap: app.closeGigCreate,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text('NEW GIG', style: epDisplay(size: 16))),
                  _ReadyPill(ready: app.canPublishGig),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 150),
                children: [
                  _FlyerStudio(
                    nameController: _posterName,
                    nameFocus: _posterFocus,
                  ),
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

class _ReadyPill extends StatelessWidget {
  final bool ready;

  const _ReadyPill({required this.ready});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ready ? Ep.blue.withValues(alpha: .2) : Ep.card,
        border: Border.all(color: ready ? Ep.blue : Ep.whiteA(.14)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        ready ? 'READY' : 'DRAFT',
        style: epText(
          size: 9.5,
          weight: FontWeight.w900,
          letterSpacing: 1.2,
          color: ready ? Ep.linkSoft : Ep.inkA(.45),
        ),
      ),
    );
  }
}

// ============================ the flyer ============================

/// The poster plus its press picker — the hero of the screen.
class _FlyerStudio extends StatelessWidget {
  final TextEditingController nameController;
  final FocusNode nameFocus;

  const _FlyerStudio({required this.nameController, required this.nameFocus});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      children: [
        _Poster(nameController: nameController, nameFocus: nameFocus),
        const SizedBox(height: 12),
        const _SwatchRow(),
        if (app.gfCustomFlyer) ...[
          const SizedBox(height: 12),
          const _OverlayToggle(),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: 250,
          child: Text(
            app.gfCustomFlyer
                ? (app.gfShowOverlay
                      ? 'Drop your flyer art — the text stays editable on top.'
                      : 'Overlay off — your art shows clean. Details still fill in below.')
                : 'Everything is tappable — fill it in any order.',
            textAlign: TextAlign.center,
            style: epText(
              size: 10.5,
              weight: FontWeight.w600,
              letterSpacing: .3,
              color: Ep.inkA(.4),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _Poster extends StatelessWidget {
  final TextEditingController? nameController;
  final FocusNode? nameFocus;
  final double width;
  final double height;

  const _Poster({
    this.nameController,
    this.nameFocus,
    this.width = 216,
    this.height = 284,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final fly = app.flyer(app.gfFly);

    return Transform.rotate(
      angle: _posterTilt,
      child: Container(
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
            // Keeps printed text legible over photographic art.
            if (app.gfCustomFlyer && app.gfShowOverlay)
              DecoratedBox(
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
            if (app.gfShowOverlay) _PosterOverlay(ink: fly.fg, poster: this),
          ],
        ),
      ),
    );
  }
}

class _CustomArtSlot extends StatelessWidget {
  final Color base;

  const _CustomArtSlot({required this.base});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return GestureDetector(
      onTap: () => app.say('Flyer upload placeholder (demo)'),
      child: ColoredBox(
        color: base,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: DashedBox(
            padding: const EdgeInsets.all(12),
            color: Ep.whiteA(.28),
            radius: 4,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 22, color: Ep.inkA(.45)),
                  const SizedBox(height: 6),
                  Text(
                    'DROP YOUR FLYER',
                    style: epText(
                      size: 10.5,
                      weight: FontWeight.w900,
                      letterSpacing: .8,
                      color: Ep.inkA(.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Name at the top, the three tappable details at the foot.
class _PosterOverlay extends StatelessWidget {
  final Color ink;
  final _Poster poster;

  const _PosterOverlay({required this.ink, required this.poster});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final venue = app.gfVenueId == null ? null : app.venue(app.gfVenueId!);
    final titleStyle = epDisplay(size: 23, color: ink, height: 1.02)
        .copyWith(letterSpacing: -.3);

    return Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: poster.nameController == null
                ? Text(app.gfName.toUpperCase(), style: titleStyle)
                : TextField(
                    controller: poster.nameController,
                    focusNode: poster.nameFocus,
                    onChanged: app.setGfName,
                    maxLines: 4,
                    minLines: 1,
                    cursorColor: ink,
                    style: titleStyle,
                    decoration: InputDecoration.collapsed(
                      hintText: 'TYPE YOUR GIG NAME',
                      hintStyle: titleStyle.copyWith(
                        color: ink.withValues(alpha: .35),
                      ),
                    ),
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
                onTap: () => showWhenSheet(context),
              ),
              const SizedBox(height: 7),
              _PosterLine(
                label: venue == null
                    ? '+ VENUE'
                    : '${venue.name.toUpperCase()} · ${venue.area.toUpperCase()}',
                unset: venue == null,
                ink: ink,
                onTap: () => showVenueSheet(context),
              ),
              const SizedBox(height: 7),
              _PosterLine(
                label: app.gfPrice == 'FREE'
                    ? 'FREE'
                    : '${app.gfPrice} AT THE DOOR',
                unset: false,
                ink: ink,
                onTap: () => showPriceSheet(context),
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
  final VoidCallback onTap;

  const _PosterLine({
    required this.label,
    required this.unset,
    required this.ink,
    required this.onTap,
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
    return GestureDetector(
      onTap: onTap,
      child: unset
          ? DashedBox(
              expand: false,
              radius: 6,
              color: ink.withValues(alpha: .55),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: text,
            )
          : text,
    );
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
          _Swatch(
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
        _Swatch(
          key: const ValueKey('press-custom'),
          selected: app.gfCustomFlyer,
          dashed: true,
          onTap: () => app.setGfFly('custom'),
          child: const Center(
            child: Icon(Icons.arrow_upward, size: 15, color: Ep.link),
          ),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final bool selected;
  final bool dashed;
  final VoidCallback onTap;
  final Widget child;

  const _Swatch({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.dashed = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: dashed ? Ep.bg : null,
          shape: BoxShape.circle,
          border: dashed
              ? null
              : Border.all(
                  color: selected ? Ep.link : Ep.whiteA(.18),
                  width: 2,
                ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Ep.link.withValues(alpha: .25),
                    spreadRadius: 3,
                  ),
                ]
              : null,
        ),
        child: dashed
            ? DashedBox(
                padding: EdgeInsets.zero,
                radius: 15,
                color: selected ? Ep.link : Ep.whiteA(.35),
                child: child,
              )
            : child,
      ),
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
    return GestureDetector(
      onTap: app.toggleGfOverlay,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 7, 13, 7),
        decoration: BoxDecoration(
          color: on ? Ep.blue.withValues(alpha: .16) : Ep.card,
          border: Border.all(
            color: on ? Ep.blue.withValues(alpha: .7) : Ep.whiteA(.14),
          ),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 32,
              height: 19,
              padding: const EdgeInsets.all(2),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: on ? Ep.blue : Ep.whiteA(.16),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Container(
                width: 15,
                height: 15,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Text overlay',
                    style: epText(
                      size: 11.5,
                      weight: FontWeight.w800,
                      letterSpacing: .3,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    on
                        ? 'Name, date and venue printed on the art'
                        : 'Art only — details show in the listing',
                    style: epText(size: 10, color: Ep.inkA(.45)),
                  ),
                ],
              ),
            ),
          ],
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
    const padding = EdgeInsets.symmetric(horizontal: 13, vertical: 12);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: Ep.card,
        borderRadius: BorderRadius.circular(13),
        border: switch (state) {
          _SlotState.done => Border.all(color: Ep.link.withValues(alpha: .45)),
          _SlotState.needed => null,
          _SlotState.optional => Border.all(color: Ep.whiteA(.12)),
        },
      ),
      child: state == _SlotState.needed
          ? DashedBox(padding: padding, color: Ep.whiteA(.3), child: child)
          : Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
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
            filled ? Ep.link : Ep.required,
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
                color: Ep.inkA(.35),
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
        tagColor: app.gfDate == null ? Ep.required : Ep.link,
        value: app.gfDate == null ? 'Pick a date' : app.gfDateLabel.toUpperCase(),
        sub: app.gfDate == null ? '' : 'Doors ${app.gfDoorsLabel}',
        state: app.gfDate == null ? _SlotState.needed : _SlotState.done,
        onTap: () => showWhenSheet(context),
      ),
      _SlotCard(
        tag: venue == null ? 'VENUE · REQUIRED' : 'VENUE ✓',
        tagColor: venue == null ? Ep.required : Ep.link,
        value: venue?.name ?? 'Where is it',
        sub: venue?.area ?? '',
        state: venue == null ? _SlotState.needed : _SlotState.done,
        onTap: () => showVenueSheet(context),
      ),
      _SlotCard(
        tag: 'PRICE',
        tagColor: Ep.inkA(.5),
        value: app.gfPrice,
        sub: app.gfPrice == 'FREE'
            ? 'Free gigs pull bigger crowds'
            : 'At the door',
        state: _SlotState.optional,
        onTap: () => showPriceSheet(context),
      ),
      _SlotCard(
        tag: 'TICKETS',
        tagColor: Ep.inkA(.5),
        value: app.gfTix == Ticketing.rsvp ? 'In-app RSVP' : 'External link',
        sub: switch (app.gfTix) {
          Ticketing.rsvp when app.gfCap == 'No cap' => 'No cap · QR at the door',
          Ticketing.rsvp => 'Cap ${app.gfCap} · QR at the door',
          Ticketing.external =>
            app.gfExt.isEmpty ? 'Add your link' : app.gfExt,
        },
        state: _SlotState.optional,
        onTap: () => showTicketsSheet(context),
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
              color: state == _SlotState.needed ? Ep.inkA(.45) : Ep.ink,
            ),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(sub,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: epText(size: 10.5, color: Ep.inkA(.45))),
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
          colors: [Ep.bg.withValues(alpha: 0), Ep.bg],
          stops: const [0, .34],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            missing.isEmpty
                ? 'Ready — fans nearby see it the second you post.'
                : 'Still needs ${missing.join(' + ')}',
            textAlign: TextAlign.center,
            style: epText(
              size: 11,
              weight: FontWeight.w700,
              letterSpacing: .3,
              color: missing.isEmpty ? Ep.link : Ep.inkA(.5),
            ),
          ),
          const SizedBox(height: 9),
          // Disabled-looking but still tappable: it says what is missing.
          GestureDetector(
            onTap: app.publishGig,
            child: EpButton(
              'PUBLISH GIG',
              fontSize: 14,
              glow: app.canPublishGig,
              kind: app.canPublishGig
                  ? EpButtonKind.filled
                  : EpButtonKind.disabled,
              padding: const EdgeInsets.symmetric(vertical: 16),
              onTap: app.publishGig,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ sheets ============================

Future<void> _openSheet(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .6),
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: builder,
  );
}

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
        color: Ep.card,
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
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.close, size: 18, color: Ep.inkA(.5)),
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

InputDecoration _sheetInput(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: epText(size: 13, color: Ep.inkA(.35)),
  filled: true,
  fillColor: Ep.bg,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: Ep.whiteA(.16)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: Ep.whiteA(.3)),
  ),
);

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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? Ep.blue.withValues(alpha: .16) : Ep.bg,
          border: selected
              ? Border.all(color: Ep.blue, width: 1.5)
              : Border.all(color: Ep.whiteA(.14)),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titleCaps ? title.toUpperCase() : title,
              style: epText(size: 12.5, weight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: epText(size: 10.5, color: Ep.inkA(.5))),
          ],
        ),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton();

  @override
  Widget build(BuildContext context) {
    return EpButton(
      'DONE',
      fontSize: 12.5,
      padding: const EdgeInsets.symmetric(vertical: 14),
      onTap: () => Navigator.pop(context),
    );
  }
}

// ---------------------------- when ----------------------------

void showWhenSheet(BuildContext context) {
  _openSheet(context, (ctx) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .82),
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
            border: Border(top: BorderSide(color: Ep.whiteA(.09))),
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
                      color: Ep.inkA(.5),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: app.gfDoors,
                      );
                      if (picked != null) app.setGfDoors(picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Ep.bg,
                        border: Border.all(color: Ep.whiteA(.16)),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        app.gfDoorsLabel,
                        style: epText(size: 12.5, weight: FontWeight.w800),
                      ),
                    ),
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
                        label: 'DOORS ${timeLabel(TimeOfDay(hour: hour, minute: 0))}',
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
              const _DoneButton(),
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
      if (day < 1 || day > days) return const SizedBox(height: 34);
      final date = DateTime(first.year, first.month, day);
      final past = date.isBefore(today);
      final selected = date == app.gfDate;

      return GestureDetector(
        onTap: past ? null : () => app.setGfDate(date),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: past
                ? null
                : selected
                ? Ep.blue
                : Ep.bg,
            border: past
                ? null
                : Border.all(
                    color: selected
                        ? Ep.blue
                        : date == today
                        ? Ep.link.withValues(alpha: .55)
                        : Ep.whiteA(.1),
                  ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$day',
            style: epText(
              size: 12,
              weight: FontWeight.w800,
              color: past
                  ? Ep.inkA(.16)
                  : selected
                  ? Colors.white
                  : Ep.inkA(.8),
            ),
          ),
        ),
      );
    }

    Widget grid(int row, Widget Function(int) child) => Row(
      children: [
        for (var column = 0; column < 7; column++) ...[
          if (column > 0) const SizedBox(width: 5),
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
            color: Ep.inkA(.45),
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
              color: Ep.inkA(.3),
            ),
          ),
        ),
        const SizedBox(height: 5),
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) const SizedBox(height: 5),
          grid(row, cell),
        ],
      ],
    );
  }
}

// ---------------------------- venue ----------------------------

void showVenueSheet(BuildContext context) {
  final app = context.read<AppState>();
  _openSheet(context, (ctx) {
    return _Sheet(
      title: 'Where is it',
      trailing: GestureDetector(
        onTap: () {
          Navigator.pop(ctx);
          app.say('New venue form placeholder — it becomes a shared record.');
        },
        child: Text(
          '+ NEW VENUE',
          style: epText(
            size: 11,
            weight: FontWeight.w900,
            letterSpacing: .6,
            color: Ep.link,
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * .6,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'Venues are shared records — the address stays consistent across '
              "every band's listings.",
              style: epText(size: 10.5, color: Ep.inkA(.4), height: 1.45),
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
  _openSheet(context, (_) => const _Sheet(title: 'Cover', child: _PriceBody()));
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
            color: isCustom ? Ep.blue.withValues(alpha: .16) : Ep.bg,
            border: isCustom
                ? Border.all(color: Ep.blue, width: 1.5)
                : Border.all(color: Ep.whiteA(.14)),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              Text('\$', style: epDisplay(size: 19, color: Ep.inkA(.6))),
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
                      color: Ep.inkA(.35),
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
                  color: Ep.inkA(.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Free gigs get roughly twice the RSVPs. Sliding scale? Put the range '
          'in the gig name.',
          style: epText(size: 10.5, color: Ep.inkA(.4), height: 1.45),
        ),
      ],
    );
  }
}

// ---------------------------- tickets ----------------------------

const _presetCaps = ['No cap', '50', '100', '150'];

void showTicketsSheet(BuildContext context) {
  _openSheet(
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
                    color: capIsCustom ? Ep.blue.withValues(alpha: .16) : Ep.bg,
                    border: capIsCustom
                        ? Border.all(color: Ep.blue, width: 1.5)
                        : Border.all(color: Ep.whiteA(.14)),
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
                              color: Ep.inkA(.35),
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
                          color: Ep.inkA(.4),
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
              decoration: _sheetInput('https://…'),
            ),
          ),
        const SizedBox(height: 14),
        const _DoneButton(),
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
      color: Ep.bg,
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
                  color: Ep.link,
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
              Text(app.gigUrl, style: epText(size: 12, color: Ep.inkA(.55))),
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
                        onTap: () => app.say('Link copied — ${app.gigUrl}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: EpButton(
                        'DOOR QR',
                        kind: EpButtonKind.ghost,
                        fontSize: 11.5,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        onTap: () => app.say('Door QR saved to photos (demo)'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: app.editPublishedGig,
                    child: Text(
                      'KEEP EDITING',
                      style: epText(
                        size: 11,
                        weight: FontWeight.w800,
                        letterSpacing: .6,
                        color: Ep.inkA(.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  GestureDetector(
                    onTap: app.makeAnotherGig,
                    child: Text(
                      'MAKE ANOTHER',
                      style: epText(
                        size: 11,
                        weight: FontWeight.w800,
                        letterSpacing: .6,
                        color: Ep.link,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: app.closeGigCreate,
                child: Text(
                  'BACK TO GIGS',
                  style: epText(
                    size: 11,
                    weight: FontWeight.w800,
                    letterSpacing: .6,
                    color: Ep.inkA(.35),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
