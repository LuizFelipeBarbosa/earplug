import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'screens/analytics.dart';
import 'screens/auth.dart';
import 'screens/band_create.dart';
import 'screens/band_dash.dart';
import 'screens/band_edit.dart';
import 'screens/band_profile.dart';
import 'screens/explore.dart';
import 'screens/gig_create.dart';
import 'screens/gig_detail.dart';
import 'screens/gig_manager.dart';
import 'screens/home.dart';
import 'screens/my_gigs.dart';
import 'theme.dart';
import 'widgets/tab_bars.dart';

void main() {
  runApp(const EarplugApp());
}

class EarplugApp extends StatelessWidget {
  const EarplugApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'EarPlug',
        debugShowCheckedModeBanner: false,
        theme: buildEpTheme(),
        home: const RootShell(),
      ),
    );
  }
}

const _fanTabScreens = {Screen.home, Screen.explore, Screen.myGigs};
const _bandTabScreens = {Screen.bandDash, Screen.bandEdit, Screen.gigMgr, Screen.analytics};

class RootShell extends StatelessWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final entry = app.current;

    final body = Stack(
      children: [
        Positioned.fill(child: _screenFor(entry)),
        if (_fanTabScreens.contains(entry.screen))
          const Positioned(left: 0, right: 0, bottom: 0, child: FanTabBar()),
        if (_bandTabScreens.contains(entry.screen))
          const Positioned(left: 0, right: 0, bottom: 0, child: BandTabBar()),
        if (app.toast.isNotEmpty)
          Positioned(left: 20, right: 20, bottom: 104, child: _Toast(message: app.toast)),
      ],
    );

    // On phones this fills the window; on wide screens (web/desktop) the app
    // renders as a centered phone-width column on a dark backdrop.
    return PopScope(
      canPop: !app.canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) app.back();
      },
      child: ColoredBox(
        color: Ep.pageBackdrop,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ClipRect(
              child: Scaffold(body: body),
            ),
          ),
        ),
      ),
    );
  }

  Widget _screenFor(ScreenEntry entry) {
    return switch (entry.screen) {
      Screen.home => const HomeScreen(),
      Screen.gig => GigDetailScreen(gigId: entry.param!),
      Screen.band => BandProfileScreen(bandId: entry.param!),
      Screen.explore => const ExploreScreen(),
      Screen.myGigs => const MyGigsScreen(),
      Screen.auth => const AuthScreen(),
      Screen.bandCreate => const BandCreateScreen(),
      Screen.bandDash => const BandDashScreen(),
      Screen.bandEdit => const BandEditScreen(),
      Screen.gigMgr => const GigManagerScreen(),
      Screen.gigCreate => const GigCreateScreen(),
      Screen.analytics => const AnalyticsScreen(),
    };
  }
}

class _Toast extends StatelessWidget {
  final String message;

  const _Toast({required this.message});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Ep.ink,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: .6),
                blurRadius: 30,
                offset: const Offset(0, 10)),
          ],
        ),
        child: Text(message,
            textAlign: TextAlign.center,
            style: epText(size: 12.5, weight: FontWeight.w800, color: Ep.bg)),
      ),
    );
  }
}
