part of '../app_state.dart';

/// The band readiness checklist as a state machine with memory: the current
/// nine-step snapshot, a persisted per-band record of which steps were last
/// seen done, and the regression that record reveals when a step later fails.
mixin _ReadinessState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  String get bandId;
  Map<String, BandSetupStatus> get _bandSetupStatuses;
  Map<String, BandDiscoveryReadiness> get _bandDiscoveryReadiness;
  BandSetupStatus? setupStatusFor(String id);
  BandDiscoveryReadiness? discoveryReadinessFor(String id);
  void switchToBand(String id);
  void openBandEditor({String? section});
  void openBandMedia();
  void openGigManager();
  void startGigCreate();
  void previewPublicProfile();
  void openInvitationPanel();

  /// The loaded memory per band; a band is absent until its first reconcile.
  final Map<String, readiness_memory.ReadinessMemory> _readinessMemories = {};

  /// One store read per band per session, shared by concurrent reconciles.
  final Map<String, Future<readiness_memory.ReadinessMemory?>>
  _readinessMemoryLoads = {};

  /// Per band, the `regressedAt` already handed out by
  /// [readinessSheetShouldAutoOpen], so each regression opens the sheet once.
  final Map<String, DateTime> _readinessAutoOpenOffered = {};

  /// Triggers the lazy loads behind both sources; null until both are in.
  ReadinessSnapshot? readinessSnapshotFor(String bandId) =>
      ReadinessSnapshot.from(
        readiness: discoveryReadinessFor(bandId),
        setup: setupStatusFor(bandId),
      );

  ReadinessRegression? readinessRegressionFor(String bandId) {
    final memory = _readinessMemories[bandId];
    if (memory == null || !memory.hasRegression) return null;
    return ReadinessRegression(
      stepIds: List.unmodifiable(memory.regressedIds),
      since: memory.regressedAt!,
    );
  }

  /// True the first time it is asked about an unacknowledged regression, and
  /// false on every later ask for that same regression, so a rebuild never
  /// opens the sheet twice. An acknowledged regression never auto-opens.
  bool readinessSheetShouldAutoOpen(String bandId) {
    final memory = _readinessMemories[bandId];
    if (memory == null ||
        !memory.hasRegression ||
        memory.regressionAcknowledged) {
      return false;
    }
    final regressedAt = memory.regressedAt!;
    if (_readinessAutoOpenOffered[bandId] == regressedAt) return false;
    _readinessAutoOpenOffered[bandId] = regressedAt;
    return true;
  }

  void acknowledgeReadinessRegression(String bandId) {
    final memory = _readinessMemories[bandId];
    if (memory == null ||
        !memory.hasRegression ||
        memory.regressionAcknowledged) {
      return;
    }
    final acknowledged = memory.copyWith(regressionAcknowledged: true);
    _readinessMemories[bandId] = acknowledged;
    unawaited(_writeReadinessMemory(bandId, acknowledged));
    notifyListeners();
  }

  /// Compares the current snapshot with the band's memory, records any step
  /// that was done before and is not now as a regression, and remembers the
  /// steps done now. Called after every successful readiness or setup refresh.
  Future<void> reconcileReadiness(String bandId) async {
    final previous =
        _readinessMemories[bandId] ?? await _loadReadinessMemory(bandId);
    if (_disposed) return;
    // Both sources may have moved while the store read was in flight; only a
    // snapshot built after the await reflects what the checklist shows.
    final snapshot = ReadinessSnapshot.from(
      readiness: _bandDiscoveryReadiness[bandId],
      setup: _bandSetupStatuses[bandId],
    );
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
        _readinessMemories.containsKey(bandId) &&
        updated.hasSameStateAs(previous);
    _readinessMemories[bandId] = updated;
    await _writeReadinessMemory(bandId, updated);
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
    String bandId,
  ) => _readinessMemoryLoads.putIfAbsent(bandId, () async {
    try {
      return await readinessMemoryStore.read(bandId);
    } catch (error) {
      logError('readinessMemory.read', error);
      return null;
    }
  });

  Future<void> _writeReadinessMemory(
    String bandId,
    readiness_memory.ReadinessMemory memory,
  ) async {
    try {
      await readinessMemoryStore.write(bandId, memory);
    } catch (error) {
      logError('readinessMemory.write', error);
    }
  }

  /// Runs the navigation a step's action stands for. Every destination is
  /// keyed on the selected band, so another band is selected first.
  void performReadinessAction(String bandId, ReadinessAction action) {
    if (bandId != this.bandId) switchToBand(bandId);
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
    }
  }

  @override
  void _clearReadinessState() {
    _readinessMemories.clear();
    _readinessMemoryLoads.clear();
    _readinessAutoOpenOffered.clear();
  }
}
