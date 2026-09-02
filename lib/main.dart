import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'band_media_state.dart';
import 'data/convex_repository.dart';
import 'data/repository.dart';
import 'env.dart';
import 'screens/analytics.dart';
import 'screens/auth.dart';
import 'screens/band_create.dart';
import 'screens/band_dash.dart';
import 'screens/band_edit.dart';
import 'screens/band_join.dart';
import 'screens/band_media.dart';
import 'screens/band_profile.dart';
import 'screens/edit_profile.dart';
import 'screens/explore.dart';
import 'screens/gig_create.dart';
import 'screens/gig_detail.dart';
import 'screens/gig_invite.dart';
import 'screens/gig_manager.dart';
import 'screens/home.dart';
import 'screens/my_gigs.dart';
import 'screens/settings.dart';
import 'screens/venue_detail.dart';
import 'services/appearance_controller.dart';
import 'services/auth_service.dart';
import 'services/auth_service_factory.dart';
import 'services/convex_service.dart';
import 'services/stadia_map_style_repository.dart';
import 'theme.dart';
import 'widgets/branding.dart';
import 'widgets/common.dart';
import 'widgets/tab_bars.dart';

SemanticsHandle? _webSemanticsHandle;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Flutter web otherwise waits for an accessibility request before building
  // its semantic DOM. Keeping one handle alive makes the app keyboard- and
  // screen-reader-discoverable from the first rendered frame.
  if (kIsWeb) {
    _webSemanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
  }
  final appearance = await AppearanceController.load();
  final joinToken = joinTokenFromUri(Uri.base);
  final performerInviteToken = performerInviteTokenFromUri(Uri.base);
  final gigId = gigIdFromUri(Uri.base);
  final bandSlug = bandSlugFromUri(Uri.base);
  if (Env.demo) {
    runApp(
      EarplugApp(
        appearance: appearance,
        initialJoinToken: joinToken,
        initialPerformerInviteToken: performerInviteToken,
        initialGigId: gigId,
        initialBandSlug: bandSlug,
      ),
    );
    return;
  }
  final configError = Env.configurationError;
  if (configError != null) {
    runApp(_ConfigErrorApp(message: configError, appearance: appearance));
    return;
  }

  final convexService = ConvexService();
  await convexService.init(Env.convexUrl);
  final auth = createPlatformAuthService();
  await auth.initialize();
  convexService.setTokenFetcher(auth.fetchConvexToken);
  final repository = ConvexRepository(convexService);
  runApp(
    EarplugApp(
      appearance: appearance,
      repository: repository,
      auth: auth,
      initialJoinToken: joinToken,
      initialPerformerInviteToken: performerInviteToken,
      initialGigId: gigId,
      initialBandSlug: bandSlug,
    ),
  );
}

String? _routeValueFromUri(Uri uri, String route) {
  String? fromSegments(List<String> segments) {
    final routeIndex = segments.indexOf(route);
    if (routeIndex == -1 || routeIndex + 1 >= segments.length) return null;
    final value = segments[routeIndex + 1].trim();
    return value.isEmpty ? null : value;
  }

  final pathValue = fromSegments(uri.pathSegments);
  if (pathValue != null) return pathValue;
  final fragment = uri.fragment;
  if (fragment.isEmpty) return null;
  return fromSegments(
    Uri.parse(fragment.startsWith('/') ? fragment : '/$fragment').pathSegments,
  );
}

String? joinTokenFromUri(Uri uri) => _routeValueFromUri(uri, 'join');

String? performerInviteTokenFromUri(Uri uri) =>
    _routeValueFromUri(uri, 'gig-invite');

String? gigIdFromUri(Uri uri) => _routeValueFromUri(uri, 'g');

String? bandSlugFromUri(Uri uri) {
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.length != 1) return null;
  final slug = segments.single.trim().toLowerCase();
  if (slug.isEmpty ||
      const {'g', 'join', 'gig-invite', 'check-in'}.contains(slug)) {
    return null;
  }
  return slug;
}

/// Shown instead of the app when the build is misconfigured — no backend, no
/// Clerk key, or a Clerk key paired with the wrong deployment. Loud on purpose:
/// the alternatives are a silent fall back to demo data, or signing in against
/// one environment while reading another and calling the empty result a bug.
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp({required this.message, required this.appearance});

  final String message;
  final AppearanceController appearance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appearance,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildEpTheme(Brightness.light),
        darkTheme: buildEpTheme(Brightness.dark),
        themeMode: appearance.mode,
        home: Builder(
          builder: (context) => ColoredBox(
            color: context.epColors.background,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('NOT CONFIGURED', style: epDisplay(size: 22)),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: epText(
                        size: 13,
                        color: context.epColors.contentSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EarplugApp extends StatelessWidget {
  const EarplugApp({
    super.key,
    required this.appearance,
    this.repository,
    this.auth,
    this.initialJoinToken,
    this.initialPerformerInviteToken,
    this.initialGigId,
    this.initialBandSlug,
  });

  final AppearanceController appearance;
  final EarplugRepository? repository;
  final AuthService? auth;
  final String? initialJoinToken;
  final String? initialPerformerInviteToken;
  final String? initialGigId;
  final String? initialBandSlug;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppearanceController>.value(value: appearance),
        Provider<StadiaMapStyleRepository>(
          create: (_) => StadiaMapStyleRepository(apiKey: Env.stadiaMapsApiKey),
          dispose: (_, repository) => repository.dispose(),
        ),
        ChangeNotifierProvider(
          create: (_) => repository == null && auth == null
              ? AppState(
                  initialJoinToken: initialJoinToken,
                  initialPerformerInviteToken: initialPerformerInviteToken,
                  initialGigId: initialGigId,
                  initialBandSlug: initialBandSlug,
                )
              : AppState(
                  repository: repository,
                  auth: auth,
                  initialJoinToken: initialJoinToken,
                  initialPerformerInviteToken: initialPerformerInviteToken,
                  initialGigId: initialGigId,
                  initialBandSlug: initialBandSlug,
                ),
        ),
        ChangeNotifierProvider<BandMediaController>(
          create: (ctx) {
            final app = ctx.read<AppState>();
            final controller = BandMediaController(
              repository: app.repository,
              say: app.say,
            );
            app.attachMediaController(controller);
            return controller;
          },
        ),
      ],
      child: Consumer<AppearanceController>(
        builder: (_, appearance, _) => MaterialApp(
          title: 'EarPlug',
          debugShowCheckedModeBanner: false,
          theme: buildEpTheme(Brightness.light),
          darkTheme: buildEpTheme(Brightness.dark),
          themeMode: appearance.mode,
          themeAnimationDuration: const Duration(milliseconds: 180),
          // A corner ribbon on everything that is not production, so which
          // dataset you are looking at is never a guess.
          builder: (context, child) {
            final app = child ?? const SizedBox.shrink();
            final label = _environmentRibbon();
            if (label == null) return app;
            return Banner(
              message: label,
              location: BannerLocation.topEnd,
              color: context.epColors.contentPrimary,
              textStyle: epText(
                size: 10,
                weight: FontWeight.w800,
                color: context.epColors.background,
              ),
              child: app,
            );
          },
          home: const RootShell(),
        ),
      ),
    );
  }
}

/// Null in production, so the live app carries no ribbon.
String? _environmentRibbon() {
  if (Env.demo) return 'DEMO';
  return Env.convexTier == DeploymentTier.development ? 'DEV' : null;
}

const _fanTabScreens = {Screen.home, Screen.explore, Screen.myGigs};
const _bandTabScreens = {
  Screen.bandDash,
  Screen.bandEdit,
  Screen.gigMgr,
  Screen.analytics,
};

class RootShell extends StatelessWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final entry = app.current;

    final body = switch (app.dataStatus) {
      DataStatus.connecting => ColoredBox(
        color: context.epColors.background,
        child: const Center(child: EpLogo.full(width: 190)),
      ),
      DataStatus.error => ColoredBox(
        color: context.epColors.background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  app.dataError ?? "Couldn't load the feed.",
                  textAlign: TextAlign.center,
                  style: epText(
                    size: 14,
                    color: context.epColors.contentSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 220,
                  child: EpButton('RETRY', onTap: app.retry),
                ),
              ],
            ),
          ),
        ),
      ),
      DataStatus.ready => Stack(
        children: [
          Positioned.fill(child: _screenFor(entry)),
          if (_fanTabScreens.contains(entry.screen))
            const Positioned(left: 0, right: 0, bottom: 0, child: FanTabBar()),
          if (_bandTabScreens.contains(entry.screen))
            const Positioned(left: 0, right: 0, bottom: 0, child: BandTabBar()),
          if (app.toast.isNotEmpty)
            Positioned(
              left: 20,
              right: 20,
              bottom: 104,
              child: _Toast(message: app.toast),
            ),
        ],
      ),
    };

    // On phones this fills the window; on wide screens (web/desktop) the app
    // renders as a centered phone-width column on a dark backdrop.
    return PopScope(
      canPop: !app.canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) app.back();
      },
      child: ColoredBox(
        color: context.epColors.surface,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ClipRect(child: Scaffold(body: body)),
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
      Screen.bandPreview => BandProfileScreen(bandId: entry.param!),
      Screen.bandJoin => const BandJoinScreen(),
      Screen.gigInvite => const GigInviteScreen(),
      Screen.venue => VenueDetailScreen(venueId: entry.param!),
      Screen.explore => const ExploreScreen(),
      Screen.myGigs => const MyGigsScreen(),
      Screen.editProfile => const EditProfileScreen(),
      Screen.settings => const SettingsScreen(),
      Screen.auth => const AuthScreen(),
      Screen.bandCreate => const BandCreateScreen(),
      Screen.bandDash => const BandDashScreen(),
      Screen.bandEdit => const BandEditScreen(),
      Screen.bandMedia => BandMediaScreen(bandId: entry.param!),
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
    return Semantics(
      container: true,
      liveRegion: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        builder: (context, t, child) {
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - t)),
              child: child,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: context.epColors.contentPrimary,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .6),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: epText(
              size: 12.5,
              weight: FontWeight.w800,
              color: context.epColors.background,
            ),
          ),
        ),
      ),
    );
  }
}
