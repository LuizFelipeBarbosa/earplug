part of '../app_state.dart';

/// The signed-in fan: interactions (RSVPs, follows, saves), profile and
/// history, the onboarding flow, and the followed-band gig subscriptions.
mixin _FanState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  bool get authed;
  int get _sessionGeneration;
  Set<String> get userGenres;
  set _stack(List<ScreenEntry> value);
  int get _locationRequestGeneration;
  set _locationRequestGeneration(int value);
  abstract DiscoveryLocation discoveryLocation;
  abstract FanCity? _discoveryHomeCity;
  abstract LatLng? currentPosition;
  abstract bool locating;
  abstract LocationFailure? locationFailure;
  abstract DiscoveryFilters filters;
  Map<String, Band> get _bands;
  List<Gig> get _allGigs;
  Map<String, int> get _goingCounts;
  Band? band(String id);
  void needAuth(PendingAuth p);
  void openMyGigsTab();
  void startBandCreate();

  final Map<String, StreamSubscription<List<Gig>>>
  _followedBandGigSubscriptions = {};
  final Map<String, Object> _followedBandGigTokens = {};
  final Map<String, List<Gig>> _followedBandGigs = {};

  final Map<String, Gig> _interactionGigs = {};

  // ---- fan data
  Set<String> rsvps = {};
  Set<String> _confirmedRsvps = {};
  final Map<String, ({bool desired, Object operation})> _pendingRsvps = {};
  Set<String> follows = {};
  Set<String> saved = {};
  int attended = 0;
  List<FanHistoryItem> history = const [];
  UserProfile? profile;
  bool _profileTutorialReplay = false;
  Object? _fanAvatarSaveOwner;
  bool get fanAvatarSaving => _fanAvatarSaveOwner != null;
  FanCity? _appliedHomePersonalization;
  final Set<String> _loadingFollowBands = {};
  Future<void> _fanGenreWrite = Future.value();
  Future<void> _profileTutorialWrite = Future.value();

  FanOnboarding? get fanOnboarding => profile?.fanOnboarding;

  bool get fanOnboardingComplete {
    final onboarding = fanOnboarding;
    return onboarding != null &&
        onboarding.preferredCity != null &&
        onboarding.genreChoice != FanGenreChoice.pending &&
        saved.isNotEmpty;
  }

  bool get showFanOnboarding => fanOnboarding != null && !fanOnboardingComplete;

  bool get profileTutorialVisible =>
      authed &&
      profile != null &&
      profile!.profileTutorialAvailable &&
      (_profileTutorialReplay || !profile!.profileTutorialCompleted);

  bool get profileTutorialAvailable =>
      authed && profile?.profileTutorialAvailable == true;

  void _cacheInteractions(Interactions interactions) {
    _confirmedRsvps = Set<String>.of(interactions.rsvpGigIds);
    final nextRsvps = Set<String>.of(_confirmedRsvps);
    for (final entry in _pendingRsvps.entries.toList()) {
      if (nextRsvps.contains(entry.key) == entry.value.desired) {
        _pendingRsvps.remove(entry.key);
      } else if (entry.value.desired) {
        nextRsvps.add(entry.key);
      } else {
        nextRsvps.remove(entry.key);
      }
    }
    rsvps = nextRsvps;
    follows = Set<String>.of(interactions.followBandIds);
    saved = Set<String>.of(interactions.savedGigIds);
    _interactionGigs
      ..clear()
      ..addEntries(interactions.gigs.map((gig) => MapEntry(gig.id, gig)));
    attended = interactions.attendedCount;
    _syncFollowedBandGigSubscriptions();
    for (final bandId in follows) {
      if (!_bands.containsKey(bandId)) unawaited(_loadFollowBand(bandId));
    }
    notifyListeners();
  }

  @override
  void _syncFollowedBandGigSubscriptions() {
    if (!authed || _nextFeedStartsAt == null) {
      _clearFollowedBandGigSubscriptions();
      return;
    }
    final removedBandIds = _followedBandGigSubscriptions.keys
        .where((bandId) => !follows.contains(bandId))
        .toList();
    for (final bandId in removedBandIds) {
      _followedBandGigTokens.remove(bandId);
      _followedBandGigs.remove(bandId);
      unawaited(_followedBandGigSubscriptions.remove(bandId)?.cancel());
    }

    for (final bandId in follows) {
      if (_followedBandGigSubscriptions.containsKey(bandId)) continue;
      final token = Object();
      _followedBandGigTokens[bandId] = token;
      _followedBandGigSubscriptions[bandId] = repository
          .upcomingGigsForBand(bandId)
          .listen(
            (gigs) {
              if (_disposed ||
                  !follows.contains(bandId) ||
                  !identical(_followedBandGigTokens[bandId], token)) {
                return;
              }
              _followedBandGigs[bandId] = List<Gig>.of(gigs);
              notifyListeners();
            },
            onError: (Object error) =>
                logError('upcomingGigsForBand $bandId', error),
          );
    }
  }

  void _clearFollowedBandGigSubscriptions() {
    _followedBandGigTokens.clear();
    _followedBandGigs.clear();
    for (final subscription in _followedBandGigSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _followedBandGigSubscriptions.clear();
  }

  @override
  Future<void> _loadFollowBand(String bandId) async {
    if (!_loadingFollowBands.add(bandId)) return;
    try {
      final loaded = await repository.band(bandId);
      if (loaded == null || _disposed) return;
      _bands[bandId] = loaded.copyWith(
        upcoming: [
          for (final gig in _allGigs)
            if (gig.lineup.contains(bandId)) gig.id,
        ],
      );
      notifyListeners();
    } catch (error) {
      logError('followBand $bandId', error);
    } finally {
      _loadingFollowBands.remove(bandId);
    }
  }

  // ========================= fan actions =========================

  /// Flips [id] in [ids] on screen straight away and persists in the
  /// background; a rejected write puts the flip back and says so. Returns
  /// whether [id] ended up on.
  bool _toggleOptimistically(
    Set<String> ids,
    String id,
    Future<void> Function(String) persist, [
    void Function()? onChanged,
  ]) {
    final wasOn = ids.contains(id);
    wasOn ? ids.remove(id) : ids.add(id);
    onChanged?.call();
    notifyListeners();
    unawaited(
      persist(id).catchError((Object error) {
        logError('toggle $id', error);
        wasOn ? ids.add(id) : ids.remove(id);
        onChanged?.call();
        say(genericErrorMessage); // notifies, so the roll-back shows
      }),
    );
    return !wasOn;
  }

  void toggleRsvp(String id) {
    final wasGoing = rsvps.contains(id);
    final nowGoing = !wasGoing;
    final operation = Object();
    _pendingRsvps[id] = (desired: nowGoing, operation: operation);
    nowGoing ? rsvps.add(id) : rsvps.remove(id);
    notifyListeners();
    unawaited(
      repository
          .toggleRsvp(id, on: nowGoing)
          .then((_) {
            if (!identical(_pendingRsvps[id]?.operation, operation)) return;
            _pendingRsvps.remove(id);
          })
          .catchError((Object error) {
            logError('toggle $id', error);
            if (!identical(_pendingRsvps[id]?.operation, operation)) return;
            _pendingRsvps.remove(id);
            wasGoing ? rsvps.add(id) : rsvps.remove(id);
            say(genericErrorMessage);
          }),
    );
    say(nowGoing ? "You're on the list. QR is in Profile." : 'RSVP removed.');
  }

  void requestRsvp(String id) {
    if (authed) {
      toggleRsvp(id);
    } else {
      needAuth(PendingAuth(PendingKind.rsvp, id));
    }
  }

  void toggleFollow(String id) {
    if (_toggleOptimistically(
      follows,
      id,
      repository.toggleFollow,
      _syncFollowedBandGigSubscriptions,
    )) {
      final name = band(id)?.name;
      say(name == null ? 'Band followed.' : 'Following $name.');
    }
  }

  void requestFollow(String id) {
    if (authed) {
      toggleFollow(id);
    } else {
      needAuth(PendingAuth(PendingKind.follow, id));
    }
  }

  void toggleSave(String id) {
    final nowSaved = _toggleOptimistically(saved, id, repository.toggleSave);
    say(nowSaved ? 'Show saved.' : 'Removed from saved shows.');
  }

  void requestSave(String id) {
    if (authed) {
      toggleSave(id);
    } else {
      needAuth(PendingAuth(PendingKind.save, id));
    }
  }

  /// Starts band creation immediately for members and preserves the attempted
  /// action for everyone else.
  void requestStartBand() {
    if (authed) {
      startBandCreate();
    } else {
      needAuth(const PendingAuth(PendingKind.band));
    }
  }

  Future<bool> saveFanProfile({
    required String name,
    required String? bio,
    required FanCity? homeLocation,
    required List<String> genres,
    required bool locationPersonalizationEnabled,
    required bool followedBandUpdatesEnabled,
  }) async {
    if (!authed) return false;
    final sessionGeneration = _sessionGeneration;
    final savedName = name.trim();
    if (savedName.isEmpty) {
      say('Add your name before saving.');
      return false;
    }
    final savedBio = bio?.trim();
    final normalizedBio = savedBio == null || savedBio.isEmpty
        ? null
        : savedBio;
    final savedGenres = List<String>.unmodifiable(genres);

    try {
      await repository.updateFanProfile(
        name: savedName,
        bio: normalizedBio,
        homeLocation: homeLocation,
        genres: savedGenres,
        locationPersonalizationEnabled: locationPersonalizationEnabled,
        followedBandUpdatesEnabled: followedBandUpdatesEnabled,
      );
    } catch (error) {
      logError('updateFanProfile', error);
      if (_isCurrentSession(sessionGeneration)) say(genericErrorMessage);
      return false;
    }

    if (!_isCurrentSession(sessionGeneration)) return false;
    final currentProfile = profile;
    if (currentProfile != null) {
      profile = currentProfile.copyWith(
        name: savedName,
        bio: normalizedBio,
        homeLocation: homeLocation,
        genres: savedGenres,
        locationPersonalizationEnabled: locationPersonalizationEnabled,
        followedBandUpdatesEnabled: followedBandUpdatesEnabled,
      );
    } else {
      await _refreshProfile(sessionGeneration: sessionGeneration);
      if (!_isCurrentSession(sessionGeneration)) return false;
    }
    userGenres
      ..clear()
      ..addAll(savedGenres);
    if (locationPersonalizationEnabled && homeLocation != null) {
      _applyFanCity(homeLocation);
      _appliedHomePersonalization = homeLocation;
    } else if (_appliedHomePersonalization != null) {
      _applyFanCity(FanCity.sf);
    }
    notifyListeners();
    return true;
  }

  Future<bool> updateFanAvatar(PickedMedia media) async {
    if (!authed || fanAvatarSaving) return false;
    final sessionGeneration = _sessionGeneration;
    final saveOwner = Object();
    _fanAvatarSaveOwner = saveOwner;
    notifyListeners();
    try {
      final storageId = await mediaUploader.uploadAvatarRaw(media: media);
      if (!_isCurrentSession(sessionGeneration)) return false;
      await repository.setAvatar(storageId);
      if (!_isCurrentSession(sessionGeneration)) return false;
      await _refreshProfile(sessionGeneration: sessionGeneration);
      return _isCurrentSession(sessionGeneration);
    } catch (error) {
      logError('setAvatar', error);
      if (_isCurrentSession(sessionGeneration)) say(genericErrorMessage);
      return false;
    } finally {
      if (identical(_fanAvatarSaveOwner, saveOwner)) {
        _fanAvatarSaveOwner = null;
        notifyListeners();
      }
    }
  }

  Future<bool> clearFanAvatar() async {
    if (!authed || fanAvatarSaving) return false;
    final sessionGeneration = _sessionGeneration;
    final saveOwner = Object();
    _fanAvatarSaveOwner = saveOwner;
    notifyListeners();
    try {
      await repository.clearAvatar();
      if (!_isCurrentSession(sessionGeneration)) return false;
      profile = profile?.copyWith(avatarUrl: null);
      notifyListeners();
      return true;
    } catch (error) {
      logError('clearAvatar', error);
      if (_isCurrentSession(sessionGeneration)) say(genericErrorMessage);
      return false;
    } finally {
      if (identical(_fanAvatarSaveOwner, saveOwner)) {
        _fanAvatarSaveOwner = null;
        notifyListeners();
      }
    }
  }

  Future<void> completeProfileTutorial() async {
    if (!profileTutorialAvailable) return;
    final sessionGeneration = _sessionGeneration;
    try {
      await _persistProfileTutorial(true, sessionGeneration);
      if (!_isCurrentSession(sessionGeneration)) return;
      profile = profile?.copyWith(profileTutorialCompleted: true);
      _profileTutorialReplay = false;
      notifyListeners();
    } catch (error) {
      logError('completeProfileTutorial', error);
      if (_isCurrentSession(sessionGeneration)) {
        say(profileSetupSaveErrorMessage);
      }
    }
  }

  void replayProfileTutorial() {
    if (!authed) {
      openMyGigsTab();
      return;
    }
    if (!profileTutorialAvailable) return;
    _set(() {
      _profileTutorialReplay = true;
      _stack = const [ScreenEntry(Screen.myGigs)];
    });
    final sessionGeneration = _sessionGeneration;
    unawaited(
      _persistProfileTutorial(false, sessionGeneration)
          .then((_) {
            if (!_isCurrentSession(sessionGeneration)) return;
            profile = profile?.copyWith(profileTutorialCompleted: false);
            notifyListeners();
          })
          .catchError((Object error) {
            logError('replayProfileTutorial', error);
            if (_isCurrentSession(sessionGeneration)) {
              say(profileSetupSaveErrorMessage);
            }
          }),
    );
  }

  Future<void> _persistProfileTutorial(bool completed, int sessionGeneration) {
    final write = _profileTutorialWrite.then((_) async {
      if (!_isCurrentSession(sessionGeneration)) return;
      await repository.setProfileTutorialCompleted(completed);
    });
    _profileTutorialWrite = write.catchError((Object _) {});
    return write;
  }

  // ========================= fan onboarding =========================

  void _setLocalFanOnboarding(
    FanOnboarding onboarding, {
    List<String>? genres,
  }) {
    final current = profile;
    if (current == null) return;
    final nextGenres = genres ?? current.genres;
    profile = current.copyWith(
      genres: List.unmodifiable(nextGenres),
      fanOnboarding: onboarding,
    );
    userGenres
      ..clear()
      ..addAll(nextGenres);
    notifyListeners();
  }

  void selectFanCity(FanCity preferredCity) {
    final previous = fanOnboarding;
    if (previous == null) return;
    final previousDiscoveryState = (
      location: discoveryLocation,
      homeCity: _discoveryHomeCity,
      position: currentPosition,
      locating: locating,
      failure: locationFailure,
      filters: filters,
    );

    _applyFanCity(preferredCity);
    _setLocalFanOnboarding(
      FanOnboarding(
        preferredCity: preferredCity,
        genreChoice: previous.genreChoice,
        collapsed: previous.collapsed,
      ),
    );
    say('Browsing ${preferredCity.label} shows.');

    unawaited(
      repository.updateFanOnboarding(preferredCity: preferredCity).catchError((
        Object error,
      ) {
        logError('updateFanOnboarding city', error);
        final current = fanOnboarding;
        if (current?.preferredCity == preferredCity) {
          _locationRequestGeneration++;
          discoveryLocation = previousDiscoveryState.location;
          _discoveryHomeCity = previousDiscoveryState.homeCity;
          currentPosition = previousDiscoveryState.position;
          locating = previousDiscoveryState.locating;
          locationFailure = previousDiscoveryState.failure;
          filters = previousDiscoveryState.filters;
          _setLocalFanOnboarding(
            FanOnboarding(
              preferredCity: previous.preferredCity,
              genreChoice: current!.genreChoice,
              collapsed: current.collapsed,
            ),
          );
        }
        say(fanSetupSaveErrorMessage);
      }),
    );
  }

  void toggleFanGenre(String genre) {
    final selected = Set<String>.of(userGenres);
    selected.contains(genre) ? selected.remove(genre) : selected.add(genre);
    _saveFanGenreChoice(
      selected.toList(),
      selected.isEmpty ? FanGenreChoice.pending : FanGenreChoice.selected,
    );
  }

  void chooseOpenGenres() => _saveFanGenreChoice(const [], FanGenreChoice.open);

  void _saveFanGenreChoice(List<String> genres, FanGenreChoice genreChoice) {
    final previous = fanOnboarding;
    if (previous == null) return;
    final previousGenres = List<String>.of(userGenres);
    _setLocalFanOnboarding(
      FanOnboarding(
        preferredCity: previous.preferredCity,
        genreChoice: genreChoice,
        collapsed: previous.collapsed,
      ),
      genres: genres,
    );

    _fanGenreWrite = _fanGenreWrite.then((_) async {
      try {
        await repository.updateFanOnboarding(
          genreChoice: genreChoice,
          genres: genres,
        );
      } catch (error) {
        logError('updateFanOnboarding genres', error);
        final current = fanOnboarding;
        if (current?.genreChoice == genreChoice &&
            setEquals(userGenres, genres.toSet())) {
          _setLocalFanOnboarding(
            FanOnboarding(
              preferredCity: current!.preferredCity,
              genreChoice: previous.genreChoice,
              collapsed: current.collapsed,
            ),
            genres: previousGenres,
          );
        }
        say(fanSetupSaveErrorMessage);
      }
    });
    unawaited(_fanGenreWrite);
  }

  void setFanOnboardingCollapsed(bool collapsed) {
    final previous = fanOnboarding;
    if (previous == null || previous.collapsed == collapsed) return;
    _setLocalFanOnboarding(
      FanOnboarding(
        preferredCity: previous.preferredCity,
        genreChoice: previous.genreChoice,
        collapsed: collapsed,
      ),
    );
    unawaited(
      repository.updateFanOnboarding(collapsed: collapsed).catchError((
        Object error,
      ) {
        logError('updateFanOnboarding collapsed', error);
        final current = fanOnboarding;
        if (current?.collapsed == collapsed) {
          _setLocalFanOnboarding(
            FanOnboarding(
              preferredCity: current!.preferredCity,
              genreChoice: current.genreChoice,
              collapsed: previous.collapsed,
            ),
          );
        }
        say(fanSetupSaveErrorMessage);
      }),
    );
  }

  int _upcomingRsvpGigsVersion = -1;
  int? _upcomingRsvpGigsMinute;
  List<Gig> _upcomingRsvpGigs = const [];

  List<Gig> get upcomingRsvpGigs {
    final now = _now();
    final minute = now.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;
    if (_upcomingRsvpGigsVersion == _stateVersion &&
        _upcomingRsvpGigsMinute == minute) {
      return _upcomingRsvpGigs;
    }
    final gigs = [
      for (final id in rsvps)
        if (_interactionGigs[id] ?? _cachedGig(id) case final Gig gig
            when gig.startsAt.isAfter(now) &&
                (gig.lifecycle == GigLifecycle.published ||
                    gig.lifecycle == GigLifecycle.cancelled) &&
                gig.tix == Ticketing.rsvp)
          gig,
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    _upcomingRsvpGigs = List<Gig>.unmodifiable(gigs);
    _upcomingRsvpGigsVersion = _stateVersion;
    _upcomingRsvpGigsMinute = minute;
    return _upcomingRsvpGigs;
  }

  int _followedBandShowsVersion = -1;
  int? _followedBandShowsMinute;
  List<Gig> _followedBandShows = const [];

  List<Gig> get followedBandShows {
    final now = DateTime.now();
    final minute = now.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;
    if (_followedBandShowsVersion == _stateVersion &&
        _followedBandShowsMinute == minute) {
      return _followedBandShows;
    }
    if (profile?.followedBandUpdatesEnabled == false || follows.isEmpty) {
      _followedBandShows = const [];
      _followedBandShowsVersion = _stateVersion;
      _followedBandShowsMinute = minute;
      return _followedBandShows;
    }
    final gigsById = {
      for (final gig in _allGigs) gig.id: gig,
      for (final gigs in _followedBandGigs.values)
        for (final gig in gigs) gig.id: gig,
    };
    final shows = [
      for (final gig in gigsById.values)
        if (!gig.startsAt.isBefore(now) && gig.lineup.any(follows.contains))
          gig,
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    _followedBandShows = List<Gig>.unmodifiable(shows);
    _followedBandShowsVersion = _stateVersion;
    _followedBandShowsMinute = minute;
    return _followedBandShows;
  }

  /// The most recent server-confirmed RSVP state, excluding local optimism.
  ///
  /// Requiring the local state too hides confirmed-only UI immediately when a
  /// removal is pending, while an add stays gated until its subscription
  /// confirmation arrives.
  bool hasConfirmedRsvp(String gigId) =>
      _confirmedRsvps.contains(gigId) && rsvps.contains(gigId);

  /// Reconciles the live count stream with one local mutation not yet echoed.
  ///
  /// [_goingCounts] is authoritative when it has covered this gig. The gig's
  /// own count is a fallback for relationship or interaction payloads that the
  /// counts stream has never included; feed gigs themselves carry zero here.
  int rsvpCount(Gig gig) {
    final authoritativeGig = _interactionGigs[gig.id] ?? gig;
    final baseGoing = _goingCounts[gig.id] ?? authoritativeGig.going;
    final pending = _pendingRsvps[gig.id];
    if (pending == null ||
        pending.desired == _confirmedRsvps.contains(gig.id)) {
      return baseGoing;
    }
    final reconciled = baseGoing + (pending.desired ? 1 : -1);
    return reconciled < 0 ? 0 : reconciled;
  }
}
