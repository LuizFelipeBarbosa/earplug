import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import 'app_links.dart';
import 'app_state.dart';
import 'band_media_state.dart';
import 'data/convex_repository.dart';
import 'data/repository.dart';
import 'env.dart';
import 'errors.dart';
import 'screens/admin_application.dart';
import 'screens/admin_queue.dart';
import 'screens/analytics.dart';
import 'screens/auth.dart';
import 'screens/band_create.dart';
import 'screens/band_dash.dart';
import 'screens/band_edit.dart';
import 'screens/band_join.dart';
import 'screens/band_media.dart';
import 'screens/band_profile.dart';
import 'screens/booking_detail.dart';
import 'screens/edit_profile.dart';
import 'screens/explore.dart';
import 'screens/gig_create.dart';
import 'screens/gig_detail.dart';
import 'screens/gig_invite.dart';
import 'screens/gig_manager.dart';
import 'screens/home.dart';
import 'screens/my_gigs.dart';
import 'screens/opportunity_applicants.dart';
import 'screens/opportunity_detail.dart';
import 'screens/opportunity_edit.dart';
import 'screens/org_application_status.dart';
import 'screens/org_apply.dart';
import 'screens/org_dash.dart';
import 'screens/org_join.dart';
import 'screens/org_opportunities.dart';
import 'screens/org_settings.dart';
import 'screens/org_team.dart';
import 'screens/org_venue_edit.dart';
import 'screens/org_venues.dart';
import 'screens/review_compose.dart';
import 'screens/settings.dart';
import 'screens/venue_detail.dart';
import 'services/appearance_controller.dart';
import 'services/auth_service.dart';
import 'services/auth_service_factory.dart';
import 'services/convex_service.dart';
import 'services/geocoding_service.dart';
import 'services/stadia_map_style_repository.dart';
import 'services/web_shell.dart';
import 'theme.dart';
import 'widgets/branding.dart';
import 'widgets/common.dart';
import 'widgets/perf_overlay.dart';
import 'widgets/tab_bars.dart';

SemanticsHandle? _webSemanticsHandle;
final _lightTheme = buildEpTheme(Brightness.light);
final _darkTheme = buildEpTheme(Brightness.dark);

bool shouldEnableWebSemantics({
  required String? queryValue,
  required bool stored,
}) {
  if (queryValue == '1') return true;
  if (queryValue == '0') return false;
  return stored;
}

void _removeSplashAfterFirstFrame() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    webShell.removeSplash();
    webShell.mark('ep:first-frame');
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    final queryValue = Uri.base.queryParameters['a11y'];
    final enableSemantics = shouldEnableWebSemantics(
      queryValue: queryValue,
      stored: webShell.readA11yPreference(),
    );
    // Eager semantics keeps a permanent DOM tree alive, so this remains opt-in
    // for performance. Flutter's accessibility placeholder still works without
    // it; see docs/performance.md for the persistent URL preference.
    if (enableSemantics) {
      _webSemanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
    }
    if (queryValue == '1') {
      webShell.writeA11yPreference(true);
    } else if (queryValue == '0') {
      webShell.writeA11yPreference(false);
    }
  }
  final appearance = await AppearanceController.load();
  final joinToken = joinTokenFromUri(Uri.base);
  final performerInviteToken = performerInviteTokenFromUri(Uri.base);
  final gigId = gigIdFromUri(Uri.base);
  final bandSlug = bandSlugFromUri(Uri.base);
  final venueRef = venueRefFromUri(Uri.base);
  final opportunityRef = opportunityRefFromUri(Uri.base);
  final bookingId = bookingIdFromUri(Uri.base);
  final orgInviteToken = orgInviteTokenFromUri(Uri.base);
  final organizerApply = organizerApplyFromUri(Uri.base);
  if (Env.demo) {
    final appState = AppState.demo(
      initialJoinToken: joinToken,
      initialPerformerInviteToken: performerInviteToken,
      initialGigId: gigId,
      initialBandSlug: bandSlug,
      initialVenueRef: venueRef,
      initialOpportunityRef: opportunityRef,
      initialBookingId: bookingId,
      initialOrgInviteToken: orgInviteToken,
      initialOrganizerApply: organizerApply,
    );
    runApp(
      EarplugApp(
        appearance: appearance,
        repository: appState.repository,
        auth: appState.auth,
        appState: appState,
      ),
    );
    _removeSplashAfterFirstFrame();
    return;
  }
  final configError = Env.configurationError;
  if (configError != null) {
    runApp(_ConfigErrorApp(message: configError, appearance: appearance));
    _removeSplashAfterFirstFrame();
    return;
  }

  final convexService = ConvexService();
  await convexService.init(Env.convexUrl);
  final auth = createPlatformAuthService();
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
      initialVenueRef: venueRef,
      initialOpportunityRef: opportunityRef,
      initialBookingId: bookingId,
      initialOrgInviteToken: orgInviteToken,
      initialOrganizerApply: organizerApply,
    ),
  );
  _removeSplashAfterFirstFrame();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      auth.initialize().catchError((Object error) {
        logError('auth.initialize', error);
      }),
    );
    convexService.setTokenFetcher(() async {
      try {
        return await auth.fetchConvexToken();
      } catch (error) {
        logError('fetchConvexToken', error);
        rethrow;
      }
    });
  });
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

String? venueRefFromUri(Uri uri) => _routeValueFromUri(uri, 'venues');

String? opportunityRefFromUri(Uri uri) =>
    _routeValueFromUri(uri, 'opportunities');

String? bookingIdFromUri(Uri uri) => _routeValueFromUri(uri, 'bookings');

String? orgInviteTokenFromUri(Uri uri) => _routeValueFromUri(uri, 'apply');

bool organizerApplyFromUri(Uri uri) =>
    uri.path == organizerApplyPath || uri.path == '$organizerApplyPath/';

String? bandSlugFromUri(Uri uri) {
  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.length != 1) return null;
  final slug = segments.single.trim().toLowerCase();
  // Marketplace routes include a second segment, so their bare prefixes can
  // still resolve band slugs issued by the backend (including the `band`
  // fallback). Only these original roots were excluded from slug allocation.
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
        theme: _lightTheme,
        darkTheme: _darkTheme,
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
    required this.repository,
    required this.auth,
    this.appState,
    this.initialJoinToken,
    this.initialPerformerInviteToken,
    this.initialGigId,
    this.initialBandSlug,
    this.initialVenueRef,
    this.initialOpportunityRef,
    this.initialBookingId,
    this.initialOrgInviteToken,
    this.initialOrganizerApply = false,
  });

  final AppearanceController appearance;
  final EarplugRepository repository;
  final AuthService auth;
  final AppState? appState;
  final String? initialJoinToken;
  final String? initialPerformerInviteToken;
  final String? initialGigId;
  final String? initialBandSlug;
  final String? initialVenueRef;
  final String? initialOpportunityRef;
  final String? initialBookingId;
  final String? initialOrgInviteToken;
  final bool initialOrganizerApply;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppearanceController>.value(value: appearance),
        Provider<StadiaMapStyleRepository>(
          create: (_) => StadiaMapStyleRepository(apiKey: Env.stadiaMapsApiKey),
          dispose: (_, repository) => repository.dispose(),
        ),
        Provider<GeocodingService>(
          create: (_) => StadiaGeocodingService(apiKey: Env.stadiaMapsApiKey),
          dispose: (_, service) =>
              (service as StadiaGeocodingService).dispose(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              appState ??
              AppState(
                repository: repository,
                auth: auth,
                initialJoinToken: initialJoinToken,
                initialPerformerInviteToken: initialPerformerInviteToken,
                initialGigId: initialGigId,
                initialBandSlug: initialBandSlug,
                initialVenueRef: initialVenueRef,
                initialOpportunityRef: initialOpportunityRef,
                initialBookingId: initialBookingId,
                initialOrgInviteToken: initialOrgInviteToken,
                initialOrganizerApply: initialOrganizerApply,
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
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: appearance.mode,
          themeAnimationDuration: kIsWeb
              ? Duration.zero
              : const Duration(milliseconds: 180),
          // A corner ribbon on everything that is not production, so which
          // dataset you are looking at is never a guess.
          builder: (context, child) {
            final app = child ?? const SizedBox.shrink();
            final label = _environmentRibbon();
            final wrappedApp = label == null
                ? app
                : Banner(
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
            if (!PerfOverlay.enabled) return wrappedApp;
            return Stack(
              children: [
                wrappedApp,
                PerfOverlay(
                  marks: webShell.marks,
                  extraStats: ConvexService.debugStats,
                ),
              ],
            );
          },
          home: const _FeedReadyMarker(child: RootShell()),
        ),
      ),
    );
  }
}

class _FeedReadyMarker extends StatefulWidget {
  const _FeedReadyMarker({required this.child});

  final Widget child;

  @override
  State<_FeedReadyMarker> createState() => _FeedReadyMarkerState();
}

class _FeedReadyMarkerState extends State<_FeedReadyMarker> {
  AppState? _app;
  bool _marked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (identical(app, _app)) return;

    _app?.removeListener(_markWhenReady);
    _app = app;
    if (_marked) return;
    app.addListener(_markWhenReady);
    _markWhenReady();
  }

  void _markWhenReady() {
    final app = _app;
    if (_marked || app?.dataStatus != DataStatus.ready) return;
    _marked = true;
    app?.removeListener(_markWhenReady);
    webShell.mark('ep:feed-ready');
  }

  @override
  void dispose() {
    _app?.removeListener(_markWhenReady);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Null in production, so the live app carries no ribbon.
String? _environmentRibbon() {
  if (Env.demo) return 'DEMO';
  return Env.convexTier == DeploymentTier.development ? 'DEV' : null;
}

class RootShell extends StatelessWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context) {
    final (
      dataStatus,
      screen,
      param,
      canGoBack,
      dataError,
      bandId,
      identityIsOrganizer,
    ) = context
        .select<
          AppState,
          (DataStatus, Screen, String?, bool, String?, String, bool)
        >((app) {
          final current = app.current;
          return (
            app.dataStatus,
            current.screen,
            current.param,
            app.canGoBack,
            app.dataError,
            app.bandId,
            app.identity is OrganizerIdentity,
          );
        });
    final app = context.read<AppState>();
    final entry = ScreenEntry(screen, param);
    final showOpportunityAsFanTab =
        screen == Screen.opportunityDetail && bandId.isEmpty;
    final isDualBookingScreen =
        screen == Screen.bookingDetail || screen == Screen.reviewCompose;
    final showBookingAsOrganizerTab =
        isDualBookingScreen && identityIsOrganizer;

    final body = switch (dataStatus) {
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
                  dataError ?? "Couldn't load the feed.",
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
          if (fanTabScreens.contains(screen) || showOpportunityAsFanTab)
            const Positioned(left: 0, right: 0, bottom: 0, child: FanTabBar()),
          if (bandTabScreens.contains(screen) &&
              !showOpportunityAsFanTab &&
              (!isDualBookingScreen || !showBookingAsOrganizerTab))
            const Positioned(left: 0, right: 0, bottom: 0, child: BandTabBar()),
          if (organizerTabScreens.contains(screen) &&
              (!isDualBookingScreen || showBookingAsOrganizerTab))
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: OrganizerTabBar(),
            ),
          const _ToastLayer(),
        ],
      ),
    };

    // On phones this fills the window; on wide screens (web/desktop) the app
    // renders as a centered phone-width column on a dark backdrop.
    return PopScope(
      canPop: !canGoBack,
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
    final key = ValueKey('${entry.screen.name}-${entry.param}');
    return switch (entry.screen) {
      Screen.home => HomeScreen(key: key),
      Screen.gig => GigDetailScreen(key: key, gigId: entry.param!),
      Screen.band => BandProfileScreen(key: key, bandId: entry.param!),
      Screen.bandPreview => BandProfileScreen(key: key, bandId: entry.param!),
      Screen.bandJoin => BandJoinScreen(key: key),
      Screen.gigInvite => GigInviteScreen(key: key),
      Screen.venue => VenueDetailScreen(key: key, venueId: entry.param!),
      Screen.explore => ExploreScreen(key: key),
      Screen.myGigs => MyGigsScreen(key: key),
      Screen.editProfile => EditProfileScreen(key: key),
      Screen.settings => SettingsScreen(key: key),
      Screen.auth => AuthScreen(key: key),
      Screen.bandCreate => BandCreateScreen(key: key),
      Screen.bandDash => BandDashScreen(key: key),
      Screen.bandEdit => BandEditScreen(key: key),
      Screen.bandMedia => BandMediaScreen(key: key, bandId: entry.param!),
      Screen.gigMgr => GigManagerScreen(key: key),
      Screen.gigCreate => GigCreateScreen(key: key),
      Screen.analytics => AnalyticsScreen(key: key),
      Screen.orgApply => OrgApplyScreen(key: key),
      Screen.orgApplicationStatus => OrgApplicationStatusScreen(key: key),
      Screen.orgJoin => OrgJoinScreen(key: key, token: entry.param!),
      Screen.orgDash => OrgDashScreen(key: key),
      Screen.orgVenues => OrgVenuesScreen(key: key),
      Screen.orgVenueEdit => OrgVenueEditScreen(
        key: key,
        venueId: entry.param!,
      ),
      Screen.orgTeam => OrgTeamScreen(key: key),
      Screen.orgSettings => OrgSettingsScreen(key: key),
      Screen.orgOpportunities => OrgOpportunitiesScreen(key: key),
      Screen.opportunityEdit => OpportunityEditScreen(
        key: key,
        opportunityId: entry.param!,
      ),
      Screen.opportunityApplicants => OpportunityApplicantsScreen(
        key: key,
        opportunityId: entry.param!,
      ),
      Screen.opportunityDetail => OpportunityDetailScreen(
        key: key,
        opportunityRef: entry.param!,
      ),
      Screen.bookingDetail => BookingDetailScreen(
        key: key,
        bookingId: entry.param!,
      ),
      Screen.reviewCompose => ReviewComposeScreen(
        key: key,
        bookingId: entry.param!,
      ),
      Screen.adminQueue => AdminQueueScreen(key: key),
      Screen.adminApplication => AdminApplicationScreen(
        key: key,
        applicationId: entry.param!,
      ),
    };
  }
}

class _ToastLayer extends StatelessWidget {
  const _ToastLayer();

  @override
  Widget build(BuildContext context) {
    final toast = context.select<AppState, String>((app) => app.toast);
    return Positioned(
      left: 20,
      right: 20,
      bottom: 104,
      child: toast.isEmpty ? const SizedBox.shrink() : _Toast(message: toast),
    );
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
