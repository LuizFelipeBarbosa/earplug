import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/auth.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_upload_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';

void main() {
  test(
    'fake auth deletes only after a successful Clerk-style operation',
    () async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      auth.deleteAccountError = const AuthException('Clerk refused deletion.');

      await expectLater(auth.deleteAccount(), throwsA(isA<AuthException>()));
      expect(auth.signedIn, isTrue);
      expect(auth.deleteAccountCalls, 1);

      auth.deleteAccountError = null;
      await auth.deleteAccount();
      expect(auth.signedIn, isFalse);
      expect(auth.deleteAccountCalls, 2);
    },
  );

  test('AppState preserves local state when account deletion fails', () async {
    final auth = FakeAuthService();
    final repository = _DeletionOrderRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(app.dispose);
    await auth.signInDemo();
    await Future<void>.delayed(Duration.zero);
    app.rsvps = {'kept-rsvp'};
    auth.deleteAccountError = const AuthException('Temporary Clerk error.');

    expect(await app.deleteAccount(), isFalse);
    expect(app.authed, isTrue);
    expect(app.rsvps, contains('kept-rsvp'));
    expect(repository.authDeleteCallsAtTombstone, [0]);

    auth.deleteAccountError = null;
    expect(await app.deleteAccount(), isTrue);
    expect(repository.authDeleteCallsAtTombstone, [0, 1]);
    expect(app.authed, isFalse);
    expect(app.rsvps, isEmpty);
    expect(app.profile, isNull);
    expect(app.current.screen, Screen.home);
  });

  test(
    'AppState does not delete Clerk when the Convex tombstone fails',
    () async {
      final auth = FakeAuthService();
      final repository = _FailingDeletionRepository(auth: auth);
      final app = AppState(repository: repository, auth: auth);
      addTearDown(app.dispose);
      await auth.signInDemo();
      await Future<void>.delayed(Duration.zero);

      expect(await app.deleteAccount(), isFalse);
      expect(auth.deleteAccountCalls, 0);
      expect(app.authed, isTrue);
    },
  );

  test(
    "an old avatar upload cannot release a new session's clear lock",
    () async {
      final auth = FakeAuthService();
      final repository = _GatedAvatarRepository(auth: auth);
      final uploadStarted = Completer<void>();
      final uploadGate = Completer<String>();
      final uploader = MediaUploadService(
        repository: repository,
        post: (_, _, _) {
          uploadStarted.complete();
          return uploadGate.future;
        },
      );
      final app = AppState(
        repository: repository,
        auth: auth,
        mediaUploadService: uploader,
      );
      addTearDown(app.dispose);
      await auth.signInDemo();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final oldUpload = app.updateFanAvatar(stubPhotoFixture());
      await uploadStarted.future;
      await app.signOut();
      await auth.signInDemo();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      repository.clearGate = Completer<void>();
      final newClear = app.clearFanAvatar();
      expect(app.fanAvatarSaving, isTrue);
      uploadGate.complete('old-session-storage');
      expect(await oldUpload, isFalse);
      expect(app.fanAvatarSaving, isTrue);

      repository.clearGate!.complete();
      expect(await newClear, isTrue);
      expect(app.fanAvatarSaving, isFalse);
    },
  );

  test(
    "an old avatar clear cannot release a new session's upload lock",
    () async {
      final auth = FakeAuthService();
      final repository = _GatedAvatarRepository(auth: auth)
        ..clearGate = Completer<void>();
      final uploadStarted = Completer<void>();
      final uploadGate = Completer<String>();
      final uploader = MediaUploadService(
        repository: repository,
        post: (_, _, _) {
          uploadStarted.complete();
          return uploadGate.future;
        },
      );
      final app = AppState(
        repository: repository,
        auth: auth,
        mediaUploadService: uploader,
      );
      addTearDown(app.dispose);
      await auth.signInDemo();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final oldClear = app.clearFanAvatar();
      await app.signOut();
      await auth.signInDemo();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final newUpload = app.updateFanAvatar(stubPhotoFixture());
      await uploadStarted.future;
      expect(app.fanAvatarSaving, isTrue);
      repository.clearGate!.complete();
      expect(await oldClear, isFalse);
      expect(app.fanAvatarSaving, isTrue);

      uploadGate.complete('new-session-storage');
      expect(await newUpload, isTrue);
      expect(app.fanAvatarSaving, isFalse);
    },
  );

  test(
    'fan profile changes publish locally only after a successful save',
    () async {
      final auth = FakeAuthService();
      final repository = _ProfileRepository(auth: auth);
      final app = AppState(repository: repository, auth: auth);
      addTearDown(app.dispose);
      await auth.signInDemo();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        await app.saveFanProfile(
          name: '  Sam Reyes  ',
          bio: '  Always by the speakers.  ',
          homeLocation: FanCity.oak,
          genres: const ['punk', 'noise'],
          locationPersonalizationEnabled: true,
          followedBandUpdatesEnabled: true,
        ),
        isTrue,
      );
      expect(app.profile?.name, 'Sam Reyes');
      expect(app.profile?.bio, 'Always by the speakers.');
      expect(app.profile?.homeLocation, FanCity.oak);
      expect(app.city, 'oak');

      expect(
        await app.saveFanProfile(
          name: 'Sam Reyes',
          bio: 'Always by the speakers.',
          homeLocation: FanCity.oak,
          genres: const ['punk', 'noise'],
          locationPersonalizationEnabled: false,
          followedBandUpdatesEnabled: true,
        ),
        isTrue,
      );
      expect(app.profile?.locationPersonalizationEnabled, isFalse);
      expect(app.city, 'sf');

      repository.failProfileSave = true;
      expect(
        await app.saveFanProfile(
          name: 'Unsaved Name',
          bio: null,
          homeLocation: null,
          genres: const [],
          locationPersonalizationEnabled: false,
          followedBandUpdatesEnabled: false,
        ),
        isFalse,
      );
      expect(app.profile?.name, 'Sam Reyes');
      expect(app.profile?.followedBandUpdatesEnabled, isTrue);
    },
  );

  test('profile tutorial persists completion and can be replayed', () async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(app.dispose);
    await auth.signInDemo();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    app.openMyGigsTab();
    expect(app.profileTutorialVisible, isTrue);
    await app.completeProfileTutorial();
    expect(app.profileTutorialVisible, isFalse);
    expect((await repository.me())?.profileTutorialCompleted, isTrue);

    app.openSettings();
    app.replayProfileTutorial();
    expect(app.current.screen, Screen.myGigs);
    expect(app.profileTutorialVisible, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect((await repository.me())?.profileTutorialCompleted, isFalse);
  });

  test('profile responses from a signed-out session are ignored', () async {
    final auth = FakeAuthService();
    final repository = _GatedProfileRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(app.dispose);

    await auth.signInDemo();
    await Future<void>.delayed(Duration.zero);
    expect(repository.meRequested, isTrue);

    await auth.signOut();
    repository.profileGate.complete(
      UserProfile(
        name: 'Previous Account',
        email: 'previous@example.com',
        genres: const ['punk'],
        attendedCount: 2,
        createdAt: DateTime(2025),
        homeLocation: FanCity.oak,
        locationPersonalizationEnabled: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(app.authed, isFalse);
    expect(app.profile, isNull);
    expect(app.userGenres, isEmpty);
    expect(app.city, 'sf');
  });

  test(
    'avatar operations and followed-band updates honor profile preferences',
    () async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      final app = AppState(repository: repository, auth: auth);
      addTearDown(app.dispose);
      await auth.signInDemo();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(await app.updateFanAvatar(stubPhotoFixture()), isTrue);
      expect(app.profile?.avatarUrl, isNotNull);
      expect(await app.clearFanAvatar(), isTrue);
      expect(app.profile?.avatarUrl, isNull);

      app.follows = {'b2', 'b4'};
      final followedShows = app.followedBandShows;
      expect(followedShows, isNotEmpty);
      expect(
        followedShows.every((gig) => gig.lineup.any(app.follows.contains)),
        isTrue,
      );
      expect(
        followedShows.map((gig) => gig.startsAt).toList(),
        orderedEquals(
          followedShows.map((gig) => gig.startsAt).toList()..sort(),
        ),
      );

      expect(
        await app.saveFanProfile(
          name: app.profile!.name,
          bio: app.profile?.bio,
          homeLocation: app.profile?.homeLocation,
          genres: app.profile!.genres,
          locationPersonalizationEnabled:
              app.profile!.locationPersonalizationEnabled,
          followedBandUpdatesEnabled: false,
        ),
        isTrue,
      );
      expect(app.followedBandShows, isEmpty);
    },
  );

  test('followed-band shows include gigs outside the discovery feed', () async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _OutsideFeedFollowRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(app.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(app.allGigs.any((gig) => gig.id == 'outside-feed'), isFalse);
    expect(
      app.followedBandShows.map((gig) => gig.id),
      contains('outside-feed'),
    );
    expect(app.gig('outside-feed')?.title, 'Beyond the Feed');
  });

  testWidgets('backing out during confirmation keeps the pending RSVP', (
    tester,
  ) async {
    final app = await _pumpAuth(
      tester,
      openGate: (app) {
        app.openGig('g1');
        app.requestRsvp('g1');
      },
    );

    expect(find.text('RSVP CONFIRMED'), findsOne);
    expect(app.rsvps, contains('g1'));
    expect(app.pending, isNull);

    // System back mid-confirmation unmounts auth and cancels its timer. The
    // replayed RSVP must survive.
    app.back();
    await tester.pump(); // the pop's frame unmounts the auth screen
    await tester.pump(const Duration(seconds: 3));
    expect(app.rsvps, contains('g1'));
    expect(app.current.screen, Screen.gig);
  });

  testWidgets('successful auth replays and returns without a taste step', (
    tester,
  ) async {
    final app = await _pumpAuth(
      tester,
      openGate: (app) {
        app.openGig('g1');
        app.requestRsvp('g1');
      },
    );

    expect(find.text('PLUG IN'), findsNothing);
    await tester.pump(const Duration(seconds: 2));

    expect(app.rsvps, contains('g1'));
    expect(app.current.screen, Screen.gig);
  });

  testWidgets('the splash lands on My Gigs for a myGigs intent', (
    tester,
  ) async {
    final app = await _pumpAuth(tester, openGate: (app) => app.openMyGigsTab());

    await tester.pump(const Duration(seconds: 2));

    expect(app.current.screen, Screen.myGigs);
  });

  testWidgets('repeated commit calls replay the pending action only once', (
    tester,
  ) async {
    final app = await _pumpAuth(
      tester,
      openGate: (app) {
        app.openGig('g1');
        app.requestRsvp('g1');
      },
    );

    await Future.wait([app.commitAuth(), app.commitAuth()]);
    await tester.pump(const Duration(seconds: 2));

    expect(app.rsvps, contains('g1'));
    expect(app.current.screen, Screen.gig);
  });

  testWidgets('the door explains public browsing and action-time accounts', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpApp(
      tester,
      beforePump: (app) => app.requestSave('g1'),
      home: const Scaffold(body: AuthScreen()),
      pumpFor: const Duration(milliseconds: 100),
    );
    expect(
      find.text(
        'Browse freely. Create an account when you RSVP, save a show, or start a band. It takes about ten seconds.',
      ),
      findsOne,
    );
    expect(find.text('PLUG IN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending action waits for user setup before replaying', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _GatedEnsureRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) async {
        app.requestRsvp('g1');
        await auth.signInDemo();
      },
      home: const Scaffold(body: AuthScreen()),
      pumpFor: const Duration(milliseconds: 100),
    );

    expect(find.text('FINISHING SIGN-IN'), findsOne);
    expect(repository.rsvpCalls, 0);

    repository.ensureGate.complete();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(repository.rsvpCalls, 1);
    expect(find.text('RSVP CONFIRMED'), findsOne);

    await harness.app.commitAuth();
    expect(repository.rsvpCalls, 1);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('replayed intent keeps a returning fan relationship on', (
    tester,
  ) async {
    final app = await _pumpAuth(
      tester,
      openGate: (app) => app.requestRsvp('g5'),
    );

    // g5 is already in the returning demo fan's account. Replaying the intent
    // must ensure it is on, not toggle it back off.
    expect(app.rsvps, contains('g5'));
    await tester.pump(const Duration(seconds: 2));
    expect(app.rsvps, contains('g5'));
  });

  testWidgets('failed user setup preserves the intent and can be retried', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _RetryEnsureRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) async {
        app.requestSave('g1');
        await auth.signInDemo();
      },
      home: const Scaffold(body: AuthScreen()),
      pumpFor: const Duration(milliseconds: 400),
    );

    expect(find.text('TRY AGAIN'), findsOne);
    expect(harness.app.pending?.kind, PendingKind.save);
    expect(repository.saveCalls, 0);

    await tester.tap(find.text('TRY AGAIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(repository.ensureCalls, 2);
    expect(repository.saveCalls, 1);
    expect(harness.app.pending, isNull);
    expect(find.text('SHOW SAVED'), findsOne);
    await tester.pump(const Duration(seconds: 2));
  });
}

class _DeletionOrderRepository extends DemoRepository {
  _DeletionOrderRepository({required this.auth}) : super(auth: auth);

  final FakeAuthService auth;
  final List<int> authDeleteCallsAtTombstone = [];

  @override
  Future<void> deleteCurrentUser() async {
    authDeleteCallsAtTombstone.add(auth.deleteAccountCalls);
  }
}

class _FailingDeletionRepository extends DemoRepository {
  _FailingDeletionRepository({required super.auth});

  @override
  Future<void> deleteCurrentUser() =>
      Future<void>.error(StateError('Convex tombstone failed'));
}

class _GatedAvatarRepository extends DemoRepository {
  _GatedAvatarRepository({required super.auth});

  Completer<void>? clearGate;

  @override
  Future<String> generateAvatarUploadUrl() async =>
      'https://upload.example/avatar';

  @override
  Future<void> clearAvatar() async {
    await clearGate?.future;
    await super.clearAvatar();
  }
}

class _OutsideFeedFollowRepository extends DemoRepository {
  _OutsideFeedFollowRepository({required super.auth});

  @override
  Stream<List<Gig>> upcomingGigsForBand(String bandId) {
    if (bandId != 'b2') return Stream.value(const []);
    final startsAt = DateTime.now().add(const Duration(days: 365));
    return Stream.value([
      Gig(
        id: 'outside-feed',
        title: 'Beyond the Feed',
        venueId: 'v1',
        price: 0,
        startsAt: startsAt,
        dateShort: Gig.dateShortFor(startsAt.millisecondsSinceEpoch),
        dateLine: Gig.dateLineFor(startsAt.millisecondsSinceEpoch, '8PM / 9PM'),
        time: '8PM / 9PM',
        when: Gig.whenFor(startsAt.millisecondsSinceEpoch),
        flyKey: 'paper',
        lineup: const ['b2'],
        going: 0,
        genres: const ['punk'],
        desc: '',
        tix: Ticketing.rsvp,
      ),
    ]);
  }
}

class _GatedEnsureRepository extends DemoRepository {
  _GatedEnsureRepository({required super.auth});

  final ensureGate = Completer<void>();
  int rsvpCalls = 0;

  @override
  Future<void> ensureUser({String? name}) => ensureGate.future;

  @override
  Future<void> ensureRsvp(String gigId) async {
    if (!ensureGate.isCompleted) {
      throw StateError('RSVP ran before ensureUser completed');
    }
    rsvpCalls++;
    await super.ensureRsvp(gigId);
  }
}

class _RetryEnsureRepository extends DemoRepository {
  _RetryEnsureRepository({required super.auth});

  int ensureCalls = 0;
  int saveCalls = 0;

  @override
  Future<void> ensureUser({String? name}) async {
    ensureCalls++;
    if (ensureCalls == 1) throw StateError('temporary setup failure');
    await super.ensureUser(name: name);
  }

  @override
  Future<void> ensureSave(String gigId) async {
    saveCalls++;
    await super.ensureSave(gigId);
  }
}

class _ProfileRepository extends DemoRepository {
  _ProfileRepository({required super.auth});

  bool failProfileSave = false;

  @override
  Future<void> updateFanProfile({
    required String name,
    required String? bio,
    required FanCity? homeLocation,
    required List<String> genres,
    required bool locationPersonalizationEnabled,
    required bool followedBandUpdatesEnabled,
  }) async {
    if (failProfileSave) throw StateError('profile save failed');
    await super.updateFanProfile(
      name: name,
      bio: bio,
      homeLocation: homeLocation,
      genres: genres,
      locationPersonalizationEnabled: locationPersonalizationEnabled,
      followedBandUpdatesEnabled: followedBandUpdatesEnabled,
    );
  }
}

class _GatedProfileRepository extends DemoRepository {
  _GatedProfileRepository({required super.auth});

  final profileGate = Completer<UserProfile?>();
  bool meRequested = false;

  @override
  Future<UserProfile?> me() {
    meRequested = true;
    return profileGate.future;
  }
}

/// Opens an authenticated route through [openGate], signs in, and pumps the
/// auth screen the way main.dart hosts it: unmounted the moment the navigation
/// stack pops it.
Future<AppState> _pumpAuth(
  WidgetTester tester, {
  required void Function(AppState app) openGate,
}) async {
  final auth = FakeAuthService();
  final harness = await pumpApp(
    tester,
    auth: auth,
    beforePump: (app) async {
      openGate(app);
      expect(app.current.screen, Screen.auth);
      await auth.signInDemo();
    },
    home: Scaffold(
      body: Consumer<AppState>(
        builder: (_, a, _) => a.current.screen == Screen.auth
            ? const AuthScreen()
            : const SizedBox.shrink(),
      ),
    ),
    pumpFor: const Duration(milliseconds: 400),
  );
  return harness.app;
}
