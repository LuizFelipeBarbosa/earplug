import 'dart:async';

import 'package:earplug/app_links.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/user_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/fixtures.dart';

void main() {
  group('calendarTemplateUrl', () {
    test('formats a local start as yyyyMMddTHHmmssZ in UTC', () {
      final startsAt = DateTime.utc(2026, 9, 16, 3, 4, 5).toLocal();
      final gig = gigFixture(id: 'calendar', startsAt: startsAt);

      expect(startsAt.isUtc, isFalse);
      final url = calendarTemplateUrl(gig: gig);
      expect(url.scheme, 'https');
      expect(url.host, 'calendar.google.com');
      expect(url.path, '/calendar/render');
      expect(url.queryParameters['action'], 'TEMPLATE');
      expect(url.queryParameters['dates'], '20260916T030405Z/20260916T060405Z');
    });

    test('defaults to exactly three hours even across a date boundary', () {
      final gig = gigFixture(
        id: 'calendar',
        startsAt: DateTime.utc(2026, 12, 31, 23, 30),
      );
      final dates = calendarTemplateUrl(
        gig: gig,
      ).queryParameters['dates']!.split('/').map(DateTime.parse).toList();

      expect(dates.first, gig.startsAt);
      expect(dates.last, DateTime.utc(2027, 1, 1, 2, 30));
      expect(dates.last.difference(dates.first), const Duration(hours: 3));
    });

    test('title, location and details round-trip special characters', () {
      final gig = gigFixture(
        id: 'calendar',
        title: 'Noise & Joy / 50% + Café?',
        createdByBand: 'private-band-id',
      ).copyWith(slug: 'noise-and-joy');
      const venue = Venue(
        id: 'venue',
        name: 'Café & Hall',
        area: 'Southside',
        addr: '2345 Channing Way, Suite #2 + Annex',
        point: LatLng(37.86, -122.26),
      );
      const presenter = 'Presented by A&B + Friends / 100%';
      final url = calendarTemplateUrl(
        gig: gig,
        venue: venue,
        presenterOrLineupLine: presenter,
      );
      final decoded = Uri.parse(url.toString()).queryParameters;

      expect(decoded['text'], gig.title);
      expect(decoded['location'], '${venue.name}, ${venue.exactAddress}');
      expect(
        decoded['details'],
        '$presenter\n${publicWebUrl('g/${gig.publicRef}')}',
      );
      expect(url.query, contains('%26'));
      expect(url.query, contains('%2B'));
      expect(url.query, contains('%25'));
      expect(url.query, contains('%0A'));
      expect(decoded['details'], isNot(contains(gig.createdByBand!)));
    });

    test(
      'omits the public link without a slug and includes it with a slug',
      () {
        final gig = gigFixture(id: 'legacy-id');
        const lineup = 'Lineup: A, B, C';
        for (final slug in ['', '   ', 'public-show']) {
          final show = gig.copyWith(slug: slug);
          final url = calendarTemplateUrl(
            gig: show,
            presenterOrLineupLine: lineup,
          );
          expect(
            url.queryParameters['details'],
            slug.trim().isEmpty
                ? lineup
                : '$lineup\n${publicWebUrl('g/${show.publicRef}')}',
          );
        }
      },
    );

    test('omits unavailable location and details', () {
      final url = calendarTemplateUrl(
        gig: gigFixture(id: 'draft', createdByBand: 'unresolved-band'),
      );
      expect(url.queryParameters, isNot(contains('location')));
      expect(url.queryParameters, isNot(contains('details')));
    });

    test('approximate venue includes its name without a private address', () {
      const venue = Venue(
        id: 'venue',
        name: 'Secret Hall',
        area: 'Southside',
        addr: 'Private address',
        point: LatLng(37.86, -122.26),
        supportsApproxLocation: true,
      );
      final url = calendarTemplateUrl(
        gig: gigFixture(id: 'gig'),
        venue: venue,
      );
      expect(url.queryParameters['location'], 'Secret Hall');
      expect(url.toString(), isNot(contains('Private')));
    });
  });

  testWidgets('clipboard success is announced only after the write resolves', (
    tester,
  ) async {
    final write = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') await write.future;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => copyForUser(
                context,
                'https://earplug.app/g/test',
                successMessage: 'Link copied.',
              ),
              child: const Text('COPY'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('COPY'));
    await tester.pump();
    expect(find.text('Link copied.'), findsNothing);
    write.complete();
    await tester.pump();
    expect(find.text('Link copied.'), findsOne);
  });

  testWidgets('clipboard failure presents a selectable-link fallback', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'blocked');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  copyForUser(context, 'https://earplug.app/static-bloom'),
              child: const Text('COPY'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('COPY'));
    await tester.pumpAndSettle();
    expect(find.text('COPY THIS LINK'), findsOne);
    expect(
      find.widgetWithText(SelectableText, 'https://earplug.app/static-bloom'),
      findsOne,
    );
  });

  testWidgets('external links validate, report blocking, and open valid URLs', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    var launches = 0;
    expect(
      await openExternalForUser(
        context,
        'javascript:alert(1)',
        launch: (_) async {
          launches++;
          return true;
        },
      ),
      isFalse,
    );
    await tester.pump();
    expect(find.text('That link is not a valid web address.'), findsOneWidget);
    expect(launches, 0);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    expect(
      await openExternalForUser(
        context,
        'https://example.com/tickets',
        launch: (uri) async {
          launches++;
          expect(uri.host, 'example.com');
          return false;
        },
      ),
      isFalse,
    );
    await tester.pump();
    expect(find.textContaining('blocked the link'), findsOneWidget);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    expect(
      await openExternalForUser(
        context,
        'https://example.com/tickets',
        launch: (_) async {
          launches++;
          return true;
        },
      ),
      isTrue,
    );
    expect(launches, 2);
  });
}
