part of '../app_state.dart';

/// Organization memberships, the selected organizer identity, and the
/// lightweight application state used by the organizer entry points.
mixin _OrganizerState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  bool get authed;
  int get _sessionGeneration;
  StreamSubscription<List<OrganizationMembership>>?
  get _organizationsSubscription;
  set _organizationsSubscription(
    StreamSubscription<List<OrganizationMembership>>? value,
  );
  void go(Screen s, [String? param]);
  void resetTo(Screen s);
  void openVenue(String id);

  int _organizationsGeneration = 0;

  String organizationId = '';
  List<OrganizationMembership> myOrganizations = const [];
  OrganizationApplication? myOrganizationApplication;

  OrganizationRole? organizerRoleFor(String organizationId) => myOrganizations
      .where((membership) => membership.organization.id == organizationId)
      .firstOrNull
      ?.role;

  bool canManageOrganization(String id) => switch (organizerRoleFor(id)) {
    OrganizationRole.owner || OrganizationRole.manager => true,
    _ => false,
  };

  bool canSeeFinance(String id) => switch (organizerRoleFor(id)) {
    OrganizationRole.owner || OrganizationRole.finance => true,
    _ => false,
  };

  bool canWorkDoor(String id) => organizerRoleFor(id) != null;

  OrganizationMembership? get currentOrganization => myOrganizations
      .where((membership) => membership.organization.id == organizationId)
      .firstOrNull;

  bool get hasOrganizerApplication => myOrganizationApplication != null;

  void switchToOrganization(String id) {
    organizationId = id;
    resetTo(Screen.orgDash);
  }

  @override
  void _restartOrganizations() {
    final generation = ++_organizationsGeneration;
    final previousSubscription = _organizationsSubscription;
    _organizationsSubscription = null;
    unawaited(previousSubscription?.cancel());
    if (_disposed || !authed || generation != _organizationsGeneration) return;

    _organizationsSubscription = repository.myOrganizations().listen(
      (memberships) {
        if (_disposed || !authed || generation != _organizationsGeneration) {
          return;
        }
        myOrganizations = memberships;
        notifyListeners();
      },
      onError: (Object error) {
        if (!_disposed && authed && generation == _organizationsGeneration) {
          logError('myOrganizations', error);
        }
      },
    );
  }

  @override
  void _clearOrganizationsState() {
    _organizationsGeneration++;
    final subscription = _organizationsSubscription;
    _organizationsSubscription = null;
    unawaited(subscription?.cancel());
    myOrganizations = const [];
    organizationId = '';
    myOrganizationApplication = null;
  }

  Future<void> refreshOrganizationApplication() async {
    final requestedSession = _sessionGeneration;
    if (!_isCurrentSession(requestedSession)) return;
    try {
      final application = await repository.myOrganizationApplication();
      if (!_isCurrentSession(requestedSession)) return;
      myOrganizationApplication = application;
      notifyListeners();
    } catch (error) {
      logError('myOrganizationApplication', error);
    }
  }

  void openOrganizerApply() => go(Screen.orgApply);

  void openOrganizationJoin(String token) => go(Screen.orgJoin, token);

  Future<void> _resolveInitialVenue(String ref) async {
    try {
      final venue = await repository.resolveVenue(ref);
      if (_disposed) return;
      if (venue == null) {
        say('Venue not found');
        return;
      }
      openVenue(venue.id);
    } catch (error) {
      logError('resolveVenue', error);
    }
  }
}
