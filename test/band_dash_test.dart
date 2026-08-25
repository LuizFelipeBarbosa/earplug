import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_dash.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  test('band entry labels follow membership count', () {
    expect(bandEntryLabel(0), 'Start a band');
    expect(bandEntryLabel(1), 'Manage band');
    expect(bandEntryLabel(2), 'Switch band');
  });

  testWidgets('dashboard derives remaining tasks from current band data', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: BandDashScreen()));

    expect(find.text('MANAGING · ADMIN'), findsOne);
    expect(find.text('DISCOVER'), findsOne);
    expect(find.text('Edit profile'), findsOne);
    expect(find.text('Preview public profile'), findsNWidgets(2));
    await tester.scrollUntilVisible(
      find.text('SETUP CHECKLIST'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('SETUP CHECKLIST'), findsOne);
    expect(find.text('3 of 7 complete'), findsOne);
    expect(find.text('Complete profile'), findsOne);
    expect(find.text('Add a profile image'), findsOne);
    expect(find.text('Add music or a clip'), findsOne);
    expect(find.text('Add social links'), findsOne);
    expect(find.text('Create first gig'), findsOne);
    expect(find.text('Invite band members'), findsOne);
    expect(find.text('Preview public profile'), findsNWidgets(2));
    expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(4));
  });

  testWidgets('dashboard profile controls use explicit admin navigation', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandDashScreen()),
    );

    await tester.tap(find.text('Edit profile'));
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandEdit);

    harness.app.returnToBandDashboard();
    await tester.pump();
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Preview public profile'),
    );
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandPreview);
    expect(harness.app.current.param, 'b1');
  });

  testWidgets('all seven setup actions route to the intended task', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _SetupRepository(auth: auth),
      home: const Scaffold(body: BandDashScreen()),
    );

    Future<void> expectAction(
      String key,
      Screen screen, {
      String? param,
    }) async {
      final action = find.byKey(ValueKey('band-setup-$key'));
      await tester.scrollUntilVisible(
        action,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(action);
      await tester.pump();
      expect(harness.app.current.screen, screen);
      expect(harness.app.current.param, param);
      harness.app.returnToBandDashboard();
      await tester.pump();
    }

    await expectAction('profile', Screen.bandEdit, param: 'required');
    await expectAction('image', Screen.bandMedia, param: 'b1');
    await expectAction('music', Screen.bandMedia, param: 'b1');
    await expectAction('social', Screen.bandEdit, param: 'links');
    await expectAction('gig', Screen.gigCreate);
    await expectAction('members', Screen.bandEdit, param: 'members');
    await expectAction('preview', Screen.bandPreview, param: 'b1');
  });

  testWidgets('members can use the dashboard without admin setup controls', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _MemberRepository(auth: auth);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandDashScreen()),
    );

    expect(find.text('MANAGING · MEMBER'), findsOne);
    expect(find.text('Preview public profile'), findsOne);
    expect(find.text('Edit profile'), findsNothing);
    expect(find.text('SETUP CHECKLIST'), findsNothing);
    expect(find.text('+ PUBLISH GIG'), findsOne);
    expect(repository.setupStatusCalls, 0);
  });

  testWidgets('single-band switcher uses manage language', (tester) async {
    await pumpApp(tester, home: const Scaffold(body: BandDashScreen()));

    await tester.tap(find.text('FOGHORN DIET ▾'));
    await tester.pumpAndSettle();

    expect(find.text('MANAGE BAND'), findsOne);
    expect(find.text('Personal account'), findsOne);
    expect(find.text('Manage band · admin'), findsOne);
    expect(find.text('START ANOTHER BAND'), findsOne);
  });

  testWidgets('multi-band switcher changes the managed band', (tester) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _MultiBandRepository(auth: auth),
      home: const Scaffold(body: BandDashScreen()),
    );

    await tester.tap(find.text('FOGHORN DIET ▾'));
    await tester.pumpAndSettle();

    expect(find.text('SWITCH BAND'), findsOne);
    expect(find.text('PIGEON COURT'), findsOne);
    await tester.tap(find.text('PIGEON COURT'));
    await tester.pumpAndSettle();

    expect(harness.app.bandId, 'b2');
    expect(harness.app.current.screen, Screen.bandDash);
  });
}

class _MultiBandRepository extends DemoRepository {
  _MultiBandRepository({required super.auth});

  @override
  Stream<List<BandMembership>> myBands() async* {
    yield [
      BandMembership(band: DemoData.bands['b1']!, role: 'admin'),
      BandMembership(band: DemoData.bands['b2']!, role: 'member'),
    ];
  }
}

class _SetupRepository extends DemoRepository {
  _SetupRepository({required super.auth});

  @override
  Future<BandSetupStatus> bandSetupStatus(String bandId) async =>
      const BandSetupStatus(
        profileComplete: true,
        profileImageAdded: false,
        musicAdded: true,
        socialLinksAdded: false,
        firstGigCreated: true,
        membersInvited: false,
        publicProfilePreviewed: true,
      );
}

class _MemberRepository extends DemoRepository {
  _MemberRepository({required super.auth});

  int setupStatusCalls = 0;

  @override
  Stream<List<BandMembership>> myBands() => Stream.value([
    BandMembership(band: DemoData.bands['b1']!, role: 'member'),
  ]);

  @override
  Future<BandSetupStatus> bandSetupStatus(String bandId) async {
    setupStatusCalls++;
    return super.bandSetupStatus(bandId);
  }
}
