import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../genres.dart';
import '../services/media_picker.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _tapeTilt = -1.2 * math.pi / 180;

/// Permanent Marker — the hand-written tape-label voice of this screen.
TextStyle _marker({double size = 13, Color color = Ep.ink, double? height}) =>
    GoogleFonts.permanentMarker(fontSize: size, color: color, height: height);

Future<void> _pickBandPhoto(BuildContext context) async {
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
  app.setNbPhoto(picked);
}

// ============================ label styles ============================

enum _LabelTexture { none, scan, dots, diagonal }

/// One cassette-label finish: base paper, ink color, and a print texture.
/// The texture prints faint on the label and boosted on its 30px swatch.
class _TapeLabel {
  final Color base;
  final Color? baseBottom; // amber's top-to-bottom fade
  final Color fg;
  final _LabelTexture texture;
  final Color labelInk;
  final Color swatchInk;

  const _TapeLabel({
    required this.base,
    this.baseBottom,
    required this.fg,
    this.texture = _LabelTexture.none,
    this.labelInk = Colors.transparent,
    this.swatchInk = Colors.transparent,
  });
}

const _labels = <String, _TapeLabel>{
  'cream': _TapeLabel(
    base: Color(0xFFEFEADC),
    fg: Color(0xFF111114),
    texture: _LabelTexture.scan,
    labelInk: Color(0x0B000000),
    swatchInk: Color(0x24000000),
  ),
  'riso': _TapeLabel(
    base: Color(0xFFF4F4F0),
    fg: Ep.blue,
    texture: _LabelTexture.dots,
    labelInk: Color(0x66F0456B),
    swatchInk: Color(0xBFF0456B),
  ),
  'amber': _TapeLabel(
    base: Color(0xFFE4DC4A),
    baseBottom: Color(0xFFD8C93A),
    fg: Color(0xFF141418),
  ),
  'ink': _TapeLabel(
    base: Color(0xFF17171B),
    fg: Ep.ink,
    texture: _LabelTexture.scan,
    labelInk: Color(0x0DFFFFFF),
    swatchInk: Color(0x29FFFFFF),
  ),
  'blue': _TapeLabel(
    base: Ep.blue,
    fg: Ep.ink,
    texture: _LabelTexture.diagonal,
    labelInk: Color(0x12FFFFFF),
    swatchInk: Color(0x38FFFFFF),
  ),
};

class _LabelPainter extends CustomPainter {
  final _TapeLabel label;
  final bool swatch;

  const _LabelPainter(this.label, {this.swatch = false});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (label.baseBottom case final bottom?) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [label.base, bottom],
          ).createShader(rect),
      );
    } else {
      canvas.drawRect(rect, Paint()..color = label.base);
    }

    final ink = Paint()..color = swatch ? label.swatchInk : label.labelInk;
    switch (label.texture) {
      case _LabelTexture.none:
        break;
      case _LabelTexture.scan:
        final pitch = swatch ? 4.0 : 5.0;
        for (double y = 0; y < size.height; y += pitch) {
          canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), ink);
        }
      case _LabelTexture.dots:
        final pitch = swatch ? 5.0 : 6.0;
        for (double y = 1; y < size.height; y += pitch) {
          for (double x = 1; x < size.width; x += pitch) {
            canvas.drawCircle(Offset(x, y), 1.2, ink);
          }
        }
      case _LabelTexture.diagonal:
        final stripe = swatch ? 4.0 : 7.0;
        ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = stripe;
        for (double d = -size.height; d < size.width; d += stripe * 2) {
          canvas.drawLine(
            Offset(d + size.height, 0),
            Offset(d, size.height),
            ink,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_LabelPainter old) =>
      old.label != label || old.swatch != swatch;
}

// ============================ screen ============================

/// Band creation as filling in a cassette: the tape is the form.
class BandCreateScreen extends StatefulWidget {
  const BandCreateScreen({super.key});

  @override
  State<BandCreateScreen> createState() => _BandCreateScreenState();
}

class _BandCreateScreenState extends State<BandCreateScreen> {
  final _tapeName = TextEditingController();
  final _lineName = TextEditingController();
  final _tapeFocus = FocusNode();
  final _lineFocus = FocusNode();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The name is editable in two places — whichever field is idle follows.
    final name = context.read<AppState>().nbName;
    for (final (controller, focus) in [
      (_tapeName, _tapeFocus),
      (_lineName, _lineFocus),
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
    _tapeName.dispose();
    _lineName.dispose();
    _tapeFocus.dispose();
    _lineFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.nbCreated) return const _CreatedView();

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
                  CircleIconButton(icon: Icons.close, onTap: app.back),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('START A BAND', style: epDisplay(size: 16)),
                  ),
                  _ReadyPill(ready: app.canCreateBand),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 150),
                children: [
                  _TapeHero(nameController: _tapeName, nameFocus: _tapeFocus),
                  _LinerNotes(nameController: _lineName, nameFocus: _lineFocus),
                ],
              ),
            ),
          ],
        ),
        const Positioned(left: 0, right: 0, bottom: 0, child: _CreateBar()),
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

// ============================ the tape ============================

/// Photo inlay behind the cassette, the cassette itself, label swatches, hint.
class _TapeHero extends StatelessWidget {
  final TextEditingController nameController;
  final FocusNode nameFocus;

  const _TapeHero({required this.nameController, required this.nameFocus});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 176,
          child: _InlaySlot(photo: app.nbPhoto),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 26, 16, 34),
          child: Column(
            children: [
              Center(
                child: _Cassette(
                  nameController: nameController,
                  nameFocus: nameFocus,
                ),
              ),
              const SizedBox(height: 13),
              const _SwatchRow(),
              const SizedBox(height: 13),
              SizedBox(
                width: 262,
                child: Text(
                  app.nbPhoto != null
                      ? 'Photo sits behind the tape — drop one in above.'
                      : 'Type on the label, tap the marker lines, or work the '
                            'notes below.',
                  textAlign: TextAlign.center,
                  style: epText(
                    size: 10.5,
                    weight: FontWeight.w600,
                    color: Ep.inkA(.45),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The strip behind the tape: a photo drop zone, or a soft blue glow.
class _InlaySlot extends StatelessWidget {
  final PickedMedia? photo;

  const _InlaySlot({required this.photo});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final picked = photo;
    if (picked == null) {
      return GestureDetector(
        // Opaque so the whole slot hits, not just the icon/text pixels.
        behavior: HitTestBehavior.opaque,
        onTap: () => _pickBandPhoto(context),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFF101014),
            gradient: RadialGradient(
              center: Alignment(0, -1),
              radius: 1.1,
              colors: [Color(0x381435F0), Colors.transparent],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 22,
                  color: Ep.inkA(.45),
                ),
                const SizedBox(height: 6),
                Text(
                  'DROP A BAND PHOTO',
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
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: const Color(0xFF101014),
          foregroundDecoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0A0A0C).withValues(alpha: .55),
                const Color(0xFF0A0A0C).withValues(alpha: .94),
              ],
            ),
          ),
          child: Image.memory(picked.bytes, fit: BoxFit.cover),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            key: const ValueKey('clear-band-photo'),
            onTap: () => app.setNbPhoto(null),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .72),
                shape: BoxShape.circle,
                border: Border.all(color: Ep.whiteA(.3)),
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// The cassette. In the editor the label is live; the created view shows it
/// finished with both reels wound.
class _Cassette extends StatelessWidget {
  final TextEditingController? nameController;
  final FocusNode? nameFocus;
  final double maxWidth;

  const _Cassette({this.nameController, this.nameFocus, this.maxWidth = 334});

  bool get _editable => nameController != null;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final label = _labels[app.nbLabel] ?? _labels.values.first;
    final genreLine = app.nbGenres.join(' · ');

    final smallStamp = epText(
      size: 8.5,
      weight: FontWeight.w900,
      letterSpacing: 1.7,
      color: label.fg.withValues(alpha: .6),
    );
    final markerLine = _marker(
      size: 13,
      color: label.fg.withValues(alpha: .85),
    );

    // Wind the reels toward the right as the form fills.
    final frac = app.nbCompletion;
    final wound = (frac * 16).round();
    final (discLeft, discRight) = _editable
        ? (31.0 - wound, 15.0 + wound)
        : (24.0, 24.0);

    final labelBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('SIDE A · DEMO', style: smallStamp),
            Text(app.nbArea?.toUpperCase() ?? 'HOME TAPING', style: smallStamp),
          ],
        ),
        const SizedBox(height: 7),
        if (_editable)
          TextField(
            controller: nameController,
            focusNode: nameFocus,
            onChanged: app.setNbName,
            minLines: 1,
            maxLines: 2,
            cursorColor: label.fg,
            style: _marker(size: 27, color: label.fg, height: 1.06),
            decoration: InputDecoration.collapsed(
              hintText: 'band name',
              hintStyle: _marker(
                size: 27,
                color: label.fg.withValues(alpha: .32),
                height: 1.06,
              ),
            ),
          )
        else
          Text(
            app.nbName,
            style: _marker(size: 27, color: label.fg, height: 1.06),
          ),
        const SizedBox(height: 7),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _editable ? () => showSoundSheet(context) : null,
                    child: Text(
                      genreLine.isEmpty ? 'what do you sound like?' : genreLine,
                      style: markerLine,
                    ),
                  ),
                  const SizedBox(height: 3),
                  GestureDetector(
                    onTap: _editable ? () => showHomeBaseSheet(context) : null,
                    child: Text(
                      app.nbArea ?? 'where are you from?',
                      style: markerLine,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _Reel(disc: discLeft, color: label.fg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Container(
                height: 1.5,
                width: 14,
                color: label.fg.withValues(alpha: .35),
              ),
            ),
            _Reel(disc: discRight, color: label.fg),
          ],
        ),
      ],
    );

    return Transform.rotate(
      angle: _tapeTilt,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E1E24), Color(0xFF121216)],
          ),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Ep.whiteA(.16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .6),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: CustomPaint(
                painter: _LabelPainter(label),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
                  child: labelBody,
                ),
              ),
            ),
            if (_editable)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      frac == 1 ? 'FULL TAPE' : 'TAPE FILLS AS YOU GO',
                      style: epText(
                        size: 8.5,
                        weight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: Ep.inkA(.4),
                      ),
                    ),
                    Text(
                      '${(frac * 100).round()}%',
                      style: epText(
                        size: 8.5,
                        weight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: Ep.link,
                      ),
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

class _Reel extends StatelessWidget {
  final double disc;
  final Color color;

  const _Reel({required this.disc, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: .75), width: 1.5),
      ),
      child: Container(
        width: disc,
        height: disc,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: .6),
        ),
      ),
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
        for (final MapEntry(key: key, value: label) in _labels.entries) ...[
          _Swatch(
            key: ValueKey('label-$key'),
            selected: app.nbLabel == key,
            onTap: () => app.setNbLabel(key),
            child: ClipOval(
              child: CustomPaint(
                painter: _LabelPainter(label, swatch: true),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(width: 9),
        ],
        _Swatch(
          key: const ValueKey('label-photo'),
          selected: app.nbPhoto != null,
          dashed: true,
          onTap: () => _pickBandPhoto(context),
          child: Center(
            child: Icon(
              app.nbPhoto != null ? Icons.check : Icons.arrow_upward,
              size: 13,
              color: Ep.link,
            ),
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

// ============================ liner notes ============================

enum _LineState { required, done, optional }

Color _numColor(_LineState state) => switch (state) {
  _LineState.required => Ep.required,
  _LineState.done => Ep.link,
  _LineState.optional => Ep.inkA(.3),
};

Color _labelColor(_LineState state) => switch (state) {
  _LineState.required => Ep.required,
  _LineState.done => Ep.link,
  _LineState.optional => Ep.inkA(.45),
};

String _lineLabel(String label, _LineState state) => switch (state) {
  _LineState.required => '$label · REQUIRED',
  _LineState.done => '$label ✓',
  _LineState.optional => label,
};

class _LinerNotes extends StatelessWidget {
  final TextEditingController nameController;
  final FocusNode nameFocus;

  const _LinerNotes({required this.nameController, required this.nameFocus});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    final bio = app.nbBio.trim();
    final crew = 1 + app.nbInvites.length;
    final inviteCount = app.nbInvites.length;
    final links = [
      if (app.nbIg.trim().isNotEmpty) 'Instagram',
      if (app.nbBc.trim().isNotEmpty) 'Bandcamp',
      if (app.nbYt.trim().isNotEmpty) 'YouTube',
    ];

    final lines = [
      _LinerLine(
        num: '02',
        label: 'SOUND',
        state: app.nbGenres.isEmpty ? _LineState.required : _LineState.done,
        value: app.nbGenres.isEmpty
            ? 'Pick your genres'
            : app.nbGenres.join(' · ').toUpperCase(),
        sub: app.nbGenres.isEmpty
            ? 'Up to three'
            : '${app.nbGenres.length} of 3',
        onTap: () => showSoundSheet(context),
      ),
      _LinerLine(
        num: '03',
        label: 'HOME BASE',
        state: app.nbArea == null ? _LineState.required : _LineState.done,
        value: app.nbArea ?? 'Where are you from',
        sub: app.nbArea == null
            ? 'Neighborhood or city'
            : 'Shows in nearby feeds',
        onTap: () => showHomeBaseSheet(context),
      ),
      _LinerLine(
        num: '04',
        label: 'SLEEVE NOTES',
        state: bio.isEmpty ? _LineState.optional : _LineState.done,
        value: bio.isEmpty
            ? 'Two sentences'
            : (bio.length > 46 ? '${bio.substring(0, 46)}…' : bio),
        sub: bio.isEmpty
            ? 'Optional, but fans read it'
            : '${bio.length} characters',
        onTap: () => showSleeveNotesSheet(context),
      ),
      _LinerLine(
        num: '05',
        label: 'CREDITS',
        state: inviteCount == 0 ? _LineState.optional : _LineState.done,
        value: crew == 1 ? 'Just you' : '$crew people',
        sub: inviteCount == 0
            ? 'Invite bandmates anytime'
            : '$inviteCount invite${inviteCount > 1 ? 's' : ''} pending',
        onTap: () => showCreditsSheet(context),
      ),
      _LinerLine(
        num: '06',
        label: 'LINKS',
        state: links.isEmpty ? _LineState.optional : _LineState.done,
        value: links.isEmpty ? 'Add your music' : links.join(' · '),
        sub: links.isEmpty ? 'Bandcamp, IG, YouTube' : 'Shown on your profile',
        onTap: () => showLinksSheet(context),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'liner notes',
                  style: _marker(size: 15, color: Ep.inkA(.75)),
                ),
              ),
              Text(
                'TAP ANY LINE · ANY ORDER',
                style: epText(
                  size: 9.5,
                  weight: FontWeight.w900,
                  letterSpacing: 1.3,
                  color: Ep.inkA(.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Ep.whiteA(.1))),
            ),
            child: Column(
              children: [
                _NameLine(controller: nameController, focusNode: nameFocus),
                ...lines,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NameLine extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _NameLine({required this.controller, required this.focusNode});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final filled = app.nbName.trim().isNotEmpty;
    final state = filled ? _LineState.done : _LineState.required;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Ep.whiteA(.1))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '01',
              style: _marker(size: 15, color: _numColor(state)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lineLabel('BAND NAME', state),
                  style: epText(
                    size: 9.5,
                    weight: FontWeight.w900,
                    letterSpacing: 1.3,
                    color: _labelColor(state),
                  ),
                ),
                const SizedBox(height: 2),
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: app.setNbName,
                  style: epText(size: 14.5, weight: FontWeight.w800),
                  decoration: InputDecoration.collapsed(
                    hintText: 'e.g. Static Bloom',
                    hintStyle: epText(
                      size: 14.5,
                      weight: FontWeight.w800,
                      color: Ep.inkA(.35),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  filled
                      ? 'earplug.app/${app.nbShareSlug}'
                      : 'Your profile URL comes from this',
                  style: epText(size: 10, color: Ep.inkA(.4)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinerLine extends StatelessWidget {
  final String num;
  final String label;
  final _LineState state;
  final String value;
  final String sub;
  final VoidCallback onTap;

  const _LinerLine({
    required this.num,
    required this.label,
    required this.state,
    required this.value,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Ep.whiteA(.1))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text(
                num,
                style: _marker(size: 15, color: _numColor(state)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _lineLabel(label, state),
                    style: epText(
                      size: 9.5,
                      weight: FontWeight.w900,
                      letterSpacing: 1.3,
                      color: _labelColor(state),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: epText(
                      size: 14.5,
                      weight: FontWeight.w800,
                      color: state == _LineState.required
                          ? Ep.inkA(.42)
                          : Ep.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(sub, style: epText(size: 10, color: Ep.inkA(.4))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('›', style: epText(size: 16, color: Ep.inkA(.3))),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================ create bar ============================

class _CreateBar extends StatelessWidget {
  const _CreateBar();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final missing = app.bandMissing;
    final live = app.canCreateBand && !app.nbSaving;
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
            missing.isNotEmpty
                ? 'Still needs ${missing.join(' + ')}'
                : app.nbEditingCreated
                ? 'Your band is live — saving updates it.'
                : 'Ready — you can post a gig the moment this lands.',
            textAlign: TextAlign.center,
            style: epText(
              size: 11,
              weight: FontWeight.w700,
              color: missing.isEmpty ? Ep.link : Ep.inkA(.5),
            ),
          ),
          const SizedBox(height: 9),
          // The wrapper owns the tap; EpButton only renders. That way an
          // unready press still lands here and says what is missing, instead
          // of being swallowed by a disabled button.
          GestureDetector(
            onTap: app.nbSaving ? null : app.createBand,
            child: EpButton(
              app.nbSaving
                  ? 'SAVING…'
                  : app.nbEditingCreated
                  ? 'SAVE CHANGES'
                  : 'CREATE BAND',
              fontSize: 14,
              glow: live,
              kind: live ? EpButtonKind.filled : EpButtonKind.disabled,
              padding: const EdgeInsets.symmetric(vertical: 16),
              onTap: null,
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
  final Widget child;

  const _Sheet({required this.title, required this.child});

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
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(title.toUpperCase(), style: epDisplay(size: 15)),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close, size: 18, color: Ep.inkA(.5)),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 34),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _sheetInput(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: epText(size: 12.5, color: Ep.inkA(.35)),
  filled: true,
  fillColor: Ep.bg,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: BorderSide(color: Ep.whiteA(.16)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: BorderSide(color: Ep.whiteA(.3)),
  ),
);

class _SheetHint extends StatelessWidget {
  final String text;

  const _SheetHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: epText(size: 10.5, color: Ep.inkA(.4), height: 1.45),
    );
  }
}

/// Input plus a filled action button — the "add one of your own" row.
class _DraftRow extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String action;
  final VoidCallback onSubmit;

  const _DraftRow({
    required this.controller,
    required this.hint,
    required this.action,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onSubmitted: (_) => onSubmit(),
            style: epText(size: 12.5),
            decoration: _sheetInput(hint),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSubmit,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: Ep.blue,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              action,
              style: epText(
                size: 11.5,
                weight: FontWeight.w900,
                letterSpacing: .7,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
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

// ---------------------------- sound ----------------------------

void showSoundSheet(BuildContext context) {
  _openSheet(context, (_) => const _Sheet(title: 'Sound', child: _SoundBody()));
}

class _SoundBody extends StatefulWidget {
  const _SoundBody();

  @override
  State<_SoundBody> createState() => _SoundBodyState();
}

class _SoundBodyState extends State<_SoundBody> {
  final _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _add() {
    context.read<AppState>().addNbGenre(_draft.text);
    _draft.clear();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final all = [
      ...kGenres,
      ...app.nbGenres.where((g) => !kGenres.contains(g)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SheetHint('Up to three — this is what fans filter by.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final genre in all)
              EpChip(
                label: genre,
                active: app.nbGenres.contains(genre),
                onTap: () => app.toggleNbGenre(genre),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _DraftRow(
          controller: _draft,
          hint: 'Something else…',
          action: 'ADD',
          onSubmit: _add,
        ),
        const SizedBox(height: 12),
        const _DoneButton(),
      ],
    );
  }
}

// ---------------------------- home base ----------------------------

void showHomeBaseSheet(BuildContext context) {
  _openSheet(
    context,
    (ctx) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * .74,
      ),
      child: const _Sheet(title: 'Home base', child: _HomeBaseBody()),
    ),
  );
}

class _HomeBaseBody extends StatefulWidget {
  const _HomeBaseBody();

  @override
  State<_HomeBaseBody> createState() => _HomeBaseBodyState();
}

class _HomeBaseBodyState extends State<_HomeBaseBody> {
  final _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _set() {
    if (_draft.text.trim().isEmpty) return;
    context.read<AppState>().setNbArea(_draft.text);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SheetHint('Fans browsing nearby see you first.'),
        for (final area in app.knownAreas) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              app.setNbArea(area.name);
              Navigator.pop(context);
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: app.nbArea == area.name
                    ? Ep.blue.withValues(alpha: .16)
                    : Ep.bg,
                border: app.nbArea == area.name
                    ? Border.all(color: Ep.blue, width: 1.5)
                    : Border.all(color: Ep.whiteA(.14)),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    area.name.toUpperCase(),
                    style: epText(size: 12.5, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(area.sub, style: epText(size: 10.5, color: Ep.inkA(.5))),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        _DraftRow(
          controller: _draft,
          hint: 'Another neighborhood or city',
          action: 'SET',
          onSubmit: _set,
        ),
      ],
    );
  }
}

// ---------------------------- sleeve notes ----------------------------

const _bioStarters = [
  'Two amps facing each other, one long argument. You will hear it in your '
      'teeth.',
  'Fast, short, gone. Sets under 20 minutes, guaranteed.',
  'Reverb-soaked garage punk from a basement that actually floods.',
];

void showSleeveNotesSheet(BuildContext context) {
  _openSheet(
    context,
    (_) => const _Sheet(title: 'Sleeve notes', child: _SleeveNotesBody()),
  );
}

class _SleeveNotesBody extends StatefulWidget {
  const _SleeveNotesBody();

  @override
  State<_SleeveNotesBody> createState() => _SleeveNotesBodyState();
}

class _SleeveNotesBodyState extends State<_SleeveNotesBody> {
  late final TextEditingController _bio;

  @override
  void initState() {
    super.initState();
    _bio = TextEditingController(text: context.read<AppState>().nbBio);
  }

  @override
  void dispose() {
    _bio.dispose();
    super.dispose();
  }

  void _useStarter() {
    final starter = _bioStarters[math.Random().nextInt(_bioStarters.length)];
    _bio.value = TextEditingValue(
      text: starter,
      selection: TextSelection.collapsed(offset: starter.length),
    );
    context.read<AppState>().setNbBio(starter);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final count = app.nbBio.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _bio,
          onChanged: app.setNbBio,
          minLines: 4,
          maxLines: 6,
          style: epText(size: 13.5, height: 1.5),
          decoration: _sheetInput('What do you sound like, where do you play?'),
        ),
        const SizedBox(height: 11),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SheetHint('$count characters${count > 180 ? ' — trim it' : ''}'),
            GestureDetector(
              onTap: _useStarter,
              child: Text(
                'USE A STARTER LINE',
                style: epText(
                  size: 10.5,
                  weight: FontWeight.w900,
                  letterSpacing: .6,
                  color: Ep.link,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        const _DoneButton(),
      ],
    );
  }
}

// ---------------------------- credits ----------------------------

/// "@mara.k" → "MA"; degrades gracefully for one-character handles.
String _handleInitials(String handle) {
  final bare = handle.replaceFirst('@', '');
  return bare.substring(0, math.min(2, bare.length)).toUpperCase();
}

void showCreditsSheet(BuildContext context) {
  _openSheet(
    context,
    (_) => const _Sheet(title: 'Credits', child: _CreditsBody()),
  );
}

class _CreditsBody extends StatefulWidget {
  const _CreditsBody();

  @override
  State<_CreditsBody> createState() => _CreditsBodyState();
}

class _CreditsBodyState extends State<_CreditsBody> {
  final _handle = TextEditingController();

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  void _invite() {
    context.read<AppState>().addNbInvite(_handle.text);
    _handle.clear();
  }

  Widget _memberRow({
    required Widget avatar,
    required String name,
    required Widget trailing,
    Color? borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Ep.bg,
        border: Border.all(color: borderColor ?? Ep.whiteA(.1)),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 10),
          Expanded(
            child: Text(name, style: epText(size: 13, weight: FontWeight.w700)),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _avatar(String text, {Color? color}) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? Ep.whiteA(.12),
        shape: BoxShape.circle,
      ),
      child: Text(text, style: epText(size: 11, weight: FontWeight.w800)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final adminName = app.profile?.name.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SheetHint(
          "You're admin. Members can post gigs and media. Invites can wait — "
          'the band works solo.',
        ),
        const SizedBox(height: 10),
        _DraftRow(
          controller: _handle,
          hint: '@username',
          action: 'INVITE',
          onSubmit: _invite,
        ),
        const SizedBox(height: 10),
        _memberRow(
          avatar: _avatar(
            adminName == null || adminName.isEmpty
                ? 'YOU'
                : profileInitials(adminName),
            color: Ep.link.withValues(alpha: .25),
          ),
          name: adminName == null || adminName.isEmpty ? 'You' : adminName,
          borderColor: Ep.link.withValues(alpha: .35),
          trailing: Text(
            'ADMIN',
            style: epText(
              size: 10,
              weight: FontWeight.w800,
              letterSpacing: .8,
              color: Ep.link,
            ),
          ),
        ),
        for (final handle in app.nbInvites) ...[
          const SizedBox(height: 10),
          _memberRow(
            avatar: _avatar(_handleInitials(handle)),
            name: handle,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'INVITED',
                  style: epText(
                    size: 10,
                    weight: FontWeight.w800,
                    letterSpacing: .8,
                    color: Ep.inkA(.45),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => app.removeNbInvite(handle),
                  child: Icon(Icons.close, size: 14, color: Ep.inkA(.4)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        const _JoinLink(),
      ],
    );
  }
}

/// The join link only becomes real when the server issues the slug. Before
/// that `nbShareSlug` is a client-side guess with no dedup, so a link copied
/// now can point at somebody else's band — the demo feed alone already has a
/// Static Bloom. So: no copy affordance until the tape lands.
class _JoinLink extends StatelessWidget {
  const _JoinLink();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (!app.nbEditingCreated) {
      return DashedBox(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        radius: 11,
        color: Ep.whiteA(.15),
        child: Text(
          'Your join link lands with the tape. Invites you add now go out the '
          'moment it does.',
          style: epText(size: 11, color: Ep.inkA(.42), height: 1.45),
        ),
      );
    }

    final url = 'earplug.app/join/${app.nbShareSlug}';
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: 'https://$url'));
        app.say('Join link copied — $url');
      },
      child: DashedBox(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        radius: 11,
        color: Ep.whiteA(.25),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                url,
                overflow: TextOverflow.ellipsis,
                style: epText(
                  size: 12,
                  weight: FontWeight.w700,
                  color: Ep.inkA(.7),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'COPY LINK',
              style: epText(
                size: 10.5,
                weight: FontWeight.w900,
                letterSpacing: .8,
                color: Ep.link,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------- links ----------------------------

void showLinksSheet(BuildContext context) {
  _openSheet(
    context,
    (_) => const _Sheet(title: 'Where to hear you', child: _LinksBody()),
  );
}

class _LinksBody extends StatefulWidget {
  const _LinksBody();

  @override
  State<_LinksBody> createState() => _LinksBodyState();
}

class _LinksBodyState extends State<_LinksBody> {
  late final TextEditingController _ig;
  late final TextEditingController _bc;
  late final TextEditingController _yt;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _ig = TextEditingController(text: app.nbIg);
    _bc = TextEditingController(text: app.nbBc);
    _yt = TextEditingController(text: app.nbYt);
  }

  @override
  void dispose() {
    _ig.dispose();
    _bc.dispose();
    _yt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final fields = [
      ('INSTAGRAM', '@yourband', _ig, app.setNbIg),
      ('BANDCAMP', 'yourband.bandcamp.com', _bc, app.setNbBc),
      ('YOUTUBE / VIDEO', 'youtube.com/@yourband', _yt, app.setNbYt),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (label, hint, controller, onChanged) in fields) ...[
          Text(
            label,
            style: epText(
              size: 9.5,
              weight: FontWeight.w900,
              letterSpacing: 1.2,
              color: Ep.inkA(.45),
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: epText(size: 12.5),
            decoration: _sheetInput(hint),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 2),
        const _DoneButton(),
      ],
    );
  }
}

// ============================ created ============================

class _CreatedView extends StatelessWidget {
  const _CreatedView();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // nbShareSlug is server-issued by now: unique, and stable across renames.
    final profileUrl = 'earplug.app/${app.nbShareSlug}';

    return ColoredBox(
      color: Ep.bg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "TAPE'S OUT",
                style: epText(
                  size: 10.5,
                  weight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Ep.link,
                ),
              ),
              const SizedBox(height: 18),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: .92, end: 1),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: const _Cassette(maxWidth: 320),
              ),
              if (app.nbPhotoUploading || app.nbPhotoError != null) ...[
                const SizedBox(height: 12),
                if (app.nbPhotoUploading)
                  Text(
                    'ADDING YOUR PHOTO…',
                    style: epText(
                      size: 11,
                      weight: FontWeight.w800,
                      letterSpacing: .6,
                      color: Ep.inkA(.5),
                    ),
                  )
                else
                  _QuietAction(
                    'RETRY PHOTO',
                    onTap: app.retryNbPhoto,
                    color: Ep.link,
                  ),
              ],
              const SizedBox(height: 18),
              Text("You're on the map.", style: epDisplay(size: 20)),
              const SizedBox(height: 4),
              Text(profileUrl, style: epText(size: 12, color: Ep.inkA(.55))),
              const SizedBox(height: 18),
              SizedBox(
                width: 300,
                child: Row(
                  children: [
                    Expanded(
                      child: EpButton(
                        'POST FIRST GIG',
                        fontSize: 11.5,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        onTap: app.postFirstGig,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: EpButton(
                        'SHARE PROFILE',
                        kind: EpButtonKind.ghost,
                        fontSize: 11.5,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: 'https://$profileUrl'),
                          );
                          app.say('Link copied — $profileUrl');
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Wrap, not Row: three labels at this size crowd a narrow phone.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 18,
                runSpacing: 10,
                children: [
                  _QuietAction(
                    'KEEP EDITING',
                    onTap: app.editCreatedBand,
                    color: Ep.inkA(.5),
                  ),
                  _QuietAction(
                    'GO TO BAND',
                    onTap: app.openCreatedBand,
                    color: Ep.inkA(.5),
                  ),
                  _QuietAction(
                    'START ANOTHER',
                    onTap: app.makeAnotherBand,
                    color: Ep.link,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the created view's low-key text actions, under the loud pair.
class _QuietAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _QuietAction(this.label, {required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: epText(
          size: 11,
          weight: FontWeight.w800,
          letterSpacing: .6,
          color: color,
        ),
      ),
    );
  }
}
