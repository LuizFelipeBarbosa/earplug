import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/edit_profile.dart';
import 'package:earplug/screens/my_gigs.dart';
import 'package:earplug/screens/settings.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('profile leads with private identity and branded fan fallback', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: const Scaffold(body: MyGigsScreen()),
    );

    expect(find.text('IDENTITY & EDIT PROFILE'), findsOne);
    expect(find.byKey(const Key('fan-profile-avatar')), findsOne);
    expect(find.byType(EpFanAvatar), findsOne);
    expect(find.text('EF'), findsOne);
    expect(find.byKey(const Key('edit-profile-action')), findsOne);
  });

  testWidgets('profile sections stay in the required order', (tester) async {
    await pumpApp(tester, home: const Scaffold(body: MyGigsScreen()));

    tester.view.physicalSize = const Size(402, 3000);
    await tester.pumpAndSettle();
    final positions = <Offset>[];
    for (final label in [
      'IDENTITY & EDIT PROFILE',
      'UPCOMING RSVPS',
      'SAVED SHOWS',
      'FOLLOWING',
      'UPCOMING SHOWS FROM FOLLOWED BANDS',
      'EVENT HISTORY',
      'SETTINGS',
    ]) {
      positions.add(tester.getTopLeft(find.text(label)));
    }

    for (var index = 1; index < positions.length; index++) {
      expect(positions[index].dy, greaterThan(positions[index - 1].dy));
    }
  });

  testWidgets(
    'every empty profile section explains itself and offers a route',
    (tester) async {
      await pumpApp(tester, home: const Scaffold(body: MyGigsScreen()));

      tester.view.physicalSize = const Size(402, 3000);
      await tester.pumpAndSettle();
      expect(
        find.text('No upcoming RSVPs. Pick a show you want to catch.'),
        findsOne,
      );
      expect(
        find.text('Nothing saved. Bookmark a show to keep it handy.'),
        findsOne,
      );
      expect(find.text('Follow bands to keep their profiles close.'), findsOne);
      expect(
        find.text('Follow a band to see its upcoming shows here.'),
        findsOne,
      );
      expect(
        find.text('Past RSVPs will build your private event history.'),
        findsOne,
      );
      expect(find.text('FIND A SHOW'), findsNWidgets(3));
      expect(find.text('EXPLORE BANDS'), findsNWidgets(2));
    },
  );

  testWidgets('failed explicit save keeps edits on screen with an error', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: _FailingProfileRepository(auth: auth),
      home: const Scaffold(body: EditProfileScreen()),
    );

    await tester.enterText(
      find.byKey(const Key('fan-name-field')),
      'Changed Name',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-fan-profile')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('save-fan-profile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('edit-profile-error')), findsOne);
    expect(find.text('Changed Name'), findsOne);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('followed-band shows open their gig details', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: const Scaffold(body: MyGigsScreen()),
    );
    final shows = harness.app.followedBandShows;
    expect(shows, isNotEmpty);
    final show = shows.firstWhere(
      (gig) =>
          !harness.app.rsvps.contains(gig.id) &&
          !harness.app.saved.contains(gig.id),
      orElse: () => shows.first,
    );

    tester.view.physicalSize = const Size(402, 5000);
    await tester.pumpAndSettle();
    final card = find.byKey(ValueKey('fan-event-${show.id}'));
    expect(card, findsOne);
    await tester.tap(card);
    await tester.pump();
    expect(harness.app.current.screen, Screen.gig);
    expect(harness.app.current.param, show.id);
  });

  testWidgets('failed unfollow rolls the Following row back', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _FailingFollowRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: MyGigsScreen()),
    );
    tester.view.physicalSize = const Size(402, 4000);
    await tester.pumpAndSettle();

    expect(harness.app.follows, contains('b1'));
    await tester.tap(find.text('FOLLOWING ✓'));
    await tester.pump(const Duration(milliseconds: 20));

    expect(repository.toggleFollowCalls, 1);
    expect(harness.app.follows, contains('b1'));
    expect(find.text('FOLLOWING ✓'), findsOne);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('profile tutorial completes and can be replayed from settings', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.resetTo(Screen.myGigs),
      home: const Scaffold(body: MyGigsScreen()),
    );

    expect(find.byKey(const Key('profile-tutorial')), findsOne);
    for (var step = 0; step < 3; step++) {
      await tester.tap(find.byKey(const Key('profile-tutorial-next')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('profile-tutorial')), findsNothing);
    expect(harness.app.profile?.profileTutorialCompleted, isTrue);

    final replayHarness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: SettingsScreen()),
    );
    await tester.tap(find.byKey(const Key('replay-profile-tutorial')));
    await tester.pumpAndSettle();
    expect(replayHarness.app.current.screen, Screen.myGigs);
    expect(replayHarness.app.profileTutorialVisible, isTrue);
  });

  testWidgets('settings separates destructive controls and protects deletion', (
    tester,
  ) async {
    final auth = FakeAuthService()..deleteAccountError = StateError('Clerk');
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: const Scaffold(body: SettingsScreen()),
    );
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('delete-account')),
      240,
      scrollable: scrollable,
    );

    final signOut = tester.widget<OutlinedButton>(
      find.byKey(const Key('settings-sign-out')),
    );
    expect(signOut.style!.foregroundColor!.resolve({}), Ep.destructive);
    expect(find.byKey(const Key('account-danger-zone')), findsOne);

    await tester.tap(find.byKey(const Key('delete-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-delete-account')));
    await tester.pumpAndSettle();
    expect(auth.deleteAccountCalls, 0);

    await tester.tap(find.byKey(const Key('delete-account')));
    await tester.pumpAndSettle();
    var confirm = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-delete-account')),
    );
    expect(confirm.onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('delete-account-confirmation')),
      'DELETE',
    );
    await tester.pump();
    confirm = tester.widget(find.byKey(const Key('confirm-delete-account')));
    expect(confirm.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('confirm-delete-account')));
    await tester.pumpAndSettle();

    expect(auth.deleteAccountCalls, 1);
    expect(harness.app.authed, isTrue);
    expect(find.byKey(const Key('delete-account-error')), findsOne);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('confirmed account deletion returns to signed-out home', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: const Scaffold(body: SettingsScreen()),
    );
    tester.view.physicalSize = const Size(402, 1300);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete-account')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('delete-account-confirmation')),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-delete-account')));
    await tester.pumpAndSettle();

    expect(auth.deleteAccountCalls, 1);
    expect(harness.app.authed, isFalse);
    expect(harness.app.current.screen, Screen.home);
    expect(find.byKey(const Key('delete-account-error')), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });
}

class _FailingProfileRepository extends DemoRepository {
  _FailingProfileRepository({required super.auth});

  @override
  Future<void> updateFanProfile({
    required String name,
    required String? bio,
    required FanCity? homeLocation,
    required List<String> genres,
    required bool locationPersonalizationEnabled,
    required bool followedBandUpdatesEnabled,
  }) async {
    throw StateError('profile update failed');
  }
}

class _FailingFollowRepository extends DemoRepository {
  _FailingFollowRepository({required super.auth});

  var toggleFollowCalls = 0;

  @override
  Stream<Interactions> myInteractions() => Stream.value(
    const Interactions(
      rsvpGigIds: {},
      followBandIds: {'b1'},
      savedGigIds: {},
      attendedCount: 0,
    ),
  );

  @override
  Future<void> toggleFollow(String bandId) async {
    toggleFollowCalls++;
    throw StateError('follow update failed');
  }
}
