import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/convex_repository.dart';
import 'data/demo_repository.dart';
import 'data/repository.dart';
import 'demo_data.dart';
import 'models.dart';
import 'services/auth_service.dart';

enum Screen {
  home,
  gig,
  band,
  explore,
  myGigs,
  auth,
  bandCreate,
  bandDash,
  bandEdit,
  gigMgr,
  gigCreate,
  analytics,
}

class ScreenEntry {
  final Screen screen;
  final String? param; // gig id or band id where relevant

  const ScreenEntry(this.screen, [this.param]);
}

enum DateFilter { all, tonight, week }

enum PendingKind { rsvp, follow, myGigs, band }

enum DataStatus { connecting, ready, error }

class PendingAuth {
  final PendingKind kind;
  final String? id;

  const PendingAuth(this.kind, [this.id]);
}

class AppState extends ChangeNotifier {
  AppState({EarplugRepository? repository, AuthService? auth})
    : this._(auth ?? FakeAuthService(), repository);

  AppState._(AuthService resolvedAuth, EarplugRepository? providedRepository)
    : auth = resolvedAuth,
      repository = providedRepository ?? DemoRepository(auth: resolvedAuth),
      _dataStatus = providedRepository is ConvexRepository
          ? DataStatus.connecting
          : DataStatus.ready {
    authed = auth.signedIn;
    if (authed) {
      authStep = 2;
      unawaited(_ensureUser());
    }
    _authSubscription = auth.signedInChanges.listen(_handleAuthChange);
    _subscribeToFeed();
    _interactionsSubscription = repository.myInteractions().listen(
      _cacheInteractions,
      onError: (_) {},
    );
    _bandsSubscription = repository.myBands().listen(
      _cacheMemberships,
      onError: (_) {},
    );
  }

  final EarplugRepository repository;
  final AuthService auth;

  StreamSubscription<bool>? _authSubscription;
  StreamSubscription<FeedSnapshot>? _feedSubscription;
  StreamSubscription<Interactions>? _interactionsSubscription;
  StreamSubscription<List<BandMembership>>? _bandsSubscription;

  DataStatus _dataStatus;
  DataStatus get dataStatus => _dataStatus;
  String? dataError;

  List<Gig> _allGigs = const [];
  Map<String, Band> _bands = {};
  Map<String, Venue> _venues = const {};
  final Map<String, List<VideoClip>> _videoCache = {};
  final Set<String> _videoLoads = {};

  // ---- navigation
  List<ScreenEntry> _stack = const [ScreenEntry(Screen.home)];
  ScreenEntry get current => _stack.last;
  bool get canGoBack => _stack.length > 1;

  // ---- session
  bool authed = false;
  PendingAuth? pending;
  int authStep = 1;
  final Set<String> userGenres = {};

  // ---- fan data
  Set<String> rsvps = {};
  Set<String> follows = {};
  Set<String> saved = {};
  int attended = 0;

  // ---- home filters
  bool mapMode = false;
  String city = 'sf'; // 'sf' | 'oak'
  DateFilter fDate = DateFilter.all;
  bool fFree = false;
  String? fGenre;

  // ---- explore
  String query = '';

  // ---- band membership
  List<String> myBands = [];
  String bandId = 'b1';

  // ---- profile edits (b1 only, mirroring the design demo)
  String? b1BioOverride;
  String linkIg = '@foghorndiet';
  String linkBc = 'foghorndiet.bandcamp.com';

  // ---- band create wizard
  int nbStep = 1;
  String nbName = '';
  final Set<String> nbGenres = {};
  String nbBio = '';
  final List<String> nbInvites = [];

  // ---- gig create form
  String gfName = '';
  String? gfDate;
  String gfTime = '8PM';
  String? gfVenueId;
  String gfPrice = 'FREE';
  Ticketing gfTix = Ticketing.rsvp;
  String gfCap = 'No cap';
  String gfExt = '';

  // ---- toast
  String toast = '';
  Timer? _toastTimer;

  @override
  void dispose() {
    _toastTimer?.cancel();
    unawaited(_authSubscription?.cancel());
    unawaited(_feedSubscription?.cancel());
    unawaited(_interactionsSubscription?.cancel());
    unawaited(_bandsSubscription?.cancel());
    super.dispose();
  }

  void _handleAuthChange(bool signedIn) {
    authed = signedIn;
    if (signedIn) {
      authStep = 2;
      unawaited(_ensureUser());
    } else {
      unawaited(_refreshConvexAuth());
    }
    notifyListeners();
  }

  Future<void> _refreshConvexAuth() async {
    final repo = repository;
    if (repo is ConvexRepository) await repo.refreshAuth();
  }

  Future<void> _ensureUser() async {
    try {
      // The websocket must carry the new identity before the mutation runs.
      await _refreshConvexAuth();
      await repository.ensureUser(name: auth.displayName);
    } catch (_) {
      say('Something broke — try again.');
    }
  }

  void _subscribeToFeed() {
    _feedSubscription = repository.feed().listen(
      (snapshot) {
        _allGigs = List<Gig>.of(snapshot.gigs);
        _venues = Map<String, Venue>.of(snapshot.venues);
        _bands = {
          for (final entry in snapshot.bands.entries)
            entry.key: entry.value.copyWith(
              upcoming: [
                for (final gig in snapshot.gigs)
                  if (gig.lineup.contains(entry.key)) gig.id,
              ],
            ),
        };
        _dataStatus = DataStatus.ready;
        dataError = null;
        notifyListeners();
      },
      onError: (Object error) {
        _dataStatus = DataStatus.error;
        dataError = '$error';
        notifyListeners();
      },
    );
  }

  void _cacheInteractions(Interactions interactions) {
    rsvps = Set<String>.of(interactions.rsvpGigIds);
    follows = Set<String>.of(interactions.followBandIds);
    saved = Set<String>.of(interactions.savedGigIds);
    attended = interactions.attendedCount;
    notifyListeners();
  }

  void _cacheMemberships(List<BandMembership> memberships) {
    myBands = [for (final membership in memberships) membership.band.id];
    for (final membership in memberships) {
      final band = membership.band;
      _bands[band.id] = band.copyWith(
        upcoming: _bands[band.id]?.upcoming ?? const [],
      );
    }
    notifyListeners();
  }

  // ========================= navigation =========================

  void go(Screen s, [String? param]) {
    _stack = [..._stack, ScreenEntry(s, param)];
    notifyListeners();
  }

  void back() {
    if (_stack.length > 1) {
      _stack = _stack.sublist(0, _stack.length - 1);
      notifyListeners();
    }
  }

  void resetTo(Screen s) {
    _stack = [ScreenEntry(s)];
    notifyListeners();
  }

  void openGig(String id) {
    if (current.screen == Screen.gig && current.param == id) return;
    go(Screen.gig, id);
  }

  void openBand(String id) => go(Screen.band, id);

  void openMyGigsTab() {
    if (authed) {
      resetTo(Screen.myGigs);
    } else {
      needAuth(const PendingAuth(PendingKind.myGigs));
    }
  }

  void say(String msg) {
    toast = msg;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      toast = '';
      notifyListeners();
    });
    notifyListeners();
  }

  // ========================= auth =========================

  void needAuth(PendingAuth p) {
    pending = p;
    authStep = 1;
    go(Screen.auth);
  }

  String get authTitle => switch (pending?.kind) {
    PendingKind.rsvp => 'Create an account to RSVP',
    PendingKind.follow => 'Create an account to follow bands',
    PendingKind.myGigs => 'Log in to see your gigs',
    PendingKind.band => 'Log in to run your band',
    null => 'Join the scene',
  };

  Future<void> login() async => await auth.signInDemo();

  Future<void> signOut() async {
    await auth.signOut();
    rsvps = {};
    follows = {};
    saved = {};
    attended = 0;
    authed = false;
    resetTo(Screen.home);
    say('Signed out.');
  }

  void toggleUserGenre(String g) {
    userGenres.contains(g) ? userGenres.remove(g) : userGenres.add(g);
    notifyListeners();
  }

  void finishAuth() {
    if (repository is ConvexRepository) {
      unawaited(
        repository.setGenres(userGenres.toList()).catchError((Object _) {
          say('Something broke — try again.');
        }),
      );
    }

    final p = pending;
    pending = null;
    switch (p?.kind) {
      case PendingKind.rsvp:
        back();
        toggleRsvp(p!.id!);
      case PendingKind.follow:
        back();
        toggleFollow(p!.id!);
      case PendingKind.myGigs:
        resetTo(Screen.myGigs);
        say('Welcome back, Sam.');
      case PendingKind.band:
        resetTo(Screen.bandDash);
      case null:
        back();
    }
  }

  // ========================= fan actions =========================

  void toggleRsvp(String id) {
    final wasOn = rsvps.contains(id);
    wasOn ? rsvps.remove(id) : rsvps.add(id);
    notifyListeners();
    say(wasOn ? 'RSVP removed.' : "You're on the list. QR is in My Gigs.");
    unawaited(
      repository.toggleRsvp(id).catchError((Object _) {
        wasOn ? rsvps.add(id) : rsvps.remove(id);
        say('Something broke — try again.');
        notifyListeners();
      }),
    );
  }

  void requestRsvp(String id) {
    if (authed) {
      toggleRsvp(id);
    } else {
      needAuth(PendingAuth(PendingKind.rsvp, id));
    }
  }

  void toggleFollow(String id) {
    final wasOn = follows.contains(id);
    wasOn ? follows.remove(id) : follows.add(id);
    notifyListeners();
    if (!wasOn) say('Following ${band(id)!.name}.');
    unawaited(
      repository.toggleFollow(id).catchError((Object _) {
        wasOn ? follows.add(id) : follows.remove(id);
        say('Something broke — try again.');
        notifyListeners();
      }),
    );
  }

  void requestFollow(String id) {
    if (authed) {
      toggleFollow(id);
    } else {
      needAuth(PendingAuth(PendingKind.follow, id));
    }
  }

  void toggleSave(String id) {
    final wasOn = saved.contains(id);
    wasOn ? saved.remove(id) : saved.add(id);
    notifyListeners();
    unawaited(
      repository.toggleSave(id).catchError((Object _) {
        wasOn ? saved.add(id) : saved.remove(id);
        say('Something broke — try again.');
        notifyListeners();
      }),
    );
  }

  // ========================= filters =========================

  void setMapMode(bool on) {
    mapMode = on;
    notifyListeners();
  }

  void setCity(String c) {
    city = c;
    say(
      c == 'oak'
          ? 'Showing gigs near Temescal.'
          : 'Showing gigs near the Mission.',
    );
  }

  void toggleDateFilter(DateFilter f) {
    fDate = fDate == f ? DateFilter.all : f;
    notifyListeners();
  }

  void toggleFree() {
    fFree = !fFree;
    notifyListeners();
  }

  void toggleGenre(String g) {
    fGenre = fGenre == g ? null : g;
    notifyListeners();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  // ========================= data access =========================

  List<Gig> get allGigs => _allGigs;

  Gig? gig(String id) {
    for (final g in allGigs) {
      if (g.id == id) return g;
    }
    return null;
  }

  Band? band(String id) => _bands[id];

  Venue venue(String id) => _venues[id]!;

  FlyerStyle flyer(String key) =>
      DemoData.flyers[key] ?? DemoData.flyers['paper']!;

  String distanceOf(Venue v) => city == 'oak' ? v.distOak : v.distSF;

  List<Gig> get feed => allGigs.where((g) {
    if (fDate == DateFilter.tonight && g.when != GigWhen.tonight) return false;
    if (fDate == DateFilter.week && g.when == GigWhen.later) return false;
    if (fFree && !g.free) return false;
    if (fGenre != null && !g.genres.contains(fGenre)) return false;
    return true;
  }).toList();

  /// RSVP count shown to bands: base demo count plus this user's RSVP.
  int rsvpCount(Gig g) => g.going + (rsvps.contains(g.id) ? 1 : 0);

  List<VideoClip> videosFor(String bandId) {
    final cached = _videoCache[bandId];
    if (cached != null) return cached;

    if (_videoLoads.add(bandId)) {
      unawaited(_loadVideos(bandId));
    }
    return const <VideoClip>[];
  }

  String bioFor(String id) {
    if (id == 'b1' && b1BioOverride != null) return b1BioOverride!;
    return band(id)?.bio ?? '';
  }

  Future<void> _loadVideos(String bandId) async {
    try {
      _videoCache[bandId] = await repository.videosFor(bandId);
      notifyListeners();
    } catch (_) {
    } finally {
      _videoLoads.remove(bandId);
    }
  }

  void retry() {
    _dataStatus = DataStatus.connecting;
    dataError = null;
    notifyListeners();
    unawaited(_restartFeed());
  }

  Future<void> _restartFeed() async {
    await _feedSubscription?.cancel();
    _subscribeToFeed();
  }

  // ========================= band view =========================

  Band? get myBand => band(bandId);
  bool get bandIsNew => bandId.startsWith('nb');

  List<Gig> get myBandGigs =>
      allGigs.where((g) => g.lineup.contains(bandId)).toList();

  String get myBandNames => myBands
      .map((id) => band(id)?.name ?? '')
      .where((n) => n.isNotEmpty)
      .join(' · ');

  void switchToBand(String id) {
    bandId = id;
    resetTo(Screen.bandDash);
  }

  void toFanView() => resetTo(Screen.home);

  void setBandBio(String v) {
    if (bandId == 'b1') {
      b1BioOverride = v;
    }
    unawaited(
      repository
          .updateBandProfile(bandId: bandId, bio: v)
          .catchError((Object _) {}),
    );
    notifyListeners();
  }

  void setLinkIg(String v) {
    linkIg = v;
    unawaited(
      repository
          .updateBandProfile(bandId: bandId, linkIg: v)
          .catchError((Object _) {}),
    );
    notifyListeners();
  }

  void setLinkBc(String v) {
    linkBc = v;
    unawaited(
      repository
          .updateBandProfile(bandId: bandId, linkBc: v)
          .catchError((Object _) {}),
    );
    notifyListeners();
  }

  void pinVideo(int index) {
    final vids = videosFor('b1');
    if (index < 0 || index >= vids.length) return;
    unawaited(_pinVideo(vids[index].id));
  }

  void moveVideo(int index, int delta) {
    final vids = videosFor('b1');
    if (index < 0 || index >= vids.length) return;
    final direction = delta < 0 ? 'up' : 'down';
    unawaited(_moveVideo(vids[index].id, direction));
  }

  Future<void> _pinVideo(String videoId) async {
    try {
      await repository.pinVideo(videoId);
      _videoCache['b1'] = await repository.videosFor('b1');
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _moveVideo(String videoId, String direction) async {
    try {
      await repository.moveVideo(videoId, direction);
      _videoCache['b1'] = await repository.videosFor('b1');
      notifyListeners();
    } catch (_) {}
  }

  // ========================= band create =========================

  void startBandCreate() {
    nbStep = 1;
    nbName = '';
    nbGenres.clear();
    nbBio = '';
    nbInvites.clear();
    go(Screen.bandCreate);
  }

  void setNbName(String v) {
    nbName = v;
    notifyListeners();
  }

  void setNbBio(String v) {
    nbBio = v;
    notifyListeners();
  }

  void toggleNbGenre(String g) {
    nbGenres.contains(g) ? nbGenres.remove(g) : nbGenres.add(g);
    notifyListeners();
  }

  void nbNext() {
    if (nbName.trim().isEmpty) return;
    nbStep = 2;
    notifyListeners();
  }

  void addNbInvite(String raw) {
    final n = raw.trim();
    if (n.isEmpty) return;
    nbInvites.add(n.startsWith('@') ? n : '@$n');
    notifyListeners();
  }

  String get nbSlug {
    final s = (nbName.isEmpty ? 'your-band' : nbName).toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    return s.length > 20 ? s.substring(0, 20) : s;
  }

  Future<void> createBand() async {
    final name = nbName.trim();
    final createdBandId = await repository.createBand(
      name: name,
      genres: nbGenres.isEmpty ? const ['punk'] : nbGenres.toList(),
      bio: nbBio,
      inviteHandles: nbInvites,
    );
    bandId = createdBandId;
    resetTo(Screen.bandDash);
    say('$name created — you are admin.');
  }

  // ========================= gig create =========================

  void setGfName(String v) {
    gfName = v;
    notifyListeners();
  }

  void setGfDate(String? v) {
    gfDate = v;
    notifyListeners();
  }

  void setGfTime(String v) {
    gfTime = v;
    notifyListeners();
  }

  void setGfVenue(String v) {
    gfVenueId = v;
    notifyListeners();
  }

  void setGfPrice(String v) {
    gfPrice = v;
    notifyListeners();
  }

  void setGfTix(Ticketing t) {
    gfTix = t;
    notifyListeners();
  }

  void setGfCap(String v) {
    gfCap = v;
    notifyListeners();
  }

  void setGfExt(String v) {
    gfExt = v;
    notifyListeners();
  }

  bool get canPublishGig =>
      gfName.trim().isNotEmpty && gfDate != null && gfVenueId != null;

  Future<void> publishGig() async {
    if (!canPublishGig) {
      say('Name, date and venue required.');
      return;
    }

    await repository.publishGig(
      bandId: bandId,
      title: gfName.trim(),
      venueId: gfVenueId!,
      price: gfPrice == 'FREE' ? 0 : int.parse(gfPrice.substring(1)),
      startsAt: DateTime.now()
          .add(const Duration(days: 7))
          .millisecondsSinceEpoch,
      doorsTime: gfTime,
      ticketing: gfTix,
      externalUrl: gfExt.isEmpty ? null : gfExt,
      cap: gfCap,
    );
    gfName = '';
    gfDate = null;
    gfTime = '8PM';
    gfVenueId = null;
    gfPrice = 'FREE';
    gfTix = Ticketing.rsvp;
    gfCap = 'No cap';
    gfExt = '';
    _stack = const [ScreenEntry(Screen.gigMgr)];
    say('Gig published — it is live in the feed.');
  }
}
