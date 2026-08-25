import 'dart:ui';

import 'package:earplug/app_state.dart';
import 'package:earplug/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('discovery boost eligibility', () {
    test('includes both window boundaries and excludes either side', () {
      final startsAt = DateTime.utc(2026, 8, 25, 3);
      final gig = _gig(
        'eligible',
        startsAt: startsAt,
        creator: 'band',
        listingReady: true,
      );
      final bands = {'band': _band('band', discoveryReady: true)};

      Set<String> at(DateTime now) =>
          discoveryBoostedGigIds(gigs: [gig], bands: bands, now: now);

      final opensAt = startsAt.subtract(discoveryBoostLead);
      final closesAt = startsAt.add(discoveryBoostGrace);
      expect(at(opensAt.subtract(const Duration(milliseconds: 1))), isEmpty);
      expect(at(opensAt), {'eligible'});
      expect(at(closesAt), {'eligible'});
      expect(at(closesAt.add(const Duration(milliseconds: 1))), isEmpty);
    });

    test('allows only the earliest active qualifying show per band', () {
      final now = DateTime.utc(2026, 8, 24, 19);
      final early = _gig(
        'early',
        startsAt: now.add(const Duration(days: 1)),
        creator: 'band',
        listingReady: true,
      );
      final later = _gig(
        'later',
        startsAt: now.add(const Duration(days: 2)),
        creator: 'band',
        listingReady: true,
      );
      final other = _gig(
        'other',
        startsAt: now.add(const Duration(days: 2)),
        creator: 'other-band',
        listingReady: true,
      );

      expect(
        discoveryBoostedGigIds(
          gigs: [later, other, early],
          bands: {
            'band': _band('band', discoveryReady: true),
            'other-band': _band('other-band', discoveryReady: true),
          },
          now: now,
        ),
        {'early', 'other'},
      );
    });

    test('fails closed for incomplete profiles and listing projections', () {
      final now = DateTime.utc(2026, 8, 24, 19);
      expect(
        discoveryBoostedGigIds(
          gigs: [
            _gig(
              'stale',
              startsAt: now.add(const Duration(days: 1)),
              creator: 'ready-band',
              listingReady: false,
            ),
            _gig(
              'incomplete',
              startsAt: now.add(const Duration(days: 1)),
              creator: 'incomplete-band',
              listingReady: true,
            ),
          ],
          bands: {
            'ready-band': _band('ready-band', discoveryReady: true),
            'incomplete-band': _band('incomplete-band', discoveryReady: false),
          },
          now: now,
        ),
        isEmpty,
      );
    });
  });

  group('discovery peer ordering', () {
    test('boosts only within the same LA day and five-mile bucket', () {
      // 19:00 UTC is noon PDT, safely away from a calendar boundary.
      final day = DateTime.utc(2026, 8, 24, 19);
      final near = _gig('near', startsAt: day);
      final otherDay = _gig(
        'other-day',
        startsAt: day.add(const Duration(days: 1)),
      );
      final boosted = _gig(
        'boosted',
        startsAt: day.add(const Duration(hours: 1)),
      );
      final nextBucket = _gig(
        'next-bucket',
        startsAt: day.add(const Duration(hours: 2)),
      );
      final distances = {
        'near': 1.0,
        'other-day': 2.0,
        'boosted': 4.9,
        'next-bucket': 5.0,
      };

      final ordered = orderDiscoveryGigs(
        gigs: [near, otherDay, boosted, nextBucket],
        distanceMiles: (gig) => distances[gig.id]!,
        boostedGigIds: {'boosted', 'next-bucket'},
      );

      // The same-day/same-bucket members exchange only their occupied slots;
      // the other day remains at index 1 and the five-mile boundary does not
      // join the nearer bucket.
      expect(ordered.map((gig) => gig.id), [
        'boosted',
        'other-day',
        'near',
        'next-bucket',
      ]);
    });

    test('uses actual distance, start time, then stable input order', () {
      final day = DateTime.utc(2026, 8, 24, 19);
      final first = _gig('first', startsAt: day);
      final second = _gig('second', startsAt: day);
      final later = _gig('later', startsAt: day.add(const Duration(hours: 1)));
      final distances = {'first': 2.0, 'second': 2.0, 'later': 1.5};

      final ordered = orderDiscoveryGigs(
        gigs: [first, second, later],
        distanceMiles: (gig) => distances[gig.id]!,
        boostedGigIds: const {},
      );
      expect(ordered.map((gig) => gig.id), ['later', 'first', 'second']);
    });
  });

  test('public readiness fields parse and survive copy methods', () {
    final band = Band.fromJson({
      '_id': 'band',
      'name': 'Complete Band',
      'genres': ['punk'],
      'area': 'Oakland',
      'colorHex': '#7B8FFF',
      'initials': 'CB',
      'followerCount': 1,
      'bio': 'bio',
      'heroUrl': null,
      'linkIg': null,
      'linkBc': null,
      'linkYt': null,
      'credits': null,
      'pastShows': const <Object>[],
      'profileComplete': true,
      'discoveryProfileReady': true,
    });
    expect(band.profileComplete, isTrue);
    expect(band.discoveryProfileReady, isTrue);
    expect(band.copyWith(profileComplete: false).profileComplete, isFalse);

    final gig = _gig(
      'gig',
      startsAt: DateTime.utc(2026, 8, 24),
      creator: 'band',
      listingReady: true,
    );
    expect(gig.createdByBand, 'band');
    expect(gig.discoveryListingReady, isTrue);
    expect(
      gig.copyWith(discoveryListingReady: false).discoveryListingReady,
      isFalse,
    );

    final readiness = BandDiscoveryReadiness.fromJson({
      'profileComplete': true,
      'profileImageReady': true,
      'clipReady': true,
      'publishedShowReady': true,
      'venuePosterReady': false,
      'publishedRevisionCurrent': false,
      'relevantShow': null,
      'nextEligibleShow': null,
      'boostWindow': null,
    });
    expect(readiness.completedCount, 4);
  });
}

Band _band(String id, {required bool discoveryReady}) => Band(
  id: id,
  name: id,
  genres: const ['punk'],
  area: 'Oakland',
  color: const Color(0xFF7B8FFF),
  initials: 'BD',
  followers: 1,
  bio: 'bio',
  profileComplete: true,
  discoveryProfileReady: discoveryReady,
);

Gig _gig(
  String id, {
  required DateTime startsAt,
  String? creator,
  bool listingReady = false,
}) => Gig(
  id: id,
  title: id,
  venueId: id,
  price: 0,
  startsAt: startsAt,
  dateShort: 'MON AUG 24',
  dateLine: 'MON · DOORS 8PM',
  time: '8PM / 9PM',
  when: GigWhen.week,
  flyKey: 'xerox',
  lineup: creator == null ? const [] : [creator],
  going: 0,
  genres: const ['punk'],
  desc: '',
  tix: Ticketing.rsvp,
  createdByBand: creator,
  discoveryListingReady: listingReady,
);
