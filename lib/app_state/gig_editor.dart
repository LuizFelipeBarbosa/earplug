part of '../app_state.dart';

/// The gig create/edit form and the managed-gig list behind it: draft
/// autosave, lineup mutations, publishing and lifecycle actions.
mixin _GigEditorState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  String get bandId;
  set _stack(List<ScreenEntry> value);
  Band? get myBand;
  void go(Screen s, [String? param]);
  Future<void> refreshBandSetupStatus(String id);
  Future<void> refreshBandDiscoveryReadiness(String id);

  // ---- gig create form
  String gfName = '';
  DateTime? gfDate;
  TimeOfDay gfDoors = const TimeOfDay(hour: 20, minute: 0);
  TimeOfDay gfStart = const TimeOfDay(hour: 21, minute: 0);
  String? gfVenueId;
  String gfPrice = 'FREE';
  Ticketing gfTix = Ticketing.rsvp;
  AgeRequirement gfAgeRequirement = AgeRequirement.allAges;
  String gfCap = 'No cap';
  String gfExt = '';
  String gfDesc = '';
  String gfFly = 'xerox';
  bool gfOverlay = true;
  PickedMedia? gfFlyerArt;
  String? gfFlyerStorageId;
  String? gfFlyerUrl;
  bool gfFlyerUploading = false;
  bool gfPublished = false;
  bool gfPreviewing = false;
  GigProject? gfProject;
  List<GigProject> managedGigProjects = const [];
  bool managedGigsLoading = false;
  String? managedGigsBandId;
  Future<void>? _managedGigsRefreshFuture;
  bool _managedGigsRefreshAgain = false;
  String gfSaveState = 'DRAFT';
  Timer? _gigAutosaveTimer;
  bool _gigSaveAgain = false;
  bool _gigDraftDirty = false;
  int _gigEditGeneration = 0;
  int _gigEditorGeneration = 0;
  Future<GigProject>? _gigCreateFuture;
  Future<void>? _gigSaveFuture;
  Future<void>? _gigLineupMutationFuture;

  // ========================= gig create =========================

  void startGigCreate() {
    _resetGigForm();
    go(Screen.gigCreate);
  }

  bool _isCurrentGigEditor(int editorGeneration) =>
      !_disposed && editorGeneration == _gigEditorGeneration;

  Future<GigProject> _createGigDraft(
    int editorGeneration,
    String requestedBandId,
  ) async {
    if (!_isCurrentGigEditor(editorGeneration)) {
      throw StateError('Gig editor is no longer active');
    }
    final hadLocalEdits = _gigDraftDirty;
    gfSaveState = 'CREATING…';
    notifyListeners();
    try {
      final project = await repository.createGigDraft(requestedBandId);
      if (!_isCurrentGigEditor(editorGeneration)) {
        try {
          await repository.deleteGig(project.id);
        } catch (error) {
          logError('discardAbandonedGigDraft', error);
        }
        return project;
      }
      if (hadLocalEdits) {
        // A fast typist can edit while the first draft request is in flight.
        // Attach the server identity without replacing those local changes.
        gfProject = project;
        notifyListeners();
      } else {
        _applyGigProject(project);
      }
      return project;
    } on Exception catch (error) {
      logError('createGigDraft', error);
      if (_isCurrentGigEditor(editorGeneration)) {
        gfSaveState = 'SAVE FAILED';
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> editGigProject(String projectId) async {
    _resetGigForm();
    go(Screen.gigCreate);
    final editorGeneration = _gigEditorGeneration;
    gfSaveState = 'LOADING…';
    notifyListeners();
    try {
      final project = await repository.getGigProject(projectId);
      if (!_isCurrentGigEditor(editorGeneration)) return;
      _applyGigProject(project);
    } on Exception catch (error) {
      logError('getGigProject', error);
      if (!_isCurrentGigEditor(editorGeneration)) return;
      gfSaveState = 'LOAD FAILED';
      say(genericErrorMessage);
      notifyListeners();
    }
  }

  void _applyGigProject(GigProject project) {
    gfProject = project;
    gfName = project.title ?? '';
    final doorsAt = project.doorsAt;
    final startsAt = project.startsAt;
    gfDate = doorsAt == null
        ? null
        : DateTime(doorsAt.year, doorsAt.month, doorsAt.day);
    if (doorsAt != null) gfDoors = TimeOfDay.fromDateTime(doorsAt);
    if (startsAt != null) gfStart = TimeOfDay.fromDateTime(startsAt);
    gfVenueId = project.venueId;
    gfPrice = project.price == 0 ? 'FREE' : '\$${project.price}';
    gfTix = project.ticketing;
    gfAgeRequirement = project.ageRequirement;
    gfCap = project.cap;
    gfExt = project.externalUrl ?? '';
    gfDesc = project.desc;
    gfFly = project.flyKey;
    gfOverlay = project.overlay;
    gfFlyerArt = null;
    gfFlyerStorageId = project.flyStorageId;
    gfFlyerUrl = project.flyerUrl;
    gfPublished = false;
    gfPreviewing = false;
    _gigDraftDirty = false;
    gfSaveState = project.hasUnpublishedChanges
        ? 'UNPUBLISHED CHANGES'
        : project.status.name.toUpperCase();
    notifyListeners();
  }

  void _changeGig(void Function() change) {
    change();
    _gigDraftDirty = true;
    _gigEditGeneration++;
    notifyListeners();
    _scheduleGigAutosave();
  }

  void _scheduleGigAutosave() {
    _gigAutosaveTimer?.cancel();
    gfSaveState = 'UNSAVED';
    _gigAutosaveTimer = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(saveGigDraft()),
    );
  }

  void setGfName(String v) => _changeGig(() => gfName = v);

  /// Tapping the selected day again clears it, as in the design.
  void setGfDate(DateTime? v) =>
      _changeGig(() => gfDate = v == null || v == gfDate ? null : v);

  void setGfDoors(TimeOfDay v) => _changeGig(() => gfDoors = v);

  void setGfStart(TimeOfDay v) => _changeGig(() => gfStart = v);

  void setGfVenue(String v) => _changeGig(() => gfVenueId = v);

  void setGfPrice(String v) => _changeGig(() => gfPrice = v);

  void setGfTix(Ticketing t) => _changeGig(() => gfTix = t);

  void setGfAgeRequirement(AgeRequirement value) =>
      _changeGig(() => gfAgeRequirement = value);

  void setGfCap(String v) => _changeGig(() => gfCap = v);

  void setGfExt(String v) => _changeGig(() => gfExt = v);

  void setGfDescription(String value) => _changeGig(() => gfDesc = value);

  void setGfFly(String key) => _changeGig(() => gfFly = key);

  void setGfFlyerArt(PickedMedia? art) => _changeGig(() {
    gfFlyerArt = art;
    gfFlyerStorageId = null;
    gfFlyerUrl = null;
  });

  void setGfFlyerUploading(bool v) => _set(() => gfFlyerUploading = v);

  void setGfFlyerStorageId(String? id) {
    _changeGig(() => gfFlyerStorageId = id);
  }

  void toggleGfOverlay() => _changeGig(() => gfOverlay = !gfOverlay);

  /// Band-supplied art rather than one of the presses.
  bool get gfCustomFlyer => gfFly == 'custom';

  /// Presses always print the details; uploaded art can show clean.
  bool get gfShowOverlay => !gfCustomFlyer || gfOverlay;

  String get gfDoorsLabel => timeLabel(gfDoors);

  String get gfStartLabel => timeLabel(gfStart);

  static const _pendingOwnerPerformerId = 'pending-owner';

  List<GigPerformer> get gfPerformers =>
      gfProject?.performers ??
      [
        GigPerformer(
          id: _pendingOwnerPerformerId,
          kind: GigPerformerKind.band,
          name: myBand?.name ?? 'Your band',
          role: GigPerformerRole.headliner,
          bandId: bandId,
        ),
      ];

  /// "Sat Aug 15", or empty until a day is picked.
  String get gfDateLabel => gfDate == null ? '' : dateLabel(gfDate!);

  bool get canPublishGig =>
      gfName.trim().isNotEmpty &&
      gfDate != null &&
      gfVenueId != null &&
      (gfProject == null || gfPerformers.isNotEmpty) &&
      (!gfCustomFlyer || gfFlyerStorageId != null) &&
      (gfTix != Ticketing.external || validExternalTicketUrl);

  bool get validExternalTicketUrl {
    final uri = Uri.tryParse(gfExt.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  /// What the publish bar still asks for, in reading order.
  List<String> get gigMissing => [
    if (gfName.trim().isEmpty) 'a name',
    if (gfDate == null) 'a date',
    if (gfVenueId == null) 'a venue',
    if (gfProject != null && gfPerformers.isEmpty) 'a performer',
    if (gfCustomFlyer && gfFlyerStorageId == null) 'your flyer art',
    if (gfTix == Ticketing.external && !validExternalTicketUrl)
      'a valid HTTPS ticket link',
  ];

  String get gigUrl {
    final canonical = gfProject?.publicSlug;
    final slug =
        canonical ??
        _slugify(gfName.trim().isEmpty ? 'your-gig' : gfName.trim());
    return publicWebDisplayUrl('g/${slug.isEmpty ? 'your-gig' : slug}');
  }

  String get gigPreviewLabel {
    final project = gfProject;
    if (project == null) return 'PRIVATE DRAFT';
    return switch (project.status) {
      GigProjectStatus.cancelled => 'CANCELLED',
      GigProjectStatus.published
          when project.hasUnpublishedChanges || _gigDraftDirty =>
        'UNPUBLISHED CHANGES',
      GigProjectStatus.published => 'LIVE',
      GigProjectStatus.draft when project.publicGigId != null => 'UNPUBLISHED',
      _ => 'PRIVATE DRAFT',
    };
  }

  DateTime? get _gfDoorsAt {
    final date = gfDate;
    if (date == null) return null;
    return DateTime(
      date.year,
      date.month,
      date.day,
      gfDoors.hour,
      gfDoors.minute,
    );
  }

  DateTime? get _gfStartsAt {
    final date = gfDate;
    if (date == null) return null;
    var startsAt = DateTime(
      date.year,
      date.month,
      date.day,
      gfStart.hour,
      gfStart.minute,
    );
    final doorsAt = _gfDoorsAt!;
    if (startsAt.isBefore(doorsAt)) {
      startsAt = startsAt.add(const Duration(days: 1));
    }
    return startsAt;
  }

  Future<GigProject?> _ensureGigDraft() async {
    if (gfProject case final project?) return project;
    final editorGeneration = _gigEditorGeneration;
    try {
      final project = await (_gigCreateFuture ??= _createGigDraft(
        editorGeneration,
        bandId,
      ));
      if (!_isCurrentGigEditor(editorGeneration) ||
          gfProject?.id != project.id) {
        return null;
      }
      return gfProject;
    } on Exception {
      return null;
    }
  }

  Future<void> saveGigDraft() {
    final lineupMutation = _gigLineupMutationFuture;
    if (lineupMutation != null) {
      return lineupMutation.then((_) => _startGigSave());
    }
    return _startGigSave();
  }

  Future<void> _startGigSave() {
    _gigAutosaveTimer?.cancel();
    if (!_gigDraftDirty && gfProject != null && _gigSaveFuture == null) {
      return Future.value();
    }
    _gigSaveAgain = true;
    final existing = _gigSaveFuture;
    if (existing != null) return existing;
    final editorGeneration = _gigEditorGeneration;
    late final Future<void> save;
    save = _runGigSaveLoop(editorGeneration).whenComplete(() {
      if (identical(_gigSaveFuture, save)) _gigSaveFuture = null;
    });
    _gigSaveFuture = save;
    return save;
  }

  GigProject _gigProjectFromCurrentForm(
    GigProject project, {
    int? revision,
    List<GigPerformer>? performers,
  }) {
    return GigProject(
      id: project.id,
      bandId: project.bandId,
      publicGigId: project.publicGigId,
      publicSlug: project.publicSlug,
      status: project.status,
      revision: revision ?? project.revision,
      publishedRevision: project.publishedRevision,
      title: gfName.trim().isEmpty ? null : gfName.trim(),
      doorsAt: _gfDoorsAt,
      startsAt: _gfStartsAt,
      venueId: gfVenueId,
      price: gfPrice == 'FREE' ? 0 : int.tryParse(gfPrice.substring(1)) ?? 0,
      flyKey: gfFly,
      flyStorageId: gfFlyerStorageId,
      flyerUrl: gfFlyerUrl,
      overlay: gfOverlay,
      desc: gfDesc,
      ticketing: gfTix,
      ageRequirement: gfAgeRequirement,
      externalUrl: gfExt.trim().isEmpty ? null : gfExt.trim(),
      cap: gfCap,
      updatedAt: _now(),
      performers: performers ?? project.performers,
    );
  }

  Future<void> _runGigSaveLoop(int editorGeneration) async {
    while (_isCurrentGigEditor(editorGeneration) && _gigSaveAgain) {
      _gigSaveAgain = false;
      final project = await _ensureGigDraft();
      if (project == null || !_isCurrentGigEditor(editorGeneration)) return;
      gfSaveState = 'SAVING…';
      notifyListeners();
      final editGeneration = _gigEditGeneration;
      try {
        final revision = await repository.saveGigDraft(
          projectId: project.id,
          revision: gfProject?.revision ?? project.revision,
          title: gfName.trim().isEmpty ? null : gfName.trim(),
          doorsAt: _gfDoorsAt,
          startsAt: _gfStartsAt,
          venueId: gfVenueId,
          price: gfPrice == 'FREE'
              ? 0
              : int.tryParse(gfPrice.substring(1)) ?? 0,
          flyKey: gfFly,
          flyStorageId: gfFlyerStorageId,
          overlay: gfOverlay,
          desc: gfDesc,
          ticketing: gfTix,
          ageRequirement: gfAgeRequirement,
          externalUrl: gfExt.trim().isEmpty ? null : gfExt.trim(),
          cap: gfCap,
        );
        if (!_isCurrentGigEditor(editorGeneration)) return;
        final current = gfProject;
        if (current != null && current.id == project.id) {
          gfProject = _gigProjectFromCurrentForm(current, revision: revision);
        }
        if (editGeneration == _gigEditGeneration) {
          _gigDraftDirty = false;
          gfSaveState = 'SAVED';
        } else {
          _gigSaveAgain = true;
        }
      } on Exception catch (error) {
        logError('saveGigDraft', error);
        if (!_isCurrentGigEditor(editorGeneration)) return;
        gfSaveState = 'SAVE FAILED';
        _gigSaveAgain = false;
      }
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> applyFlyerProposal(FlyerEntryProposal proposal) async {
    _changeGig(() {
      if (proposal.title != null) gfName = proposal.title!;
      if (proposal.date != null) gfDate = proposal.date;
      if (proposal.doors case final doors?) {
        gfDoors = TimeOfDay(hour: doors.hour, minute: doors.minute);
      }
      if (proposal.start case final start?) {
        gfStart = TimeOfDay(hour: start.hour, minute: start.minute);
      }
      if (proposal.venueId != null) gfVenueId = proposal.venueId;
      if (proposal.price != null) {
        gfPrice = proposal.price == 0 ? 'FREE' : '\$${proposal.price}';
      }
    });
    await saveGigDraft();
    for (final band in proposal.bands) {
      if (gfPerformers.any((performer) => performer.bandId == band.id)) {
        continue;
      }
      await addExistingGigPerformer(band.id);
    }
  }

  Future<void> publishGig() async {
    if (gfFlyerUploading) {
      say('Still uploading your flyer. One sec.');
      return;
    }

    if (!canPublishGig) {
      say('Add ${gigMissing.join(' + ')} first.');
      return;
    }

    await saveGigDraft();
    final project = gfProject;
    if (project == null || gfSaveState == 'SAVE FAILED') return;
    final editorGeneration = _gigEditorGeneration;
    final venueId = gfVenueId!;
    final String publicGigId;
    GigProject? publishedProject;
    try {
      publicGigId = await repository.publishGigDraft(project.id);
      publishedProject = await repository.getGigProject(project.id);
    } on Exception catch (error) {
      logError('publishGig', error);
      say(genericErrorMessage);
      return;
    }
    if (!_isCurrentGigEditor(editorGeneration) || gfProject?.id != project.id) {
      return;
    }

    // A publish beyond the bounded global feed may not change its payload, so
    // do not rely on the feed subscription alone to retire this venue cache.
    _invalidateVenueDetails({venueId});
    final current = gfProject!;
    gfProject = GigProject(
      id: current.id,
      bandId: current.bandId,
      publicGigId: publicGigId,
      publicSlug: publishedProject.publicSlug ?? current.publicSlug,
      status: GigProjectStatus.published,
      revision: current.revision,
      publishedRevision: current.revision,
      title: current.title,
      doorsAt: current.doorsAt,
      startsAt: current.startsAt,
      venueId: current.venueId,
      price: current.price,
      flyKey: current.flyKey,
      flyStorageId: current.flyStorageId,
      flyerUrl: current.flyerUrl,
      overlay: current.overlay,
      desc: current.desc,
      ticketing: current.ticketing,
      ageRequirement: current.ageRequirement,
      externalUrl: current.externalUrl,
      cap: current.cap,
      updatedAt: _now(),
      performers: current.performers,
    );
    gfSaveState = 'PUBLISHED';
    gfPublished = true;
    notifyListeners();
    unawaited(refreshBandSetupStatus(bandId));
    unawaited(refreshBandDiscoveryReadiness(bandId));
  }

  /// "Keep editing" — back to the form with everything still filled in.
  void editPublishedGig() => _set(() => gfPublished = false);

  void makeAnotherGig() => startGigCreate();

  void previewGigDraft() => _set(() => gfPreviewing = true);

  void closeGigPreview() => _set(() => gfPreviewing = false);

  Future<void> addExistingGigPerformer(String performerBandId) async {
    await _queueGigLineupMutation(
      'addGigPerformer',
      (project) => repository.addGigPerformer(
        projectId: project.id,
        kind: GigPerformerKind.band,
        role: GigPerformerRole.support,
        bandId: performerBandId,
      ),
    );
  }

  Future<void> addNamedGigPerformer(String name, {required bool invite}) async {
    final performerName = name.trim();
    if (performerName.isEmpty) return;
    await _queueGigLineupMutation(
      'addGigPerformer',
      (project) => repository.addGigPerformer(
        projectId: project.id,
        kind: invite ? GigPerformerKind.invited : GigPerformerKind.text,
        role: GigPerformerRole.support,
        name: performerName,
      ),
      onSuccess: invite ? (_) => say('Invite link ready to share.') : null,
    );
  }

  Future<void> setGigPerformerRole(
    String performerId,
    GigPerformerRole role,
  ) async {
    await _queueGigLineupMutation(
      'updateGigPerformer',
      (project) => repository.updateGigPerformer(
        performerId: performerId == _pendingOwnerPerformerId
            ? project.performers.first.id
            : performerId,
        role: role,
      ),
    );
  }

  Future<void> removeGigPerformer(String performerId) async {
    await _queueGigLineupMutation(
      'removeGigPerformer',
      (_) => repository.removeGigPerformer(performerId),
    );
  }

  Future<void> moveGigPerformer(int oldIndex, int newIndex) async {
    await _queueGigLineupMutation('reorderGigPerformers', (project) {
      final performers = List<GigPerformer>.of(project.performers);
      performers.insert(newIndex, performers.removeAt(oldIndex));
      return repository.reorderGigPerformers(
        project.id,
        performers.map((performer) => performer.id).toList(),
      );
    });
  }

  Future<void> _queueGigLineupMutation(
    String operation,
    Future<GigProject> Function(GigProject project) mutation, {
    void Function(GigProject project)? onSuccess,
  }) {
    final editorGeneration = _gigEditorGeneration;
    final previous = _gigLineupMutationFuture;
    late final Future<void> queued;
    queued = (previous ?? Future.value())
        .then((_) async {
          if (!_isCurrentGigEditor(editorGeneration)) return;
          await _startGigSave();
          if (!_isCurrentGigEditor(editorGeneration) ||
              gfSaveState == 'SAVE FAILED') {
            return;
          }
          final project = gfProject;
          if (project == null) return;
          try {
            final updated = await mutation(project);
            if (!_isCurrentGigEditor(editorGeneration) ||
                gfProject?.id != project.id) {
              return;
            }
            gfProject = _gigProjectFromCurrentForm(
              updated,
              performers: updated.performers,
            );
            if (!_gigDraftDirty) {
              gfSaveState = updated.hasUnpublishedChanges
                  ? 'UNPUBLISHED CHANGES'
                  : 'SAVED';
            }
            onSuccess?.call(updated);
            notifyListeners();
          } on Exception catch (error) {
            logError(operation, error);
            if (_isCurrentGigEditor(editorGeneration)) {
              say(genericErrorMessage);
            }
          }
        })
        .whenComplete(() {
          if (identical(_gigLineupMutationFuture, queued)) {
            _gigLineupMutationFuture = null;
          }
        });
    _gigLineupMutationFuture = queued;
    return queued;
  }

  Future<void> refreshManagedGigs() {
    _managedGigsRefreshAgain = true;
    return _managedGigsRefreshFuture ??= _runManagedGigsRefresh().whenComplete(
      () => _managedGigsRefreshFuture = null,
    );
  }

  Future<void> _runManagedGigsRefresh() async {
    managedGigsLoading = true;
    if (!_disposed) notifyListeners();
    do {
      _managedGigsRefreshAgain = false;
      final requestedBandId = bandId;
      try {
        final projects = await repository.manageGigs(requestedBandId);
        if (requestedBandId != bandId) {
          _managedGigsRefreshAgain = true;
          continue;
        }
        managedGigProjects = projects;
        managedGigsBandId = requestedBandId;
      } on Exception catch (error) {
        logError('manageGigs', error);
        if (requestedBandId != bandId) _managedGigsRefreshAgain = true;
      }
    } while (_managedGigsRefreshAgain);
    managedGigsLoading = false;
    if (!_disposed) notifyListeners();
  }

  void ensureManagedGigs() {
    if (managedGigsBandId != bandId && !managedGigsLoading) {
      Future.microtask(refreshManagedGigs);
    }
  }

  Future<void> duplicateGigProject(String projectId) async {
    try {
      final duplicate = await repository.duplicateGig(projectId);
      await refreshManagedGigs();
      await editGigProject(duplicate.id);
    } on Exception catch (error) {
      logError('duplicateGig', error);
      say(genericErrorMessage);
    }
  }

  Future<void> unpublishGigProject(String projectId) async {
    await _runGigLifecycle(
      'unpublishGig',
      () => repository.unpublishGig(projectId),
    );
  }

  Future<void> cancelGigProject(String projectId) async {
    await _runGigLifecycle('cancelGig', () => repository.cancelGig(projectId));
  }

  Future<void> deleteGigProject(String projectId) async {
    await _runGigLifecycle('deleteGig', () => repository.deleteGig(projectId));
  }

  Future<void> _runGigLifecycle(
    String operation,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      await refreshManagedGigs();
    } on Exception catch (error) {
      logError(operation, error);
      say(genericErrorMessage);
    }
  }

  /// The ✕ in the header: done here, back to the gig manager.
  void closeGigCreate() {
    final pristine = gfProject == null && !_gigDraftDirty;
    if (pristine) {
      _set(() {
        managedGigsBandId = bandId;
        _stack = const [ScreenEntry(Screen.gigMgr)];
      });
      unawaited(refreshManagedGigs());
      return;
    }
    final saved = saveGigDraft();
    _set(() {
      // The explicit refresh below must run after the final save. Mark this
      // band as loaded so the manager's first build does not start a racing
      // pre-save refresh of its own.
      managedGigsBandId = bandId;
      _stack = const [ScreenEntry(Screen.gigMgr)];
    });
    unawaited(saved.then((_) => refreshManagedGigs()));
  }

  void _resetGigForm() {
    _gigEditorGeneration++;
    gfName = '';
    gfDate = null;
    gfDoors = const TimeOfDay(hour: 20, minute: 0);
    gfStart = const TimeOfDay(hour: 21, minute: 0);
    gfVenueId = null;
    gfPrice = 'FREE';
    gfTix = Ticketing.rsvp;
    gfAgeRequirement = AgeRequirement.allAges;
    gfCap = 'No cap';
    gfExt = '';
    gfDesc = '';
    gfFly = 'xerox';
    gfOverlay = true;
    gfFlyerArt = null;
    gfFlyerStorageId = null;
    gfFlyerUrl = null;
    gfFlyerUploading = false;
    gfPublished = false;
    gfPreviewing = false;
    gfProject = null;
    gfSaveState = 'DRAFT';
    _gigAutosaveTimer?.cancel();
    _gigCreateFuture = null;
    _gigSaveFuture = null;
    _gigLineupMutationFuture = null;
    _gigSaveAgain = false;
    _gigDraftDirty = false;
    _gigEditGeneration = 0;
  }
}
