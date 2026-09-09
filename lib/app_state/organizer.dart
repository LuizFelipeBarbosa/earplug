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
  void needAuth(PendingAuth p);
  void openVenue(String id);

  int _organizationsGeneration = 0;

  String organizationId = '';
  List<OrganizationMembership> myOrganizations = const [];
  OrganizationApplication? myOrganizationApplication;

  bool isHostOrganization(String id) =>
      myOrganizations
          .where((membership) => membership.organization.id == id)
          .firstOrNull
          ?.organization
          .orgType ==
      OrganizationType.privateHost;

  bool get currentIsHost => isHostOrganization(organizationId);

  bool isVenueOperatorOrganization(String id) =>
      myOrganizations
          .where((membership) => membership.organization.id == id)
          .firstOrNull
          ?.organization
          .orgType ==
      OrganizationType.venueOperator;

  bool get currentIsVenueOperator =>
      isVenueOperatorOrganization(organizationId);

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

  bool get hasHostApplication =>
      myOrganizationApplication?.kind == ApplicationKind.host;

  void switchToOrganization(String id) {
    organizationId = id;
    resetTo(Screen.orgDash);
  }

  Future<bool> requestVenueApproval(
    String opportunityId, {
    String? message,
  }) async {
    try {
      await repository.requestVenueConsent(
        opportunityId: opportunityId,
        message: message,
      );
      say('Venue approval requested');
      return true;
    } catch (error) {
      logError('requestVenueConsent', error);
      say(_venueApprovalErrorMessage(error));
      return false;
    }
  }

  Future<bool> withdrawVenueApproval(String consentId) async {
    try {
      await repository.withdrawVenueConsent(consentId);
      say('Venue approval request withdrawn');
      return true;
    } catch (error) {
      logError('withdrawVenueConsent', error);
      say(_venueApprovalErrorMessage(error));
      return false;
    }
  }

  Future<bool> decideVenueApproval(
    String consentId, {
    required bool granted,
    String? note,
  }) async {
    try {
      await repository.decideVenueConsent(
        consentId: consentId,
        granted: granted,
        note: note,
      );
      say(granted ? 'Venue approval granted' : 'Venue approval declined');
      return true;
    } catch (error) {
      logError('decideVenueConsent', error);
      say(_venueApprovalErrorMessage(error));
      return false;
    }
  }

  Future<bool> revokeVenueApproval(String consentId, {String? note}) async {
    try {
      await repository.revokeVenueConsent(consentId, note: note);
      say('Venue approval revoked');
      return true;
    } catch (error) {
      logError('revokeVenueConsent', error);
      say(_venueApprovalErrorMessage(error));
      return false;
    }
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

  void openOrganizerApply() {
    if (!authed) {
      needAuth(const PendingAuth(PendingKind.orgApply));
      return;
    }
    go(Screen.orgApply);
  }

  void openHostApply() {
    if (!authed) {
      needAuth(const PendingAuth(PendingKind.hostApply));
      return;
    }
    go(Screen.hostApply);
  }

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

/// Extracts a user-facing reason from a venue-approval repository error,
/// mirroring `serverErrorMessage` in widgets/form_bits.dart without taking
/// a dependency on that widget file. Demo/Convex errors surface as
/// `Bad state: <message>` (StateError) or `Uncaught Error: <message>`
/// (Convex server errors); fall back to the generic message otherwise.
String _venueApprovalErrorMessage(Object error) {
  final text = error.toString();
  const uncaughtMarker = 'Uncaught Error:';
  final uncaughtIndex = text.lastIndexOf(uncaughtMarker);
  if (uncaughtIndex >= 0) {
    for (final line
        in text.substring(uncaughtIndex + uncaughtMarker.length).split('\n')) {
      final message = line.trim();
      if (message.isNotEmpty) return message;
    }
  }
  for (final prefix in const ['Bad state: ', 'Exception: ', 'ConvexError: ']) {
    if (text.startsWith(prefix)) return text.substring(prefix.length).trim();
  }
  return genericErrorMessage;
}
