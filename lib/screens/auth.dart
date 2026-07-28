import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
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

class _Step1 extends StatelessWidget {
  final AppState app;

  const _Step1({required this.app});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: Image.asset('assets/images/listen_local_bw.png', width: 220)),
        const SizedBox(height: 20),
        Text(app.authTitle.toUpperCase(),
            textAlign: TextAlign.center, style: epDisplay(size: 19, height: 1.2)),
        const SizedBox(height: 8),
        Text('Browsing never needs an account.\nThis does. Takes ten seconds.',
            textAlign: TextAlign.center,
            style: epText(size: 12.5, color: Ep.inkA(.55), height: 1.5)),
        const SizedBox(height: 22),
        EpButton(' Continue with Apple',
            kind: EpButtonKind.light,
            padding: const EdgeInsets.symmetric(vertical: 14),
            onTap: app.login),
        const SizedBox(height: 14),
        EpButton('G · Continue with Google',
            kind: EpButtonKind.ghost,
            padding: const EdgeInsets.symmetric(vertical: 14),
            onTap: app.login),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: app.login,
          child: Text('Use email instead',
              textAlign: TextAlign.center,
              style: epText(size: 12, weight: FontWeight.w700, color: Ep.inkA(.65))
                  .copyWith(decoration: TextDecoration.underline, decorationColor: Ep.inkA(.65))),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: app.back,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text('← KEEP BROWSING',
                textAlign: TextAlign.center,
                style: epText(
                    size: 12, weight: FontWeight.w800, letterSpacing: 1, color: Ep.inkA(.45))),
          ),
        ),
      ],
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
        Text('WHAT DO YOU\nLIKE LOUD?', style: epDisplay(size: 24, height: 1.05)),
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
              'punk', 'hardcore', 'garage', 'noise', 'post-punk',
              'shoegaze', 'surf', 'thrash', 'ska', 'emo'
            ])
              EpChip(
                  label: t,
                  active: app.userGenres.contains(t),
                  onTap: () => app.toggleUserGenre(t)),
          ],
        ),
        const SizedBox(height: 24),
        EpButton(picked > 0 ? 'DONE — $picked PICKED' : 'DONE', onTap: app.finishAuth),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: app.finishAuth,
          child: Text('Skip for now',
              textAlign: TextAlign.center,
              style: epText(size: 12, weight: FontWeight.w700, color: Ep.inkA(.5))),
        ),
      ],
    );
  }
}
