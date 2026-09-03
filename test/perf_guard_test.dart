import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/home.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_map.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:earplug/widgets/video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/async.dart';
import 'support/fake_video_player_platform.dart';
import 'support/fixtures.dart';
import 'support/harness.dart';

void main() {
  group('performance regression guards', () {
    testWidgets('navigation chrome does not use BackdropFilter', (
      tester,
    ) async {
      await pumpApp(
        tester,
        home: const Scaffold(bottomNavigationBar: FanTabBar()),
      );
      expect(find.byType(BackdropFilter), findsNothing);

      await pumpApp(
        tester,
        home: const Scaffold(bottomNavigationBar: BandTabBar()),
      );
      expect(find.byType(BackdropFilter), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildEpTheme(),
          home: Scaffold(
            body: StickyActionBar(
              secondaryLabel: 'Preview',
              onSecondary: () {},
              primaryLabel: 'Save changes',
              onPrimary: () {},
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    test(
      'AppState memoizes collections and rebuilds feed after filtering',
      () async {
        final auth = FakeAuthService();
        await auth.signInDemo();
        final app = AppState.demo(
          repository: DemoRepository(auth: auth),
          auth: auth,
        );
        addTearDown(app.dispose);
        await flushAsyncWork();

        final feed = app.feed;
        expect(identical(app.feed, app.feed), isTrue);
        expect(identical(app.venues, app.venues), isTrue);

        app.setPriceFilter(PriceFilter.free);
        expect(identical(app.feed, feed), isFalse);
      },
    );

    testWidgets(
      'raster EpMap renders no vector layer or style repository dependency',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildEpTheme(Brightness.light),
            home: const Scaffold(
              body: EpMap(
                tiles: EpMapTiles.raster,
                options: MapOptions(
                  initialCenter: LatLng(34.05, -118.24),
                  initialZoom: 12,
                ),
              ),
            ),
          ),
        );

        expect(find.byType(TileLayer), findsOne);
        expect(find.byType(vt.VectorTileLayer), findsNothing);

        await tester.pump();
        expect(find.byType(TileLayer), findsOne);
        expect(find.byType(vt.VectorTileLayer), findsNothing);
      },
    );

    testWidgets('Home list lazily builds a 60-gig feed', (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      await pumpApp(
        tester,
        auth: auth,
        repository: _BigFeedRepository(auth: auth),
        home: const Scaffold(body: HomeScreen()),
        beforePump: (app) => app.setMapMode(false),
      );

      expect(tester.widgetList(find.byType(FanEventCard)).length, lessThan(60));
    });

    group('video thumbnail', () {
      late VideoPlayerPlatform originalPlatform;
      late FakeVideoPlayerPlatform fakePlatform;

      setUp(() {
        originalPlatform = VideoPlayerPlatform.instance;
        fakePlatform = FakeVideoPlayerPlatform();
        VideoPlayerPlatform.instance = fakePlatform;
      });

      tearDown(() {
        VideoPlayerPlatform.instance = originalPlatform;
      });

      testWidgets(
        'legacyFrameEnabled false never creates a VideoPlayerController',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: SizedBox(
                width: 200,
                height: 100,
                child: BandVideoThumbnail(
                  media: videoMediaFixture(),
                  fallback: const ColoredBox(color: Colors.red),
                  legacyFrameEnabled: false,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(fakePlatform.calls, isNot(contains('create')));
        },
      );
    });
  });
}

class _BigFeedRepository extends DemoRepository {
  _BigFeedRepository({required super.auth});

  late final FeedSnapshot _snapshot = FeedSnapshot(
    gigs: List.generate(60, (index) {
      final source = DemoData.gigs.first;
      return Gig(
        id: 'big-$index',
        slug: 'big-$index',
        title: source.title,
        venueId: source.venueId,
        price: source.price,
        startsAt: source.startsAt,
        doorsAt: source.doorsAt,
        dateShort: source.dateShort,
        dateLine: source.dateLine,
        time: source.time,
        when: source.when,
        flyKey: source.flyKey,
        lineup: source.lineup,
        performers: source.performers,
        going: source.going,
        genres: source.genres,
        desc: source.desc,
        tix: source.tix,
        externalUrl: source.externalUrl,
        flyerUrl: source.flyerUrl,
        cap: source.cap,
        ageRequirement: source.ageRequirement,
        lifecycle: source.lifecycle,
        createdByBand: source.createdByBand,
        discoveryListingReady: source.discoveryListingReady,
      );
    }),
    venues: DemoData.venues,
    bands: DemoData.bands,
  );

  @override
  Stream<FeedSnapshot> feed() => Stream.value(_snapshot);
}
