import 'package:earplug/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Gig.fromJson', () {
    test('parses a full payload consistently with or without injected now', () {
      final fixedNow = DateTime(2100, 7, 1, 12);
      final startsAt = DateTime(2100, 7, 28, 20);
      final json = _gigJson(startsAt);

      final withDefaultNow = Gig.fromJson(json);
      final withInjectedNow = Gig.fromJson(json, now: fixedNow);

      expect(withDefaultNow.id, withInjectedNow.id);
      expect(withDefaultNow.slug, withInjectedNow.slug);
      expect(withDefaultNow.title, withInjectedNow.title);
      expect(withDefaultNow.venueId, withInjectedNow.venueId);
      expect(withDefaultNow.price, withInjectedNow.price);
      expect(withDefaultNow.startsAt, withInjectedNow.startsAt);
      expect(withDefaultNow.doorsAt, withInjectedNow.doorsAt);
      expect(withDefaultNow.dateShort, withInjectedNow.dateShort);
      expect(withDefaultNow.dateLine, withInjectedNow.dateLine);
      expect(withDefaultNow.time, withInjectedNow.time);
      expect(withDefaultNow.when, withInjectedNow.when);
      expect(withDefaultNow.flyKey, withInjectedNow.flyKey);
      expect(withDefaultNow.lineup, withInjectedNow.lineup);
      expect(
        withDefaultNow.performers.map(
          (performer) => (
            performer.id,
            performer.kind,
            performer.name,
            performer.role,
            performer.bandId,
            performer.inviteUrl,
          ),
        ),
        withInjectedNow.performers.map(
          (performer) => (
            performer.id,
            performer.kind,
            performer.name,
            performer.role,
            performer.bandId,
            performer.inviteUrl,
          ),
        ),
      );
      expect(withDefaultNow.going, withInjectedNow.going);
      expect(withDefaultNow.genres, withInjectedNow.genres);
      expect(withDefaultNow.desc, withInjectedNow.desc);
      expect(withDefaultNow.tix, withInjectedNow.tix);
      expect(withDefaultNow.externalUrl, withInjectedNow.externalUrl);
      expect(withDefaultNow.flyerUrl, withInjectedNow.flyerUrl);
      expect(withDefaultNow.cap, withInjectedNow.cap);
      expect(withDefaultNow.ageRequirement, withInjectedNow.ageRequirement);
      expect(withDefaultNow.lifecycle, withInjectedNow.lifecycle);
      expect(withDefaultNow.createdByBand, withInjectedNow.createdByBand);
      expect(
        withDefaultNow.discoveryListingReady,
        withInjectedNow.discoveryListingReady,
      );

      expect(withInjectedNow.when, GigWhen.later);
      expect(
        withInjectedNow.dateLine,
        '${_weekdayNames[startsAt.weekday - 1]} · DOORS 7PM',
      );
      expect(withInjectedNow.time, '7PM / 8PM');
      expect(withInjectedNow.going, 37);
      expect(withInjectedNow.performers, hasLength(2));
      expect(withInjectedNow.performers.first.kind, GigPerformerKind.band);
      expect(withInjectedNow.performers.last.kind, GigPerformerKind.text);
    });

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

    test('defaults a missing going count to zero', () {
      final gig = Gig.fromJson(
        _gigJson(DateTime(2026, 7, 28, 20), includeGoingCount: false),
        now: DateTime(2026, 7, 28, 12),
      );

      expect(gig.going, 0);
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

    test('parses every field from a full band payload', () {
      final json = <String, dynamic>{
        '_id': 'band-full',
        'slug': 'foghorn-diet',
        'name': 'Foghorn Diet',
        'genres': ['garage', 'surf punk'],
        'area': 'Mission, SF',
        'colorHex': '#7B8FFF',
        'initials': 'FD',
        'followerCount': 486,
        'bio': 'Reverb-soaked garage punk from San Francisco.',
        'linkIg': '@foghorndiet',
        'linkBc': 'https://foghorndiet.bandcamp.com',
        'linkYt': 'https://youtube.com/@foghorndiet',
        'credits': 'Photo by Jules Rivera',
        'avatarUrl': 'https://example.com/foghorn-avatar.jpg',
        'bannerUrl': 'https://example.com/foghorn-banner.jpg',
        'heroUrl': 'https://example.com/foghorn-legacy.jpg',
        'profileComplete': true,
        'discoveryProfileReady': false,
        'pastShows': [
          {'title': 'Casa Quake', 'meta': 'JUL 12 · OAKLAND'},
          {'title': 'The Foghorn Club', 'meta': 'JUN 21 · SAN FRANCISCO'},
        ],
      };

      final band = Band.fromJson(json);

      expect(band.id, 'band-full');
      expect(band.slug, 'foghorn-diet');
      expect(band.name, 'Foghorn Diet');
      expect(band.genres, ['garage', 'surf punk']);
      expect(band.area, 'Mission, SF');
      expect(band.color.toARGB32(), 0xFF7B8FFF);
      expect(band.initials, 'FD');
      expect(band.followers, 486);
      expect(band.bio, 'Reverb-soaked garage punk from San Francisco.');
      expect(band.linkIg, '@foghorndiet');
      expect(band.linkBc, 'https://foghorndiet.bandcamp.com');
      expect(band.linkYt, 'https://youtube.com/@foghorndiet');
      expect(band.credits, 'Photo by Jules Rivera');
      expect(band.avatarUrl, 'https://example.com/foghorn-avatar.jpg');
      expect(band.bannerUrl, 'https://example.com/foghorn-banner.jpg');
      expect(band.heroUrl, 'https://example.com/foghorn-legacy.jpg');
      expect(band.profileComplete, isTrue);
      expect(band.discoveryProfileReady, isFalse);
      expect(band.isSummary, isFalse);
      expect(band.upcoming, isEmpty);
      expect(band.past, hasLength(2));
      expect(band.past.first.title, 'Casa Quake');
      expect(band.past.first.meta, 'JUL 12 · OAKLAND');
      expect(band.past.last.title, 'The Foghorn Club');
      expect(band.past.last.meta, 'JUN 21 · SAN FRANCISCO');
      expect(band.copyWith().isSummary, isFalse);
      expect(band.copyWith(isSummary: true).isSummary, isTrue);
    });
  });
}

Map<String, dynamic> _gigJson(
  DateTime startsAt, {
  bool includeGoingCount = true,
}) => <String, dynamic>{
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
  if (includeGoingCount) 'goingCount': 37,
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

const _weekdayNames = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
