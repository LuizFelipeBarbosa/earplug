import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange, TimeOfDay;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_links.dart';
import 'band_identity.dart';
import 'band_media_state.dart';
import 'data/convex_repository.dart';
import 'data/demo_repository.dart';
import 'data/repository.dart';
import 'date_names.dart';
import 'discovery_filters.dart';
import 'discovery_policy.dart';
import 'errors.dart';
import 'flyer_styles.dart';
import 'memo.dart';
import 'models.dart';
import 'navigation.dart';
import 'services/auth_service.dart';
import 'services/browser_history.dart';
import 'services/flyer_text_extractor.dart';
import 'services/location_service.dart';
import 'services/media_picker.dart';
import 'services/media_upload_service.dart';

export 'date_names.dart' show dateLabel, monthLabel, timeLabel;
export 'discovery_filters.dart';
export 'discovery_policy.dart';
export 'navigation.dart';

part 'app_state/band_console.dart';
part 'app_state/band_create.dart';
part 'app_state/bookings.dart';
part 'app_state/catalog.dart';
part 'app_state/discovery.dart';
part 'app_state/fan.dart';
part 'app_state/gig_editor.dart';
part 'app_state/navigation.dart';
part 'app_state/opportunities.dart';
part 'app_state/organizer.dart';
part 'app_state/payments.dart';
part 'app_state/session.dart';
part 'app_state/venues.dart';

enum DataStatus { connecting, ready, error }

/// What every domain of [AppState] can rely on: the injected services, the
/// disposal flag, and the toast.
///
/// Derived-getter caches (the feed, the venue list, the gig index, …) are
/// keyed on the identity of the collections they read, so every collection a
/// cache reads — gigs, bands, venues, the interaction and relationship gig
/// maps — is replaced with a new instance when it changes, never mutated in
/// place. An in-place write would leave a cache serving stale derived data.
mixin _AppStateCore on ChangeNotifier {
  EarplugRepository get repository;
  AuthService get auth;
  LocationService get locationService;
  MediaUploadService get mediaUploader;
  DateTime Function() get _now;

  // ---- cross-domain private members
  // A part reaches a sibling's private member only through a shared
  // supertype. Most are redeclared in the requires block of the part that
  // needs them; the ones below are declared here instead because that would
  // leave their implementation looking unused to the analyzer (methods called
  // only from siblings, fields the owner writes but only siblings read).
  DateTime? get _nextFeedStartsAt;
  Map<String, Venue> get _venues;
  void _applyFanCity(FanCity selectedCity);
  void _invalidateVenueDetails(Set<String> ids);
  void _refreshExploreBands();
  Gig? _cachedGig(String id);
  bool _isCurrentSession(int generation);
  Future<bool> _refreshProfile({int? sessionGeneration});
  void _scheduleDiscoveryBoundaryRefresh();
  Future<void> _loadFollowBand(String bandId);
  void _syncFollowedBandGigSubscriptions();
  void _normalizeCustomDateRange();
  void _clearMemberships();
  void _restartMemberships();
  void _clearOrganizationsState();
  void _restartOrganizations();
  void _resetBandForm();
  // Implemented by _OpportunityState and called from _NavigationState.resetTo.
  void _onBandChanged();
  // Implemented by _OpportunityState and called by AppState's session cleanup.
  // AppState resolves the concrete implementation rather than this declaration.
  // ignore: unused_element
  void _clearOpportunityState();
  void _clearSessionSensitiveState();
  void _syncPublicGigSubscriptionForCurrentScreen();
  Future<void> _loadPublicGig(String id);
  Future<void> _markBandPreviewed(String id);
  Future<void> _refreshHistory();

  bool _disposed = false;
  int _discoveryBoundaryTick = 0;

  BandMediaController? _media;

  void attachMediaController(BandMediaController c) => _media = c;

  // ---- toast
  String toast = '';
  Timer? _toastTimer;

  void say(String msg) {
    toast = msg;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      toast = '';
      notifyListeners();
    });
    notifyListeners();
  }

  /// Assigns, then notifies — the shape every plain form setter has.
  void _set(void Function() assign) {
    assign();
    notifyListeners();
  }
}

class AppState extends ChangeNotifier
    with
        _AppStateCore,
        _GigEditorState,
        _BandCreateState,
        _VenueState,
        _DiscoveryState,
        _FanState,
        _BandConsoleState,
        _OpportunityState,
        _BookingState,
        _PaymentState,
        _OrganizerState,
        _CatalogState,
        _SessionState,
        _NavigationState {
  AppState({
    required EarplugRepository repository,
    required AuthService auth,
    LocationService? locationService,
    MediaUploadService? mediaUploadService,
    String? initialJoinToken,
    String? initialPerformerInviteToken,
    String? initialGigId,
    String? initialBandSlug,
    String? initialVenueRef,
    String? initialOpportunityRef,
    String? initialBookingId,
    String? initialCheckoutSessionId,
    String? initialCheckoutCancelBookingId,
    String? initialStripeReturn,
    String? initialOrgInviteToken,
    bool initialOrganizerApply = false,
    DateTime Function()? now,
  }) : this._(
         auth,
         repository,
         locationService ?? GeolocatorLocationService(),
         mediaUploadService,
         initialJoinToken,
         initialPerformerInviteToken,
         initialGigId,
         initialBandSlug,
         initialVenueRef,
         initialOpportunityRef,
         initialBookingId,
         initialCheckoutSessionId,
         initialCheckoutCancelBookingId,
         initialStripeReturn,
         initialOrgInviteToken,
         initialOrganizerApply,
         now ?? DateTime.now,
       );

  /// Offline state over in-memory demo fixtures. Its only production caller
  /// is the `EARPLUG_DEMO` branch of `main()`, so release builds that leave
  /// the flag off tree-shake [DemoRepository] and [FakeAuthService] away.
  factory AppState.demo({
    EarplugRepository? repository,
    AuthService? auth,
    LocationService? locationService,
    MediaUploadService? mediaUploadService,
    String? initialJoinToken,
    String? initialPerformerInviteToken,
    String? initialGigId,
    String? initialBandSlug,
    String? initialVenueRef,
    String? initialOpportunityRef,
    String? initialBookingId,
    String? initialCheckoutSessionId,
    String? initialCheckoutCancelBookingId,
    String? initialStripeReturn,
    String? initialOrgInviteToken,
    bool initialOrganizerApply = false,
    DateTime Function()? now,
  }) {
    final resolvedAuth = auth ?? FakeAuthService();
    return AppState(
      repository: repository ?? DemoRepository(auth: resolvedAuth),
      auth: resolvedAuth,
      locationService: locationService,
      mediaUploadService: mediaUploadService,
      initialJoinToken: initialJoinToken,
      initialPerformerInviteToken: initialPerformerInviteToken,
      initialGigId: initialGigId,
      initialBandSlug: initialBandSlug,
      initialVenueRef: initialVenueRef,
      initialOpportunityRef: initialOpportunityRef,
      initialBookingId: initialBookingId,
      initialCheckoutSessionId: initialCheckoutSessionId,
      initialCheckoutCancelBookingId: initialCheckoutCancelBookingId,
      initialStripeReturn: initialStripeReturn,
      initialOrgInviteToken: initialOrgInviteToken,
      initialOrganizerApply: initialOrganizerApply,
      now: now,
    );
  }

  AppState._(
    this.auth,
    this.repository,
    this.locationService,
    MediaUploadService? providedMediaUploader,
    String? initialJoinToken,
    String? initialPerformerInviteToken,
    String? initialGigId,
    String? initialBandSlug,
    String? initialVenueRef,
    String? initialOpportunityRef,
    String? initialBookingId,
    String? initialCheckoutSessionId,
    String? initialCheckoutCancelBookingId,
    String? initialStripeReturn,
    String? initialOrgInviteToken,
    bool initialOrganizerApply,
    this._now,
  ) : // Only a real backend has a connection to wait on; the demo data is
      // already in memory, so it must not show the connecting screen.
      _dataStatus = repository is ConvexRepository
          ? DataStatus.connecting
          : DataStatus.ready {
    mediaUploader =
        providedMediaUploader ?? MediaUploadService(repository: repository);
    _stopBrowserHistory = listenForBrowserBack(_popAppStack);
    authed = auth.signedIn;
    if (authed) {
      authStep = 2;
      _authReady = _ensureUser();
      unawaited(_authReady);
    }
    _authSubscription = auth.signedInChanges.listen(_handleAuthChange);
    _subscribeToFeed();
    _interactionsSubscription = repository.myInteractions().listen(
      _cacheInteractions,
      onError: (Object error) => logError('myInteractions', error),
    );
    // Public demo mode may preload membership-shaped sample data, but
    // authenticated routing waits for the post-refresh stream below.
    if (!authed) {
      _bandsSubscription = _listenToMemberships(
        ++_membershipsGeneration,
        requireAuthentication: false,
      );
    }
    final performerToken = initialPerformerInviteToken?.trim();
    final joinToken = initialJoinToken?.trim();
    final gigId = initialGigId?.trim();
    final bandSlug = initialBandSlug?.trim();
    final orgInviteToken = initialOrgInviteToken?.trim();
    if (performerToken != null && performerToken.isNotEmpty) {
      _stack = [ScreenEntry(Screen.gigInvite, performerToken)];
      unawaited(_resolvePerformerInvite(performerToken));
    } else if (joinToken != null && joinToken.isNotEmpty) {
      _stack = [ScreenEntry(Screen.bandJoin, joinToken)];
      unawaited(_resolveJoinInvite(joinToken));
    } else if (orgInviteToken != null && orgInviteToken.isNotEmpty) {
      _stack = [ScreenEntry(Screen.orgJoin, orgInviteToken)];
    } else if (initialOrganizerApply) {
      if (authed) {
        _stack = const [ScreenEntry(Screen.orgApply)];
      } else {
        // Clerk still needs the incoming OAuth callback query parameters.
        // Seed auth state without changing the browser URL during startup.
        pending = const PendingAuth(PendingKind.orgApply);
        _authConfirmationKind = PendingKind.orgApply;
        _stack = const [ScreenEntry(Screen.home), ScreenEntry(Screen.auth)];
      }
    } else if (gigId != null && gigId.isNotEmpty) {
      _stack = [ScreenEntry(Screen.gig, gigId)];
      unawaited(_loadPublicGig(gigId));
    } else if (bandSlug != null && bandSlug.isNotEmpty) {
      _stack = [ScreenEntry(Screen.band, bandSlug)];
      unawaited(_loadPublicBand(bandSlug));
    }

    final venueRef = initialVenueRef?.trim();
    if (venueRef != null && venueRef.isNotEmpty) {
      unawaited(_resolveInitialVenue(venueRef));
    }
    final opportunityRef = initialOpportunityRef?.trim();
    if (opportunityRef != null && opportunityRef.isNotEmpty) {
      _stack = [ScreenEntry(Screen.opportunityDetail, opportunityRef)];
      unawaited(resolveOpportunity(opportunityRef));
    }
    final bookingId = initialBookingId?.trim();
    if (bookingId != null && bookingId.isNotEmpty) {
      _stack = [
        const ScreenEntry(Screen.home),
        ScreenEntry(Screen.bookingDetail, bookingId),
      ];
      if (authed) {
        unawaited(loadBooking(bookingId));
      } else {
        // Preserve the incoming URL, including Clerk's OAuth callback params.
        pending = PendingAuth(PendingKind.booking, bookingId);
        _authConfirmationKind = PendingKind.booking;
        _stack.add(const ScreenEntry(Screen.auth));
      }
    }
    final checkoutSessionId = initialCheckoutSessionId?.trim();
    if (checkoutSessionId != null && checkoutSessionId.isNotEmpty) {
      _stack = [ScreenEntry(Screen.checkoutReturn, checkoutSessionId)];
    }
    final checkoutCancelBookingId = initialCheckoutCancelBookingId?.trim();
    if (checkoutCancelBookingId != null && checkoutCancelBookingId.isNotEmpty) {
      _stack = [ScreenEntry(Screen.checkoutCancel, checkoutCancelBookingId)];
    }
    final stripeReturn = initialStripeReturn?.trim();
    if (stripeReturn != null && stripeReturn.isNotEmpty) {
      _stack = [ScreenEntry(Screen.stripeReturn, stripeReturn)];
    }
  }

  @override
  final EarplugRepository repository;
  @override
  final AuthService auth;
  @override
  final LocationService locationService;
  @override
  final DateTime Function() _now;
  @override
  late final MediaUploadService mediaUploader;

  StreamSubscription<bool>? _authSubscription;
  StreamSubscription<Interactions>? _interactionsSubscription;
  @override
  StreamSubscription<List<BandMembership>>? _bandsSubscription;
  @override
  StreamSubscription<List<OrganizationMembership>>? _organizationsSubscription;
  @override
  DataStatus _dataStatus;
  DataStatus get dataStatus => _dataStatus;

  @override
  void dispose() {
    _disposed = true;
    _membershipsGeneration++;
    _organizationsGeneration++;
    _gigEditorGeneration++;
    _toastTimer?.cancel();
    _gigAutosaveTimer?.cancel();
    _discoveryBoundaryTimer?.cancel();
    _dayRolloverTimer?.cancel();
    _stopBrowserHistory?.call();
    _stopBrowserHistory = null;
    unawaited(_authSubscription?.cancel());
    unawaited(_feedSubscription?.cancel());
    unawaited(_goingCountsSubscription?.cancel());
    unawaited(_venueDirectorySubscription?.cancel());
    unawaited(_interactionsSubscription?.cancel());
    unawaited(_bandsSubscription?.cancel());
    unawaited(_organizationsSubscription?.cancel());
    unawaited(_publicGigSubscription?.cancel());
    _clearFollowedBandGigSubscriptions();
    super.dispose();
  }

  @override
  void _clearSessionSensitiveState() {
    _sessionGeneration++;
    authed = false;
    _clearMemberships();
    _clearOrganizationsState();
    isPlatformAdmin = false;
    rsvps = {};
    _confirmedRsvps = {};
    _pendingRsvps.clear();
    follows = {};
    saved = {};
    attended = 0;
    history = const [];
    profile = null;
    userGenres.clear();
    pending = null;
    _authReady = null;
    _authCommit = null;
    _authConfirmationKind = null;
    _postAuthScreen = null;
    authStep = 1;
    _fanGenreWrite = Future.value();
    _profileTutorialWrite = Future.value();
    _profileTutorialReplay = false;
    _fanAvatarSaveOwner = null;
    _appliedHomePersonalization = null;
    _loadingFollowBands.clear();
    _clearFollowedBandGigSubscriptions();
    _interactionGigs = const {};
    _locationRequestGeneration++;
    discoveryLocation = DiscoveryLocation.sf;
    _discoveryHomeCity = null;
    currentPosition = null;
    locating = false;
    locationFailure = null;
    filters = const DiscoveryFilters();
    query = '';
    exploreResultType = ExploreResultType.all;
    _bandSetupStatuses.clear();
    _bandSetupLoading.clear();
    _bandDiscoveryReadiness.clear();
    _bandDiscoveryLoading.clear();
    _bandDiscoveryBoundaryRefreshPending.clear();
    _bandInvites.clear();
    _bandInviteLoading.clear();
    _scheduleDiscoveryBoundaryRefresh();
    _media?.clearForSignOut();
    _resetBandForm();
    _clearOpportunityState();
    _clearBookingState();
    _clearPaymentState();
    _resetGigForm();
  }
}

/// The URL form of a name: lowercased, with every run of anything else a dash.
String _slugify(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');
