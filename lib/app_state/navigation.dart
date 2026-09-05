part of '../app_state.dart';

/// The screen stack, its browser-history mirror, and every `open…`
/// entry point that pushes a screen and kicks off what it needs.
mixin _NavigationState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  bool get authed;
  String get bandId;
  String get organizationId;
  UserProfile? get profile;
  Map<String, Band> get _bands;
  Gig? gig(String id);
  Venue? knownVenue(String id);
  bool isAdminOf(String id);
  OrganizationRole? organizerRoleFor(String organizationId);
  Booking? bookingById(String id);
  ActiveIdentity identityForBooking(Booking booking);
  void ensureExploreBands();
  void needAuth(PendingAuth p);
  Future<void> loadBandProfileDetails(String id, {bool refresh = false});
  Future<void> refreshBandSetupStatus(String id);
  Future<void> refreshBandDiscoveryReadiness(String id);
  Future<void> refreshBandInvite(String id);
  Future<void> refreshManagedGigs();

  VoidCallback? _stopBrowserHistory;

  // ---- navigation
  List<ScreenEntry> _stack = const [ScreenEntry(Screen.home)];
  ScreenEntry get current => _stack.last;
  bool get canGoBack => _stack.length > 1;
  ActiveIdentity get identity {
    final screen = current.screen;
    if (screen == Screen.bookingDetail || screen == Screen.reviewCompose) {
      final booking = bookingById(current.param ?? '');
      if (booking != null) return identityForBooking(booking);
      if (organizationId.isNotEmpty) {
        return OrganizerIdentity(
          organizationId,
          organizerRoleFor(organizationId),
        );
      }
      if (bandId.isNotEmpty) return BandIdentity(bandId);
      return const PersonalIdentity();
    }
    if (organizerTabScreens.contains(screen)) {
      return OrganizerIdentity(
        organizationId,
        organizerRoleFor(organizationId),
      );
    }
    if (adminScreens.contains(screen)) return const AdminIdentity();
    if (bandTabScreens.contains(screen)) {
      if (screen == Screen.opportunityDetail && bandId.isEmpty) {
        return const PersonalIdentity();
      }
      return BandIdentity(bandId);
    }
    return const PersonalIdentity();
  }

  // ========================= navigation =========================

  void go(Screen s, [String? param]) {
    _set(() {
      _stack = [..._stack, ScreenEntry(s, param)];
      _syncPublicGigSubscriptionForCurrentScreen();
    });
    pushBrowserPath(_browserPathFor(s, param));
    if (current.screen == Screen.explore) ensureExploreBands();
  }

  void back() {
    if (_stack.length <= 1) {
      if (current.screen == Screen.gig || current.screen == Screen.orgApply) {
        resetTo(Screen.home);
      }
      return;
    }
    _popAppStack();
    replaceBrowserPath(_browserPathFor(current.screen, current.param));
  }

  void _popAppStack() {
    if (_disposed || _stack.length <= 1) return;
    _set(() {
      _stack = _stack.sublist(0, _stack.length - 1);
      _syncPublicGigSubscriptionForCurrentScreen();
    });
    _refreshVisibleBandDashboard();
    if (current.screen == Screen.explore) ensureExploreBands();
  }

  void resetTo(Screen s) {
    _set(() {
      _stack = [ScreenEntry(s)];
      _syncPublicGigSubscriptionForCurrentScreen();
    });
    replaceBrowserPath(_browserPathFor(s, null));
    _refreshVisibleBandDashboard();
    _onBandChanged();
    if (current.screen == Screen.explore) ensureExploreBands();
  }

  String _browserPathFor(Screen screen, String? param) => switch (screen) {
    Screen.gig => '/g/${gig(param ?? '')?.publicRef ?? param ?? ''}',
    Screen.band => '/${_bands[param]?.publicRef ?? param ?? ''}',
    Screen.venue => _venueBrowserPath(param),
    Screen.orgJoin => '/apply/${param ?? ''}',
    Screen.opportunityDetail => '/opportunities/${param ?? ''}',
    Screen.orgApply => organizerApplyPath,
    _ => '/',
  };

  String _venueBrowserPath(String? param) {
    final requestedRef = param ?? '';
    final venue = knownVenue(requestedRef);
    final slug = venue?.slug?.trim();
    final browserRef = slug != null && slug.isNotEmpty
        ? slug
        : venue?.id ?? requestedRef;
    return '/venues/$browserRef';
  }

  void _refreshVisibleBandDashboard() {
    if (current.screen == Screen.bandDash && bandId.isNotEmpty) {
      unawaited(refreshBandSetupStatus(bandId));
      unawaited(refreshBandDiscoveryReadiness(bandId));
    }
  }

  void openGig(String id) {
    if (current.screen == Screen.gig && current.param == id) return;
    go(Screen.gig, id);
    unawaited(_loadPublicGig(id));
  }

  void openBand(String id) {
    go(Screen.band, id);
    unawaited(loadBandProfileDetails(id));
    if (_bands[id]?.isSummary == true) unawaited(_loadFollowBand(id));
  }

  void previewPublicProfile() {
    final id = bandId;
    if (id.isEmpty) return;
    go(Screen.bandPreview, id);
    unawaited(loadBandProfileDetails(id));
    unawaited(_markBandPreviewed(id));
  }

  void returnToBandDashboard() => resetTo(Screen.bandDash);

  void openBandEditor({String? section}) {
    if (!isAdminOf(bandId)) return;
    go(Screen.bandEdit, section);
    unawaited(loadBandProfileDetails(bandId, refresh: true));
    if (section == 'members') unawaited(refreshBandInvite(bandId));
  }

  void openInvitationPanel() => openBandEditor(section: 'members');

  void openVenue(String id) {
    if (current.screen == Screen.venue && current.param == id) return;
    _invalidateVenueDetails({id});
    go(Screen.venue, id);
  }

  void openBandMedia() => go(Screen.bandMedia, bandId);

  void openGigManager() {
    resetTo(Screen.gigMgr);
    unawaited(refreshManagedGigs());
  }

  void openMyGigsTab() {
    if (authed) {
      unawaited(_refreshHistory());
      resetTo(Screen.myGigs);
    } else {
      needAuth(const PendingAuth(PendingKind.myGigs));
    }
  }

  void openEditProfile() {
    if (authed && profile != null) {
      go(Screen.editProfile);
    } else if (authed) {
      say('Your profile is still loading.');
      unawaited(_refreshProfile());
    } else {
      needAuth(const PendingAuth(PendingKind.myGigs));
    }
  }

  void openSettings() {
    if (authed) {
      go(Screen.settings);
    } else {
      needAuth(const PendingAuth(PendingKind.myGigs));
    }
  }
}
