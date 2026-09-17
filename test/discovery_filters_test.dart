import 'package:earplug/app_state.dart';
import 'package:earplug/demo_data.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';

import 'support/discovery_app.dart';

void main() {
  group('discovery filters', () {
    test(
      'starts on Map and combines multi-genre filters with OR semantics',
      () async {
        final app = await discoveryApp();

        expect(app.mapMode, isTrue);
        app.toggleGenre('hardcore');
        app.toggleGenre('surf');

        expect(app.feed.map((gig) => gig.id), ['g2', 'g1', 'g4']);
        app.toggleFree();
        expect(app.feed.map((gig) => gig.id), ['g1']);
      },
    );

    test('homeFeed ignores genres while feed applies them', () async {
      final app = await discoveryApp();

      app.toggleGenre('hardcore');
      app.toggleGenre('surf');

      expect(app.feed.map((gig) => gig.id), ['g2', 'g1', 'g4']);
      expect(app.homeFeed.length, app.allGigs.length);
    });

    test('homeFeed keeps its instance across genre changes only', () async {
      final app = await discoveryApp();

      final before = app.homeFeed;
      app.toggleGenre('hardcore');
      expect(app.homeFeed, same(before));

      app.toggleFree();
      expect(app.homeFeed, isNot(same(before)));
    });

    test('homeFeed applies date, price and distance filters', () async {
      final app = await discoveryApp();
      final selected = DemoData.gigs[1].startsAt;

      app.setDateRange(DateTimeRange(start: selected, end: selected));
      expect(app.homeFeed.map((gig) => gig.id), ['g2']);

      app.clearDateFilter();
      app.setPriceFilter(PriceFilter.free);
      expect(app.homeFeed.every((gig) => gig.free), isTrue);

      app.setPriceFilter(PriceFilter.any);
      app.useCurrentPosition(DemoData.venues['v1']!.point);
      app.setDistanceFilter(1);
      expect(
        app.homeFeed.every(
          (gig) => app.distanceMilesFromCurrent(app.venue(gig.venueId))! <= 1,
        ),
        isTrue,
      );
    });

    test('custom date ranges include the whole selected end date', () async {
      final app = await discoveryApp();
      final selected = DemoData.gigs[1].startsAt;

      app.setDateRange(DateTimeRange(start: selected, end: selected));

      expect(app.fDate, DateFilter.custom);
      expect(app.feed.map((gig) => gig.id), ['g2']);
    });

    test('custom dates stop before a partially loaded calendar day', () async {
      final latest = DemoData.gigs
          .map((gig) => gig.startsAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final app = await discoveryApp(
        nextFeedStartsAt: latest.add(const Duration(hours: 1)),
      );
      final expectedLast = DateTime(latest.year, latest.month, latest.day - 1);

      expect(app.lastSelectableDiscoveryDate, expectedLast);

      app.setDateRange(DateTimeRange(start: latest, end: latest));
      expect(
        app.fDateRange,
        DateTimeRange(start: expectedLast, end: expectedLast),
      );
    });

    test('custom dates include a fully loaded final calendar day', () async {
      final latest = DemoData.gigs
          .map((gig) => gig.startsAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final app = await discoveryApp(
        nextFeedStartsAt: DateTime(latest.year, latest.month, latest.day + 1),
      );

      expect(
        app.lastSelectableDiscoveryDate,
        DateTime(latest.year, latest.month, latest.day),
      );
    });

    test('custom dates allow today for an exhaustive empty feed', () async {
      final app = await discoveryApp(feedGigs: const []);

      expect(app.canSelectCustomDate, isTrue);
      expect(app.lastSelectableDiscoveryDate, app.firstSelectableDiscoveryDate);
    });

    test('custom dates disable when today is only partially loaded', () async {
      final todayGig = DemoData.gigs.first;
      final app = await discoveryApp(
        feedGigs: [todayGig],
        nextFeedStartsAt: todayGig.startsAt.add(const Duration(hours: 1)),
      );

      expect(app.canSelectCustomDate, isFalse);
      app.setDateRange(
        DateTimeRange(start: todayGig.startsAt, end: todayGig.startsAt),
      );
      expect(app.fDate, DateFilter.all);
      expect(app.fDateRange, isNull);
    });

    test('all advanced filters combine in one result set', () async {
      final venue = DemoData.venues['v1']!;
      final show = DemoData.gigs[1];
      final app = await discoveryApp();
      app.useCurrentPosition(venue.point);
      app.setDateRange(DateTimeRange(start: show.startsAt, end: show.startsAt));
      app.toggleGenre('surf');
      app.setPriceFilter(PriceFilter.paid);
      app.setDistanceFilter(1);

      expect(app.feed.map((gig) => gig.id), ['g2']);
    });

    test('widened ranges stay within the date picker horizon', () async {
      final app = await discoveryApp();
      final lastDate = app.lastSelectableDiscoveryDate;
      app.setDateRange(
        DateTimeRange(
          start: DateTime(lastDate.year, lastDate.month, lastDate.day - 2),
          end: lastDate,
        ),
      );

      app.widenDateFilter();

      expect(app.fDateRange!.end, lastDate);
      expect(
        app.fDateRange!.start.isBefore(app.firstSelectableDiscoveryDate),
        isFalse,
      );
    });

    test(
      'clear all preserves location and the intentional view switch',
      () async {
        final venue = DemoData.venues['v1']!;
        final app = await discoveryApp();
        app.useCurrentPosition(venue.point);
        app.setMapMode(false);
        app.toggleDateFilter(DateFilter.tonight);
        app.toggleGenre('punk');
        app.setPriceFilter(PriceFilter.paid);
        app.setDistanceFilter(5);

        app.clearDiscoveryFilters();

        expect(app.filters.activeCount, 0);
        expect(app.discoveryLocation, DiscoveryLocation.current);
        expect(app.currentPosition, venue.point);
        expect(app.mapMode, isFalse);
      },
    );
  });
}
