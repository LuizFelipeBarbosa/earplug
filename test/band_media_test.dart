import 'dart:async';
import 'dart:typed_data';

import 'package:earplug/app_state.dart';
import 'package:earplug/band_media_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_media.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_picker.dart';
import 'package:earplug/services/media_upload_service.dart';
import 'package:earplug/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('renders seeded media and both upload slots', (tester) async {
    await _pumpBandMedia(tester);

    expect(find.text('+ CLIP'), findsOneWidget);
    expect(find.text('+ PHOTOS'), findsOneWidget);
    expect(
      find.text('This is what we sound like — live at Foghorn Club'),
      findsOneWidget,
    );
    expect(find.text('Riptide (practice take, one mic)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the empty state when the repository has no media', (
    tester,
  ) async {
    await _pumpBandMedia(
      tester,
      repositoryBuilder: (auth) => _EmptyMediaDemoRepository(auth: auth),
    );

    expect(find.text('NOTHING POSTED YET'), findsOneWidget);
    expect(find.text('+ POST YOUR FIRST CLIP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an in-flight upload and then its new media row', (
    tester,
  ) async {
    late _GatedSaveDemoRepository repository;
    final harness = await _pumpBandMedia(
      tester,
      repositoryBuilder: (auth) {
        repository = _GatedSaveDemoRepository(auth: auth);
        return repository;
      },
    );
    harness.picker.nextVideo = _videoFixture();

    await tester.tap(find.text('+ CLIP'));
    await tester.pump();

    expect(find.text('UPLOADING'), findsOneWidget);
    expect(find.text('riptide_live.mp4'), findsOneWidget);
    expect(find.text('SAVING…'), findsOneWidget);

    repository.saveGate.complete();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('RIPTIDE LIVE'),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('RIPTIDE LIVE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed uploads can be discarded', (tester) async {
    final harness = await _pumpBandMedia(
      tester,
      repositoryBuilder: (auth) => _HttpUploadDemoRepository(auth: auth),
      uploaderBuilder: (repository) => MediaUploadService(
        repository: repository,
        post: (url, bytes, contentType) async {
          throw Exception('simulated upload failure');
        },
      ),
    );
    harness.picker.nextVideo = _videoFixture();

    await tester.tap(find.text('+ CLIP'));
    await tester.pumpAndSettle();

    expect(find.text('RETRY'), findsOneWidget);
    expect(find.text('DISCARD'), findsOneWidget);
    expect(find.textContaining('simulated upload failure'), findsOneWidget);

    await tester.tap(find.text('DISCARD'));
    await tester.pump();

    expect(find.text('riptide_live.mp4'), findsNothing);
    expect(find.text('RETRY'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('members are gated from uploads and management controls', (
    tester,
  ) async {
    final harness = await _pumpBandMedia(
      tester,
      repositoryBuilder: (auth) => _MemberDemoRepository(auth: auth),
    );

    expect(find.text('PIN'), findsNothing);
    expect(find.text('PINNED ★'), findsNothing);
    expect(find.text('↑'), findsNothing);
    expect(find.text('↓'), findsNothing);
    expect(find.text('✕'), findsNothing);

    await tester.tap(find.text('+ CLIP'));
    await tester.pump();

    expect(harness.app.toast, 'Only band admins can post media.');

    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete requires confirmation and removes the selected row', (
    tester,
  ) async {
    await _pumpBandMedia(tester);
    const title = 'This is what we sound like — live at Foghorn Club';
    final deleteButton = find.byKey(const ValueKey('delete-bm1'));
    await tester.scrollUntilVisible(
      deleteButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('DELETE'), findsOneWidget);
    expect(find.text('KEEP'), findsOneWidget);
    expect(find.text(title), findsWidgets);

    await tester.tap(find.text('DELETE'));
    await tester.pumpAndSettle();

    expect(find.text(title), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<_BandMediaHarness> _pumpBandMedia(
  WidgetTester tester, {
  DemoRepository Function(FakeAuthService auth)? repositoryBuilder,
  MediaUploadService Function(EarplugRepository repository)? uploaderBuilder,
}) async {
  tester.view.physicalSize = const Size(402, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final auth = FakeAuthService();
  final repository =
      repositoryBuilder?.call(auth) ?? DemoRepository(auth: auth);
  final app = AppState(repository: repository, auth: auth);
  final picker = FakeMediaPicker();
  final controller = BandMediaController(
    repository: repository,
    say: app.say,
    picker: picker,
    uploader:
        uploaderBuilder?.call(repository) ??
        MediaUploadService(repository: repository),
  );
  app.attachMediaController(controller);
  addTearDown(controller.dispose);
  addTearDown(app.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<BandMediaController>.value(value: controller),
      ],
      child: MaterialApp(
        theme: buildEpTheme(),
        home: const BandMediaScreen(bandId: 'b1'),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _BandMediaHarness(app: app, picker: picker);
}

class _BandMediaHarness {
  final AppState app;
  final FakeMediaPicker picker;

  const _BandMediaHarness({required this.app, required this.picker});
}

PickedMedia _videoFixture() => PickedMedia(
  bytes: Uint8List.fromList([1, 2, 3]),
  filename: 'riptide_live.mp4',
  contentType: 'video/mp4',
  sizeBytes: 3,
);

class FakeMediaPicker implements MediaPicker {
  PickedMedia? nextPhoto;
  List<PickedMedia> nextPhotos = [];
  PickedMedia? nextVideo;
  MediaPickException? nextException;

  @override
  Future<PickedMedia?> pickPhoto() async {
    _throwIfNeeded();
    return nextPhoto;
  }

  @override
  Future<List<PickedMedia>> pickPhotos({int limit = 10}) async {
    _throwIfNeeded();
    return nextPhotos;
  }

  @override
  Future<PickedMedia?> pickVideo() async {
    _throwIfNeeded();
    return nextVideo;
  }

  void _throwIfNeeded() {
    final error = nextException;
    if (error != null) throw error;
  }
}

class _EmptyMediaDemoRepository extends DemoRepository {
  _EmptyMediaDemoRepository({required super.auth});

  @override
  Future<List<BandMedia>> mediaFor(String bandId) async => const [];
}

class _MemberDemoRepository extends DemoRepository {
  _MemberDemoRepository({required super.auth});

  @override
  Stream<List<BandMembership>> myBands() async* {
    yield [BandMembership(band: DemoData.bands['b1']!, role: 'member')];
  }
}

class _GatedSaveDemoRepository extends DemoRepository {
  _GatedSaveDemoRepository({required super.auth});

  final saveGate = Completer<void>();

  @override
  Future<String> addBandMedia({
    required String bandId,
    required MediaKind kind,
    required String storageId,
    required String title,
    String? caption,
    int? lengthSec,
  }) async {
    await saveGate.future;
    return super.addBandMedia(
      bandId: bandId,
      kind: kind,
      storageId: storageId,
      title: title,
      caption: caption,
      lengthSec: lengthSec,
    );
  }
}

class _HttpUploadDemoRepository extends DemoRepository {
  _HttpUploadDemoRepository({required super.auth});

  @override
  Future<String> generateMediaUploadUrl(String bandId) async =>
      'https://fake.upload/x';
}
