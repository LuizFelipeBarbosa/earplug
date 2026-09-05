import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/branding.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';

// The stamp's fixed tilt, used everywhere the door stamp is drawn.
const _stampAngle = -9 * math.pi / 180;
const _stepPadding = EdgeInsets.fromLTRB(22, 24, 22, 30);

/// "29 JUL 26" — the date pressed into the door stamp.
String _stampDate() {
  const months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  final now = DateTime.now();
  final day = now.day.toString().padLeft(2, '0');
  final year = (now.year % 100).toString().padLeft(2, '0');
  return '$day ${months[now.month - 1]} $year';
}

/// Auth as getting stamped at the door. A successful sign-in immediately
/// replays the action that brought the fan here, then shows a short
/// confirmation before returning them to where they started.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  String? _method; // 'Apple' | 'Google' | 'Email'
  bool _leaving = false;
  bool _completionScheduled = false;
  PendingKind? _completedKind;
  String? _completionError;
  Timer? _leaveTimer;

  @override
  void dispose() {
    _leaveTimer?.cancel();
    super.dispose();
  }

  void _pickMethod(String method) {
    setState(() => _method = method);
  }

  void _clearMethod() {
    setState(() => _method = null);
  }

  void _scheduleCompletion(AppState app) {
    if (_leaving || _completionScheduled) return;
    _completionScheduled = true;
    final completedKind = app.pending?.kind ?? app.authConfirmationKind;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(() async {
        try {
          await app.commitAuth();
          if (!mounted) return;
          setState(() {
            _completedKind = completedKind;
            _leaving = true;
          });
          _leaveTimer = Timer(const Duration(milliseconds: 900), () {
            if (mounted) app.leaveAuth();
          });
        } catch (error) {
          if (!mounted) return;
          setState(() {
            _completionScheduled = false;
            _completionError = error.toString().trim();
          });
        }
      }());
    });
  }

  void _retryCompletion() => setState(() => _completionError = null);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    final Widget step;
    if (_leaving || app.authStep == 2) {
      if (_completionError == null) _scheduleCompletion(app);
      step = _leaving
          ? _ThroughStep(kind: _completedKind)
          : _CompletingStep(error: _completionError, onRetry: _retryCompletion);
    } else {
      step = _DoorStep(
        app: app,
        method: _method,
        onPick: _pickMethod,
        onClearPick: _clearMethod,
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.1,
          colors: [context.epColors.surfaceRaised, context.epColors.background],
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
                const EpLogo.full(width: 118),
                Text(
                  'DOOR · 21:00',
                  style: epText(
                    size: 9,
                    weight: FontWeight.w900,
                    letterSpacing: 1.9,
                    color: context.epColors.contentDisabled,
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

// ========================= the door =========================

enum _EntryStage { providers, email, emailCode }

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
  final _codeController = TextEditingController();

  _EntryStage _stage = _EntryStage.providers;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_codeChanged);
  }

  void _codeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: _stepPadding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(
              0,
              constraints.maxHeight - _stepPadding.vertical,
            ),
          ),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'GET ON\nEARPLUG',
                  style: epDisplay(size: 38, height: .98),
                ),
                const SizedBox(height: 12),
                Text(
                  'Browse freely. Create an account when you RSVP, save a show, or start a band. It takes about ten seconds.',
                  style: epText(
                    size: 11.5,
                    color: context.epColors.contentSecondary,
                    height: 1.5,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Center(
                      child: _StampWell(stamped: widget.method != null),
                    ),
                  ),
                ),
                EpCard(
                  variant: EpCardVariant.raised,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_stage == _EntryStage.providers)
                        ..._buildProviders()
                      else
                        ..._buildEntry(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildProviders() {
    final locked = _loading || widget.app.authStep == 2;
    final codeMethods = widget.app.auth.supportsEmailSignIn
        ? _MethodTile('EMAIL', onTap: locked ? null : _showEmail)
        : null;

    return [
      if (widget.app.auth.supportsAppleSignIn) ...[
        EpButton(
          ' Continue with Apple',
          kind: locked ? EpButtonKind.disabled : EpButtonKind.light,
          padding: const EdgeInsets.symmetric(vertical: 15),
          onTap: locked ? null : () => _startOAuth(OAuthProvider.apple),
        ),
        const SizedBox(height: 9),
      ],
      if (widget.app.auth.supportsGoogleSignIn) ...[
        EpButton(
          'G · Continue with Google',
          kind: locked ? EpButtonKind.disabled : EpButtonKind.ghost,
          padding: const EdgeInsets.symmetric(vertical: 15),
          onTap: locked ? null : () => _startOAuth(OAuthProvider.google),
        ),
        const SizedBox(height: 9),
      ],
      ?codeMethods,
      if (_error != null) ...[const SizedBox(height: 9), _InlineError(_error!)],
      const SizedBox(height: 9),
      TextAction('← KEEP BROWSING', onTap: locked ? null : widget.app.back),
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
          decoration: epInputDecoration(context, 'you@example.com'),
          onSubmitted: (_) {
            if (_stage == _EntryStage.email) _sendEmailCode();
          },
        ),
      const SizedBox(height: 10),
      if (_stage == _EntryStage.email)
        EpButton(
          _loading ? 'SENDING…' : 'SEND CODE',
          kind: _loading ? EpButtonKind.disabled : EpButtonKind.filled,
          onTap: _loading ? null : _sendEmailCode,
        ),
      if (_stage == _EntryStage.emailCode) _buildCodeEntry(),
      if (_stage == _EntryStage.email && _error != null) ...[
        const SizedBox(height: 9),
        _InlineError(_error!),
      ],
      const SizedBox(height: 8),
      TextAction('← BACK', onTap: _loading ? null : _showProviders),
    ];
  }

  Widget _buildCodeEntry() {
    final codeComplete = RegExp(
      r'^\d{6}$',
    ).hasMatch(_codeController.text.trim());
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
          style: epText(size: 18, weight: FontWeight.w800, letterSpacing: 5),
          decoration: epInputDecoration(
            context,
            '6-digit code',
          ).copyWith(counterText: ''),
          maxLength: 6,
          onSubmitted: (_) => _verifyEmailCode(),
        ),
        const SizedBox(height: 10),
        EpButton(
          _loading ? 'VERIFYING…' : 'VERIFY',
          kind: _loading || !codeComplete
              ? EpButtonKind.disabled
              : EpButtonKind.filled,
          onTap: _loading || !codeComplete ? null : _verifyEmailCode,
        ),
        if (_error != null) ...[
          const SizedBox(height: 9),
          _InlineError(_error!),
        ],
        const SizedBox(height: 12),
        TextAction(
          'RESEND CODE',
          onTap: _loading ? null : _sendEmailCode,
          color: context.epColors.accent,
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

  void _showProviders() {
    widget.onClearPick();
    setState(() {
      _stage = _EntryStage.providers;
      _error = null;
      _emailController.clear();
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

  Future<void> _verifyEmailCode() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final verified = await widget.app.auth.verifyEmailCode(code);
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
    return message.isEmpty ? 'Something went wrong. Try again.' : message;
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
              ? _StampThud(
                  child: _DoorStamp(
                    size: 158,
                    borderColor: context.epColors.accent,
                    inkColor: context.epColors.accent,
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
  late final AnimationController _controller;
  bool _pulseStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
      return;
    }
    if (_pulseStarted) return;

    _pulseStarted = true;
    _controller.value = 1;
    unawaited(_runPulse());
  }

  Future<void> _runPulse() async {
    try {
      for (var cycle = 0; cycle < 3; cycle++) {
        await _controller.reverse().orCancel;
        await _controller.forward().orCancel;
      }
    } on TickerCanceled {
      // Disposing the widget or enabling reduced motion cancels the pulse.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: .28,
        end: .7,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'PRESS HERE',
            style: epText(
              size: 10,
              weight: FontWeight.w900,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'pick a method below',
            style: epText(
              size: 9.5,
              color: context.epColors.contentSecondary,
              letterSpacing: .6,
            ),
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
        child: Transform.rotate(angle: _stampAngle, child: widget.child),
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
    return EpButton(label, kind: EpButtonKind.outline, onTap: onTap);
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
        color: context.epColors.destructive,
        height: 1.35,
      ),
    );
  }
}

// ========================= confirmation =========================

class _CompletingStep extends StatelessWidget {
  const _CompletingStep({required this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error == null) ...[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 16),
            Text('FINISHING SIGN-IN'),
          ] else ...[
            Icon(
              Icons.error_outline,
              color: context.epColors.destructive,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: epText(size: 12, color: context.epColors.destructive),
            ),
            const SizedBox(height: 16),
            EpButton('TRY AGAIN', onTap: onRetry),
          ],
        ],
      ),
    );
  }
}

class _ThroughStep extends StatelessWidget {
  const _ThroughStep({required this.kind});

  final PendingKind? kind;

  @override
  Widget build(BuildContext context) {
    return _RiseIn(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: _stampAngle,
              child: _DoorStamp(
                size: 150,
                borderColor: context.epColors.accent,
                inkColor: context.epColors.accent,
              ),
            ),
            const SizedBox(height: 14),
            Text(switch (kind) {
              PendingKind.rsvp => 'RSVP CONFIRMED',
              PendingKind.save => 'SHOW SAVED',
              PendingKind.follow => 'BAND FOLLOWED',
              PendingKind.band => "LET'S START YOUR BAND",
              PendingKind.join || PendingKind.orgJoin => 'READY TO JOIN',
              PendingKind.gigInvite => 'READY TO CLAIM',
              PendingKind.orgApply => 'READY TO APPLY',
              PendingKind.booking => 'BOOKING READY',
              PendingKind.myGigs || null => 'ACCOUNT READY',
            }, style: epDisplay(size: 19)),
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
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
