import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../band_media_state.dart';
import '../genres.dart';
import '../services/media_picker.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';

/// Permanent Marker gives the screen its hand-written tape-label voice.
TextStyle _marker({
  double size = 13,
  Color color = Ep.contentPrimary,
  double? height,
}) => TextStyle(
  fontFamily: 'Permanent Marker',
  fontSize: size,
  color: color,
  height: height,
);

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
    fg: Ep.brand,
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
    fg: Ep.contentPrimary,
    texture: _LabelTexture.scan,
    labelInk: Color(0x0DFFFFFF),
    swatchInk: Color(0x29FFFFFF),
  ),
  'blue': _TapeLabel(
    base: Ep.brand,
    fg: Ep.contentPrimary,
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
  final _lineName = TextEditingController();
  final _lineFocus = FocusNode();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final name = context.read<AppState>().nbName;
    if (_lineFocus.hasFocus || _lineName.text == name) return;
    _lineName.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
  }

  @override
  void dispose() {
    _lineName.dispose();
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
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Ep.border)),
              ),
              child: Row(
                children: [
                  CircleIconButton(icon: Icons.close, onTap: app.back),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('START A BAND', style: epDisplay(size: 16)),
                  ),
                  ReadyPill(ready: app.canCreateBand),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 150),
                children: [
                  const _TapeHero(),
                  _ProfileDetails(
                    nameController: _lineName,
                    nameFocus: _lineFocus,
                  ),
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

// ============================ the tape ============================

/// Photo inlay behind the cassette, the cassette itself, label swatches, hint.
class _TapeHero extends StatelessWidget {
  const _TapeHero();

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
              const Center(child: _Cassette()),
              const SizedBox(height: 13),
              const _SwatchRow(),
              if (app.nbPhoto != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => _pickBandPhoto(context),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('CHANGE PHOTO'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('clear-band-photo'),
                      onPressed: () => app.setNbPhoto(null),
                      icon: const Icon(Icons.close),
                      label: const Text('REMOVE PHOTO'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 13),
              SizedBox(
                width: 262,
                child: Text(
                  app.nbPhoto != null
                      ? 'Photo sits behind the tape as a preview.'
                      : 'Use the standard fields below; the tape previews '
                            'your profile as you go.',
                  textAlign: TextAlign.center,
                  style: epText(
                    size: 10.5,
                    weight: FontWeight.w600,
                    color: Ep.contentDisabled,
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

/// The strip behind the tape is an upright, non-interactive preview.
class _InlaySlot extends StatelessWidget {
  final PickedMedia? photo;

  const _InlaySlot({required this.photo});

  @override
  Widget build(BuildContext context) {
    final picked = photo;
    if (picked == null) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: Ep.surface,
          gradient: RadialGradient(
            center: Alignment(0, -1),
            radius: 1.1,
            colors: [Ep.surfaceSelected, Colors.transparent],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.photo_outlined,
                size: 22,
                color: Ep.contentSecondary,
              ),
              const SizedBox(height: 6),
              Text(
                'BAND PHOTO PREVIEW',
                style: Theme.of(
                  context,
                ).textTheme.epLabel.copyWith(color: Ep.contentSecondary),
              ),
            ],
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
      ],
    );
  }
}

/// The cassette. In the editor the label is live; the created view shows it
/// finished with both reels wound.
class _Cassette extends StatelessWidget {
  final double maxWidth;

  const _Cassette({this.maxWidth = 334});

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
    final (discLeft, discRight) = (31.0 - wound, 15.0 + wound);

    final labelBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('SIDE A · SAMPLE', style: smallStamp),
            Text(
              app.nbArea?.toUpperCase() ?? 'SET HOME BASE',
              style: smallStamp,
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          app.nbName.trim().isEmpty ? 'band name' : app.nbName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
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
                  Text(
                    genreLine.isEmpty ? 'what do you sound like?' : genreLine,
                    style: markerLine,
                  ),
                  const SizedBox(height: 3),
                  Text(app.nbArea ?? 'where are you from?', style: markerLine),
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

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
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
                      color: Ep.contentSecondary,
                    ),
                  ),
                  Text(
                    '${(frac * 100).round()}%',
                    style: epText(
                      size: 8.5,
                      weight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: Ep.accent,
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
          Swatch(
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
        Swatch(
          key: const ValueKey('label-photo'),
          selected: app.nbPhoto != null,
          dashed: true,
          onTap: () => _pickBandPhoto(context),
          child: Center(
            child: Icon(
              app.nbPhoto != null ? Icons.check : Icons.arrow_upward,
              size: 13,
              color: Ep.accent,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================ profile details ============================

enum _LineState { required, done, optional }

Color _numColor(_LineState state) => switch (state) {
  _LineState.required => Ep.warning,
  _LineState.done => Ep.accent,
  _LineState.optional => Ep.contentDisabled,
};

Color _labelColor(_LineState state) => switch (state) {
  _LineState.required => Ep.warning,
  _LineState.done => Ep.accent,
  _LineState.optional => Ep.contentDisabled,
};

String _lineLabel(String label, _LineState state) => switch (state) {
  _LineState.required => '$label · REQUIRED',
  _LineState.done => '$label ✓',
  _LineState.optional => '$label · OPTIONAL',
};

class _ProfileDetails extends StatelessWidget {
  final TextEditingController nameController;
  final FocusNode nameFocus;

  const _ProfileDetails({
    required this.nameController,
    required this.nameFocus,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    final bio = app.nbBio.trim();
    final credits = app.nbCredits.trim();
    final links = [
      if (app.nbIg.trim().isNotEmpty) 'Instagram',
      if (app.nbBc.trim().isNotEmpty) 'Bandcamp',
      if (app.nbYt.trim().isNotEmpty) 'YouTube',
    ];

    final lines = [
      _ProfileLine(
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
      _ProfileLine(
        num: '03',
        label: 'HOME BASE',
        state: app.nbArea == null ? _LineState.required : _LineState.done,
        value: app.nbArea ?? 'Where are you from',
        sub: app.nbArea == null
            ? 'Neighborhood or city'
            : 'Shows in nearby feeds',
        onTap: () => showHomeBaseSheet(context),
      ),
      _ProfileLine(
        num: '04',
        label: 'PROFILE IMAGE',
        state: app.nbPhoto == null ? _LineState.optional : _LineState.done,
        value: app.nbPhoto == null ? 'Add a band photo' : 'Photo selected',
        sub: app.nbPhoto == null
            ? 'Optional; you can add one later'
            : 'Shown across your profile',
        onTap: () => _pickBandPhoto(context),
      ),
      _ProfileLine(
        num: '05',
        label: 'SHORT BIO',
        state: bio.isEmpty ? _LineState.optional : _LineState.done,
        value: bio.isEmpty
            ? 'Tell fans about the band'
            : (bio.length > 46 ? '${bio.substring(0, 46)}…' : bio),
        sub: bio.isEmpty
            ? 'Optional; two sentences is plenty'
            : '${bio.length} characters',
        onTap: () => showShortBioSheet(context),
      ),
      _ProfileLine(
        num: '06',
        label: 'LINKS',
        state: links.isEmpty ? _LineState.optional : _LineState.done,
        value: links.isEmpty ? 'Add your music' : links.join(' · '),
        sub: links.isEmpty ? 'Bandcamp, IG, YouTube' : 'Shown on your profile',
        onTap: () => showLinksSheet(context),
      ),
      _ProfileLine(
        num: '07',
        label: 'CREDITS',
        state: credits.isEmpty ? _LineState.optional : _LineState.done,
        value: credits.isEmpty ? 'Add credits' : credits,
        sub: credits.isEmpty
            ? 'Producers, artists, labels, and collaborators'
            : 'Shown on your public profile',
        onTap: () => showCreditsSheet(context),
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
                  'PROFILE DETAILS',
                  style: Theme.of(context).textTheme.epSectionHeading,
                ),
              ),
              Flexible(
                child: Text(
                  'CREATE NOW, FINISH ANY TIME',
                  textAlign: TextAlign.end,
                  style: epText(
                    size: 9.5,
                    weight: FontWeight.w900,
                    letterSpacing: 1.3,
                    color: Ep.contentDisabled,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'Required details',
            style: epText(
              size: 12,
              weight: FontWeight.w800,
              color: Ep.contentPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              border: const Border(top: BorderSide(color: Ep.border)),
            ),
            child: Column(
              children: [
                _NameLine(controller: nameController, focusNode: nameFocus),
                ...lines.take(2),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Optional details',
            style: epText(
              size: 12,
              weight: FontWeight.w800,
              color: Ep.contentPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Ep.border)),
            ),
            child: Column(children: lines.skip(2).toList()),
          ),
          const SizedBox(height: 12),
          _ProfileLine(
            num: '08',
            label: 'MUSIC / CLIPS',
            state: _LineState.optional,
            value: app.nbEditingCreated
                ? 'Manage music and videos'
                : 'Add music after creating your band',
            sub: 'Bandcamp and YouTube links can also be added above',
            onTap: () {
              if (app.nbEditingCreated) {
                app.openBandMedia();
              } else {
                app.say('Create your band first, then add music and clips.');
              }
            },
          ),
          _ProfileLine(
            num: '09',
            label: 'BAND MEMBERS',
            state: _LineState.optional,
            value: app.nbEditingCreated
                ? 'Open invitation panel'
                : 'Invite members after creating your band',
            sub: 'Secure join links are created once your band is live',
            onTap: () {
              if (app.nbEditingCreated) {
                app.openInvitationPanel();
              } else {
                app.say('Create your band first, then invite band members.');
              }
            },
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
        border: const Border(bottom: BorderSide(color: Ep.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '01',
              style: Theme.of(
                context,
              ).textTheme.epLabel.copyWith(color: _numColor(state)),
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
                      color: Ep.contentDisabled,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  filled
                      ? publicWebDisplayUrl(app.nbShareSlug)
                      : 'Your profile URL comes from this',
                  style: epText(size: 10, color: Ep.contentDisabled),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  final String num;
  final String label;
  final _LineState state;
  final String value;
  final String sub;
  final VoidCallback onTap;

  const _ProfileLine({
    required this.num,
    required this.label,
    required this.state,
    required this.value,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 13),
            decoration: BoxDecoration(
              border: const Border(bottom: BorderSide(color: Ep.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    num,
                    style: Theme.of(
                      context,
                    ).textTheme.epLabel.copyWith(color: _numColor(state)),
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
                              ? Ep.contentDisabled
                              : Ep.contentPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: epText(size: 10, color: Ep.contentDisabled),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    '›',
                    style: epText(size: 16, color: Ep.contentDisabled),
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
          colors: [Ep.background.withValues(alpha: 0), Ep.background],
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
                ? 'Your band is live. Save to publish these updates.'
                : 'Ready. Profile image, short bio, and links can wait.',
            textAlign: TextAlign.center,
            style: epText(
              size: 11,
              weight: FontWeight.w700,
              color: missing.isEmpty ? Ep.accent : Ep.contentSecondary,
            ),
          ),
          const SizedBox(height: 9),
          EpButton(
            app.nbSaving
                ? 'SAVING…'
                : app.nbEditingCreated
                ? 'SAVE CHANGES'
                : 'CREATE BAND',
            fontSize: 14,
            kind: live ? EpButtonKind.filled : EpButtonKind.disabled,
            padding: const EdgeInsets.symmetric(vertical: 16),
            onTap: live ? app.createBand : null,
          ),
        ],
      ),
    );
  }
}

// ============================ sheets ============================

class _Sheet extends StatelessWidget {
  final String title;
  final Widget child;

  const _Sheet({required this.title, required this.child});

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
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(title.toUpperCase(), style: epDisplay(size: 15)),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
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

class _SheetHint extends StatelessWidget {
  final String text;

  const _SheetHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: epText(size: 10.5, color: Ep.contentDisabled, height: 1.45),
    );
  }
}

/// Input plus a filled action button for adding a custom option.
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
            decoration: sheetInput(hint),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: onSubmit, child: Text(action)),
      ],
    );
  }
}

// ---------------------------- sound ----------------------------

void showSoundSheet(BuildContext context) {
  showEpSheet(
    context,
    (_) => const _Sheet(title: 'Sound', child: _SoundBody()),
  );
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
        const _SheetHint('Choose up to three. Fans use these to find you.'),
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
        const DoneButton(),
      ],
    );
  }
}

// ---------------------------- home base ----------------------------

void showHomeBaseSheet(BuildContext context) {
  showEpSheet(
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
          EpCard(
            variant: app.nbArea == area.name
                ? EpCardVariant.selected
                : EpCardVariant.standard,
            onTap: () {
              app.setNbArea(area.name);
              Navigator.pop(context);
            },
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  area.name.toUpperCase(),
                  style: epText(size: 12.5, weight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  area.sub,
                  style: epText(size: 10.5, color: Ep.contentSecondary),
                ),
              ],
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

// ---------------------------- short bio ----------------------------

const _bioStarters = [
  'Two amps facing each other, one long argument. You will hear it in your '
      'teeth.',
  'Fast, short, gone. Sets under 20 minutes, guaranteed.',
  'Reverb-soaked garage punk from a basement that actually floods.',
];

void showShortBioSheet(BuildContext context) {
  showEpSheet(
    context,
    (_) => const _Sheet(title: 'Short bio', child: _ShortBioBody()),
  );
}

class _ShortBioBody extends StatefulWidget {
  const _ShortBioBody();

  @override
  State<_ShortBioBody> createState() => _ShortBioBodyState();
}

class _ShortBioBodyState extends State<_ShortBioBody> {
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
          decoration: sheetInput('What do you sound like, where do you play?'),
        ),
        const SizedBox(height: 11),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SheetHint(
              '$count characters${count > 180 ? '. Try trimming it.' : ''}',
            ),
            TextAction(
              'USE A STARTER LINE',
              onTap: _useStarter,
              size: 10.5,
              letterSpacing: .6,
            ),
          ],
        ),
        const SizedBox(height: 11),
        const DoneButton(),
      ],
    );
  }
}

// ---------------------------- credits ----------------------------

void showCreditsSheet(BuildContext context) {
  showEpSheet(
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
  late final TextEditingController _credits;

  @override
  void initState() {
    super.initState();
    _credits = TextEditingController(text: context.read<AppState>().nbCredits);
  }

  @override
  void dispose() {
    _credits.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SheetHint(
          'Credit producers, visual artists, labels, collaborators, or anyone '
          'else who helped make the work.',
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('create-credits'),
          controller: _credits,
          onChanged: app.setNbCredits,
          minLines: 3,
          maxLines: 6,
          style: epText(size: 13, height: 1.45),
          decoration: sheetInput('Recorded by…\nArtwork by…\nReleased with…'),
        ),
        const SizedBox(height: 12),
        const DoneButton(),
      ],
    );
  }
}

// ---------------------------- links ----------------------------

void showLinksSheet(BuildContext context) {
  showEpSheet(
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
              color: Ep.contentDisabled,
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: epText(size: 12.5),
            decoration: sheetInput(hint),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 2),
        const DoneButton(),
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
    final profileUrl = publicWebDisplayUrl(app.nbShareSlug);

    return ColoredBox(
      color: Ep.background,
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
                  color: Ep.accent,
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
                      color: Ep.contentSecondary,
                    ),
                  )
                else
                  _QuietAction(
                    'RETRY PHOTO',
                    onTap: app.retryNbPhoto,
                    color: Ep.accent,
                  ),
              ],
              const SizedBox(height: 18),
              Text("You're on the map.", style: epDisplay(size: 20)),
              const SizedBox(height: 4),
              Text(
                profileUrl,
                style: epText(size: 12, color: Ep.contentSecondary),
              ),
              const SizedBox(height: 18),
              Text(
                'WHAT WOULD YOU LIKE TO DO NEXT?',
                style: epDisplay(size: 13),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: 300,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EpButton(
                      'POST A MUSIC CLIP',
                      fontSize: 11.5,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      onTap: app.openBandMedia,
                    ),
                    const SizedBox(height: 8),
                    EpButton(
                      'PUBLISH A GIG',
                      kind: EpButtonKind.outline,
                      fontSize: 11.5,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      onTap: app.postFirstGig,
                    ),
                    const SizedBox(height: 8),
                    EpButton(
                      'INVITE BAND MEMBERS',
                      kind: EpButtonKind.outline,
                      fontSize: 11.5,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      onTap: app.openInvitationPanel,
                    ),
                    const SizedBox(height: 4),
                    TextAction(
                      'NOT NOW',
                      onTap: app.openCreatedBand,
                      color: Ep.contentSecondary,
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
                    color: Ep.contentSecondary,
                  ),
                  _QuietAction(
                    'SHARE PROFILE',
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: publicWebUrl(app.nbShareSlug)),
                      );
                      app.say('Link copied: $profileUrl');
                    },
                    color: Ep.contentSecondary,
                  ),
                  _QuietAction(
                    'START ANOTHER',
                    onTap: app.makeAnotherBand,
                    color: Ep.accent,
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
    return TextAction(
      label,
      onTap: onTap,
      color: color,
      size: 11,
      letterSpacing: .6,
    );
  }
}
