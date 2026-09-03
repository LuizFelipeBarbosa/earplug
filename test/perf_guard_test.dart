import 'dart:async';

import 'package:convex_flutter/convex_flutter.dart';
import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/home.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/convex_service.dart';
import 'package:earplug/services/convex_transport.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_map.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:earplug/widgets/video_thumbnail.dart';
// fake_async is already resolved transitively for deterministic timer tests.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/fake_video_player_platform.dart';
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
        await _flushAsyncWork();

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
                  media: _videoMedia(),
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

  test('ConvexService skips a duplicate raw payload and parses once', () {
    fakeAsync((async) {
      final transport = _FakeConvexTransport();
      final service = ConvexService(transport: transport);
      unawaited(service.init('https://fake.convex.cloud'));
      async.flushMicrotasks();

      var parseCalls = 0;
      final values = <int>[];
      final subscription = service
          .subscribe<int>('messages:list', const <String, dynamic>{}, (
            decoded,
          ) {
            parseCalls++;
            return (decoded as Map<String, dynamic>)['value'] as int;
          })
          .listen(values.add);
      addTearDown(subscription.cancel);
      async.flushMicrotasks();

      final before = ConvexService.debugStats.value.duplicatePayloadsSkipped;
      const raw = '{"value":1}';
      transport
        ..sendUpdate(raw)
        ..sendUpdate(raw);
      async.flushMicrotasks();

      expect(parseCalls, 1);
      expect(values, <int>[1]);
      expect(
        ConvexService.debugStats.value.duplicatePayloadsSkipped - before,
        1,
      );

      unawaited(subscription.cancel());
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 251));
      async.flushMicrotasks();
    });
  });
}

Future<void> _flushAsyncWork() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

BandMedia _videoMedia() => const BandMedia(
  id: 'm1',
  bandId: 'b1',
  kind: MediaKind.video,
  url: 'https://example.com/video.mp4',
  thumbnailUrl: null,
  title: 'Clip',
  caption: null,
  sizeBytes: 10,
  views: 2,
  lengthSec: 30,
  pinned: true,
  order: 0,
  isHero: false,
);

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

class _FakeConvexTransport implements ConvexTransport {
  late void Function(String) _onUpdate;

  @override
  bool get isConnected => true;

  @override
  Stream<WebSocketConnectionState> get connectionState => const Stream.empty();

  @override
  Duration get operationTimeout => const Duration(seconds: 1);

  @override
  Future<void> initialize(String url) => Future<void>.value();

  @override
  Future<String> query(String name, Map<String, dynamic> args) {
    throw UnimplementedError();
  }

  @override
  Future<String> mutation({
    required String name,
    required Map<String, dynamic> args,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ConvexTransportSubscription> subscribe({
    required String name,
    required Map<String, dynamic> args,
    required void Function(String) onUpdate,
    required void Function(String, String?) onError,
  }) {
    _onUpdate = onUpdate;
    return Future<ConvexTransportSubscription>.value(
      const _FakeSubscriptionHandle(),
    );
  }

  @override
  Future<void> setAuthWithRefresh({
    required Future<String?> Function() fetchToken,
  }) => Future<void>.value();

  @override
  Future<void> clearAuth() => Future<void>.value();

  void sendUpdate(String raw) => _onUpdate(raw);
}

class _FakeSubscriptionHandle implements ConvexTransportSubscription {
  const _FakeSubscriptionHandle();

  @override
  void cancel() {}
}
