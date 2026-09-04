import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_dash.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/accessibility.dart';
import 'support/harness.dart';

void main() {
  testWidgets('dashboard derives remaining tasks from current band data', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: BandDashScreen()));

    expect(find.text('MANAGING · ADMIN'), findsOne);
    expect(find.text('DISCOVER'), findsOne);
    expect(find.text('FANS'), findsOne);
    expect(find.byType(VoltStrip), findsOne);
    expect(find.text('DOOR MODE'), findsOne);
    expect(find.byKey(const Key('band-next-public-gig')), findsOne);
    expect(find.text('PUBLISH GIG'), findsOne);
    expect(find.text('ADD MEDIA'), findsOne);
    expect(find.text('ANALYTICS'), findsOne);
    expect(find.byKey(const Key('band-command-edit-profile')), findsOne);
    expect(find.text('PREVIEW PUBLIC PROFILE →'), findsOne);
    await tester.scrollUntilVisible(
      find.text('SETUP CHECKLIST'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('SETUP CHECKLIST'), findsOne);
    expect(find.text('3 of 7 complete'), findsOne);
    final setup = find.byKey(const Key('band-setup-checklist'));
    for (final label in [
      'Complete profile',
      'Add a profile image',
      'Add music or a clip',
      'Add social links',
      'Create first gig',
      'Invite band members',
      'Preview public profile',
    ]) {
      expect(find.descendant(of: setup, matching: find.text(label)), findsOne);
    }
    expect(
      find.descendant(of: setup, matching: find.byIcon(Icons.check_circle)),
      findsNWidgets(3),
    );
    expect(
      find.descendant(
        of: setup,
        matching: find.byIcon(Icons.radio_button_unchecked),
      ),
      findsNWidgets(4),
    );
  });

  testWidgets('role copy and interactive checklist rows meet size floors', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: BandDashScreen()));

    final roleText = tester.widget<Text>(find.text('MANAGING · ADMIN'));
    expect(roleText.style?.fontSize, greaterThanOrEqualTo(11));

    final scrollable = find.byType(Scrollable).first;
    for (final id in [
      'profile',
      'image',
      'clip',
      'show',
      'listing',
      'revision',
    ]) {
      final row = find.byKey(ValueKey('band-discovery-$id'));
      await tester.scrollUntilVisible(row, 120, scrollable: scrollable);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    }
    for (final id in [
      'profile',
      'image',
      'music',
      'social',
      'gig',
      'members',
      'preview',
    ]) {
      final row = find.byKey(ValueKey('band-setup-$id'));
      await tester.scrollUntilVisible(row, 120, scrollable: scrollable);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('dashboard profile controls use explicit admin navigation', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandDashScreen()),
    );

    final editProfile = find.byKey(const Key('band-command-edit-profile'));
    await tester.scrollUntilVisible(
      editProfile,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(editProfile);
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandEdit);

    harness.app.returnToBandDashboard();
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('PREVIEW PUBLIC PROFILE →'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('PREVIEW PUBLIC PROFILE →'));
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandPreview);
    expect(harness.app.current.param, 'b1');
  });

  testWidgets('Next Up retains the public gig deep link', (tester) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandDashScreen()),
    );

    await tester.tap(find.byKey(const Key('band-next-public-gig')));
    await tester.pump();

    expect(harness.app.current.screen, Screen.gig);
    expect(harness.app.current.param, 'g2');
  });

  testWidgets('discovery readiness is separate from the setup checklist', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: BandDashScreen()));

    final card = find.byKey(const Key('discovery-readiness-card'));
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(card, findsOne);
    expect(find.text('5 of 6 complete'), findsOne);
    for (var index = 0; index < 6; index++) {
      expect(find.byKey(ValueKey('discovery-segment-$index')), findsOne);
    }
    expect(find.text('Assign a valid profile image'), findsOne);
    expect(find.text('Upload a video clip'), findsOne);
    expect(
      find.textContaining('NEXT ELIGIBLE · RIPTIDE RELEASE SHOW'),
      findsOne,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('band-setup-checklist')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('SETUP CHECKLIST'), findsOne);
  });

  testWidgets('discovery readiness requeries at boost window boundaries', (
    tester,
  ) async {
    final auth = FakeAuthService();
    var now = DateTime.utc(2026, 8, 25, 19);
    final repository = _BoundaryReadinessRepository(auth: auth, now: now);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandDashScreen()),
      now: () => now,
    );
    final card = find.byKey(const Key('discovery-readiness-card'));
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining('ACTIVE NOW'), findsNothing);

    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.textContaining('ACTIVE NOW'), findsOne);

    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.textContaining('ACTIVE NOW'), findsNothing);
    expect(repository.readinessCalls, greaterThanOrEqualTo(3));
  });

  testWidgets('profile-complete badge disappears after the bio is cleared', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandDashScreen()),
    );
    expect(find.byKey(const Key('profile-complete-badge')), findsOne);
    final band = harness.app.myBand!;

    await harness.app.saveBandProfile(
      BandProfileUpdate(
        bandId: band.id,
        name: band.name,
        genres: band.genres,
        area: band.area,
        bio: '',
        linkIg: band.linkIg ?? '',
        linkBc: band.linkBc ?? '',
        linkYt: band.linkYt ?? '',
        credits: band.credits ?? '',
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('profile-complete-badge')), findsNothing);
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
        140,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(action);
      await tester.pump();
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
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandDashScreen()),
    );

    expect(find.text('MANAGING · MEMBER'), findsOne);
    expect(find.text('VIEW PUBLIC PROFILE →'), findsOne);
    expect(find.byKey(const Key('band-public-profile')), findsOne);
    expect(find.byKey(const Key('band-command-edit-profile')), findsNothing);
    expect(find.text('DOOR MODE'), findsNothing);
    expect(find.text('SETUP CHECKLIST'), findsNothing);
    expect(find.text('PUBLISH GIG'), findsNothing);
    expect(repository.setupStatusCalls, 0);

    await tester.tap(find.byKey(const Key('band-public-profile')));
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandPreview);
    expect(harness.app.current.param, 'b1');

    harness.app.openBandEditor();
    expect(harness.app.current.screen, Screen.bandPreview);
  });

  testWidgets('single-band switcher lists the managed account', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      home: const Scaffold(body: BandDashScreen()),
    );

    await tester.tap(find.text('FOGHORN DIET'));
    await tester.pumpAndSettle();

    expect(find.text('YOUR ACCOUNTS'), findsOne);
    expect(find.text('Personal account'), findsOne);
    expect(find.text('Manage band · admin'), findsOne);
    expect(find.text('START ANOTHER BAND'), findsOne);
  });

  testWidgets('multi-band switcher changes the managed band', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _MultiBandRepository(auth: auth),
      home: const Scaffold(body: BandDashScreen()),
    );

    await tester.tap(find.text('FOGHORN DIET'));
    await tester.pumpAndSettle();

    expect(find.text('YOUR ACCOUNTS'), findsOne);
    expect(find.text('PIGEON COURT'), findsOne);
    await tester.tap(find.text('PIGEON COURT'));
    await tester.pumpAndSettle();

    expect(harness.app.bandId, 'b2');
    expect(harness.app.current.screen, Screen.bandDash);
  });

  testWidgets('dashboard is usable at increased text scale', (tester) async {
    await pumpApp(tester, home: scaledScreen(const BandDashScreen()));

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
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

class _BoundaryReadinessRepository extends DemoRepository {
  _BoundaryReadinessRepository({required super.auth, required DateTime now})
    : opensAt = now.add(const Duration(seconds: 2)),
      closesAt = now.add(const Duration(seconds: 4));

  final DateTime opensAt;
  final DateTime closesAt;
  int readinessCalls = 0;

  @override
  Stream<FeedSnapshot> feed() =>
      Stream.value(const FeedSnapshot(gigs: [], venues: {}, bands: {}));

  @override
  Stream<List<BandMembership>> myBands() => Stream.value([
    BandMembership(band: DemoData.bands['b1']!, role: 'admin'),
  ]);

  @override
  Future<BandDiscoveryReadiness> bandDiscoveryReadiness(
    String bandId, {
    DateTime? now,
  }) async {
    readinessCalls++;
    final current = now ?? DateTime.now();
    final show = BandDiscoveryShow(
      gigId: 'boundary-gig',
      projectId: 'boundary-project',
      title: 'Boundary Show',
      startsAt: closesAt.subtract(discoveryBoostGrace),
    );
    return BandDiscoveryReadiness(
      profileComplete: true,
      profileImageReady: true,
      clipReady: true,
      publishedShowReady: true,
      venuePosterReady: true,
      publishedRevisionCurrent: true,
      relevantShow: show,
      nextEligibleShow: show,
      boostWindow: DiscoveryBoostWindow(
        opensAt: opensAt,
        closesAt: closesAt,
        active: !current.isBefore(opensAt) && !current.isAfter(closesAt),
      ),
    );
  }
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
