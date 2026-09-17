import 'dart:async';

import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_media.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_upload_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';

const _gateMessage = 'Only band admins can post media.';
const _hint = 'Tap a tile to manage. Hold and drag to reorder.';
const _caption = 'Videos up to 25 MB · photos up to 8 MB';

void main() {
  testWidgets('header, hint, caption and square grid use the media layout', (
    tester,
  ) async {
    final harness = await _pumpBandMedia(tester);

    expect(find.text('MEDIA'), findsOne);
    expect(_key('band-media-back'), findsOne);
    expect(find.textContaining('ITEM'), findsNothing);
    expect(tester.widget<EpMonoText>(_key('band-media-hint')).text, _hint);
    expect(
      tester.widget<EpMonoText>(_key('band-media-caption')).text,
      _caption,
    );
    expect(find.text(_hint.toUpperCase()), findsOne);
    expect(find.text(_caption.toUpperCase()), findsOne);
    final grid = tester.widget<GridView>(_key('band-media-grid'));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
    expect(delegate.mainAxisSpacing, 16);
    expect(delegate.crossAxisSpacing, 16);
    expect(delegate.childAspectRatio, 1);
    expect(_gridTileKeys(), [
      'band-media-add',
      ...harness.media.mediaFor('b1').map(_tileKey),
    ]);
    final add = tester.getRect(_key('band-media-add'));
    final first = tester.getRect(
      _key(_tileKey(harness.media.mediaFor('b1').first)),
    );
    expect(add.width, closeTo(add.height, .01));
    expect(add.left, EpLayout.gutter);
    expect(first.top, add.top);
    expect(first.left - add.right, closeTo(16, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters preserve the global order and All restores every tile', (
    tester,
  ) async {
    final harness = await _pumpBandMedia(tester);
    final original = harness.media.mediaFor('b1');
    expect(original, hasLength(7));
    expect(
      tester.widget<EpPill>(_key('band-media-filter-all')).selected,
      isTrue,
    );

    for (final filter in ['videos', 'photos', 'all']) {
      await tester.tap(_key('band-media-filter-$filter'));
      await tester.pumpAndSettle();
      for (final item in original) {
        final visible = filter == 'all' || (filter == 'videos') == item.isVideo;
        expect(_key(_tileKey(item)), visible ? findsOne : findsNothing);
      }
      expect(_gridTileKeys(), [
        'band-media-add',
        ...original
            .where(
              (item) => filter == 'all' || (filter == 'videos') == item.isVideo,
            )
            .map(_tileKey),
      ]);
      for (final name in ['all', 'videos', 'photos']) {
        final pill = tester.widget<EpPill>(_key('band-media-filter-$name'));
        expect(pill.selected, name == filter);
        expect(pill.variant, EpPillVariant.outline);
      }
    }
  });

  testWidgets(
    'Add opens Video and Photos actions, including the photos picker',
    (tester) async {
      final harness = await _pumpBandMedia(tester);
      await tester.tap(_key('band-media-add'));
      await tester.pumpAndSettle();

      final sheet = tester.widget<EpActionSheet>(find.byType(EpActionSheet));
      expect(sheet.header, 'Add');
      expect(sheet.items.map((item) => item.label), ['Video', 'Photos']);
      expect(find.text('Video'), findsOne);
      expect(find.text('Photos'), findsOne);
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      expect(harness.picker.photoListCalls, 1);
      expect(find.byType(EpActionSheet), findsNothing);
    },
  );

  testWidgets(
    'videos show play, duration and exactly one featured badge; photos have none',
    (tester) async {
      await _pumpBandMedia(tester);
      for (final item in DemoData.b1Media) {
        expect(
          _key('band-media-play-${item.id}'),
          item.isVideo ? findsOne : findsNothing,
        );
        expect(
          _key('band-media-duration-${item.id}'),
          item.isVideo ? findsOne : findsNothing,
        );
        expect(
          _key('band-media-featured-${item.id}'),
          item.id == 'bm1' ? findsOne : findsNothing,
        );
      }
      expect(find.text('PROCESSING'), findsNWidgets(7));
    },
  );

  testWidgets('video with no duration keeps play and processing overlays', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final video = videoMediaFixture(
      id: 'no-duration',
      title: 'Untimed clip',
      url: '',
      lengthSec: null,
      sizeBytes: null,
      views: null,
    );
    await _pumpBandMedia(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)..returns('mediaFor', [video]),
    );
    expect(_key('band-media-play-no-duration'), findsOne);
    expect(_key('band-media-duration-no-duration'), findsNothing);
    expect(find.text('PROCESSING'), findsOne);
  });

  for (final filter in ['all', 'videos', 'photos']) {
    testWidgets('long-press drag reorders globally with the $filter filter', (
      tester,
    ) async {
      final auth = FakeAuthService();
      final repository = _RecordingRepository(auth: auth);
      final harness = await _pumpBandMedia(
        tester,
        auth: auth,
        repository: repository,
      );
      final original = harness.media.mediaFor('b1');
      // Photos interleave the videos in the repository's global display order.
      final source = original.firstWhere(
        (item) => item.id == (filter == 'photos' ? 'bm7' : 'bm1'),
      );
      final target = original.firstWhere(
        (item) => item.id == (filter == 'videos' ? 'bm3' : 'bm6'),
      );
      final toIndex = original.indexOf(target);
      final expected = original.map((item) => item.id).toList()
        ..remove(source.id);
      expected.insert(toIndex, source.id);
      final gate = repository.gate('reorderMedia');
      await tester.tap(_key('band-media-filter-$filter'));
      await tester.pumpAndSettle();

      await _dragTile(tester, source, target);

      expect(repository.reorders, [
        (bandId: 'b1', mediaId: source.id, toIndex: toIndex),
      ]);
      expect(repository.callsTo('reorderMedia'), 1);
      expect(harness.media.mediaFor('b1').map((item) => item.id), expected);
      final visibleIds = original
          .where(
            (item) => filter == 'all' || (filter == 'videos') == item.isVideo,
          )
          .map((item) => item.id)
          .toSet();
      final tilesById = {for (final item in original) item.id: _tileKey(item)};
      expect(_gridTileKeys(), [
        'band-media-add',
        ...expected.where(visibleIds.contains).map((id) => tilesById[id]!),
      ]);

      gate.complete();
      await tester.pumpAndSettle();
      expect(harness.media.mediaFor('b1').map((item) => item.id), expected);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'tile sheet shows kind position, permitted actions and destructive Remove',
    (tester) async {
      await _pumpBandMedia(tester);
      await _openTile(tester, 'video-media-bm2');
      expect(_key('band-media-sheet'), findsOne);
      expect(
        tester.widget<EpMonoText>(_key('band-media-sheet-status')).text,
        'Processing · clip 2 of 5',
      );
      for (final action in ['feature', 'front', 'replace', 'remove']) {
        expect(_key('band-media-action-$action'), findsOne);
      }
      expect(
        tester.widget<EpMenuRow>(_key('band-media-action-feature')).label,
        'Set as featured',
      );
      expect(
        tester.widget<EpMenuRow>(_key('band-media-action-front')).label,
        'Move to front',
      );
      expect(
        tester.widget<EpMenuRow>(_key('band-media-action-replace')).label,
        'Replace video',
      );
      final removeIcon = tester.widget<Icon>(
        find.descendant(
          of: _key('band-media-action-remove'),
          matching: find.byIcon(Icons.delete_outline),
        ),
      );
      expect(
        removeIcon.color,
        tester.element(_key('band-media-sheet')).epColors.destructive,
      );
      await _dismissSheet(tester);

      await _openTile(tester, 'video-media-bm1');
      expect(_key('band-media-action-feature'), findsNothing);
      expect(_key('band-media-action-front'), findsNothing);
      await _dismissSheet(tester);

      await tester.tap(_key('band-media-filter-photos'));
      await tester.pumpAndSettle();
      await _openTile(tester, 'photo-media-bm6');
      expect(_key('band-media-action-feature'), findsNothing);
      // First in the photo filter is not first globally.
      expect(_key('band-media-action-front'), findsOne);
      expect(
        tester.widget<EpMenuRow>(_key('band-media-action-replace')).label,
        'Replace photo',
      );
      expect(
        tester.widget<EpMonoText>(_key('band-media-sheet-status')).text,
        'Processing · photo 1 of 2',
      );
    },
  );

  testWidgets('ready sheet uses ready status and a success dot', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final ready = videoMediaFixture().copyWith(pinned: false, order: 1);
    await _pumpBandMedia(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returns('mediaFor', [DemoData.b1Media.first, ready]),
    );
    await _openTile(tester, 'video-media-m1');
    expect(
      tester.widget<EpMonoText>(_key('band-media-sheet-status')).text,
      'Ready · clip 2 of 2',
    );
    final dot = tester.widget<EpMonoText>(
      find.descendant(
        of: _key('band-media-sheet'),
        matching: find.byWidgetPredicate(
          (widget) => widget is EpMonoText && widget.text == '●',
        ),
      ),
    );
    expect(
      dot.color,
      tester.element(_key('band-media-sheet')).epColors.success,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('featuring a video closes the sheet and transfers the star', (
    tester,
  ) async {
    final harness = await _pumpBandMedia(tester);
    await _openTile(tester, 'video-media-bm2');
    await tester.tap(_key('band-media-action-feature'));
    await tester.pumpAndSettle();
    expect(harness.media.pinnedVideoFor('b1')?.id, 'bm2');
    expect(_key('band-media-sheet'), findsNothing);
    expect(_key('band-media-featured-bm2'), findsOne);
    expect(_key('band-media-featured-bm1'), findsNothing);
  });

  testWidgets(
    'Move to front places a photo at the global front and closes the sheet',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _RecordingRepository(auth: auth);
      final harness = await _pumpBandMedia(
        tester,
        auth: auth,
        repository: repository,
      );
      await _openTile(tester, 'photo-media-bm7');
      await tester.tap(_key('band-media-action-front'));
      await tester.pumpAndSettle();
      expect(repository.reorders, [(bandId: 'b1', mediaId: 'bm7', toIndex: 0)]);
      expect(harness.media.mediaFor('b1').first.id, 'bm7');
      expect(_gridTileKeys()[1], 'photo-media-bm7');
      expect(_key('band-media-sheet'), findsNothing);
    },
  );

  for (final video in [true, false]) {
    testWidgets(
      'Replace ${video ? 'video' : 'photo'} picks the same kind and keeps its position',
      (tester) async {
        final harness = await _pumpBandMedia(tester);
        final id = video ? 'bm2' : 'bm6';
        final original = harness.media.mediaFor('b1');
        final index = original.indexWhere((item) => item.id == id);
        harness.picker.nextVideo = videoFixture(filename: 'replacement.mp4');
        harness.picker.nextPhoto = photoFixture(filename: 'replacement.png');
        await _openTile(tester, '${video ? 'video' : 'photo'}-media-$id');
        await tester.tap(_key('band-media-action-replace'));
        await tester.pumpAndSettle();
        final current = harness.media.mediaFor('b1');
        expect(current, hasLength(original.length));
        expect(current[index].title, 'REPLACEMENT');
        expect(current[index].isVideo, video);
        expect(current.any((item) => item.id == id), isFalse);
        expect(harness.picker.videoCalls, video ? 1 : 0);
        expect(harness.picker.photoCalls, video ? 0 : 1);
        expect(_key('band-media-sheet'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Remove ${video ? 'video' : 'photo'} keeps confirmation and deletes only on DELETE',
      (tester) async {
        final harness = await _pumpBandMedia(tester);
        final id = video ? 'bm2' : 'bm6';
        final tile = '${video ? 'video' : 'photo'}-media-$id';
        for (final confirm in [false, true]) {
          await _openTile(tester, tile);
          await tester.tap(_key('band-media-action-remove'));
          await tester.pumpAndSettle();
          expect(_key('band-media-sheet'), findsNothing);
          expect(find.text('REMOVE ${video ? 'VIDEO' : 'PHOTO'}?'), findsOne);
          expect(find.text('DELETE'), findsOne);
          expect(find.text('KEEP'), findsOne);
          expect(harness.media.mediaFor('b1'), hasLength(7));
          await tester.tap(find.text(confirm ? 'DELETE' : 'KEEP'));
          await tester.pumpAndSettle();
          expect(_key(tile), confirm ? findsNothing : findsOne);
        }
        expect(harness.media.mediaFor('b1'), hasLength(6));
      },
    );
  }

  testWidgets('members see every applicable action but can only browse', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _RecordingRepository(auth: auth)
      ..returnsStream<List<BandMembership>>(
        'myBands',
        () => Stream.value([
          BandMembership(band: DemoData.bands['b1']!, role: 'member'),
        ]),
      );
    final harness = await _pumpBandMedia(
      tester,
      auth: auth,
      repository: repository,
    );
    final original = harness.media.mediaFor('b1');
    expect(find.byType(LongPressDraggable<String>), findsNothing);
    for (final action in ['feature', 'front', 'replace', 'remove']) {
      harness.app.say('');
      await _openTile(tester, 'video-media-bm2');
      for (final visibleAction in ['feature', 'front', 'replace', 'remove']) {
        expect(_key('band-media-action-$visibleAction'), findsOne);
      }
      await tester.tap(_key('band-media-action-$action'));
      await tester.pumpAndSettle();
      expect(harness.app.toast, _gateMessage);
      expect(_key('band-media-sheet'), findsNothing);
      expect(find.text('REMOVE VIDEO?'), findsNothing);
      expect(harness.media.mediaFor('b1'), original);
    }
    for (final label in ['Video', 'Photos']) {
      harness.app.say('');
      await _chooseAdd(tester, label);
      await tester.pumpAndSettle();
      expect(harness.app.toast, _gateMessage);
    }
    harness.app.say('');
    await _dragTile(tester, original.first, original.last);
    expect(harness.app.toast, _gateMessage);
    expect(repository.reorders, isEmpty);
    expect(repository.pinCalls, 0);
    expect(repository.removeCalls, 0);
    expect(repository.callsTo('addBandMedia'), 0);
    expect(harness.picker.videoCalls, 0);
    expect(harness.picker.photoCalls, 0);
    expect(harness.picker.photoListCalls, 0);
    expect(harness.media.mediaFor('b1'), original);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saving upload appears immediately after Add and becomes a media tile',
    (tester) async {
      final auth = FakeAuthService();
      final repository = StubRepository(auth: auth);
      final saveGate = repository.gate('addBandMedia');
      final harness = await _pumpBandMedia(
        tester,
        auth: auth,
        repository: repository,
      );
      harness.picker.nextVideo = videoFixture();
      await _chooseAdd(tester, 'Video');
      await tester.pump(const Duration(milliseconds: 400));

      final upload = harness.media.uploadsFor('b1').single;
      expect(upload.phase, MediaUploadPhase.saving);
      expect(_gridTileKeys().take(2), [
        'band-media-add',
        'band-media-upload-${upload.id}',
      ]);
      expect(find.text('SAVING'), findsOne);
      final progress = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(progress.minHeight, 2);
      expect(progress.value, isNull);
      expect(tester.takeException(), isNull);

      saveGate.complete();
      await tester.pumpAndSettle();
      expect(harness.media.uploadsFor('b1'), isEmpty);
      final uploaded = harness.media
          .mediaFor('b1')
          .singleWhere((item) => item.title == 'RIPTIDE LIVE');
      expect(_key(_tileKey(uploaded)), findsOne);
      expect(_key('band-media-upload-${upload.id}'), findsNothing);
    },
  );

  testWidgets('uploading phase shows an indeterminate progress tile', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = HttpUploadDemoRepository(auth: auth);
    final postGate = Completer<String>();
    final harness = await _pumpBandMedia(
      tester,
      auth: auth,
      repository: repository,
      uploader: MediaUploadService(
        repository: repository,
        thumbnailGenerator: FakeVideoThumbnailGenerator(),
        post: (url, bytes, contentType) => postGate.future,
      ),
    );
    harness.picker.nextVideo = videoFixture();
    await _chooseAdd(tester, 'Video');
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      harness.media.uploadsFor('b1').single.phase,
      MediaUploadPhase.uploading,
    );
    expect(find.text('UPLOADING'), findsOne);
    expect(find.byType(LinearProgressIndicator), findsOne);
    expect(tester.takeException(), isNull);
    postGate.complete('st_uploaded');
    await tester.pumpAndSettle();
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets(
      'failed upload retries and discards without overflow at text scale $scale',
      (tester) async {
        final auth = FakeAuthService();
        final repository = HttpUploadDemoRepository(auth: auth);
        var shouldFail = true;
        var postCalls = 0;
        final harness = await _pumpBandMedia(
          tester,
          auth: auth,
          repository: repository,
          textScale: scale,
          uploader: MediaUploadService(
            repository: repository,
            thumbnailGenerator: FakeVideoThumbnailGenerator(),
            post: (url, bytes, contentType) async {
              postCalls++;
              if (shouldFail) throw Exception('simulated upload failure');
              return 'st_uploaded';
            },
          ),
        );
        harness.picker.nextVideo = videoFixture();
        await _chooseAdd(tester, 'Video');
        await tester.pumpAndSettle();
        final failed = harness.media.uploadsFor('b1').single;
        expect(find.text('UPLOAD FAILED'), findsOne);
        expect(find.textContaining('simulated upload failure'), findsOne);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(_key('band-media-upload-retry-${failed.id}'), findsOne);
        expect(_key('band-media-upload-discard-${failed.id}'), findsOne);
        expect(postCalls, 1);
        expect(tester.takeException(), isNull);

        shouldFail = false;
        await tester.tap(_key('band-media-upload-retry-${failed.id}'));
        await tester.pumpAndSettle();
        expect(postCalls, 3);
        expect(harness.media.uploadsFor('b1'), isEmpty);
        expect(harness.picker.videoCalls, 1);

        shouldFail = true;
        await _chooseAdd(tester, 'Video');
        await tester.pumpAndSettle();
        final discarded = harness.media.uploadsFor('b1').single;
        await tester.tap(_key('band-media-upload-discard-${discarded.id}'));
        await tester.pumpAndSettle();
        expect(harness.media.uploadsFor('b1'), isEmpty);
        expect(_key('band-media-upload-${discarded.id}'), findsNothing);
        expect(postCalls, 4);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('phone grid and tile sheet fit at text scale $scale', (
      tester,
    ) async {
      await _pumpBandMedia(tester, textScale: scale);
      expect(tester.view.physicalSize, const Size(390, 844));
      expect(tester.takeException(), isNull);
      await _openTile(tester, 'video-media-bm2');
      expect(_key('band-media-action-remove').hitTestable(), findsOne);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty media keeps only the Add tile and caption', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await _pumpBandMedia(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returns('mediaFor', const <BandMedia>[]),
    );
    expect(_gridTileKeys(), ['band-media-add']);
    expect(_key('band-media-caption'), findsOne);
    expect(find.textContaining('NO '), findsNothing);
  });

  testWidgets('initial loading shows LOADING until media arrives', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = StubRepository(auth: auth);
    final gate = repository.gate('mediaFor');
    final harness = await _pumpBandMedia(
      tester,
      auth: auth,
      repository: repository,
    );
    expect(harness.media.isLoading('b1'), isTrue);
    expect(find.text('LOADING…'), findsOne);
    expect(_key('band-media-grid'), findsNothing);
    expect(tester.takeException(), isNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('LOADING…'), findsNothing);
    expect(_gridTileKeys(), hasLength(8));
  });

  testWidgets(
    'initial load failure waits for Retry and refreshes successfully',
    (tester) async {
      final auth = FakeAuthService();
      final repository = StubRepository(auth: auth)
        ..failOnce('mediaFor', StateError('Media offline'));
      final harness = await _pumpBandMedia(
        tester,
        auth: auth,
        repository: repository,
      );
      expect(find.text('Bad state: Media offline'), findsOne);
      expect(_key('band-media-retry'), findsOne);
      expect(repository.callsTo('mediaFor'), 1);
      await tester.tap(_key('band-media-filter-photos'));
      await tester.pumpAndSettle();
      expect(repository.callsTo('mediaFor'), 1);
      await tester.tap(_key('band-media-retry'));
      await tester.pumpAndSettle();
      expect(repository.callsTo('mediaFor'), 2);
      expect(harness.media.loadErrorFor('b1'), isNull);
      expect(_key('band-media-retry'), findsNothing);
      expect(_gridTileKeys(), [
        'band-media-add',
        'photo-media-bm6',
        'photo-media-bm7',
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _key(String value) => find.byKey(ValueKey(value));

String _tileKey(BandMedia item) =>
    '${item.isVideo ? 'video' : 'photo'}-media-${item.id}';

List<String> _gridTileKeys() => find
    .descendant(
      of: _key('band-media-grid'),
      matching: find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            (key.value == 'band-media-add' ||
                key.value.startsWith('video-media-') ||
                key.value.startsWith('photo-media-') ||
                key.value.startsWith('band-media-upload-') &&
                    !key.value.contains('-retry-') &&
                    !key.value.contains('-discard-'));
      }),
    )
    .evaluate()
    .map((element) => (element.widget.key! as ValueKey<String>).value)
    .toList();

Future<void> _openTile(WidgetTester tester, String key) async {
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

Future<void> _dismissSheet(WidgetTester tester) async {
  Navigator.of(tester.element(_key('band-media-sheet'))).pop();
  await tester.pumpAndSettle();
}

Future<void> _chooseAdd(WidgetTester tester, String label) async {
  await tester.tap(_key('band-media-add'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pump();
}

Future<void> _dragTile(
  WidgetTester tester,
  BandMedia source,
  BandMedia target,
) async {
  final destination = tester.getCenter(_key(_tileKey(target)));
  final gesture = await tester.startGesture(
    tester.getCenter(_key(_tileKey(source))),
  );
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.moveTo(destination);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<AppHarness> _pumpBandMedia(
  WidgetTester tester, {
  FakeAuthService? auth,
  EarplugRepository? repository,
  MediaUploadService? uploader,
  double textScale = 1,
}) => pumpApp(
  tester,
  size: const Size(390, 844),
  auth: auth,
  repository: repository,
  uploader: uploader,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: const Scaffold(body: BandMediaScreen(bandId: 'b1')),
    ),
  ),
);

// StubRepository counts reorder calls but does not capture their arguments.
class _RecordingRepository extends StubRepository {
  _RecordingRepository({required super.auth});

  final reorders = <({String bandId, String mediaId, int toIndex})>[];
  int pinCalls = 0;
  int removeCalls = 0;

  @override
  Future<void> reorderMedia({
    required String bandId,
    required String mediaId,
    required int toIndex,
  }) {
    reorders.add((bandId: bandId, mediaId: mediaId, toIndex: toIndex));
    return super.reorderMedia(
      bandId: bandId,
      mediaId: mediaId,
      toIndex: toIndex,
    );
  }

  @override
  Future<void> pinBandMedia(String mediaId) {
    pinCalls++;
    return super.pinBandMedia(mediaId);
  }

  @override
  Future<void> deleteBandMedia(String mediaId) {
    removeCalls++;
    return super.deleteBandMedia(mediaId);
  }
}
