import 'package:earplug/data/convex_repository.dart';
import 'package:earplug/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Gig.fromJson', () {
    test('derives tonight, this week, and later values from injected now', () {
      final now = DateTime(2026, 7, 28, 12);
      final tonight = Gig.fromJson(
        _gigJson(DateTime(2026, 7, 28, 20)),
        now: now,
      );
      final thisWeek = Gig.fromJson(
        _gigJson(DateTime(2026, 7, 31, 20)),
        now: now,
      );
      final later = Gig.fromJson(_gigJson(DateTime(2026, 8, 4, 20)), now: now);

      expect(tonight.dateShort, 'TUE JUL 28');
      expect(tonight.dateLine, 'TONIGHT · DOORS 7PM');
      expect(tonight.dateLine, startsWith('TONIGHT · DOORS '));
      expect(tonight.when, GigWhen.tonight);

      expect(thisWeek.dateShort, 'FRI JUL 31');
      expect(thisWeek.dateLine, 'FRI · DOORS 7PM');
      expect(thisWeek.when, GigWhen.week);

      expect(later.dateShort, 'TUE AUG 4');
      expect(later.dateLine, 'TUE · DOORS 7PM');
      expect(later.when, GigWhen.later);
    });

    test('relabels clock-derived fields after midnight without churn', () {
      final startsAt = DateTime(2026, 7, 28, 23, 30);
      final gig = Gig.fromJson(
        _gigJson(startsAt),
        now: DateTime(2026, 7, 28, 23),
      );
      expect(gig.when, GigWhen.tonight);
      expect(gig.dateLine, 'TONIGHT · DOORS 7PM');

      final nextDay = DateTime(2026, 7, 29, 0, 30);
      final relabeled = gig.relabeled(now: nextDay);
      expect(relabeled.when, GigWhen.week);
      expect(relabeled.dateLine, 'TUE · DOORS 7PM');
      expect(relabeled.dateLine, isNot(gig.dateLine));

      expect(relabeled.relabeled(now: nextDay), same(relabeled));
    });
  });

  group('Gig date derivations', () {
    final now = DateTime(2026, 7, 28, 12);

    test('classifies tonight by calendar day', () {
      final sameDay = DateTime(2026, 7, 28, 1).millisecondsSinceEpoch;
      expect(Gig.whenFor(sameDay, now: now), GigWhen.tonight);
      expect(
        Gig.dateLineFor(sameDay, '8PM / 9PM', now: now),
        'TONIGHT · DOORS 8PM',
      );
    });

    test('classifies dates just under seven days away as this week', () {
      final startsAt = now
          .add(const Duration(days: 7))
          .subtract(const Duration(milliseconds: 1))
          .millisecondsSinceEpoch;
      expect(Gig.whenFor(startsAt, now: now), GigWhen.week);
    });

    test('classifies the exact seven-day boundary as later', () {
      final startsAt = now.add(const Duration(days: 7)).millisecondsSinceEpoch;
      expect(Gig.whenFor(startsAt, now: now), GigWhen.later);
    });
  });

  test('parses a gigs:feed contract payload', () {
    final firstStartsAt = DateTime.now()
        .add(const Duration(days: 2))
        .millisecondsSinceEpoch;
    final secondStartsAt = DateTime.now()
        .add(const Duration(days: 9))
        .millisecondsSinceEpoch;
    final nextStartsAt = DateTime.now()
        .add(const Duration(days: 10))
        .millisecondsSinceEpoch;
    final fixture = <String, dynamic>{
      'gigs': [
        {
          '_id': 'g1',
          'title': 'Basement Blowout',
          'venueId': 'v1',
          'price': 0,
          'startsAt': firstStartsAt,
          'doorsTime': '8PM / 9PM',
          'flyKey': 'paper',
          'lineup': ['b1', 'b2'],
          'genres': ['punk'],
          'desc': 'A loud basement show.',
          'ticketing': 'rsvp',
          'externalUrl': null,
          'cap': 'No cap',
          'goingCount': 43,
          'createdByBand': null,
        },
        {
          '_id': 'g2',
          'title': 'Record Release',
          'venueId': 'v2',
          'price': 12,
          'startsAt': secondStartsAt,
          'doorsTime': '7PM / 8PM',
          'flyKey': 'blue',
          'lineup': ['b2'],
          'genres': ['garage'],
          'desc': 'A release show.',
          'ticketing': 'external',
          'externalUrl': 'https://example.com/tickets',
          'cap': '200',
          'goingCount': 18,
          'createdByBand': 'b2',
        },
      ],
      'venues': [
        {
          '_id': 'v1',
          'name': 'The Foghorn Club',
          'area': 'Mission, SF',
          'addr': '2455 Harrison St, San Francisco',
          'lat': 37.7524,
          'lng': -122.4180,
        },
        {
          '_id': 'v2',
          'name': 'Nightcrawler Records',
          'area': 'Temescal, Oakland',
          'addr': '486 40th St, Oakland',
          'lat': 37.8180,
          'lng': -122.2690,
        },
      ],
      'bands': [
        {
          '_id': 'b1',
          'name': 'Foghorn Diet',
          'genres': ['garage', 'surf punk'],
          'area': 'Mission, SF',
          'colorHex': '#7B8FFF',
          'initials': 'FD',
          'followerCount': 486,
          'bio': 'Reverb-soaked garage punk.',
          'linkIg': '@foghorndiet',
          'linkBc': 'foghorndiet.bandcamp.com',
          'pastShows': [
            {'title': 'Casa Quake', 'meta': 'JUL 12'},
          ],
        },
        {
          '_id': 'b2',
          'name': 'Pigeon Court',
          'genres': ['post-punk'],
          'area': 'Temescal, Oakland',
          'colorHex': '#B9C4FF',
          'initials': 'PC',
          'followerCount': 1214,
          'bio': 'Wiry post-punk.',
          'linkIg': null,
          'linkBc': null,
          'pastShows': <Map<String, dynamic>>[],
        },
      ],
      'nextStartsAt': nextStartsAt,
    };

    final snapshot = parseFeedSnapshot(fixture);

    expect(snapshot.gigs.map((gig) => gig.id), ['g1', 'g2']);
    expect(snapshot.venues['v2']!.name, 'Nightcrawler Records');
    expect(snapshot.bands['b1']!.past.single.meta, 'JUL 12');
    expect(snapshot.gigs.first.dateShort, Gig.dateShortFor(firstStartsAt));
    expect(
      snapshot.gigs.first.startsAt,
      DateTime.fromMillisecondsSinceEpoch(firstStartsAt),
    );
    expect(
      snapshot.gigs.first.dateLine,
      Gig.dateLineFor(firstStartsAt, '8PM / 9PM'),
    );
    expect(snapshot.gigs.first.when, Gig.whenFor(firstStartsAt));
    expect(snapshot.gigs.last.tix, Ticketing.external);
    expect(
      snapshot.nextStartsAt,
      DateTime.fromMillisecondsSinceEpoch(nextStartsAt),
    );
  });

  group('Band.fromJson', () {
    test('parses a slim band summary with omitted profile details', () {
      final json = <String, dynamic>{
        '_id': 'band-summary',
        'slug': 'the-night-shifts',
        'name': 'The Night Shifts',
        'genres': ['post-punk', 'garage'],
        'area': 'Oakland',
        'colorHex': '#1435F0',
        'initials': 'NS',
        'followerCount': 218,
        'avatarUrl': 'https://example.com/night-shifts-avatar.jpg',
        'profileComplete': true,
        'discoveryProfileReady': true,
      };

      final band = Band.fromJson(json);

      expect(band.id, 'band-summary');
      expect(band.slug, 'the-night-shifts');
      expect(band.name, 'The Night Shifts');
      expect(band.genres, ['post-punk', 'garage']);
      expect(band.area, 'Oakland');
      expect(band.color.toARGB32(), 0xFF1435F0);
      expect(band.initials, 'NS');
      expect(band.followers, 218);
      expect(band.avatarUrl, 'https://example.com/night-shifts-avatar.jpg');
      expect(band.profileComplete, isTrue);
      expect(band.discoveryProfileReady, isTrue);
      expect(band.isSummary, isTrue);
      expect(band.bio, '');
      expect(band.past, isEmpty);
      expect(band.linkIg, isNull);
      expect(band.linkBc, isNull);
      expect(band.linkYt, isNull);
      expect(band.credits, isNull);
      expect(band.bannerUrl, isNull);
      expect(band.heroUrl, isNull);
      expect(band.copyWith().isSummary, isTrue);
      expect(band.copyWith(isSummary: false).isSummary, isFalse);

      final withExplicitEmptyBio = Band.fromJson({...json, 'bio': ''});
      expect(withExplicitEmptyBio.isSummary, isFalse);
    });
  });

  group('UserProfile fan onboarding', () {
    test('parses enrolled fan state', () {
      final profile = UserProfile.fromJson({
        'name': 'Sam Reyes',
        'email': 'sam@example.com',
        'genres': <String>['punk'],
        'attendedCount': 2,
        'createdAt': 1234,
        'fanOnboarding': <String, Object?>{
          'preferredCity': 'oak',
          'genreChoice': 'selected',
          'collapsed': true,
        },
      });

      expect(profile.fanOnboarding?.preferredCity, FanCity.oak);
      expect(profile.fanOnboarding?.genreChoice, FanGenreChoice.selected);
      expect(profile.fanOnboarding?.collapsed, isTrue);
    });

    test('keeps legacy or unenrolled profiles unenrolled', () {
      Map<String, Object?> legacyProfile({Object? fanOnboarding}) => {
        'name': 'Legacy Fan',
        'email': 'legacy@example.com',
        'genres': <String>[],
        'attendedCount': 0,
        'createdAt': 1234,
        'fanOnboarding': ?fanOnboarding,
      };

      expect(UserProfile.fromJson(legacyProfile()).fanOnboarding, isNull);
      expect(
        UserProfile.fromJson({
          ...legacyProfile(),
          'fanOnboarding': null,
        }).fanOnboarding,
        isNull,
      );
    });

    test('uses privacy-safe defaults for existing user payloads', () {
      final profile = UserProfile.fromJson({
        'name': 'Legacy Fan',
        'email': 'legacy@example.com',
        'genres': <String>[],
        'attendedCount': 0,
        'createdAt': 1234,
      });

      expect(profile.avatarUrl, isNull);
      expect(profile.bio, isNull);
      expect(profile.homeLocation, isNull);
      expect(profile.locationPersonalizationEnabled, isFalse);
      expect(profile.followedBandUpdatesEnabled, isTrue);
      expect(profile.profileTutorialAvailable, isFalse);
      expect(profile.profileTutorialCompleted, isFalse);
    });

    test('parses editable identity and preference fields', () {
      final profile = UserProfile.fromJson({
        'name': 'Sam Reyes',
        'email': 'sam@example.com',
        'genres': <String>['punk', 'noise'],
        'attendedCount': 2,
        'createdAt': 1234,
        'avatarUrl': 'https://example.com/avatar.jpg',
        'bio': 'Always by the speakers.',
        'homeLocation': 'berkeley',
        'locationPersonalizationEnabled': true,
        'followedBandUpdatesEnabled': false,
        'profileTutorialCompleted': true,
      });

      expect(profile.avatarUrl, 'https://example.com/avatar.jpg');
      expect(profile.bio, 'Always by the speakers.');
      expect(profile.homeLocation, FanCity.berkeley);
      expect(profile.locationPersonalizationEnabled, isTrue);
      expect(profile.followedBandUpdatesEnabled, isFalse);
      expect(profile.profileTutorialAvailable, isTrue);
      expect(profile.profileTutorialCompleted, isTrue);
    });
  });

  group('fan home location search', () {
    test('matches city names and common region formats case-insensitively', () {
      expect(fanCityFromLocationInput('berkeley'), FanCity.berkeley);
      expect(fanCityFromLocationInput('BERKELEY, CA'), FanCity.berkeley);
      expect(
        fanCityFromLocationInput('San Mateo, California'),
        FanCity.sanMateo,
      );
      expect(fanCityFromLocationInput('sf'), FanCity.sf);
      expect(fanCityFromLocationInput('unknown'), isNull);
    });

    test('suggests only supported locations', () {
      expect(fanCitySuggestions('san').toList(), [
        FanCity.sf,
        FanCity.sanMateo,
        FanCity.sanJose,
        FanCity.sanRafael,
      ]);
      expect(fanCitySuggestions('los angeles'), isEmpty);
    });
  });

  test('fan history parses the enriched RSVP-only wire shape', () {
    final item = FanHistoryItem.fromJson({
      'gigId': 'gig-1',
      'title': 'Noise Night',
      'startsAt': 1774137600000,
      'venueName': 'Peralta Hall',
      'bandNames': <String>['Static Bloom', 'Court Date'],
      'flyKey': 'blue',
      'flyerUrl': null,
      'status': 'rsvped',
    });

    expect(item.gigId, 'gig-1');
    expect(item.venueName, 'Peralta Hall');
    expect(item.bandNames, ['Static Bloom', 'Court Date']);
    expect(item.flyerUrl, isNull);
    expect(item.status, FanHistoryStatus.rsvped);
  });
}

Map<String, dynamic> _gigJson(DateTime startsAt) => <String, dynamic>{
  '_id': 'gig-1',
  'slug': 'night-shifts-at-the-foghorn',
  'title': 'Night Shifts at The Foghorn',
  'venueId': 'venue-1',
  'price': 18,
  'startsAt': startsAt.millisecondsSinceEpoch,
  'doorsAt': startsAt.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
  'doorsTime': '7PM / 8PM',
  'flyKey': 'paper',
  'lineup': ['band-1', 'band-2'],
  'performers': [
    {'name': 'The Night Shifts', 'role': 'headliner', 'bandId': 'band-1'},
    {'name': 'Touring Friends', 'role': 'support', 'bandId': null},
  ],
  'goingCount': 37,
  'genres': ['post-punk', 'garage'],
  'desc': 'A loud night of Bay Area post-punk.',
  'ticketing': 'external',
  'externalUrl': 'https://example.com/tickets',
  'flyerUrl': 'https://example.com/flyers/gig-1.jpg',
  'cap': '250',
  'ageRequirement': '21Plus',
  'lifecycle': 'published',
  'createdByBand': 'band-1',
  'discoveryListingReady': true,
};
