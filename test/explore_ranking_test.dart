import 'package:earplug/date_names.dart';
import 'package:earplug/explore_ranking.dart';
import 'package:earplug/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'support/fixtures.dart';

final _now = DateTime(2026, 9, 14, 20);

ExploreSignals _signals({
  Set<String> userGenres = const {},
  Set<String> followed = const {},
  Set<String> saved = const {},
  Set<String> friends = const {},
  Set<String> boosted = const {},
  FanCity? city,
  bool signedIn = true,
  String seed = 'seed',
  DateTime? now,
}) => ExploreSignals(
      userGenres: userGenres,
      followedBandIds: followed,
      savedGigIds: saved,
      rsvpGigIds: const {},
      homeCity: city,
      signedIn: signedIn,
      seed: seed,
      now: now ?? _now,
      friendGigIds: friends,
      boostedGigIds: boosted,
    );

Venue _venue(String id, {String area = 'Oakland', String? city, int? capacity, VenueType? type}) =>
    Venue(id: id, name: id, area: area, city: city, addr: '', point: const LatLng(0, 0), capacityPublic: capacity, venueType: type);

Gig _gig(String id, DateTime at, {String? title, GigWhen when = GigWhen.week, String venueId = 'v1', List<String> genres = const ['punk'], List<String> lineup = const [], int price = 10, DateTime? doorsAt}) =>
    gigFixture(id: id, title: title, startsAt: at, when: when, venueId: venueId, genres: genres, lineup: lineup, price: price, doorsAt: doorsAt);

void main() {
  test('recommends unfollowed bands sharing user genres ahead of others', () {
    final bands = {'a': bandFixture(id: 'a', genres: ['punk']), 'b': bandFixture(id: 'b', genres: ['noise'])};
    expect(rankRecommendedBands(bands: bands, feed: const [], signals: _signals(userGenres: {'punk'})).first, 'a');
  });

  test('a band with a show inside 7 days outranks one without', () {
    final gig = _gig('g', _now.add(const Duration(days: 3)), lineup: ['a']);
    final bands = {'a': bandFixture(id: 'a').copyWith(upcoming: ['g']), 'b': bandFixture(id: 'b')};
    expect(rankRecommendedBands(bands: bands, feed: [gig], signals: _signals()), ['a', 'b']);
  });

  test('discoveryProfileReady and avatar break ties before followers', () {
    final bands = {
      'ready': bandFixture(id: 'ready', followers: 1, discoveryProfileReady: true).copyWith(avatarUrl: 'a'),
      'plain': bandFixture(id: 'plain', followers: 99),
    };
    expect(rankRecommendedBands(bands: bands, feed: const [], signals: _signals()).first, 'ready');
  });

  test('signed-out signals degrade to upcoming plus followers', () {
    final bands = {'soon': bandFixture(id: 'soon', followers: 1).copyWith(upcoming: ['g']), 'popular': bandFixture(id: 'popular', followers: 20)};
    expect(rankRecommendedBands(bands: bands, feed: [_gig('g', _now.add(const Duration(days: 1)), lineup: ['soon'])], signals: _signals(signedIn: false)), ['soon', 'popular']);
  });

  test('adjacent recommendations avoid the same first genre when possible', () {
    final bands = {
      'a': bandFixture(id: 'a', genres: ['punk'], followers: 5),
      'b': bandFixture(id: 'b', genres: ['punk'], followers: 4),
      'c': bandFixture(id: 'c', genres: ['noise'], followers: 3),
    };
    final ids = rankRecommendedBands(bands: bands, feed: const [], signals: _signals());
    expect(ids.take(2), ['a', 'c']);
  });

  test('genre-night collections appear only for user genres with >= 2 matching gigs', () {
    final feed = [_gig('1', _now, genres: ['punk']), _gig('2', _now, genres: ['punk']), _gig('3', _now, genres: ['noise'])];
    final keys = buildCollections(feed: feed, venue: _venue, bands: const {}, signals: _signals(userGenres: {'punk', 'noise'})).map((c) => c.key);
    expect(keys, contains('genre:punk'));
    expect(keys, isNot(contains('genre:noise')));
  });

  test('trending genres fill in when the user has no genres', () {
    final feed = [_gig('1', _now, genres: ['punk']), _gig('2', _now, genres: ['punk']), _gig('3', _now, genres: ['noise']), _gig('4', _now, genres: ['noise'])];
    final keys = buildCollections(feed: feed, venue: _venue, bands: const {}, signals: _signals()).map((c) => c.key).toSet();
    expect(keys, containsAll(['genre:punk', 'genre:noise']));
  });

  test('home-city collection matches venue.city and area alias', () {
    final feed = [_gig('1', _now, venueId: 'city'), _gig('2', _now, venueId: 'area')];
    Venue resolve(String id) => id == 'city' ? _venue(id, city: 'San Francisco') : _venue(id, area: 'SF');
    expect(buildCollections(feed: feed, venue: resolve, bands: const {}, signals: _signals(city: FanCity.sf)).map((c) => c.key), contains('city:sf'));
  });

  test('big/small rooms use capacityPublic then venueType as fallback', () {
    final feed = [_gig('1', _now, venueId: 'big'), _gig('2', _now, venueId: 'small'), _gig('3', _now, venueId: 'hall'), _gig('4', _now, venueId: 'bar')];
    Venue resolve(String id) => switch (id) { 'big' => _venue(id, capacity: 300), 'small' => _venue(id, capacity: 100), 'hall' => _venue(id, type: VenueType.hall), _ => _venue(id, type: VenueType.bar) };
    final cs = buildCollections(feed: feed, venue: resolve, bands: const {}, signals: _signals());
    expect(cs.map((c) => c.key), containsAll(['bigRooms', 'smallRooms']));
  });

  test('doors-open-soon uses doorsAt and respects the 4h window', () {
    final feed = [_gig('near', _now.add(const Duration(hours: 6)), doorsAt: _now.add(const Duration(hours: 2))), _gig('far', _now.add(const Duration(hours: 5)))];
    final keys = buildCollections(feed: feed, venue: _venue, bands: const {}, signals: _signals()).where((c) => c.key == 'doorsSoon').expand((c) => c.gigs).map((g) => g.id);
    expect(keys, ['near']);
  });

  test('collection order is stable for one seed and day and differs across seeds', () {
    final feed = [for (var i = 0; i < 12; i++) _gig('$i', _now.add(const Duration(days: 2)), genres: ['g${i ~/ 2}'])];
    final genres = {for (var i = 0; i < 6; i++) 'g$i'};
    final a = buildCollections(feed: feed, venue: _venue, bands: const {}, signals: _signals(seed: 'a', userGenres: genres)).map((c) => c.key).toList();
    final b = buildCollections(feed: feed, venue: _venue, bands: const {}, signals: _signals(seed: 'a', userGenres: genres)).map((c) => c.key).toList();
    final c = buildCollections(feed: feed, venue: _venue, bands: const {}, signals: _signals(seed: 'b', userGenres: genres)).map((c) => c.key).toList();
    expect(b, a);
    expect(c, isNot(a));
    expect(c.take(2), a.take(2));
  });

  test('order rotates when the day changes and top two stay fixed', () {
    final feed = [for (var i = 0; i < 12; i++) _gig('$i', _now.add(const Duration(days: 2)), genres: ['g${i ~/ 2}'])];
    final genres = {for (var i = 0; i < 6; i++) 'g$i'};
    final monday = buildCollections(feed: feed, venue: _venue, bands: const {}, signals: _signals(seed: 'a', userGenres: genres)).map((c) => c.key).toList();
    final tuesday = buildCollections(feed: feed, venue: _venue, bands: const {}, signals: _signals(seed: 'a', userGenres: genres, now: _now.add(const Duration(days: 1)))).map((c) => c.key).toList();
    expect(tuesday.take(2), monday.take(2));
    expect(tuesday, isNot(monday));
  });

  test('venuesWithShows drops unknown venue and orders by next show start time', () {
    final feed = [_gig('late', _now.add(const Duration(days: 2)), venueId: 'v2'), _gig('early', _now.add(const Duration(days: 1)), venueId: 'v1'), _gig('bad', _now, venueId: 'bad')];
    Venue resolve(String id) => id == 'bad' ? _venue('') : _venue(id);
    final result = venuesWithShows(feed: feed, venue: resolve);
    expect(result.map((v) => v.venue.id), ['v1', 'v2']);
  });

  test('weekendWindow picks coming Friday on Monday and current Friday on Saturday', () {
    final monday = weekendWindow(DateTime(2026, 9, 14, 20));
    final saturday = weekendWindow(DateTime(2026, 9, 19, 20));
    expect(monday.start, DateTime(2026, 9, 18));
    expect(saturday.start, DateTime(2026, 9, 18));
  });

  test('rankGenres puts attended before followed-band before profile genres', () {
    final signals = _signals(userGenres: {'profile'}, followed: {'b'});
    final chips = rankGenres(feed: const [], attendedGigGenres: const [['attended']], interactionGigs: const [], bands: {'b': bandFixture(id: 'b', genres: ['followed'])}, signals: signals);
    expect(chips.map((c) => c.genre).take(3), ['attended', 'followed', 'profile']);
  });

  test('signed-out rankGenres orders by feed count desc', () {
    final feed = [_gig('1', _now, genres: ['noise']), _gig('2', _now, genres: ['noise']), _gig('3', _now, genres: ['punk'])];
    expect(rankGenres(feed: feed, attendedGigGenres: const [], interactionGigs: const [], bands: const {}, signals: _signals(signedIn: false)).first.genre, 'noise');
  });

  test('buildGenrePage orders by day then relevance and matches lineup band genre', () {
    final early = _gig('early', _now.add(const Duration(days: 1)), lineup: ['band']);
    final later = _gig('later', _now.add(const Duration(days: 2)), genres: ['punk']);
    final page = buildGenrePage(genre: 'punk', feed: [later, early], bands: {'band': bandFixture(id: 'band', genres: ['punk'])}, directoryBandIds: const [], signals: _signals(), distanceMiles: (_) => 1);
    expect(page.week.map((g) => g.id), ['early', 'later']);
    expect(page.bandIds, contains('band'));
  });

  test('fnv1a is deterministic and non-negative', () {
    expect(fnv1a('hello'), fnv1a('hello'));
    expect(fnv1a('hello'), greaterThanOrEqualTo(0));
  });

  test('gigRelevance rewards fan signals, genres, timing, and free gigs', () {
    final gig = _gig('saved', _now.add(const Duration(days: 1)), genres: ['Post Punk'], lineup: ['band'], price: 0);
    final bands = {'band': bandFixture(id: 'band', genres: ['noise'])};
    final base = gigRelevance(gig: gig, bands: bands, signals: _signals(), distanceMiles: 0);
    expect(gigRelevance(gig: gig, bands: bands, signals: _signals(followed: {'band'}), distanceMiles: 0), greaterThan(base));
    expect(gigRelevance(gig: gig, bands: bands, signals: _signals(saved: {'saved'}), distanceMiles: 0), greaterThan(base));
    expect(gigRelevance(gig: gig, bands: bands, signals: _signals(friends: {'saved'}), distanceMiles: 0), greaterThan(base));
    expect(gigRelevance(gig: gig, bands: bands, signals: _signals(boosted: {'saved'}), distanceMiles: 0), greaterThan(base));
    expect(gigRelevance(gig: gig, bands: bands, signals: _signals(userGenres: {'punk'}), distanceMiles: 0), greaterThan(base));
    final inThree = gigRelevance(gig: gig, bands: bands, signals: _signals(), distanceMiles: 0);
    final inSeven = gigRelevance(gig: gig.copyWith(startsAt: _now.add(const Duration(days: 6))), bands: bands, signals: _signals(), distanceMiles: 0);
    final later = gigRelevance(gig: gig.copyWith(startsAt: _now.add(const Duration(days: 8))), bands: bands, signals: _signals(), distanceMiles: 0);
    expect(inThree, greaterThan(inSeven));
    expect(inSeven, greaterThan(later));
    expect(gigRelevance(gig: gig.copyWith(price: 10), bands: bands, signals: _signals(), distanceMiles: 0), lessThan(inThree));
  });

  test('gigRelevance distance penalty decreases and saturates', () {
    final gig = _gig('g', _now);
    int score(double miles) => gigRelevance(gig: gig, bands: const {}, signals: _signals(), distanceMiles: miles);
    expect(score(0), greaterThan(score(10)));
    expect(score(10), greaterThan(score(20)));
    expect(score(30), equals(score(100)));
  });

  test('rankForYou avoids featured venue-day collisions', () {
    final gigs = [
      _gig('a', _now.add(const Duration(days: 1)), venueId: 'v1', title: 'A'),
      _gig('b', _now.add(const Duration(days: 1)), venueId: 'v1', title: 'B'),
      _gig('c', _now.add(const Duration(days: 1)), venueId: 'v2', title: 'C'),
    ];
    final ranked = rankForYou(gigs: gigs, bands: const {}, signals: _signals(), distanceMiles: (_) => 0);
    expect(ranked.featured.map((gig) => gig.id), ['a', 'c']);
    expect(ranked.forYou.map((gig) => gig.id), ['b']);
  });

  test('rankForYou filters and orders for-you gigs', () {
    final gigs = [
      _gig('featured', _now.add(const Duration(days: 2))),
      _gig('before', _now.add(const Duration(days: 1))),
      _gig('later-low', _now.add(const Duration(days: 3)), genres: ['noise']),
      _gig('later-high', _now.add(const Duration(days: 3)), genres: ['punk']),
    ];
    final ranked = rankForYou(gigs: gigs, bands: const {}, signals: _signals(saved: {'featured', 'later-high'}), distanceMiles: (_) => 0, featuredCount: 1);
    expect(ranked.featured.map((gig) => gig.id), ['featured']);
    expect(ranked.forYou.map((gig) => gig.id), ['later-high', 'later-low']);
    expect(rankForYou(gigs: [gigs.first], bands: const {}, signals: _signals(), distanceMiles: (_) => 0).forYou, isEmpty);
  });

  test('discoverRail interleaves and drains the remaining side', () {
    final venues = [for (var i = 1; i <= 3; i++) VenueWithShows(venue: _venue('v$i'), gigs: [_gig('g$i', _now)])];
    expect(discoverRail(venues: venues, recommendedBandIds: ['b1']).map((e) => e.kind), [DiscoverKind.venue, DiscoverKind.band, DiscoverKind.venue, DiscoverKind.venue]);
    expect(discoverRail(venues: venues.take(1).toList(), recommendedBandIds: ['b1', 'b2', 'b3']).map((e) => e.kind), [DiscoverKind.venue, DiscoverKind.band, DiscoverKind.band, DiscoverKind.band]);
  });
}
