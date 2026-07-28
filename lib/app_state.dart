import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import 'demo_data.dart';
import 'models.dart';

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

class PendingAuth {
  final PendingKind kind;
  final String? id;

  const PendingAuth(this.kind, [this.id]);
}

/// App-wide state, ported 1:1 from the design's demo logic. Auth is faked
/// (Clerk goes here later) and all data is in-memory (Convex goes here later).
class AppState extends ChangeNotifier {
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
  final Set<String> rsvps = {};
  final Set<String> follows = {};
  final Set<String> saved = {};
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
  List<String> myBands = ['b1'];
  String bandId = 'b1';
  Band? newBand; // the band created in-session, id 'nb'

  // ---- profile edits (b1 only, mirroring the design demo)
  String? b1BioOverride;
  List<VideoClip>? b1VidsOverride;
  String linkIg = '@foghorndiet';
  String linkBc = 'foghorndiet.bandcamp.com';

  // ---- published-in-session gigs
  final List<Gig> customGigs = [];

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
    super.dispose();
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
  // Fake auth for the design phase; swap for Clerk when wiring the backend.

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

  void login() {
    authed = true;
    authStep = 2;
    rsvps.add('g5');
    follows.addAll(['b2', 'b4']);
    saved.add('g6');
    attended = 12;
    notifyListeners();
  }

  void toggleUserGenre(String g) {
    userGenres.contains(g) ? userGenres.remove(g) : userGenres.add(g);
    notifyListeners();
  }

  void finishAuth() {
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
    final on = rsvps.contains(id);
    on ? rsvps.remove(id) : rsvps.add(id);
    say(on ? 'RSVP removed.' : "You're on the list. QR is in My Gigs.");
  }

  void requestRsvp(String id) {
    if (authed) {
      toggleRsvp(id);
    } else {
      needAuth(PendingAuth(PendingKind.rsvp, id));
    }
  }

  void toggleFollow(String id) {
    final on = follows.contains(id);
    on ? follows.remove(id) : follows.add(id);
    if (!on) say('Following ${band(id)!.name}.');
    notifyListeners();
  }

  void requestFollow(String id) {
    if (authed) {
      toggleFollow(id);
    } else {
      needAuth(PendingAuth(PendingKind.follow, id));
    }
  }

  // ========================= filters =========================

  void setMapMode(bool on) {
    mapMode = on;
    notifyListeners();
  }

  void setCity(String c) {
    city = c;
    say(c == 'oak' ? 'Showing gigs near Temescal.' : 'Showing gigs near the Mission.');
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

  List<Gig> get allGigs => [...DemoData.gigs, ...customGigs];

  Gig? gig(String id) {
    for (final g in allGigs) {
      if (g.id == id) return g;
    }
    return null;
  }

  Band? band(String id) => id == 'nb' ? newBand : DemoData.bands[id];

  Venue venue(String id) => DemoData.venues[id]!;

  FlyerStyle flyer(String key) => DemoData.flyers[key] ?? DemoData.flyers['paper']!;

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

  List<VideoClip> videosFor(String bandId) =>
      bandId == 'b1' ? (b1VidsOverride ?? DemoData.b1Videos) : DemoData.genericVideos;

  String bioFor(String id) {
    if (id == 'b1') return b1BioOverride ?? DemoData.bands['b1']!.bio;
    return band(id)?.bio ?? '';
  }

  // ========================= band view =========================

  Band? get myBand => band(bandId);
  bool get bandIsNew => bandId == 'nb';

  List<Gig> get myBandGigs =>
      allGigs.where((g) => g.lineup.contains(bandId)).toList();

  String get myBandNames =>
      myBands.map((id) => band(id)?.name ?? '').where((n) => n.isNotEmpty).join(' · ');

  void switchToBand(String id) {
    bandId = id;
    resetTo(Screen.bandDash);
  }

  void toFanView() => resetTo(Screen.home);

  void setBandBio(String v) {
    if (bandId == 'b1') {
      b1BioOverride = v;
    } else if (newBand != null) {
      newBand = newBand!.copyWith(bio: v);
    }
    notifyListeners();
  }

  void setLinkIg(String v) {
    linkIg = v;
    notifyListeners();
  }

  void setLinkBc(String v) {
    linkBc = v;
    notifyListeners();
  }

  void pinVideo(int index) {
    final vids = videosFor('b1');
    b1VidsOverride = [
      for (var i = 0; i < vids.length; i++) vids[i].copyWith(pinned: i == index),
    ];
    notifyListeners();
  }

  void moveVideo(int index, int delta) {
    final vids = [...videosFor('b1')];
    final j = index + delta;
    if (j < 0 || j >= vids.length) return;
    final tmp = vids[index];
    vids[index] = vids[j];
    vids[j] = tmp;
    b1VidsOverride = vids;
    notifyListeners();
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
    final s = (nbName.isEmpty ? 'your-band' : nbName)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return s.length > 20 ? s.substring(0, 20) : s;
  }

  void createBand() {
    final name = nbName.trim();
    newBand = Band(
      name: name,
      genres: nbGenres.isEmpty ? const ['punk'] : nbGenres.toList(),
      area: 'Mission, SF',
      color: const Color(0xFF8FE6C4),
      initials: name
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => w[0])
          .take(2)
          .join()
          .toUpperCase(),
      followers: 1 + nbInvites.length,
      bio: nbBio.isEmpty ? 'New band. No recordings yet. Come see us anyway.' : nbBio,
    );
    if (!myBands.contains('nb')) myBands = [...myBands, 'nb'];
    bandId = 'nb';
    _stack = const [ScreenEntry(Screen.bandDash)];
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

  void publishGig() {
    if (!canPublishGig) {
      say('Name, date and venue required.');
      return;
    }
    final date = gfDate!.toUpperCase();
    customGigs.add(Gig(
      id: 'gx${customGigs.length + 1}',
      title: gfName.trim(),
      venueId: gfVenueId!,
      price: gfPrice == 'FREE' ? 0 : int.parse(gfPrice.substring(1)),
      dateShort: date,
      dateLine: '$date · DOORS $gfTime',
      time: '$gfTime doors',
      when: GigWhen.later,
      flyKey: 'bluetype',
      lineup: [bandId],
      going: 0,
      genres: const ['punk'],
      desc: '${gfTix == Ticketing.external ? 'Tickets via external link. ' : 'RSVP in app. '}'
          'Listed by ${myBand?.name ?? ''}.',
      tix: gfTix,
      cap: gfCap,
    ));
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
