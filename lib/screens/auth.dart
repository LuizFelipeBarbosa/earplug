import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

// Door-stamp accent palette from the Sign In v3 design.
const _stampAccent = Color(0xFF4B62FF);
const _stampInk = Color(0xFF8C9DFF);
const _errorColor = Color(0xFFFF6B6B);

const _genres = [
  'punk',
  'hardcore',
  'garage',
  'noise',
  'post-punk',
  'shoegaze',
  'surf',
  'thrash',
  'ska',
  'emo',
];

/// "29 JUL 26" — the date pressed into the door stamp.
String _stampDate() {
  const months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  final now = DateTime.now();
  final day = now.day.toString().padLeft(2, '0');
  final year = (now.year % 100).toString().padLeft(2, '0');
  return '$day ${months[now.month - 1]} $year';
}

/// Sign In v3 — auth as getting stamped at the door. Step 1 picks a method
/// (the stamp thuds down), step 2 is the optional taste picker, then a short
/// "you're through" splash before the pending action completes.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  String? _method; // 'Apple' | 'Google' | 'Email' | 'Phone'
  bool _holdingStamp = false; // keeps step 1 up while the stamp thud plays
  bool _leaving = false; // "you're through" splash before finishAuth
  Timer? _holdTimer;
  Timer? _leaveTimer;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _leaveTimer?.cancel();
    super.dispose();
  }

  void _pickMethod(String method) {
    _holdTimer?.cancel();
    setState(() {
      _method = method;
      _holdingStamp = true;
    });
    _holdTimer = Timer(const Duration(milliseconds: 1150), () {
      if (mounted) setState(() => _holdingStamp = false);
    });
  }

  void _clearMethod() {
    _holdTimer?.cancel();
    setState(() {
      _method = null;
      _holdingStamp = false;
    });
  }

  void _enterTheRoom(AppState app) {
    // Commit genres + the pending action now; the splash only delays the
    // navigation, so backing out mid-splash can't drop what they signed in for.
    app.commitAuth();
    setState(() => _leaving = true);
    _leaveTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) app.leaveAuth();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    final Widget step;
    if (_leaving) {
      step = const _ThroughStep();
    } else if (app.authStep == 2 && !_holdingStamp) {
      step = _TasteStep(
        app: app,
        via: _method,
        onDone: () => _enterTheRoom(app),
      );
    } else {
      step = _DoorStep(
        app: app,
        method: _method,
        onPick: _pickMethod,
        onClearPick: _clearMethod,
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.1,
          colors: [Color(0xFF191920), Ep.bg],
          stops: [0, .68],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(22, headerTopPad(context), 22, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Image.asset('assets/images/listen_local_bw.png', width: 98),
                Text(
                  'DOOR · 21:00',
                  style: epText(
                    size: 9,
                    weight: FontWeight.w900,
                    letterSpacing: 1.9,
                    color: Ep.inkA(.36),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: step),
        ],
      ),
    );
  }
}

// ========================= step 1 — the door =========================

enum _EntryStage { providers, email, emailCode, phone, phoneCode }

class _DoorStep extends StatefulWidget {
  final AppState app;
  final String? method;
  final ValueChanged<String> onPick;
  final VoidCallback onClearPick;

  const _DoorStep({
    required this.app,
    required this.method,
    required this.onPick,
    required this.onClearPick,
  });

  @override
  State<_DoorStep> createState() => _DoorStepState();
}

class _DoorStepState extends State<_DoorStep> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  _EntryStage _stage = _EntryStage.providers;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 54),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('GET ON\nEARPLUG', style: epDisplay(size: 38, height: .98)),
                const SizedBox(height: 12),
                Text(
                  'Browsing needs no account. This does — ten seconds at the door.',
                  style: epText(size: 11.5, color: Ep.inkA(.42), height: 1.5),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Center(child: _StampWell(stamped: widget.method != null)),
                  ),
                ),
                if (_stage == _EntryStage.providers)
                  ..._buildProviders()
                else
                  ..._buildEntry(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildProviders() {
    return [
      if (widget.app.auth.supportsAppleSignIn) ...[
        EpButton(
          ' Continue with Apple',
          kind: _loading ? EpButtonKind.disabled : EpButtonKind.light,
          padding: const EdgeInsets.symmetric(vertical: 15),
          onTap: _loading ? null : () => _startOAuth(OAuthProvider.apple),
        ),
        const SizedBox(height: 9),
      ],
      if (widget.app.auth.supportsGoogleSignIn) ...[
        EpButton(
          'G · Continue with Google',
          kind: _loading ? EpButtonKind.disabled : EpButtonKind.ghost,
          padding: const EdgeInsets.symmetric(vertical: 15),
          onTap: _loading ? null : () => _startOAuth(OAuthProvider.google),
        ),
        const SizedBox(height: 9),
      ],
      Row(
        children: [
          Expanded(
            child: _MethodTile('EMAIL', onTap: _loading ? null : _showEmail),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _MethodTile('PHONE', onTap: _loading ? null : _showPhone),
          ),
        ],
      ),
      if (_error != null) ...[const SizedBox(height: 9), _InlineError(_error!)],
      const SizedBox(height: 9),
      _TextAction('← KEEP BROWSING', onTap: widget.app.back),
    ];
  }

  List<Widget> _buildEntry() {
    return [
      if (_stage == _EntryStage.email || _stage == _EntryStage.emailCode)
        TextField(
          controller: _emailController,
          enabled: !_loading && _stage == _EntryStage.email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
          style: epText(size: 14),
          decoration: epInputDecoration('you@example.com'),
          onSubmitted: (_) {
            if (_stage == _EntryStage.email) _sendEmailCode();
          },
        ),
      if (_stage == _EntryStage.phone || _stage == _EntryStage.phoneCode)
        TextField(
          controller: _phoneController,
          enabled: !_loading && _stage == _EntryStage.phone,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          autocorrect: false,
          style: epText(size: 14),
          decoration: epInputDecoration('+1 555 555 0100'),
          onSubmitted: (_) {
            if (_stage == _EntryStage.phone) _sendPhoneCode();
          },
        ),
      const SizedBox(height: 10),
      if (_stage == _EntryStage.email)
        EpButton(
          _loading ? 'SENDING…' : 'SEND CODE',
          kind: _loading ? EpButtonKind.disabled : EpButtonKind.filled,
          onTap: _loading ? null : _sendEmailCode,
        ),
      if (_stage == _EntryStage.phone)
        EpButton(
          _loading ? 'SENDING…' : 'SEND CODE',
          kind: _loading ? EpButtonKind.disabled : EpButtonKind.filled,
          onTap: _loading ? null : _sendPhoneCode,
        ),
      if (_stage == _EntryStage.emailCode)
        _buildCodeEntry(verify: _verifyEmailCode, resend: _sendEmailCode),
      if (_stage == _EntryStage.phoneCode)
        _buildCodeEntry(verify: _verifyPhoneCode, resend: _sendPhoneCode),
      if ((_stage == _EntryStage.email || _stage == _EntryStage.phone) &&
          _error != null) ...[
        const SizedBox(height: 9),
        _InlineError(_error!),
      ],
      const SizedBox(height: 8),
      _TextAction('← BACK', onTap: _loading ? null : _showProviders),
    ];
  }

  Widget _buildCodeEntry({
    required Future<void> Function() verify,
    required Future<void> Function() resend,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _codeController,
          enabled: !_loading,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: epDisplay(size: 18, letterSpacing: 5),
          decoration: epInputDecoration(
            '6-digit code',
          ).copyWith(counterText: ''),
          maxLength: 6,
          onSubmitted: (_) => verify(),
        ),
        const SizedBox(height: 10),
        EpButton(
          _loading ? 'VERIFYING…' : 'VERIFY',
          kind: _loading ? EpButtonKind.disabled : EpButtonKind.filled,
          onTap: _loading ? null : verify,
        ),
        if (_error != null) ...[const SizedBox(height: 9), _InlineError(_error!)],
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _loading ? null : resend,
          child: Text(
            'resend code',
            textAlign: TextAlign.center,
            style: epText(size: 11.5, weight: FontWeight.w700, color: Ep.link)
                .copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: Ep.link,
                ),
          ),
        ),
      ],
    );
  }

  void _showEmail() {
    widget.onPick('Email');
    setState(() {
      _stage = _EntryStage.email;
      _error = null;
    });
  }

  void _showPhone() {
    widget.onPick('Phone');
    setState(() {
      _stage = _EntryStage.phone;
      _error = null;
    });
  }

  void _showProviders() {
    widget.onClearPick();
    setState(() {
      _stage = _EntryStage.providers;
      _error = null;
      _emailController.clear();
      _phoneController.clear();
      _codeController.clear();
    });
  }

  Future<void> _startOAuth(OAuthProvider provider) async {
    widget.onPick(provider == OAuthProvider.apple ? 'Apple' : 'Google');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.app.auth.signInWithOAuth(provider);
    } catch (error) {
      if (error is AuthException && error.message.isEmpty) {
        if (mounted) widget.onClearPick();
        return;
      }
      if (mounted) {
        widget.onClearPick();
        setState(() => _error = _messageFor(error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendEmailCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.app.auth.startEmailSignIn(_emailController.text);
      if (!mounted) return;
      setState(() {
        _stage = _EntryStage.emailCode;
        _codeController.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendPhoneCode() async {
    final phoneNumber = _phoneController.text.replaceAll(
      RegExp(r'[\s\-().]'),
      '',
    );
    if (!phoneNumber.startsWith('+')) {
      setState(() => _error = 'Include your country code, e.g. +1');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.app.auth.startPhoneSignIn(phoneNumber);
      if (!mounted) return;
      setState(() {
        _stage = _EntryStage.phoneCode;
        _codeController.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyEmailCode() {
    return _verifyCode(widget.app.auth.verifyEmailCode);
  }

  Future<void> _verifyPhoneCode() {
    return _verifyCode(widget.app.auth.verifyPhoneCode);
  }

  Future<void> _verifyCode(Future<bool> Function(String code) verify) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final verified = await verify(_codeController.text.trim());
      if (!verified && mounted) {
        setState(() => _error = 'That code is wrong or expired.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _messageFor(Object error) {
    final message = error.toString().trim();
    return message.isEmpty ? 'Something went wrong — try again.' : message;
  }
}

/// The dashed circle where the stamp lands: pulsing "PRESS HERE" until a
/// method is picked, then the stamp thuds in.
class _StampWell extends StatelessWidget {
  final bool stamped;

  const _StampWell({required this.stamped});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedCirclePainter(Ep.whiteA(.15)),
      child: SizedBox(
        width: 198,
        height: 198,
        child: Center(
          child: stamped
              ? const _StampThud(
                  child: _DoorStamp(
                    size: 158,
                    borderColor: _stampAccent,
                    inkColor: _stampAccent,
                  ),
                )
              : const _PressHerePulse(),
        ),
      ),
    );
  }
}

class _PressHerePulse extends StatefulWidget {
  const _PressHerePulse();

  @override
  State<_PressHerePulse> createState() => _PressHerePulseState();
}

class _PressHerePulseState extends State<_PressHerePulse>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: .28, end: .7).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'PRESS HERE',
            style: epText(size: 10, weight: FontWeight.w900, letterSpacing: 2.4),
          ),
          const SizedBox(height: 5),
          Text(
            'pick a method below',
            style: epText(size: 9.5, color: Ep.inkA(.5), letterSpacing: .6),
          ),
        ],
      ),
    );
  }
}

/// The stamp slamming down: oversized and transparent, overshooting to
/// slightly squashed, then settling — always at the -9° stamp angle.
class _StampThud extends StatefulWidget {
  final Widget child;

  const _StampThud({required this.child});

  @override
  State<_StampThud> createState() => _StampThudState();
}

class _StampThudState extends State<_StampThud>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  late final _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.55, end: .93), weight: 55),
    TweenSequenceItem(tween: Tween(begin: .93, end: 1.04), weight: 23),
    TweenSequenceItem(tween: Tween(begin: 1.04, end: 1), weight: 22),
  ]).animate(_controller);

  late final _opacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, .55),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: Transform.rotate(
          angle: -9 * math.pi / 180,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The circular "★ EARPLUG ★ / IN / date" hand stamp.
class _DoorStamp extends StatelessWidget {
  final double size;
  final Color borderColor;
  final Color inkColor;

  const _DoorStamp({
    required this.size,
    required this.borderColor,
    required this.inkColor,
  });

  @override
  Widget build(BuildContext context) {
    final scale = size / 158;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 3),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '★ EARPLUG ★',
            style: epText(
              size: 9 * scale,
              weight: FontWeight.w900,
              letterSpacing: 2.2,
              color: inkColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'IN',
            style: epDisplay(size: 44 * scale, height: .9, color: inkColor),
          ),
          const SizedBox(height: 2),
          Text(
            _stampDate(),
            style: epText(
              size: 9 * scale,
              weight: FontWeight.w900,
              letterSpacing: 2,
              color: inkColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;

  const _DashedCirclePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..addOval(Rect.fromLTWH(1, 1, size.width - 2, size.height - 2));
    const dash = 6.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) => old.color != color;
}

class _MethodTile extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _MethodTile(this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Ep.whiteA(.16)),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          label,
          style: epText(
            size: 12,
            weight: FontWeight.w900,
            letterSpacing: 1.2,
            color: Ep.inkA(.8),
          ),
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _TextAction(this.label, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: epText(
            size: 11.5,
            weight: FontWeight.w900,
            letterSpacing: 1.4,
            color: Ep.inkA(.4),
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;

  const _InlineError(this.message);

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: epText(
        size: 11.5,
        weight: FontWeight.w700,
        color: _errorColor,
        height: 1.35,
      ),
    );
  }
}

// ========================= step 2 — taste =========================

class _TasteStep extends StatelessWidget {
  final AppState app;
  final String? via;
  final VoidCallback onDone;

  const _TasteStep({required this.app, required this.via, required this.onDone});

  // Each chip sits at its own slight tilt, like slapped-on stickers.
  static const _tilts = [-1.6, 1.2, -.8, 1.7, -1.2, .9, -1.8, 1.1, -.6, 1.5];

  @override
  Widget build(BuildContext context) {
    final picked = app.userGenres.length;
    return _RiseIn(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 54),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Transform.rotate(
                        angle: -9 * math.pi / 180,
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _stampAccent, width: 2),
                          ),
                          child: Text(
                            'IN',
                            style: epDisplay(size: 15, color: _stampInk),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        via == null
                            ? 'PLUGGED IN'
                            : 'PLUGGED IN VIA ${via!.toUpperCase()}',
                        style: epText(
                          size: 11,
                          weight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: Ep.inkA(.55),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'WHAT DO YOU\nLIKE LOUD?',
                    style: epDisplay(size: 30, height: 1.02),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Optional — skip it and we read it off the shows you hit.',
                    style: epText(size: 11.5, color: Ep.inkA(.42), height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (i, genre) in _genres.indexed)
                        _TasteChip(
                          label: genre,
                          active: app.userGenres.contains(genre),
                          tiltDeg: _tilts[i % _tilts.length],
                          onTap: () => app.toggleUserGenre(genre),
                        ),
                    ],
                  ),
                  const Expanded(child: SizedBox(height: 24)),
                  EpButton(
                    picked > 0
                        ? 'INTO THE ROOM — $picked PICKED'
                        : 'INTO THE ROOM',
                    glow: true,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    onTap: onDone,
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

class _TasteChip extends StatelessWidget {
  final String label;
  final bool active;
  final double tiltDeg;
  final VoidCallback onTap;

  const _TasteChip({
    required this.label,
    required this.active,
    required this.tiltDeg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tiltDeg * math.pi / 180,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? Ep.blue.withValues(alpha: .24) : null,
            border: Border.all(
              color: active ? _stampAccent : Ep.whiteA(.17),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label.toUpperCase(),
            style: epText(
              size: 10.5,
              weight: FontWeight.w900,
              letterSpacing: 1.4,
              color: active ? const Color(0xFFA9B8FF) : Ep.inkA(.68),
            ),
          ),
        ),
      ),
    );
  }
}

// ========================= step 3 — through =========================

class _ThroughStep extends StatelessWidget {
  const _ThroughStep();

  @override
  Widget build(BuildContext context) {
    return _RiseIn(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: -9 * math.pi / 180,
              child: const _DoorStamp(
                size: 150,
                borderColor: _stampAccent,
                inkColor: _stampInk,
              ),
            ),
            const SizedBox(height: 14),
            Text("YOU'RE THROUGH", style: epDisplay(size: 19)),
          ],
        ),
      ),
    );
  }
}

/// The design's ep-rise entrance: slide up 10px while fading in.
class _RiseIn extends StatelessWidget {
  final Widget child;

  const _RiseIn({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
