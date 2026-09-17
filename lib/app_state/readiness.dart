part of '../app_state.dart';

const _bandReadinessScopePrefix = 'band:';
const _orgReadinessScopePrefix = 'org:';

/// The scope key under which a band's readiness is tracked and remembered.
String bandReadinessScope(String bandId) => '$_bandReadinessScopePrefix$bandId';

/// The scope key under which an organization's host readiness is tracked and
/// remembered.
String orgReadinessScope(String orgId) => '$_orgReadinessScopePrefix$orgId';

/// A readiness checklist as a state machine with memory: the current
/// snapshot for a scope (`band:<bandId>` with nine steps, `org:<orgId>` with
/// two), a persisted per-scope record of which steps were last seen done,
/// and the regression that record reveals when a step later fails.
mixin _ReadinessState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  String get bandId;
  String get organizationId;
  Map<String, BandSetupStatus> get _bandSetupStatuses;
  Map<String, BandDiscoveryReadiness> get _bandDiscoveryReadiness;
  BandSetupStatus? setupStatusFor(String id);
  BandDiscoveryReadiness? discoveryReadinessFor(String id);
  void switchToBand(String id);
  void switchToOrganization(String id);
  void go(Screen s, [String? param]);
  void openBandEditor({String? section});
  void openBandMedia();
  void openGigManager();
  void startGigCreate();
  void previewPublicProfile();
  void openInvitationPanel();
  void openFinance();

  /// The loaded memory per scope; a scope is absent until its first reconcile.
  final Map<String, readiness_memory.ReadinessMemory> _readinessMemories = {};

  /// One store read per scope per session, shared by concurrent reconciles.
  final Map<String, Future<readiness_memory.ReadinessMemory?>>
  _readinessMemoryLoads = {};

  /// Per scope, the `regressedAt` already handed out by
  /// [readinessSheetShouldAutoOpen], so each regression opens the sheet once.
  final Map<String, DateTime> _readinessAutoOpenOffered = {};

  /// The host checklist for [orgId], or null while it cannot be built.
  ///
  /// Hook for the organizer lane: returns null until it is wired to live
  /// organization data (profile completeness and Stripe readiness), so an
  /// `org:` scope renders nothing and remembers nothing for now.
  ReadinessSnapshot? hostReadinessSnapshotFor(String orgId) => null;

  /// Triggers the lazy loads behind the band sources; null until both are
  /// in. An `org:` scope defers to [hostReadinessSnapshotFor].
  ReadinessSnapshot? readinessSnapshotFor(String scopeKey) =>
      _readinessSnapshot(scopeKey, triggerLoads: true);

  /// With [triggerLoads] the band sources start loading when absent; without
  /// it the snapshot reflects only what is already held, which is what a
  /// reconcile must compare against.
  ReadinessSnapshot? _readinessSnapshot(
    String scopeKey, {
    required bool triggerLoads,
  }) {
    if (scopeKey.startsWith(_bandReadinessScopePrefix)) {
      final bandId = scopeKey.substring(_bandReadinessScopePrefix.length);
      return ReadinessSnapshot.band(
        readiness: triggerLoads
            ? discoveryReadinessFor(bandId)
            : _bandDiscoveryReadiness[bandId],
        setup: triggerLoads
            ? setupStatusFor(bandId)
            : _bandSetupStatuses[bandId],
      );
    }
    if (scopeKey.startsWith(_orgReadinessScopePrefix)) {
      return hostReadinessSnapshotFor(
        scopeKey.substring(_orgReadinessScopePrefix.length),
      );
    }
    return null;
  }

  ReadinessRegression? readinessRegressionFor(String scopeKey) {
    final memory = _readinessMemories[scopeKey];
    if (memory == null || !memory.hasRegression) return null;
    return ReadinessRegression(
      stepIds: List.unmodifiable(memory.regressedIds),
      since: memory.regressedAt!,
    );
  }

  /// True the first time it is asked about an unacknowledged regression, and
  /// false on every later ask for that same regression, so a rebuild never
  /// opens the sheet twice. An acknowledged regression never auto-opens.
  bool readinessSheetShouldAutoOpen(String scopeKey) {
    final memory = _readinessMemories[scopeKey];
    if (memory == null ||
        !memory.hasRegression ||
        memory.regressionAcknowledged) {
      return false;
    }
    final regressedAt = memory.regressedAt!;
    if (_readinessAutoOpenOffered[scopeKey] == regressedAt) return false;
    _readinessAutoOpenOffered[scopeKey] = regressedAt;
    return true;
  }

  void acknowledgeReadinessRegression(String scopeKey) {
    final memory = _readinessMemories[scopeKey];
    if (memory == null ||
        !memory.hasRegression ||
        memory.regressionAcknowledged) {
      return;
    }
    final acknowledged = memory.copyWith(regressionAcknowledged: true);
    _readinessMemories[scopeKey] = acknowledged;
    unawaited(_writeReadinessMemory(scopeKey, acknowledged));
    notifyListeners();
  }

  /// Compares the current snapshot with the scope's memory, records any step
  /// that was done before and is not now as a regression, and remembers the
  /// steps done now. Called after every successful readiness or setup refresh.
  Future<void> reconcileReadiness(String scopeKey) async {
    final previous =
        _readinessMemories[scopeKey] ?? await _loadReadinessMemory(scopeKey);
    if (_disposed) return;
    // The sources may have moved while the store read was in flight; only a
    // snapshot built after the await reflects what the checklist shows.
    final snapshot = _readinessSnapshot(scopeKey, triggerLoads: false);
    if (snapshot == null) return;

    final now = _now();
    final updated = previous == null
        ? readiness_memory.ReadinessMemory(
            doneIds: snapshot.doneIds,
            seenAt: now,
          )
        : _reconciled(previous, snapshot, now);
    final unchanged =
        previous != null &&
        _readinessMemories.containsKey(scopeKey) &&
        updated.hasSameStateAs(previous);
    _readinessMemories[scopeKey] = updated;
    await _writeReadinessMemory(scopeKey, updated);
    if (!unchanged && !_disposed) notifyListeners();
  }

  /// Steps that were done at the last look and are not done now join the
  /// regression; a regressed step that is done again leaves it. A brand-new
  /// regression stamps `since`; one that only grows keeps its original stamp.
  static readiness_memory.ReadinessMemory _reconciled(
    readiness_memory.ReadinessMemory memory,
    ReadinessSnapshot snapshot,
    DateTime now,
  ) {
    final doneNow = snapshot.doneIds;
    final regressedIds = <String>{
      for (final step in snapshot.steps)
        if (!step.done &&
            (memory.regressedIds.contains(step.id) ||
                memory.doneIds.contains(step.id)))
          step.id,
    };
    final newlyMissing = regressedIds.difference(memory.regressedIds);
    if (snapshot.complete || regressedIds.isEmpty) {
      return memory.copyWith(
        doneIds: doneNow,
        seenAt: now,
        clearRegression: true,
      );
    }
    if (newlyMissing.isEmpty) {
      return memory.copyWith(
        doneIds: doneNow,
        seenAt: now,
        regressedIds: regressedIds,
      );
    }
    return memory.copyWith(
      doneIds: doneNow,
      seenAt: now,
      regressedAt: memory.hasRegression ? memory.regressedAt : now,
      regressedIds: regressedIds,
      regressionAcknowledged: false,
    );
  }

  Future<readiness_memory.ReadinessMemory?> _loadReadinessMemory(
    String scopeKey,
  ) => _readinessMemoryLoads.putIfAbsent(scopeKey, () async {
    try {
      return await readinessMemoryStore.read(scopeKey);
    } catch (error) {
      logError('readinessMemory.read', error);
      return null;
    }
  });

  Future<void> _writeReadinessMemory(
    String scopeKey,
    readiness_memory.ReadinessMemory memory,
  ) async {
    try {
      await readinessMemoryStore.write(scopeKey, memory);
    } catch (error) {
      logError('readinessMemory.write', error);
    }
  }

  /// Runs the navigation a step's action stands for. Every destination is
  /// keyed on the selected band or organization, so the scope's owner is
  /// selected first when another one is.
  void performReadinessAction(String scopeKey, ReadinessAction action) {
    if (scopeKey.startsWith(_orgReadinessScopePrefix)) {
      final orgId = scopeKey.substring(_orgReadinessScopePrefix.length);
      if (orgId != organizationId) switchToOrganization(orgId);
    } else if (scopeKey.startsWith(_bandReadinessScopePrefix)) {
      final bandId = scopeKey.substring(_bandReadinessScopePrefix.length);
      if (bandId != this.bandId) switchToBand(bandId);
    }
    switch (action) {
      case ReadinessAction.editProfile:
        openBandEditor(section: 'required');
      case ReadinessAction.addMedia:
        openBandMedia();
      case ReadinessAction.manageShow:
      case ReadinessAction.republish:
        openGigManager();
      case ReadinessAction.createShow:
        startGigCreate();
      case ReadinessAction.preview:
        previewPublicProfile();
      case ReadinessAction.editLinks:
        openBandEditor(section: 'links');
      case ReadinessAction.inviteMembers:
        openInvitationPanel();
      case ReadinessAction.editOrgProfile:
        openOrgProfileEditor();
      case ReadinessAction.setUpFinance:
        openOrgFinance();
    }
  }

  /// The organization settings screen, where the public profile is edited;
  /// the same route the organizer dash's Settings row takes.
  void openOrgProfileEditor() => go(Screen.orgSettings);

  /// The organization finance screen, which offers Connect Stripe until the
  /// account is ready; the same route the dash's Finance "Set up" row takes.
  void openOrgFinance() => openFinance();

  @override
  void _clearReadinessState() {
    _readinessMemories.clear();
    _readinessMemoryLoads.clear();
    _readinessAutoOpenOffered.clear();
  }
}
