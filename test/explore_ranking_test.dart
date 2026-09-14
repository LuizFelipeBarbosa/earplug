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
  FanCity? city,
  bool signedIn = true,
  String seed = 'seed',
  DateTime? now,
}) => ExploreSignals(
      userGenres: userGenres,
      followedBandIds: followed,
      savedGigIds: const {},
      rsvpGigIds: const {},
      homeCity: city,
      signedIn: signedIn,
      seed: seed,
      now: now ?? _now,
    );

Venue _venue(String id, {String area = 'Oakland', String? city, int? capacity, VenueType? type}) =>
    Venue(id: id, name: id, area: area, city: city, addr: '', point: const LatLng(0, 0), capacityPublic: capacity, venueType: type);

Gig _gig(String id, DateTime at, {GigWhen when = GigWhen.week, String venueId = 'v1', List<String> genres = const ['punk'], List<String> lineup = const [], int price = 10, DateTime? doorsAt}) =>
    gigFixture(id: id, startsAt: at, when: when, venueId: venueId, genres: genres, lineup: lineup, price: price, doorsAt: doorsAt);

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
}
