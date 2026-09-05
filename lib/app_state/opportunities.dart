part of '../app_state.dart';

/// Organizer opportunity management, band discovery and applications, and
/// the policy controlling whether bands can write gigs.
mixin _OpportunityState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  String get bandId;
  void go(Screen s, [String? param]);

  final Map<String, List<Opportunity>> _opportunitiesByOrg = {};
  final Map<String, DataStatus> _opportunitiesStatusByOrg = {};
  final Map<String, Object> _opportunitiesLoadTokens = {};

  List<Opportunity> opportunitiesFor(String organizationId) =>
      _opportunitiesByOrg[organizationId] ?? const [];

  DataStatus opportunitiesStatus(String organizationId) =>
      _opportunitiesStatusByOrg[organizationId] ?? DataStatus.connecting;

  Future<void> refreshOpportunities(String organizationId) async {
    if (_disposed) return;
    final token = Object();
    _opportunitiesLoadTokens[organizationId] = token;
    try {
      final opportunities = await repository.manageOpportunities(
        organizationId,
      );
      if (_disposed ||
          !identical(_opportunitiesLoadTokens[organizationId], token)) {
        return;
      }
      _opportunitiesByOrg[organizationId] = opportunities;
      _opportunitiesStatusByOrg[organizationId] = DataStatus.ready;
    } catch (error) {
      if (_disposed ||
          !identical(_opportunitiesLoadTokens[organizationId], token)) {
        return;
      }
      _opportunitiesStatusByOrg[organizationId] = DataStatus.error;
      logError('manageOpportunities', error);
    }
    notifyListeners();
  }

  final Map<String, Opportunity> _opportunityById = {};
  final Map<String, Object> _opportunityByIdTokens = {};

  Future<Opportunity?> loadOpportunity(
    String id, {
    bool refresh = false,
  }) async {
    if (_disposed) return null;
    final cached = _opportunityById[id];
    if (!refresh && cached != null) return cached;
    final token = Object();
    _opportunityByIdTokens[id] = token;
    try {
      final opportunity = await repository.opportunity(id);
      if (_disposed || !identical(_opportunityByIdTokens[id], token)) {
        return null;
      }
      if (opportunity != null &&
          !identical(_opportunityById[id], opportunity)) {
        _opportunityById[id] = opportunity;
        notifyListeners();
      }
      return opportunity;
    } catch (error) {
      logError('opportunity', error);
      return null;
    }
  }

  void openOpportunityEditor([String? id]) =>
      go(Screen.opportunityEdit, id ?? 'new');

  void openOpportunityApplicants(String id) =>
      go(Screen.opportunityApplicants, id);

  OpportunityBrowseState browse = const OpportunityBrowseState();
  OpportunityFilters browseFilters = const OpportunityFilters();
  Object? _browseLoadToken;

  void setBrowseFilters(OpportunityFilters filters) {
    browseFilters = filters;
    browse = const OpportunityBrowseState(status: DataStatus.connecting);
    notifyListeners();
    unawaited(refreshBrowse());
  }

  Future<void> refreshBrowse() async {
    if (_disposed) return;
    final token = Object();
    _browseLoadToken = token;
    final requestedBandId = bandId;
    try {
      final page = await repository.browseOpportunities(
        bandId: requestedBandId.isEmpty ? null : requestedBandId,
        filters: browseFilters,
      );
      if (_disposed || !identical(_browseLoadToken, token)) return;
      final invited = requestedBandId.isEmpty
          ? const <BrowseItem>[]
          : await repository.invitedOpportunities(requestedBandId);
      if (_disposed || !identical(_browseLoadToken, token)) return;
      browse = OpportunityBrowseState(
        items: page.items,
        invited: invited,
        cursor: page.continueCursor,
        isDone: page.isDone,
        status: DataStatus.ready,
      );
    } catch (error) {
      if (_disposed || !identical(_browseLoadToken, token)) return;
      _recordBrowseError(error);
    }
    notifyListeners();
  }

  Future<void> loadMoreOpportunities() async {
    if (_disposed || browse.isDone) return;
    final token = Object();
    _browseLoadToken = token;
    try {
      final page = await repository.browseOpportunities(
        cursor: browse.cursor,
        bandId: bandId.isEmpty ? null : bandId,
        filters: browseFilters,
      );
      if (_disposed || !identical(_browseLoadToken, token)) return;
      browse = OpportunityBrowseState(
        items: [...browse.items, ...page.items],
        invited: browse.invited,
        cursor: page.continueCursor,
        isDone: page.isDone,
        status: DataStatus.ready,
      );
    } catch (error) {
      if (_disposed || !identical(_browseLoadToken, token)) return;
      _recordBrowseError(error);
    }
    notifyListeners();
  }

  void _recordBrowseError(Object error) {
    browse = OpportunityBrowseState(
      items: browse.items,
      invited: browse.invited,
      cursor: browse.cursor,
      isDone: browse.isDone,
      status: DataStatus.error,
      error: '$error',
    );
    logError('browseOpportunities', error);
  }

  List<BandApplication> myApplications = const [];
  Object? _myApplicationsLoadToken;

  Future<void> refreshMyApplications() async {
    if (_disposed) return;
    final token = Object();
    _myApplicationsLoadToken = token;
    if (bandId.isEmpty) {
      myApplications = const [];
      notifyListeners();
      return;
    }
    try {
      final applications = await repository.myApplications(bandId);
      if (_disposed || !identical(_myApplicationsLoadToken, token)) return;
      myApplications = applications;
      notifyListeners();
    } catch (error) {
      logError('myApplications', error);
    }
  }

  Future<BrowseItem?> resolveOpportunity(String ref) async {
    try {
      return await repository.resolveOpportunity(
        ref,
        bandId: bandId.isEmpty ? null : bandId,
      );
    } catch (error) {
      logError('resolveOpportunity', error);
      return null;
    }
  }

  void openOpportunity(String ref) => go(Screen.opportunityDetail, ref);

  bool gigWritePolicy = true;
  Object? _gigWritePolicyLoadToken;

  Future<void> refreshGigWritePolicy() async {
    if (_disposed) return;
    final token = Object();
    _gigWritePolicyLoadToken = token;
    try {
      final policy = await repository.gigWritePolicy();
      if (_disposed || !identical(_gigWritePolicyLoadToken, token)) return;
      gigWritePolicy = policy.bandGigWrites;
      notifyListeners();
    } catch (error) {
      logError('gigWritePolicy', error);
    }
  }

  String _lastKnownBandId = '';

  @override
  void _onBandChanged() {
    if (_lastKnownBandId == bandId) return;
    _lastKnownBandId = bandId;
    unawaited(refreshBrowse());
    unawaited(refreshMyApplications());
    unawaited(refreshGigWritePolicy());
  }

  @override
  void _clearOpportunityState() {
    // Invalidate in-flight loads before clearing the session's cached values.
    _opportunitiesLoadTokens.clear();
    _opportunityByIdTokens.clear();
    _browseLoadToken = null;
    _myApplicationsLoadToken = null;
    _gigWritePolicyLoadToken = null;
    _opportunitiesByOrg.clear();
    _opportunitiesStatusByOrg.clear();
    _opportunityById.clear();
    browse = const OpportunityBrowseState();
    browseFilters = const OpportunityFilters();
    myApplications = const [];
    gigWritePolicy = true;
    _lastKnownBandId = '';
  }
}

class OpportunityBrowseState {
  const OpportunityBrowseState({
    this.items = const [],
    this.invited = const [],
    this.cursor,
    this.isDone = false,
    this.status = DataStatus.connecting,
    this.error,
  });

  final List<BrowseItem> items;
  final List<BrowseItem> invited;
  final String? cursor;
  final bool isDone;
  final DataStatus status;
  final String? error;
}
