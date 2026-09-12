import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_links.dart' show legalEffective, legalPrivacyUrl, legalTermsUrl;
import '../app_state.dart';
import '../services/auth_service.dart';
import '../services/user_actions.dart' show openExternalForUser;
import '../theme.dart';
import '../widgets/branding.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/form_bits.dart';

// The stamp's fixed tilt, used everywhere the door stamp is drawn.
const _stampAngle = -9 * math.pi / 180;
const _stepPadding = EdgeInsets.fromLTRB(20, 24, 20, 32);

/// The door column never grows past a comfortable reading width on desktop.
const _stepMaxWidth = 420.0;

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

/// "21:00" — the door time shown next to the mark.
String _doorTime() {
  final now = DateTime.now();
  return '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';
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
      step = _DoorStep(app: app);
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
            padding: EdgeInsets.fromLTRB(
              EpLayout.gutter,
              headerTopPad(context),
              EpLayout.gutter,
              0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _stepMaxWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const EpLogo.compact(height: 28),
                    Flexible(child: EpEyebrow('Door · ${_doorTime()}')),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: step),
        ],
      ),
    );
  }
}

// ========================= the door =========================

/// Which half of the single email row is showing: the address, or the code
/// that was just sent to it.
enum _EntryStage { email, code }

class _DoorStep extends StatefulWidget {
  final AppState app;

  const _DoorStep({required this.app});

  @override
  State<_DoorStep> createState() => _DoorStepState();
}

class _DoorStepState extends State<_DoorStep> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _termsRecognizer = TapGestureRecognizer();
  final _privacyRecognizer = TapGestureRecognizer();

  _EntryStage _stage = _EntryStage.email;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_codeChanged);
    _termsRecognizer.onTap = () => openExternalForUser(context, legalTermsUrl);
    _privacyRecognizer.onTap = () =>
        openExternalForUser(context, legalPrivacyUrl);
  }

  void _codeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: _stepPadding,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _stepMaxWidth,
              minHeight: math.max(
                0,
                constraints.maxHeight - _stepPadding.vertical,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // An empty leading child gives the pitch an equal share of
                // the slack above and below, centring it over the actions
                // while they stay pinned to the bottom.
                const SizedBox.shrink(),
                _buildPitch(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildEntry(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The vertically centred sell: eyebrow, hero, copy, door stamp.
  Widget _buildPitch() {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.epColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EpEyebrow.accent("You're on the list"),
        const SizedBox(height: 12),
        // Scales down rather than clipping when the hero cannot fit the
        // width (narrow phones, large text).
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'GET ON\n'),
                const TextSpan(text: 'EarPlug'),
                TextSpan(
                  text: '.',
                  style: TextStyle(color: palette.accent),
                ),
              ],
            ),
            style: textTheme.epDisplayAt(64).copyWith(color: palette.ink),
            semanticsLabel: 'Get on EarPlug.',
          ),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            'Browse freely. Create an account when you RSVP, save a show, '
            'or start a band. It takes about ten seconds.',
            style: textTheme.epBody.copyWith(color: palette.muted),
          ),
        ),
        const SizedBox(height: 40),
        Transform.rotate(angle: _stampAngle, child: const _DoorStamp()),
      ],
    );
  }

  /// Everything the fan can act on, in one column: Google, the email row,
  /// feedback, the legal line and the way out.
  List<Widget> _buildEntry() {
    final auth = widget.app.auth;
    final locked = _loading || widget.app.authStep == 2;

    return [
      if (auth.supportsAppleSignIn) ...[
        EpPill(
          label: 'Continue with Apple',
          size: EpPillSize.large,
          expand: true,
          onPressed: locked ? null : () => _startOAuth(OAuthProvider.apple),
        ),
        const SizedBox(height: 12),
      ],
      if (auth.supportsGoogleSignIn) ...[
        EpPill(
          label: 'Continue with Google',
          size: EpPillSize.large,
          expand: true,
          onPressed: locked ? null : () => _startOAuth(OAuthProvider.google),
        ),
        const SizedBox(height: 12),
      ],
      if (auth.supportsEmailSignIn) ...[
        _buildEmailRow(),
        const SizedBox(height: 12),
      ],
      if (_error != null) ...[
        InlineFormFeedback(error: _error),
        const SizedBox(height: 12),
      ],
      if (legalEffective) ...[_buildLegalConsent(), const SizedBox(height: 4)],
      TextAction('← Keep browsing', onTap: locked ? null : widget.app.back),
    ];
  }

  /// One row for the whole email sign-in: the address plus "Send code", which
  /// becomes the 6-digit code plus "Verify" once the code is on its way.
  Widget _buildEmailRow() {
    final onCode = _stage == _EntryStage.code;
    final submit = onCode ? _verifyEmailCode : _sendEmailCode;
    final label = onCode
        ? (_loading ? 'Verifying…' : 'Verify')
        : (_loading ? 'Sending…' : 'Send code');
    final canSubmit = !_loading && (!onCode || _codeIsComplete);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EpUnderlineField(
          // Rebuild the field outright so it picks up the other controller.
          key: ValueKey(_stage),
          controller: onCode ? _codeController : _emailController,
          icon: Icons.mail_outline,
          hint: onCode ? '6-digit code' : 'you@example.com',
          keyboardType: onCode
              ? TextInputType.number
              : TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: [
            onCode ? AutofillHints.oneTimeCode : AutofillHints.email,
          ],
          onChanged: onCode ? _clampCode : null,
          onSubmitted: (_) {
            if (!_loading) submit();
          },
          trailing: EpPill(
            label: label,
            variant: EpPillVariant.primary,
            size: EpPillSize.regular,
            onPressed: canSubmit ? submit : null,
          ),
        ),
        if (onCode)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextAction(
                '← Use a different email',
                onTap: _loading ? null : _restartWithEmail,
              ),
              TextAction(
                'Resend code',
                onTap: _loading ? null : _sendEmailCode,
                color: context.epColors.accent,
              ),
            ],
          ),
      ],
    );
  }

  bool get _codeIsComplete =>
      RegExp(r'^\d{6}$').hasMatch(_codeController.text.trim());

  /// [EpUnderlineField] takes no `inputFormatters`, so the code row keeps
  /// itself to six digits here.
  void _clampCode(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final clamped = digits.length > 6 ? digits.substring(0, 6) : digits;
    if (clamped == value) return;
    _codeController.value = TextEditingValue(
      text: clamped,
      selection: TextSelection.collapsed(offset: clamped.length),
    );
  }

  Widget _buildLegalConsent() {
    final linkStyle = TextStyle(
      color: context.epColors.accent,
      decoration: TextDecoration.underline,
    );
    return Text.rich(
      TextSpan(
        text: 'By continuing you agree to the ',
        children: [
          TextSpan(
            text: 'Terms',
            style: linkStyle,
            recognizer: _termsRecognizer,
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: linkStyle,
            recognizer: _privacyRecognizer,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      key: const Key('auth-legal-consent'),
      style: Theme.of(
        context,
      ).textTheme.epBody.copyWith(color: context.epColors.muted),
      textAlign: TextAlign.center,
    );
  }

  void _restartWithEmail() {
    setState(() {
      _stage = _EntryStage.email;
      _error = null;
      _codeController.clear();
    });
  }

  Future<void> _startOAuth(OAuthProvider provider) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.app.auth.signInWithOAuth(provider);
    } catch (error) {
      // An empty message means the fan dismissed the provider sheet.
      if (error is AuthException && error.message.isEmpty) return;
      if (mounted) setState(() => _error = _messageFor(error));
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
        _stage = _EntryStage.code;
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

/// The circular "★ EarPlug ★ / IN / date" hand stamp. Callers tilt it to
/// [_stampAngle].
class _DoorStamp extends StatelessWidget {
  const _DoorStamp();

  @override
  Widget build(BuildContext context) {
    final accent = context.epColors.accent;
    return Container(
      width: 150,
      height: 150,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent, width: 2),
      ),
      // The circle is a fixed disc, so the ink shrinks to stay inside it at
      // large text scales instead of spilling over the border.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EpMonoText('★ EarPlug ★', color: accent, keepCase: true),
            const SizedBox(height: 2),
            EpDisplay('In', size: 44, color: accent),
            const SizedBox(height: 2),
            EpMonoText(_stampDate(), color: accent),
          ],
        ),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
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
              const EpDisplay('Finishing sign-in', size: 20),
            ] else ...[
              Icon(
                Icons.error_outline,
                color: context.epColors.destructive,
                size: 24,
              ),
              const SizedBox(height: 12),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.epBody.copyWith(
                  color: context.epColors.destructive,
                ),
              ),
              const SizedBox(height: 16),
              EpPill(
                label: 'Try again',
                variant: EpPillVariant.primary,
                size: EpPillSize.regular,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.rotate(angle: _stampAngle, child: const _DoorStamp()),
              const SizedBox(height: 14),
              EpDisplay(
                switch (kind) {
                  PendingKind.rsvp => 'RSVP confirmed',
                  PendingKind.save => 'Show saved',
                  PendingKind.follow => 'Band followed',
                  PendingKind.band => "Let's start your band",
                  PendingKind.join || PendingKind.orgJoin => 'Ready to join',
                  PendingKind.gigInvite => 'Ready to claim',
                  PendingKind.orgApply ||
                  PendingKind.hostApply => 'Ready to apply',
                  PendingKind.booking => 'Booking ready',
                  PendingKind.tickets => 'Tickets ready',
                  PendingKind.myGigs || null => 'Account ready',
                },
                size: 20,
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ],
          ),
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
