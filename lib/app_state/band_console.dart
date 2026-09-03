part of '../app_state.dart';

/// The band side of the app: memberships and roles, the selected band,
/// its profile details, setup and discovery readiness, invites, join and
/// performer-invite flows, history and recap.
mixin _BandConsoleState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  bool get authed;
  StreamSubscription<List<BandMembership>>? get _bandsSubscription;
  set _bandsSubscription(StreamSubscription<List<BandMembership>>? value);
  set _stack(List<ScreenEntry> value);
  Map<String, Band> get _bands;
  set _bands(Map<String, Band> value);
  List<Gig> get allGigs;
  set managedGigsBandId(String? value);
  Band? band(String id);
  void resetTo(Screen s);
  void needAuth(PendingAuth p);
  Future<void> refreshManagedGigs();

  int _membershipsGeneration = 0;

  final Map<String, String> _bandRoles = {};

  /// Past gigs per band, from `gigs:pastForBand`. Lazily loaded on first read.
  /// Follows `BandMediaController.mediaFor` / `_loadMedia`: a read-triggered
  /// per-band cache with a staleness token and one final notification.
  /// Deliberate deviation: media retries after its own failure rebuild; this
  /// cache gates on the error map until an explicit [refreshBandHistory].
  final Map<String, BandHistory> _bandHistory = {};
  final Map<String, Object> _bandHistoryTokens = {};
  final Map<String, String> _bandHistoryErrors = {};

  /// Aggregated performance data per band, from `analytics:bandRecap`.
  /// Lazily loaded and held on failure until an explicit [refreshBandRecap].
  final Map<String, BandRecap> _bandRecap = {};
  final Map<String, Object> _bandRecapTokens = {};
  final Map<String, String> _bandRecapErrors = {};

  final Map<String, BandProfileDetails> _bandProfileDetails = {};
  final Set<String> _bandProfileDetailsLoading = {};
  final Map<String, BandSetupStatus> _bandSetupStatuses = {};
  final Set<String> _bandSetupLoading = {};
  final Map<String, BandDiscoveryReadiness> _bandDiscoveryReadiness = {};
  final Set<String> _bandDiscoveryLoading = {};
  final Set<String> _bandDiscoveryBoundaryRefreshPending = {};
  final Map<String, BandInvite?> _bandInvites = {};
  final Set<String> _bandInviteLoading = {};

  BandInviteResolution? joinInvite;
  String? joinToken;
  bool joinInviteLoading = false;
  String? joinInviteError;
  bool joinInviteAccepting = false;
  bool joinInviteAccepted = false;

  PerformerInviteResolution? performerInvite;
  String? performerInviteToken;
  bool performerInviteLoading = false;
  String? performerInviteError;
  bool performerInviteClaiming = false;
  bool performerInviteClaimed = false;
  String? performerInviteBandId;
  int _performerInviteGeneration = 0;

  // ---- band membership
  List<String> myBands = [];
  String bandId = '';
  bool _membershipsLoaded = false;
  bool get membershipsLoaded => authed && _membershipsLoaded;

  void _cacheMemberships(List<BandMembership> memberships) {
    _membershipsLoaded = true;
    myBands = [for (final membership in memberships) membership.band.id];
    if (myBands.isEmpty) {
      bandId = '';
    } else if (bandId.isEmpty) {
      bandId = myBands.first;
    }
    final bands = Map.of(_bands);
    for (final membership in memberships) {
      final band = membership.band;
      _bandRoles[band.id] = membership.role;
      bands[band.id] = band.copyWith(
        upcoming: bands[band.id]?.upcoming ?? const [],
      );
    }
    _bands = bands;
    _scheduleDiscoveryBoundaryRefresh();
    notifyListeners();
  }

  @override
  void _restartMemberships() {
    final generation = ++_membershipsGeneration;
    final previousSubscription = _bandsSubscription;
    _bandsSubscription = null;
    unawaited(previousSubscription?.cancel());
    if (_disposed || !authed || generation != _membershipsGeneration) return;

    _bandsSubscription = _listenToMemberships(
      generation,
      requireAuthentication: true,
    );
  }

  StreamSubscription<List<BandMembership>> _listenToMemberships(
    int generation, {
    required bool requireAuthentication,
  }) {
    return repository.myBands().listen(
      (memberships) {
        if (_disposed ||
            (requireAuthentication && !authed) ||
            generation != _membershipsGeneration) {
          return;
        }
        _cacheMemberships(memberships);
      },
      onError: (Object error) {
        if (generation == _membershipsGeneration) {
          logError('myBands', error);
        }
      },
    );
  }

  @override
  void _clearMemberships() {
    _membershipsGeneration++;
    final subscription = _bandsSubscription;
    _bandsSubscription = null;
    unawaited(subscription?.cancel());
    _membershipsLoaded = false;
    myBands = [];
    bandId = '';
    _bandRoles.clear();
  }

  /// A band's past gigs, or null until the first load lands. Kicks the load off
  /// on first read; a failed load is not retried until [refreshBandHistory].
  BandHistory? bandHistory(String id) {
    final cached = _bandHistory[id];
    if (cached != null) return cached;
    if (!_bandHistoryTokens.containsKey(id) &&
        !_bandHistoryErrors.containsKey(id)) {
      unawaited(_loadBandHistory(id));
    }
    return null;
  }

  /// Why the last load for [id] failed, or null.
  String? bandHistoryError(String id) => _bandHistoryErrors[id];

  /// Clears any recorded failure and loads again — the RETRY affordance.
  void refreshBandHistory(String id) {
    _bandHistoryErrors.remove(id);
    notifyListeners();
    unawaited(_loadBandHistory(id));
  }

  Future<void> _loadBandHistory(String id) async {
    final token = Object();
    _bandHistoryTokens[id] = token;
    try {
      final loaded = await repository.bandHistory(id);
      if (_disposed || !identical(_bandHistoryTokens[id], token)) return;
      _bandHistory[id] = loaded;
      _bandHistoryErrors.remove(id);
    } catch (error) {
      logError('bandHistory', error);
      if (_disposed || !identical(_bandHistoryTokens[id], token)) return;
      _bandHistoryErrors[id] = '$error';
    } finally {
      if (!_disposed && identical(_bandHistoryTokens[id], token)) {
        _bandHistoryTokens.remove(id);
        notifyListeners();
      }
    }
  }

  /// A band's performance recap, or null until the first load lands. Kicks the
  /// load off on first read; failures wait for [refreshBandRecap].
  BandRecap? bandRecap(String id) {
    final cached = _bandRecap[id];
    if (cached != null) return cached;
    if (!_bandRecapTokens.containsKey(id) &&
        !_bandRecapErrors.containsKey(id)) {
      unawaited(_loadBandRecap(id));
    }
    return null;
  }

  /// Why the last recap load for [id] failed, or null.
  String? bandRecapError(String id) => _bandRecapErrors[id];

  /// Clears any recorded recap failure and loads again — the RETRY affordance.
  void refreshBandRecap(String id) {
    _bandRecapErrors.remove(id);
    notifyListeners();
    unawaited(_loadBandRecap(id));
  }

  Future<void> _loadBandRecap(String id) async {
    final token = Object();
    _bandRecapTokens[id] = token;
    try {
      final loaded = await repository.bandRecap(id);
      if (_disposed || !identical(_bandRecapTokens[id], token)) return;
      _bandRecap[id] = loaded;
      _bandRecapErrors.remove(id);
    } catch (error) {
      logError('bandRecap', error);
      if (_disposed || !identical(_bandRecapTokens[id], token)) return;
      _bandRecapErrors[id] = '$error';
    } finally {
      if (!_disposed && identical(_bandRecapTokens[id], token)) {
        _bandRecapTokens.remove(id);
        notifyListeners();
      }
    }
  }

  String roleFor(String id) => _bandRoles[id] ?? 'member';

  bool isAdminOf(String id) => _bandRoles[id] == 'admin';

  String bioFor(String id) => band(id)?.bio ?? '';

  String linkIgFor(String id) => band(id)?.linkIg ?? '';

  String linkBcFor(String id) => band(id)?.linkBc ?? '';

  String linkYtFor(String id) => band(id)?.linkYt ?? '';

  // ========================= band view =========================

  Band? get myBand => band(bandId);

  final Memo<({List<Gig> gigs, String bandId}), List<Gig>> _myBandGigsMemo =
      Memo();

  List<Gig> get myBandGigs {
    final inputs = (gigs: allGigs, bandId: bandId);
    return _myBandGigsMemo(
      inputs,
      () => List<Gig>.unmodifiable(
        inputs.gigs.where((gig) => gig.lineup.contains(inputs.bandId)),
      ),
    );
  }

  void switchToBand(String id) {
    bandId = id;
    resetTo(Screen.bandDash);
    unawaited(refreshBandSetupStatus(id));
    unawaited(refreshBandDiscoveryReadiness(id));
  }

  void toFanView() => resetTo(Screen.home);

  BandProfileDetails? profileDetailsFor(String id) {
    final details = _bandProfileDetails[id];
    if (details == null) unawaited(loadBandProfileDetails(id));
    return details;
  }

  Future<void> loadBandProfileDetails(String id, {bool refresh = false}) async {
    if ((!refresh && _bandProfileDetails.containsKey(id)) ||
        !_bandProfileDetailsLoading.add(id)) {
      return;
    }
    try {
      _bandProfileDetails[id] = await repository.bandProfileDetails(id);
    } catch (error) {
      logError('bandProfileDetails', error);
    } finally {
      _bandProfileDetailsLoading.remove(id);
      if (!_disposed) notifyListeners();
    }
  }

  BandSetupStatus? setupStatusFor(String id) {
    final status = _bandSetupStatuses[id];
    if (status == null && isAdminOf(id)) {
      unawaited(refreshBandSetupStatus(id));
    }
    return status;
  }

  bool setupStatusLoadingFor(String id) => _bandSetupLoading.contains(id);

  Future<void> refreshBandSetupStatus(String id) async {
    if (!isAdminOf(id) || !_bandSetupLoading.add(id)) return;
    try {
      _bandSetupStatuses[id] = await repository.bandSetupStatus(id);
    } catch (error) {
      logError('bandSetupStatus', error);
    } finally {
      _bandSetupLoading.remove(id);
      if (!_disposed) notifyListeners();
    }
  }

  BandDiscoveryReadiness? discoveryReadinessFor(String id) {
    final readiness = _bandDiscoveryReadiness[id];
    if (readiness == null && isAdminOf(id)) {
      unawaited(refreshBandDiscoveryReadiness(id));
    }
    return readiness;
  }

  bool discoveryReadinessLoadingFor(String id) =>
      _bandDiscoveryLoading.contains(id);

  Future<void> refreshBandDiscoveryReadiness(String id) async {
    if (!isAdminOf(id) || !_bandDiscoveryLoading.add(id)) return;
    try {
      _bandDiscoveryReadiness[id] = await repository.bandDiscoveryReadiness(
        id,
        now: _now(),
      );
    } catch (error) {
      logError('bandDiscoveryReadiness', error);
    } finally {
      _bandDiscoveryLoading.remove(id);
      final refreshAtBoundary =
          _bandDiscoveryBoundaryRefreshPending.remove(id) && isAdminOf(id);
      if (!_disposed) {
        _scheduleDiscoveryBoundaryRefresh();
        notifyListeners();
        if (refreshAtBoundary) unawaited(refreshBandDiscoveryReadiness(id));
      }
    }
  }

  @override
  Future<void> _markBandPreviewed(String id) async {
    try {
      await repository.markBandPreviewed(id);
      await refreshBandSetupStatus(id);
      await refreshBandDiscoveryReadiness(id);
    } catch (error) {
      logError('markBandPreviewed', error);
    }
  }

  Future<void> saveBandProfile(BandProfileUpdate update) async {
    final name = update.name.trim();
    final area = update.area.trim();
    if (name.isEmpty || area.isEmpty || update.genres.isEmpty) {
      throw ArgumentError('Band name, sound, and home base are required.');
    }
    if (update.genres.length > 3) {
      throw ArgumentError('Choose no more than three genres.');
    }

    final normalized = BandProfileUpdate(
      bandId: update.bandId,
      name: name,
      genres: List<String>.of(update.genres),
      area: area,
      bio: update.bio.trim(),
      linkIg: update.linkIg.trim(),
      linkBc: update.linkBc.trim(),
      linkYt: update.linkYt.trim(),
      credits: update.credits.trim(),
    );
    await repository.updateBandProfile(normalized);

    final existing = _bands[update.bandId];
    if (existing != null) {
      final profileComplete =
          normalized.name.isNotEmpty &&
          normalized.genres.isNotEmpty &&
          normalized.genres.length <= 3 &&
          normalized.genres.every((genre) => genre.trim().isNotEmpty) &&
          normalized.area.isNotEmpty &&
          normalized.bio.isNotEmpty;
      _bands = {
        ..._bands,
        update.bandId: existing.copyWith(
          name: normalized.name,
          initials: bandInitialsFor(normalized.name),
          genres: normalized.genres,
          area: normalized.area,
          bio: normalized.bio,
          linkIg: normalized.linkIg,
          linkBc: normalized.linkBc,
          linkYt: normalized.linkYt,
          credits: normalized.credits,
          profileComplete: profileComplete,
          discoveryProfileReady: profileComplete
              ? existing.discoveryProfileReady
              : false,
        ),
      };
    }
    final currentDetails = _bandProfileDetails[update.bandId];
    _bandProfileDetails[update.bandId] = BandProfileDetails(
      credits: normalized.credits.isEmpty ? null : normalized.credits,
      linkIg: normalized.linkIg.isEmpty ? null : normalized.linkIg,
      linkBc: normalized.linkBc.isEmpty ? null : normalized.linkBc,
      linkYt: normalized.linkYt.isEmpty ? null : normalized.linkYt,
      memberNames: currentDetails?.memberNames ?? const [],
    );
    notifyListeners();
    await refreshBandSetupStatus(update.bandId);
    await refreshBandDiscoveryReadiness(update.bandId);
  }

  BandInvite? inviteFor(String id) => _bandInvites[id];

  bool inviteLoadingFor(String id) => _bandInviteLoading.contains(id);

  Future<void> refreshBandInvite(String id) async {
    if (!isAdminOf(id) || !_bandInviteLoading.add(id)) return;
    try {
      _bandInvites[id] = await repository.bandInvite(id);
    } catch (error) {
      logError('bandInvite', error);
    } finally {
      _bandInviteLoading.remove(id);
      if (!_disposed) notifyListeners();
    }
  }

  Future<BandInvite> createBandInvitation() async {
    final invite = await repository.createBandInvite(bandId);
    _bandInvites[bandId] = invite;
    notifyListeners();
    return invite;
  }

  Future<BandInvite> rotateBandInvitation() async {
    final invite = await repository.rotateBandInvite(bandId);
    _bandInvites[bandId] = invite;
    notifyListeners();
    return invite;
  }

  Future<void> revokeBandInvitation() async {
    final id = bandId;
    await repository.revokeBandInvite(id);
    final current = _bandInvites[id];
    if (current != null) {
      _bandInvites[id] = BandInvite(
        bandId: current.bandId,
        token: current.token,
        expiresAt: current.expiresAt,
        revoked: true,
        expired: current.expired,
      );
    }
    notifyListeners();
  }

  Future<void> archiveCurrentBand() async {
    final id = bandId;
    if (id.isEmpty || !isAdminOf(id)) {
      throw StateError('Band admin access required.');
    }

    Object? archiveError;
    StackTrace? archiveStackTrace;
    try {
      await repository.archiveBand(id);
    } catch (error, stackTrace) {
      archiveError = error;
      archiveStackTrace = stackTrace;
    }

    try {
      final status = await repository.bandArchiveStatus(id);
      if (!status.archived) {
        if (archiveError != null) {
          Error.throwWithStackTrace(archiveError, archiveStackTrace!);
        }
        throw StateError('Band archive could not be verified.');
      }
    } catch (statusError, statusStackTrace) {
      if (archiveError != null) {
        Error.throwWithStackTrace(archiveError, archiveStackTrace!);
      }
      Error.throwWithStackTrace(statusError, statusStackTrace);
    }

    myBands = myBands.where((candidate) => candidate != id).toList();
    _bandRoles.remove(id);
    _bandInvites.remove(id);
    _bands = Map.of(_bands)..remove(id);
    bandId = myBands.firstOrNull ?? '';
    managedGigsBandId = null;
    _stack = const [ScreenEntry(Screen.myGigs)];
    replaceBrowserPath('/');
    notifyListeners();
    say('Band archived. Future owned gigs were cancelled.');
  }

  Future<void> openJoinInvite(String token) async {
    _stack = [ScreenEntry(Screen.bandJoin, token)];
    notifyListeners();
    await _resolveJoinInvite(token);
  }

  Future<void> _resolveJoinInvite(String token) async {
    joinToken = token;
    joinInvite = null;
    joinInviteError = null;
    joinInviteAccepted = false;
    joinInviteLoading = true;
    notifyListeners();
    try {
      final resolved = await repository.resolveBandInvite(token);
      if (resolved == null) {
        joinInviteError = 'This invitation is invalid, expired, or revoked.';
      } else {
        joinInvite = resolved;
      }
    } catch (error) {
      logError('resolveBandInvite', error);
      joinInviteError = genericErrorMessage;
    } finally {
      joinInviteLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> confirmJoinInvite() async {
    final token = joinToken;
    if (token == null || joinInvite == null || joinInviteAccepting) return;
    if (!authed) {
      needAuth(PendingAuth(PendingKind.join, token));
      return;
    }
    await _acceptJoinInvite(token);
  }

  Future<void> _acceptJoinInvite(String token) async {
    joinInviteAccepting = true;
    joinInviteError = null;
    notifyListeners();
    try {
      final accepted = await repository.acceptBandInvite(token);
      bandId = accepted.bandId;
      if (!myBands.contains(accepted.bandId)) {
        myBands = [...myBands, accepted.bandId];
      }
      if (accepted.membershipCreated) {
        _bandRoles[accepted.bandId] = 'member';
      }
      if (!_bands.containsKey(accepted.bandId)) {
        unawaited(_loadFollowBand(accepted.bandId));
      }
      joinInviteAccepted = true;
      _restartMemberships();
      unawaited(loadBandProfileDetails(accepted.bandId, refresh: true));
    } catch (error) {
      logError('acceptBandInvite', error);
      joinInviteError = 'This invitation could not be accepted.';
      rethrow;
    } finally {
      joinInviteAccepting = false;
      if (!_disposed) notifyListeners();
    }
  }

  List<String> get performerInviteAdminBandIds => [
    for (final id in myBands)
      if (isAdminOf(id)) id,
  ];

  void selectPerformerInviteBand(String id) {
    if (isAdminOf(id)) _set(() => performerInviteBandId = id);
  }

  Future<void> openPerformerInvite(String token) async {
    _stack = [ScreenEntry(Screen.gigInvite, token)];
    notifyListeners();
    await _resolvePerformerInvite(token);
  }

  Future<void> _resolvePerformerInvite(String token) async {
    final generation = ++_performerInviteGeneration;
    performerInviteToken = token;
    performerInvite = null;
    performerInviteError = null;
    performerInviteClaimed = false;
    performerInviteBandId = null;
    performerInviteLoading = true;
    notifyListeners();
    try {
      final resolved = await repository.resolvePerformerInvite(token);
      if (_disposed || generation != _performerInviteGeneration) return;
      if (resolved == null) {
        performerInviteError =
            'This invitation is invalid, expired, or revoked.';
      } else {
        performerInvite = resolved;
      }
    } catch (error) {
      logError('resolvePerformerInvite', error);
      if (_disposed || generation != _performerInviteGeneration) return;
      performerInviteError = genericErrorMessage;
    } finally {
      if (!_disposed && generation == _performerInviteGeneration) {
        performerInviteLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> confirmPerformerInvite(String claimingBandId) async {
    final token = performerInviteToken;
    if (token == null || performerInvite == null || performerInviteClaiming) {
      return;
    }
    if (!authed) {
      needAuth(PendingAuth(PendingKind.gigInvite, token));
      return;
    }
    if (!isAdminOf(claimingBandId)) {
      performerInviteError = 'Choose a band you administer.';
      notifyListeners();
      return;
    }

    performerInviteClaiming = true;
    performerInviteError = null;
    notifyListeners();
    try {
      await repository.claimPerformerInvite(
        token: token,
        bandId: claimingBandId,
      );
      performerInviteBandId = claimingBandId;
      performerInviteClaimed = true;
      managedGigsBandId = null;
    } catch (error) {
      logError('claimPerformerInvite', error);
      performerInviteError = 'This invitation could not be claimed.';
      rethrow;
    } finally {
      performerInviteClaiming = false;
      if (!_disposed) notifyListeners();
    }
  }

  void openClaimedGigManager() {
    final claimingBandId = performerInviteBandId;
    if (claimingBandId == null) return;
    bandId = claimingBandId;
    resetTo(Screen.gigMgr);
    unawaited(refreshManagedGigs());
  }
}
