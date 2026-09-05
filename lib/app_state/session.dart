part of '../app_state.dart';

enum PendingKind {
  rsvp,
  follow,
  save,
  myGigs,
  band,
  join,
  gigInvite,
  orgApply,
  orgJoin,
}

class PendingAuth {
  final PendingKind kind;
  final String? id;

  const PendingAuth(this.kind, [this.id]);
}

/// The signed-in session: auth changes, the pending action behind the auth
/// gate, profile and history refreshes, sign-out and account deletion.
mixin _SessionState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  abstract FanCity? _appliedHomePersonalization;
  abstract UserProfile? profile;
  set history(List<FanHistoryItem> value);
  Set<String> get rsvps;
  set rsvps(Set<String> value);
  Set<String> get follows;
  set follows(Set<String> value);
  Set<String> get saved;
  set saved(Set<String> value);
  Band? band(String id);
  void go(Screen s, [String? param]);
  void back();
  void resetTo(Screen s);
  Future<void> refreshOrganizationApplication();
  Future<void> refreshGigWritePolicy();

  int _sessionGeneration = 0;

  // ---- session
  bool authed = false;
  bool isPlatformAdmin = false;
  PendingAuth? pending;
  PendingKind? _authConfirmationKind;
  PendingKind? get authConfirmationKind => _authConfirmationKind;
  int authStep = 1;
  final Set<String> userGenres = {};
  Future<bool>? _authReady;
  Future<void>? _authCommit;

  void _handleAuthChange(bool signedIn) {
    _sessionGeneration++;
    authed = signedIn;
    if (signedIn) {
      _clearMemberships();
      _clearOrganizationsState();
      authStep = 2;
      _authReady = _ensureUser();
      unawaited(_authReady);
    } else {
      _clearSessionSensitiveState();
      unawaited(
        repository.refreshAuth().catchError(
          (Object error) => logError('refreshAuth', error),
        ),
      );
    }
    notifyListeners();
  }

  Future<bool> _ensureUser() async {
    final sessionGeneration = _sessionGeneration;
    try {
      // The websocket must carry the new identity before the mutation runs.
      await repository.refreshAuth();
      if (!_isCurrentSession(sessionGeneration)) return false;
      await repository.ensureUser(name: auth.displayName);
      if (!_isCurrentSession(sessionGeneration)) return false;
      _restartMemberships();
      _restartOrganizations();
      unawaited(refreshOrganizationApplication());
      unawaited(refreshGigWritePolicy());
      unawaited(_refreshPlatformAdmin(sessionGeneration));
      await _refreshProfile(sessionGeneration: sessionGeneration);
      if (!_isCurrentSession(sessionGeneration)) return false;
      unawaited(_refreshHistory(sessionGeneration: sessionGeneration));
      return true;
    } catch (error) {
      logError('ensureUser', error);
      if (_isCurrentSession(sessionGeneration)) say(genericErrorMessage);
      return false;
    }
  }

  @override
  bool _isCurrentSession(int generation) =>
      !_disposed && authed && generation == _sessionGeneration;

  @override
  Future<void> _refreshHistory({int? sessionGeneration}) async {
    final requestedSession = sessionGeneration ?? _sessionGeneration;
    try {
      final loaded = await repository.history();
      if (!_isCurrentSession(requestedSession)) return;
      history = loaded;
      notifyListeners();
    } catch (error) {
      logError('history', error);
    }
  }

  @override
  Future<bool> _refreshProfile({int? sessionGeneration}) async {
    final requestedSession = sessionGeneration ?? _sessionGeneration;
    try {
      final loadedProfile = await repository.me();
      if (!_isCurrentSession(requestedSession)) return false;
      profile = loadedProfile;
      userGenres
        ..clear()
        ..addAll(loadedProfile?.genres ?? const []);
      FanCity? preferredCity;
      if (loadedProfile?.locationPersonalizationEnabled == true) {
        preferredCity = loadedProfile?.homeLocation;
      } else if (loadedProfile?.homeLocation == null) {
        preferredCity = loadedProfile?.fanOnboarding?.preferredCity;
      }
      if (preferredCity != null) {
        _applyFanCity(preferredCity);
        if (loadedProfile?.locationPersonalizationEnabled == true) {
          _appliedHomePersonalization = preferredCity;
        }
      } else if (_appliedHomePersonalization != null) {
        _applyFanCity(FanCity.sf);
      }
      notifyListeners();
      return true;
    } catch (error) {
      logError('me', error);
      return false;
    }
  }

  Future<void> _refreshPlatformAdmin(int sessionGeneration) async {
    try {
      final loaded = await repository.isPlatformAdmin();
      if (!_isCurrentSession(sessionGeneration)) return;
      isPlatformAdmin = loaded;
      notifyListeners();
    } catch (error) {
      logError('isPlatformAdmin', error);
      if (!_isCurrentSession(sessionGeneration)) return;
      isPlatformAdmin = false;
      notifyListeners();
    }
  }

  // ========================= auth =========================

  void needAuth(PendingAuth p) {
    pending = p;
    _authConfirmationKind = p.kind;
    authStep = 1;
    _authCommit = null;
    _postAuthScreen = null;
    go(Screen.auth);
    if (p.kind == PendingKind.orgJoin) {
      // Keep the invitation address through a full-page OAuth redirect.
      replaceBrowserPath('/apply/${Uri.encodeComponent(p.id!)}');
    } else if (p.kind == PendingKind.orgApply) {
      // Startup restores the application intent after an OAuth page reload.
      replaceBrowserPath(organizerApplyPath);
    }
  }

  Future<void> login() async => auth.signInDemo();

  Future<void> signOut() async {
    await auth.signOut();
    _clearSessionSensitiveState();
    resetTo(Screen.home);
    say('Signed out.');
  }

  void switchToAdmin() => resetTo(Screen.adminQueue);

  Future<bool> deleteAccount() async {
    try {
      // Establish the Convex tombstone while this Clerk session can still
      // authenticate. The eventual user.deleted webhook is only a retry path.
      await repository.deleteCurrentUser();
      await auth.deleteAccount();
    } catch (error) {
      logError('deleteAccount', error);
      say(genericErrorMessage);
      return false;
    }

    _clearSessionSensitiveState();
    resetTo(Screen.home);
    say('Account deleted.');
    return true;
  }

  /// Where [leaveAuth] lands, decided by [commitAuth]; null pops back to
  /// wherever the auth gate was opened from.
  Screen? _postAuthScreen;

  /// The durable half of finishing auth: completes the action that triggered
  /// the gate. Runs before any confirmation delay so
  /// backing out (or being killed) mid-splash can't drop the pending action.
  Future<void> commitAuth() {
    final inProgress = _authCommit;
    if (inProgress != null) return inProgress;
    final commit = _commitAuth();
    _authCommit = commit;
    unawaited(
      commit.catchError((Object _) {
        if (identical(_authCommit, commit)) _authCommit = null;
      }),
    );
    return commit;
  }

  Future<void> _commitAuth() async {
    final ready = await (_authReady ??= _ensureUser());
    if (!ready) {
      _authReady = null;
      throw const AuthException("Couldn't finish sign-in. Try again.");
    }
    final p = pending;
    switch (p?.kind) {
      case PendingKind.rsvp:
        await repository.ensureRsvp(p!.id!);
        rsvps = {...rsvps, p.id!};
        say("You're on the list. QR is in Profile.");
        _postAuthScreen = null;
      case PendingKind.follow:
        await repository.ensureFollow(p!.id!);
        follows = {...follows, p.id!};
        _syncFollowedBandGigSubscriptions();
        final name = band(p.id!)?.name;
        say(name == null ? 'Band followed.' : 'Following $name.');
        _postAuthScreen = null;
      case PendingKind.save:
        await repository.ensureSave(p!.id!);
        saved = {...saved, p.id!};
        say('Show saved.');
        _postAuthScreen = null;
      case PendingKind.myGigs:
        _postAuthScreen = Screen.myGigs;
        final name = (profile?.name ?? auth.displayName)?.trim();
        say(
          name == null || name.isEmpty
              ? 'Welcome back.'
              : 'Welcome back, ${name.split(' ').first}.',
        );
      case PendingKind.band:
        _resetBandForm();
        _postAuthScreen = Screen.bandCreate;
      case PendingKind.join:
        _postAuthScreen = Screen.bandJoin;
      case PendingKind.gigInvite:
        _postAuthScreen = Screen.gigInvite;
      case PendingKind.orgApply:
        _postAuthScreen = Screen.orgApply;
      case PendingKind.orgJoin:
        // Pop back to the invitation, retaining its token and requiring the
        // recipient to accept explicitly after authentication.
        _postAuthScreen = null;
      case null:
        _postAuthScreen = null;
    }
    pending = null;
  }

  /// The navigation half: leaves the auth screen for wherever [commitAuth]
  /// decided. Skipping this (user backed out first) loses nothing.
  void leaveAuth() {
    final destination = _postAuthScreen;
    _postAuthScreen = null;
    if (destination == null) {
      back();
    } else {
      resetTo(destination);
    }
    _authConfirmationKind = null;
  }

  Future<void> finishAuth() async {
    await commitAuth();
    leaveAuth();
  }
}
