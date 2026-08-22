import 'dart:async';

import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_media.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_upload_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';
import 'support/harness.dart';

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
    final auth = FakeAuthService();
    await _pumpBandMedia(
      tester,
      auth: auth,
      repository: _EmptyMediaDemoRepository(auth: auth),
    );

    expect(find.text('NOTHING POSTED YET'), findsOneWidget);
    expect(find.text('+ POST YOUR FIRST CLIP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an in-flight upload and then its new media row', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _GatedSaveDemoRepository(auth: auth);
    final harness = await _pumpBandMedia(
      tester,
      auth: auth,
      repository: repository,
    );
    harness.picker.nextVideo = videoFixture();

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
    final auth = FakeAuthService();
    final repository = HttpUploadDemoRepository(auth: auth);
    final harness = await _pumpBandMedia(
      tester,
      auth: auth,
      repository: repository,
      uploader: MediaUploadService(
        repository: repository,
        post: (url, bytes, contentType) async {
          throw Exception('simulated upload failure');
        },
      ),
    );
    harness.picker.nextVideo = videoFixture();

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

  testWidgets('members see disabled uploads and no management controls', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await _pumpBandMedia(
      tester,
      auth: auth,
      repository: _MemberDemoRepository(auth: auth),
    );

    expect(find.text('PIN'), findsNothing);
    expect(find.text('PINNED ★'), findsNothing);
    expect(find.text('↑'), findsNothing);
    expect(find.text('↓'), findsNothing);
    expect(find.text('✕'), findsNothing);

    final clipSlot = tester.widget<EpCard>(
      find.ancestor(of: find.text('+ CLIP'), matching: find.byType(EpCard)),
    );
    expect(clipSlot.variant, EpCardVariant.disabled);
    expect(harness.app.toast, isEmpty);
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

Future<AppHarness> _pumpBandMedia(
  WidgetTester tester, {
  FakeAuthService? auth,
  EarplugRepository? repository,
  MediaUploadService? uploader,
}) => pumpApp(
  tester,
  auth: auth,
  repository: repository,
  uploader: uploader,
  home: const BandMediaScreen(bandId: 'b1'),
);

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
