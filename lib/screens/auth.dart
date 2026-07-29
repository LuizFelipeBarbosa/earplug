import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Two-step auth: provider buttons (Clerk hooks in here later), then optional
/// taste picker that seeds recommendations.
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Container(
      color: Ep.bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.fromLTRB(26, 70, 26, 40),
      child: SingleChildScrollView(
        child: app.authStep == 1 ? _Step1(app: app) : _Step2(app: app),
      ),
    );
  }
}

enum _EmailStage { providers, email, code }

class _Step1 extends StatefulWidget {
  final AppState app;

  const _Step1({required this.app});

  @override
  State<_Step1> createState() => _Step1State();
}

class _Step1State extends State<_Step1> {
  static const _errorColor = Color(0xFFFF6B6B);

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();

  _EmailStage _stage = _EmailStage.providers;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Image.asset('assets/images/listen_local_bw.png', width: 220),
        ),
        const SizedBox(height: 20),
        Text(
          app.authTitle.toUpperCase(),
          textAlign: TextAlign.center,
          style: epDisplay(size: 19, height: 1.2),
        ),
        const SizedBox(height: 8),
        Text(
          'Browsing never needs an account.\nThis does. Takes ten seconds.',
          textAlign: TextAlign.center,
          style: epText(size: 12.5, color: Ep.inkA(.55), height: 1.5),
        ),
        const SizedBox(height: 22),
        if (_stage == _EmailStage.providers) ...[
          EpButton(
            ' Continue with Apple',
            kind: EpButtonKind.light,
            padding: const EdgeInsets.symmetric(vertical: 14),
            onTap: _loading ? null : () => _startOAuth(OAuthProvider.apple),
          ),
          const SizedBox(height: 14),
          EpButton(
            'G · Continue with Google',
            kind: EpButtonKind.ghost,
            padding: const EdgeInsets.symmetric(vertical: 14),
            onTap: _loading ? null : () => _startOAuth(OAuthProvider.google),
          ),
          if (_error != null) ...[
            const SizedBox(height: 9),
            _InlineError(_error!),
          ],
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _showEmail,
            child: Text(
              'Use email instead',
              textAlign: TextAlign.center,
              style:
                  epText(
                    size: 12,
                    weight: FontWeight.w700,
                    color: Ep.inkA(.65),
                  ).copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: Ep.inkA(.65),
                  ),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: app.back,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                '← KEEP BROWSING',
                textAlign: TextAlign.center,
                style: epText(
                  size: 12,
                  weight: FontWeight.w800,
                  letterSpacing: 1,
                  color: Ep.inkA(.45),
                ),
              ),
            ),
          ),
        ] else ...[
          TextField(
            controller: _emailController,
            enabled: !_loading && _stage == _EmailStage.email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            style: epText(size: 14),
            decoration: epInputDecoration('you@example.com'),
            onSubmitted: (_) {
              if (_stage == _EmailStage.email) _sendCode();
            },
          ),
          const SizedBox(height: 10),
          if (_stage == _EmailStage.email)
            EpButton(
              _loading ? 'SENDING…' : 'SEND CODE',
              kind: _loading ? EpButtonKind.disabled : EpButtonKind.filled,
              onTap: _loading ? null : _sendCode,
            ),
          if (_stage == _EmailStage.code) ...[
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
              onSubmitted: (_) => _verifyCode(),
            ),
            const SizedBox(height: 10),
            EpButton(
              _loading ? 'VERIFYING…' : 'VERIFY',
              kind: _loading ? EpButtonKind.disabled : EpButtonKind.filled,
              onTap: _loading ? null : _verifyCode,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 9),
            _InlineError(_error!),
          ],
          if (_stage == _EmailStage.code) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _loading ? null : _resendCode,
              child: Text(
                'resend code',
                textAlign: TextAlign.center,
                style:
                    epText(
                      size: 11.5,
                      weight: FontWeight.w700,
                      color: Ep.link,
                    ).copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor: Ep.link,
                    ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _loading ? null : _showProviders,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                '← BACK',
                textAlign: TextAlign.center,
                style: epText(
                  size: 12,
                  weight: FontWeight.w800,
                  letterSpacing: 1,
                  color: Ep.inkA(.45),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showEmail() {
    setState(() {
      _stage = _EmailStage.email;
      _error = null;
    });
  }

  void _showProviders() {
    setState(() {
      _stage = _EmailStage.providers;
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
      final message = _messageFor(error);
      if (message == 'Coming soon on mobile — use email') {
        widget.app.say(message);
      } else if (mounted) {
        setState(() => _error = message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.app.auth.startEmailSignIn(_emailController.text);
      if (!mounted) return;
      setState(() {
        _stage = _EmailStage.code;
        _codeController.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    await _sendCode();
  }

  Future<void> _verifyCode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final verified = await widget.app.auth.verifyEmailCode(
        _codeController.text.trim(),
      );
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

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: epText(
        size: 11.5,
        weight: FontWeight.w700,
        color: _Step1State._errorColor,
        height: 1.35,
      ),
    );
  }
}

class _Step2 extends StatelessWidget {
  final AppState app;

  const _Step2({required this.app});

  @override
  Widget build(BuildContext context) {
    final picked = app.userGenres.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'WHAT DO YOU\nLIKE LOUD?',
          style: epDisplay(size: 24, height: 1.05),
        ),
        const SizedBox(height: 14),
        Text(
          "Optional. Seeds your recommendations — skip it and we'll figure you out from the shows you hit.",
          style: epText(size: 12.5, color: Ep.inkA(.55), height: 1.5),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in const [
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
            ])
              EpChip(
                label: t,
                active: app.userGenres.contains(t),
                onTap: () => app.toggleUserGenre(t),
              ),
          ],
        ),
        const SizedBox(height: 24),
        EpButton(
          picked > 0 ? 'DONE — $picked PICKED' : 'DONE',
          onTap: app.finishAuth,
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: app.finishAuth,
          child: Text(
            'Skip for now',
            textAlign: TextAlign.center,
            style: epText(
              size: 12,
              weight: FontWeight.w700,
              color: Ep.inkA(.5),
            ),
          ),
        ),
      ],
    );
  }
}
