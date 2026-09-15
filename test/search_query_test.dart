import 'package:earplug/models.dart';
import 'package:earplug/search_query.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/fixtures.dart';

void main() {
  final now = DateTime(2026, 9, 15, 20);

  List<SearchHit> rank(
    String query,
    Iterable<Gig> gigs, {
    DateTime? at,
    Map<String, Band> bands = const {},
    Map<String, Venue> venues = const {},
    double? Function(Gig)? distanceMiles,
    Set<String> friendGigIds = const {},
    Set<String> savedGigIds = const {},
  }) => rankSearchResults(
    parsed: parseSearchQuery(query),
    gigs: gigs,
    band: (id) => bands[id],
    venue: (id) => venues[id],
    now: at ?? now,
    distanceMiles: distanceMiles,
    friendGigIds: friendGigIds,
    savedGigIds: savedGigIds,
  );

  group('parseSearchQuery', () {
    test('extracts the worked free events example', () {
      const raw = 'free events tonight in oakland';
      final parsed = parseSearchQuery(raw);

      expect(parsed.raw, raw);
      expect(parsed.free, isTrue);
      expect(parsed.time, {SearchTimeTerm.tonight});
      expect(parsed.nearMe, isFalse);
      expect(parsed.terms, ['oakland']);
      expect(parsed.isEmpty, isFalse);
    });

    for (final phrase in ['this week', 'this-week', 'this   week', 'week']) {
      test('recognizes $phrase between remaining words', () {
        final parsed = parseSearchQuery('Punk $phrase Oakland');
        expect(parsed.time, {SearchTimeTerm.thisWeek});
        expect(parsed.terms, ['punk', 'oakland']);
      });
    }

    for (final phrase in ['near me', 'near   me', 'nearby', 'near']) {
      test('fully consumes $phrase', () {
        final parsed = parseSearchQuery('Punk $phrase Oakland');
        expect(parsed.nearMe, isTrue);
        expect(parsed.terms, ['punk', 'oakland']);
      });
    }

    test('is case insensitive and uses fixed label ordering', () {
      final parsed = parseSearchQuery(
        'Oakland NEAR ME Tomorrow FREE this-WEEK TODAY TONIGHT Punk tonight',
      );

      expect(parsed.time, SearchTimeTerm.values.toSet());
      expect(parsed.free, isTrue);
      expect(parsed.nearMe, isTrue);
      expect(parsed.terms, ['oakland', 'punk']);
      expect(parsed.labels, [
        'TONIGHT',
        'TODAY',
        'TOMORROW',
        'THIS WEEK',
        'FREE',
        'NEAR ME',
        'OAKLAND',
        'PUNK',
      ]);
    });

    test('removes standalone stop words throughout the input', () {
      final parsed = parseSearchQuery(
        'events Punk event shows in show the Oakland gigs gig at a me',
      );
      expect(parsed.terms, ['punk', 'oakland']);
      expect(parsed.nearMe, isFalse);
    });

    test('does not consume reserved words inside names', () {
      final parsed = parseSearchQuery('Freeman Tonightly Weekender Nearness');
      expect(parsed.terms, ['freeman', 'tonightly', 'weekender', 'nearness']);
      expect(parsed.time, isEmpty);
      expect(parsed.free, isFalse);
      expect(parsed.nearMe, isFalse);
    });

    test('handles punctuation and non-ASCII names', () {
      final parsed = parseSearchQuery('FREE, tonight! in São Paulo');
      expect(parsed.free, isTrue);
      expect(parsed.time, {SearchTimeTerm.tonight});
      expect(parsed.terms, ['são', 'paulo']);
    });

    test('empty and stop-word-only queries have no labels', () {
      for (final raw in ['', ' \t\n ', 'events in the shows']) {
        final parsed = parseSearchQuery(raw);
        expect(parsed.isEmpty, isTrue);
        expect(parsed.labels, isEmpty);
        expect(parsed.time, isEmpty);
        expect(parsed.free, isFalse);
        expect(parsed.nearMe, isFalse);
        expect(parsed.terms, isEmpty);
      }
      for (final raw in ['today', 'free', 'near', 'punk']) {
        expect(parseSearchQuery(raw).isEmpty, isFalse);
      }
    });
  });

  group('rankSearchResults hard filters', () {
    test('empty search does not even iterate gigs', () {
      final gigs = Iterable<Gig>.generate(
        1,
        (_) => throw StateError('gigs must not be read'),
      );
      expect(rank(' ', gigs), isEmpty);
    });

    test('tonight starts at now and ends before tomorrow', () {
      final gigs = [
        gigFixture(id: 'earlier', startsAt: DateTime(2026, 9, 15, 19)),
        gigFixture(id: 'now', startsAt: now),
        gigFixture(id: 'late', startsAt: DateTime(2026, 9, 15, 23, 59)),
        gigFixture(id: 'tomorrow', startsAt: DateTime(2026, 9, 16)),
      ];
      expect(rank('tonight', gigs).map((hit) => hit.gig.id), ['now', 'late']);
    });

    test('today includes all of today, even already-started gigs', () {
      final gigs = [
        gigFixture(id: 'yesterday', startsAt: DateTime(2026, 9, 14, 23, 59)),
        gigFixture(id: 'midnight', startsAt: DateTime(2026, 9, 15)),
        gigFixture(id: 'late', startsAt: DateTime(2026, 9, 15, 23, 59)),
        gigFixture(id: 'tomorrow', startsAt: DateTime(2026, 9, 16)),
      ];
      expect(rank('today', gigs).map((hit) => hit.gig.id), [
        'midnight',
        'late',
      ]);
    });

    test('tomorrow uses calendar midnight boundaries', () {
      final gigs = [
        gigFixture(id: 'today', startsAt: DateTime(2026, 9, 15, 23, 59)),
        gigFixture(id: 'midnight', startsAt: DateTime(2026, 9, 16)),
        gigFixture(id: 'late', startsAt: DateTime(2026, 9, 16, 23, 59)),
        gigFixture(id: 'thursday', startsAt: DateTime(2026, 9, 17)),
      ];
      expect(rank('tomorrow', gigs).map((hit) => hit.gig.id), [
        'midnight',
        'late',
      ]);
    });

    test('this week includes now through Sunday, excluding next Monday', () {
      final gigs = [
        gigFixture(id: 'earlier', startsAt: DateTime(2026, 9, 15, 19, 59)),
        gigFixture(id: 'now', startsAt: now),
        gigFixture(id: 'sunday', startsAt: DateTime(2026, 9, 20, 23, 59)),
        gigFixture(id: 'monday', startsAt: DateTime(2026, 9, 21)),
      ];
      expect(rank('this week', gigs).map((hit) => hit.gig.id), [
        'now',
        'sunday',
      ]);
    });

    test('this week on Sunday still includes the rest of Sunday', () {
      final sunday = DateTime(2026, 9, 20, 20);
      final gigs = [
        gigFixture(id: 'earlier', startsAt: DateTime(2026, 9, 20, 19, 59)),
        gigFixture(id: 'now', startsAt: sunday),
        gigFixture(id: 'late', startsAt: DateTime(2026, 9, 20, 23, 59, 59)),
        gigFixture(id: 'monday', startsAt: DateTime(2026, 9, 21)),
      ];
      expect(rank('week', gigs, at: sunday).map((hit) => hit.gig.id), [
        'now',
        'late',
      ]);
    });

    test('tomorrow rolls over the year using calendar dates', () {
      final gigs = [
        gigFixture(id: 'new-year', startsAt: DateTime(2027)),
        gigFixture(id: 'jan-2', startsAt: DateTime(2027, 1, 2)),
      ];
      expect(
        rank(
          'tomorrow',
          gigs,
          at: DateTime(2026, 12, 31, 20),
        ).map((hit) => hit.gig.id),
        ['new-year'],
      );
    });

    test('multiple time terms combine with OR', () {
      final gigs = [
        gigFixture(id: 'today', startsAt: now),
        gigFixture(id: 'tomorrow', startsAt: DateTime(2026, 9, 16, 20)),
        gigFixture(id: 'thursday', startsAt: DateTime(2026, 9, 17, 20)),
      ];
      expect(rank('tonight tomorrow', gigs).map((hit) => hit.gig.id), [
        'today',
        'tomorrow',
      ]);
    });

    test('free uses the gig price even when ticketing differs', () {
      final gigs = [
        gigFixture(id: 'free', startsAt: now, price: 0, tix: Ticketing.paid),
        gigFixture(id: 'paid', startsAt: now, price: 12, tix: Ticketing.rsvp),
      ];
      expect(rank('free', gigs).map((hit) => hit.gig.id), ['free']);
    });

    test('all text terms must match, and can match different fields', () {
      const venue = Venue(
        id: 'oakland',
        name: 'The Hall',
        area: 'East Bay',
        city: 'Oakland',
        addr: '',
        point: LatLng(0, 0),
      );
      final gigs = [
        gigFixture(
          id: 'both',
          title: 'Punkhouse',
          venueId: venue.id,
          startsAt: now,
        ),
        gigFixture(id: 'one', title: 'Punkhouse', startsAt: now),
      ];
      final hits = rank('punk oakland', gigs, venues: {venue.id: venue});
      expect(hits.map((hit) => hit.gig.id), ['both']);
      expect(hits.single.matched, ['title', 'location']);
    });

    test('four-hour cutoff is inclusive and today restores older gigs', () {
      final older = gigFixture(
        id: 'older',
        title: 'Punk',
        startsAt: now.subtract(const Duration(hours: 5)),
      );
      final gigs = [
        older,
        gigFixture(
          id: 'at-cutoff',
          title: 'Punk',
          startsAt: now.subtract(const Duration(hours: 4)),
        ),
      ];
      expect(rank('punk', gigs).map((hit) => hit.gig.id), ['at-cutoff']);
      expect(rank('today punk', [older]).single.gig.id, 'older');
      // Tonight's separate time filter still requires a start at or after now.
      expect(rank('tonight punk', [older]), isEmpty);
      expect(rank('today tonight punk', [older]).single.gig.id, 'older');
    });
  });

  group('rankSearchResults scoring and sorting', () {
    test('field weights rank title above band above venue above location', () {
      final performer = bandFixture(id: 'b1', name: 'PUNK', genres: []);
      const musicVenue = Venue(
        id: 'music',
        name: 'Punk',
        area: '',
        addr: '',
        point: LatLng(0, 0),
      );
      const location = Venue(
        id: 'location',
        name: 'The Hall',
        area: 'Punk',
        addr: '',
        point: LatLng(0, 0),
      );
      final hits = rank(
        'punk',
        [
          gigFixture(id: 'location', venueId: location.id, startsAt: now),
          gigFixture(id: 'venue', venueId: musicVenue.id, startsAt: now),
          gigFixture(id: 'band', lineup: [performer.id], startsAt: now),
          gigFixture(id: 'title', title: 'Punk', startsAt: now),
        ],
        bands: {performer.id: performer},
        venues: {musicVenue.id: musicVenue, location.id: location},
      );

      expect(hits.map((hit) => hit.gig.id), [
        'title',
        'band',
        'venue',
        'location',
      ]);
      expect(hits.map((hit) => hit.score), [7.0, 6.0, 5.0, 4.0]);
      expect(hits.map((hit) => hit.matched), [
        ['title'],
        ['band'],
        ['venue'],
        ['location'],
      ]);
    });

    test('neighborhood, city, and area all match location terms', () {
      const venue = Venue(
        id: 'v1',
        name: 'The Hall',
        neighborhood: 'Uptown',
        city: 'Oakland',
        area: 'East Bay',
        addr: '',
        point: LatLng(0, 0),
      );
      final hits = rank(
        'uptown oakland east',
        [gigFixture(id: 'gig', startsAt: now)],
        venues: {venue.id: venue},
      );
      expect(hits.single.matched, ['location']);
      expect(hits.single.score, 6.0);
    });

    test('gig and band genres match at lower weight without match labels', () {
      final performer = bandFixture(
        id: 'b1',
        name: 'The Trio',
        genres: ['Punk'],
      );
      final hits = rank(
        'punk',
        [
          gigFixture(id: 'gig-genre', genres: ['Punk'], startsAt: now),
          gigFixture(
            id: 'band-genre',
            lineup: ['missing', performer.id],
            startsAt: now,
          ),
          gigFixture(id: 'no-match', lineup: ['missing'], startsAt: now),
        ],
        bands: {performer.id: performer},
      );
      expect(hits.map((hit) => hit.gig.id), ['band-genre', 'gig-genre']);
      expect(hits.map((hit) => hit.score), [3.0, 3.0]);
      expect(hits.every((hit) => hit.matched.isEmpty), isTrue);
    });

    test('genre can satisfy one of multiple required terms', () {
      final hits = rank('punk trio', [
        gigFixture(
          id: 'both',
          title: 'The Trio',
          genres: ['Punk'],
          startsAt: now,
        ),
        gigFixture(id: 'one', title: 'The Trio', startsAt: now),
      ]);
      expect(hits.single.gig.id, 'both');
      expect(hits.single.score, 10.0);
      expect(hits.single.matched, ['title']);
    });

    test('each category and exact term contribute only once', () {
      final performer = bandFixture(
        id: 'b1',
        name: 'Punk Rock',
        genres: ['Punk'],
      );
      const venue = Venue(
        id: 'v1',
        name: 'Punk Rock',
        area: 'Punk Rock',
        city: 'Punk',
        addr: '',
        point: LatLng(0, 0),
      );
      final hits = rank(
        'punk rock',
        [
          gigFixture(
            id: 'all',
            title: 'Punk Rock Punk',
            lineup: ['b1', 'b1'],
            genres: ['Punk', 'Rock'],
            startsAt: now,
          ),
        ],
        bands: {'b1': performer},
        venues: {'v1': venue},
      );
      expect(hits.single.score, 22.0); // 6 + 5 + 4 + 3 + 2 + two exact terms.
      expect(hits.single.matched, ['title', 'band', 'venue', 'location']);
    });

    test('exact whole words beat substrings and word prefixes', () {
      final hits = rank('punk', [
        gigFixture(id: 'prefix', title: 'Punkhouse', startsAt: now),
        gigFixture(id: 'substring', title: 'Cyberpunk', startsAt: now),
        gigFixture(id: 'exact', title: 'PUNK!', startsAt: now),
      ]);
      expect(hits.map((hit) => hit.gig.id), ['exact', 'substring', 'prefix']);
      expect(hits.map((hit) => hit.score), [7.0, 6.0, 6.0]);
    });

    test('friend and saved bonuses accumulate', () {
      final hits = rank(
        'free',
        [
          for (final id in ['plain', 'saved', 'friend', 'both'])
            gigFixture(id: id, startsAt: now),
        ],
        friendGigIds: {'friend', 'both'},
        savedGigIds: {'saved', 'both'},
      );
      expect(hits.map((hit) => hit.gig.id), [
        'both',
        'friend',
        'saved',
        'plain',
      ]);
      expect(hits.map((hit) => hit.score), [2.5, 1.5, 1.0, 0.0]);
    });

    test('near me orders equal scores by distance, with unknown last', () {
      final distances = {'close': 1.0, 'far': 9.0};
      final hits = rank('near me', [
        gigFixture(id: 'unknown', startsAt: now),
        gigFixture(id: 'far', startsAt: now),
        gigFixture(id: 'close', startsAt: now.add(const Duration(hours: 1))),
      ], distanceMiles: (gig) => distances[gig.id]);
      expect(hits.map((hit) => hit.gig.id), ['close', 'far', 'unknown']);
    });

    test('score remains primary when near me is present', () {
      final hits = rank('near me punk', [
        gigFixture(id: 'close', title: 'Punkhouse', startsAt: now),
        gigFixture(id: 'far', title: 'Punk', startsAt: now),
      ], distanceMiles: (gig) => gig.id == 'close' ? 1 : 9);
      expect(hits.map((hit) => hit.gig.id), ['far', 'close']);
    });

    test('time and case-insensitive title settle remaining ties', () {
      final gigs = [
        gigFixture(
          id: 'late',
          title: 'First',
          startsAt: now.add(const Duration(hours: 1)),
        ),
        gigFixture(id: 'beta', title: 'Beta', startsAt: now),
        gigFixture(id: 'alpha', title: 'alpha', startsAt: now),
      ];
      expect(
        rank(
          'free',
          gigs,
          distanceMiles: (_) => throw StateError('not near'),
        ).map((hit) => hit.gig.id),
        ['alpha', 'beta', 'late'],
      );
      expect(rank('near', gigs).map((hit) => hit.gig.id), [
        'alpha',
        'beta',
        'late',
      ]);
      expect(
        rank('near', gigs, distanceMiles: (_) => 2).map((hit) => hit.gig.id),
        ['alpha', 'beta', 'late'],
      );
    });
  });

  test('searchMetaLine pluralizes and appends ordered labels', () {
    expect(searchMetaLine(parseSearchQuery(''), 1), '1 RESULT');
    expect(searchMetaLine(parseSearchQuery(''), 0), '0 RESULTS');
    expect(searchMetaLine(parseSearchQuery(''), 9), '9 RESULTS');
    expect(searchMetaLine(parseSearchQuery('punk'), 1), '1 RESULT · PUNK');
    expect(
      searchMetaLine(parseSearchQuery('tomorrow'), 0),
      '0 RESULTS · TOMORROW',
    );
    expect(
      searchMetaLine(parseSearchQuery('free tonight'), 9),
      '9 RESULTS · TONIGHT · FREE',
    );
  });
}
