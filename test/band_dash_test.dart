import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_dash.dart';
import 'package:earplug/screens/door_mode.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

const _readiness = Key('band-readiness');
const _hero = Key('band-next-up');

const _stepIds = [
  'band-discovery-profile',
  'band-discovery-image',
  'band-discovery-clip',
  'band-discovery-show',
  'band-discovery-listing',
  'band-discovery-revision',
  'band-setup-preview',
  'band-setup-social',
  'band-setup-members',
];

/// The demo band has five steps done; these four are still to do.
const _demoTodo = [
  'band-discovery-image',
  'band-setup-preview',
  'band-setup-social',
  'band-setup-members',
];

const _allMissingSetup = BandSetupStatus(
  profileComplete: false,
  profileImageAdded: false,
  musicAdded: false,
  socialLinksAdded: false,
  firstGigCreated: false,
  membersInvited: false,
  publicProfilePreviewed: false,
);

const _allMissingReadiness = BandDiscoveryReadiness(
  profileComplete: false,
  profileImageReady: false,
  clipReady: false,
  publishedShowReady: false,
  venuePosterReady: false,
  publishedRevisionCurrent: false,
);

Future<void> _tapAfterScroll(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    140,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Finder _rowAction(Key row) =>
    find.descendant(of: find.byKey(row), matching: find.byType(TextButton));

void main() {
  testWidgets('dashboard leads with the hero, then readiness, then manage', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: BandDashScreen()));

    expect(find.text('MANAGING · ADMIN'), findsOne);
    expect(find.byKey(const Key('profile-complete-badge')), findsNothing);
    expect(find.text('DISCOVER'), findsOne);
    expect(find.text('FANS'), findsNothing);
    expect(find.text('NEXT RSVPS'), findsNothing);
    expect(find.text('CLIPS'), findsNothing);
    expect(find.byType(EpStatGrid), findsNothing);

    expect(find.byKey(_hero), findsOne);
    expect(find.text('NEXT UP'), findsOne);
    expect(find.byKey(const Key('band-next-up-when')), findsOne);
    expect(find.text('DOOR MODE'), findsOne);
    expect(find.byKey(const Key('band-next-public-gig')), findsOne);
    expect(find.text('PUBLISH ANOTHER'), findsNothing);

    // Readiness sits directly under the hero, showing only what is left.
    expect(find.byKey(_readiness), findsOne);
    expect(find.text('READINESS'), findsOne);
    expect(find.text('5 OF 9'), findsOne);
    for (var index = 0; index < 9; index++) {
      expect(find.byKey(ValueKey('readiness-segment-$index')), findsOne);
    }
    for (final id in _stepIds) {
      expect(
        find.byKey(ValueKey(id)),
        _demoTodo.contains(id) ? findsOne : findsNothing,
        reason: id,
      );
    }
    final toggle = find.byKey(const Key('band-readiness-toggle'));
    await tester.scrollUntilVisible(
      toggle,
      140,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(of: toggle, matching: find.text('VIEW 5 COMPLETED')),
      findsOne,
    );
    await tester.tap(toggle);
    await tester.pump();
    for (final id in _stepIds) {
      expect(find.byKey(ValueKey(id)), findsOne, reason: id);
    }
    expect(find.text('Complete profile'), findsOne);
    expect(find.text('Add social links'), findsOne);
    expect(find.text('Invite band members'), findsOne);

    // The manage menu follows, without descriptions or stats.
    final manage = find.text('MANAGE');
    await tester.scrollUntilVisible(
      manage,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(manage, findsOne);
    for (final row in [
      'band-command-publish-gig',
      'band-command-add-media',
      'band-command-analytics',
      'band-dash-payouts',
      'band-command-edit-profile',
      'band-command-members',
      'band-public-profile',
    ]) {
      expect(find.byKey(Key(row)), findsOne, reason: row);
      expect(tester.widget<EpMenuRow>(find.byKey(Key(row))).sub, isNull);
    }
    expect(find.text('PUBLISH A GIG'), findsOne);
    expect(find.text('ADD MEDIA'), findsOne);
    expect(find.text('INSIGHTS'), findsOne);
    expect(find.text('PREVIEW PUBLIC PROFILE'), findsOne);
  });

  testWidgets('hero is visible without scrolling on a 390x844 phone', (
    tester,
  ) async {
    await pumpApp(
      tester,
      size: const Size(390, 844),
      home: const Scaffold(body: BandDashScreen()),
    );

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.pixels, 0);
    final hero = tester.getRect(find.byKey(_hero));
    expect(hero.top, greaterThanOrEqualTo(0));
    expect(hero.bottom, lessThanOrEqualTo(844));
    expect(
      tester.getRect(find.byKey(const Key('band-next-door-mode'))).bottom,
      lessThanOrEqualTo(844),
    );
  });

  testWidgets('discover chip uses the accent outline variant', (tester) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandDashScreen()),
    );

    final discover = find.byKey(const Key('band-dash-discover'));
    expect(
      tester.widget<EpPill>(discover).variant,
      EpPillVariant.accentOutline,
    );
    await tester.tap(discover);
    await tester.pump();
    expect(harness.app.current.screen, Screen.home);
  });

  testWidgets('empty hero prompts admins to publish a gig', (tester) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _NoGigsRepository(auth: auth, role: 'admin'),
      home: const Scaffold(body: BandDashScreen()),
    );

    expect(find.byKey(_hero), findsNothing);
    expect(find.byKey(const Key('band-next-up-empty')), findsOne);
    expect(find.text('NOTHING SCHEDULED'), findsOne);
    expect(find.text('NO GIG COMING UP — PUBLISH ONE'), findsOne);
    await tester.tap(find.byKey(const Key('band-next-up-publish')));
    await tester.pump();
    expect(harness.app.current.screen, Screen.gigCreate);
  });

  testWidgets('empty hero offers members no publish action', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _NoGigsRepository(auth: auth, role: 'member'),
      home: const Scaffold(body: BandDashScreen()),
    );

    expect(find.byKey(const Key('band-next-up-empty')), findsOne);
    expect(find.byKey(const Key('band-next-up-publish')), findsNothing);
  });

  testWidgets('role copy and interactive checklist rows meet size floors', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: BandDashScreen()));

    final roleText = tester.widget<Text>(find.text('MANAGING · ADMIN'));
    expect(roleText.style?.fontSize, greaterThanOrEqualTo(11));

    final scrollable = find.byType(Scrollable).first;
    await _tapAfterScroll(
      tester,
      find.byKey(const Key('band-readiness-toggle')),
    );

    for (final row in [
      const ValueKey('band-discovery-profile'),
      const ValueKey('band-setup-members'),
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(row),
        120,
        scrollable: scrollable,
      );
      expect(tester.getSize(find.byKey(row)).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('dashboard profile controls use explicit admin navigation', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandDashScreen()),
    );

    await _tapAfterScroll(
      tester,
      find.byKey(const Key('band-command-edit-profile')),
    );
    expect(harness.app.current.screen, Screen.bandEdit);

    harness.app.returnToBandDashboard();
    await tester.pump();
    await _tapAfterScroll(tester, find.byKey(const Key('band-public-profile')));
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

  for (final size in [const Size(402, 900), const Size(1280, 1100)]) {
    testWidgets('members row opens the band members sheet at $size', (
      tester,
    ) async {
      final auth = FakeAuthService();
      await pumpApp(
        tester,
        size: size,
        auth: auth,
        repository: StubRepository(auth: auth)
          ..returns(
            'bandProfileDetails',
            const BandProfileDetails(memberNames: ['Avery', 'Morgan']),
          ),
        home: const Scaffold(body: BandDashScreen()),
      );

      final row = find.byKey(const Key('band-command-members'));
      await tester.scrollUntilVisible(
        row,
        140,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.widget<EpMenuRow>(row).trailingText, '2');
      await _tapAfterScroll(tester, row);
      await tester.pumpAndSettle();

      final sheet = find.byKey(const Key('band-members-sheet'));
      expect(sheet, findsOne);
      expect(find.text('BAND MEMBERS · 2'), findsOne);
      for (final member in ['Avery', 'Morgan']) {
        expect(
          find.descendant(
            of: sheet,
            matching: find.byKey(ValueKey('accepted-member-$member')),
          ),
          findsOne,
        );
      }
    });
  }

  testWidgets('invitation navigation opens the sheet on dashboard arrival', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandDashScreen()),
      beforePump: (app) => app.openInvitationPanel(),
    );

    expect(harness.app.current.screen, Screen.bandDash);
    expect(harness.app.current.param, 'members');
    expect(harness.app.canGoBack, isFalse);
    final sheet = find.byKey(const Key('band-members-sheet'));
    expect(sheet, findsOne);
    expect(find.byKey(const ValueKey('accepted-member-Band admin')), findsOne);

    Navigator.of(tester.element(sheet)).pop();
    await tester.pumpAndSettle();
    await harness.app.refreshBandInvite('b1');
    await tester.pumpAndSettle();
    expect(harness.app.current.param, 'members');
    expect(sheet, findsNothing);

    harness.app.returnToBandDashboard();
    await tester.pumpAndSettle();
    harness.app.openInvitationPanel();
    await tester.pumpAndSettle();
    expect(sheet, findsOne);
  });

  for (final ticketing in Ticketing.values) {
    testWidgets(
      'dashboard uses the public gig door roster for ${ticketing.name}',
      (tester) async {
        final auth = FakeAuthService();
        final repository = _DoorRepository(auth: auth, ticketing: ticketing);
        await pumpApp(
          tester,
          auth: auth,
          repository: repository,
          home: const Scaffold(body: BandDashScreen()),
        );

        await tester.tap(find.text('DOOR MODE'));
        await tester.pumpAndSettle();

        expect(find.byType(DoorModeScreen), findsOne);
        expect(repository.organizerRosterRequests, ['g2']);
        expect(repository.projectRosterRequests, isEmpty);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('door-organizer-roster')))
              .data,
          'RSVPs 4/17 · Tickets 3/12',
        );
      },
    );
  }

  for (final state in [
    null,
    StripeAccountState.none,
    StripeAccountState.onboarding,
    StripeAccountState.restricted,
    StripeAccountState.enabled,
  ]) {
    testWidgets('payouts row flags unfinished Stripe setup for $state', (
      tester,
    ) async {
      final auth = FakeAuthService();
      final repository = StubRepository(auth: auth);
      if (state == null) {
        repository.wraps<StripeAccountStatus>(
          'bandPayoutStatus',
          (_) => throw StateError('offline'),
        );
      } else {
        repository.returns(
          'bandPayoutStatus',
          StripeAccountStatus(
            state: state,
            hasAccount: state != StripeAccountState.none,
            chargesEnabled: state == StripeAccountState.enabled,
            payoutsEnabled: state == StripeAccountState.enabled,
            detailsSubmitted: state == StripeAccountState.enabled,
            requirementsDue: const [],
            cardPaymentsStatus: state == StripeAccountState.enabled
                ? 'active'
                : null,
          ),
        );
      }
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const Scaffold(body: BandDashScreen()),
        beforePump: (app) => app.switchToBand('b1'),
      );
      expect(harness.app.bandPayoutStatus?.state, state);

      final tile = find.byKey(const Key('band-dash-payouts'));
      await tester.scrollUntilVisible(
        tile,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      final badge = find.descendant(
        of: tile,
        matching: find.byKey(const Key('band-dash-payouts-badge')),
      );
      if (state == StripeAccountState.enabled) {
        expect(badge, findsNothing);
        expect(find.text('SET UP'), findsNothing);
      } else {
        expect(badge, findsOne);
        expect(
          find.descendant(of: badge, matching: find.text('SET UP')),
          findsOne,
        );
      }
      expect(find.text('ENABLED'), findsNothing);
      expect(find.text('FINISH SETUP'), findsNothing);
    });
  }

  testWidgets('readiness module and boost footer draw on the merged data', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: BandDashScreen()));

    expect(find.byKey(_readiness), findsOne);
    expect(find.text('READINESS'), findsOne);
    expect(find.text('5 OF 9'), findsOne);
    expect(find.byType(EpReadinessBar), findsOne);
    // One merged list: the old separate checklist section is gone.
    expect(find.text('SETUP CHECKLIST'), findsNothing);
    expect(find.text('PROFILE COMPLETE'), findsNothing);

    await _tapAfterScroll(
      tester,
      find.byKey(const Key('band-readiness-toggle')),
    );
    expect(find.text('Profile image'), findsOne);
    expect(find.text('Video clip'), findsOne);
    expect(find.text('Public profile previewed'), findsOne);

    final next = find.byKey(const Key('band-boost-next'));
    await tester.scrollUntilVisible(
      next,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<EpMonoText>(next).text,
      'Next eligible · Riptide Release Show',
    );
    expect(
      tester
          .widget<EpMonoText>(find.byKey(const Key('band-boost-window')))
          .text,
      startsWith('Boost window · '),
    );
    expect(find.text('BOOST NOW'), findsNothing);
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
    final window = find.byKey(const Key('band-boost-window'));
    await tester.scrollUntilVisible(
      window,
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.textContaining('ACTIVE NOW'), findsNothing);

    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.textContaining('ACTIVE NOW'), findsOne);
    expect(
      tester.widget<EpMonoText>(window).color,
      tester.element(window).epColors.accent,
    );

    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.textContaining('ACTIVE NOW'), findsNothing);
    expect(repository.readinessCalls, greaterThanOrEqualTo(3));
  });

  testWidgets('a fully ready band shows manage directly under the hero', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returns(
          'bandSetupStatus',
          const BandSetupStatus(
            profileComplete: true,
            profileImageAdded: true,
            musicAdded: true,
            socialLinksAdded: true,
            firstGigCreated: true,
            membersInvited: true,
            publicProfilePreviewed: true,
          ),
        )
        ..returns(
          'bandDiscoveryReadiness',
          const BandDiscoveryReadiness(
            profileComplete: true,
            profileImageReady: true,
            clipReady: true,
            publishedShowReady: true,
            venuePosterReady: true,
            publishedRevisionCurrent: true,
          ),
        ),
      home: const Scaffold(body: BandDashScreen()),
    );

    expect(find.byKey(_readiness), findsNothing);
    expect(find.byKey(const Key('band-readiness-retry')), findsNothing);
    expect(find.byKey(const Key('band-boost-next')), findsNothing);
    final heroBottom = tester.getBottomLeft(find.byKey(_hero)).dy;
    final manageTop = tester.getTopLeft(find.text('MANAGE')).dy;
    expect(manageTop - heroBottom, closeTo(28, 1));
  });

  testWidgets('every readiness action routes to the intended task', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returns('bandSetupStatus', _allMissingSetup)
        ..returns('bandDiscoveryReadiness', _allMissingReadiness),
      home: const Scaffold(body: BandDashScreen()),
    );

    Future<void> expectAction(
      String key,
      Screen screen, {
      String? param,
    }) async {
      await _tapAfterScroll(tester, _rowAction(ValueKey('band-$key')));
      expect(harness.app.current.screen, screen);
      expect(harness.app.current.param, param);
      harness.app.returnToBandDashboard();
      await tester.pump();
    }

    await expectAction('discovery-profile', Screen.bandEdit, param: 'required');
    await expectAction('discovery-image', Screen.bandMedia, param: 'b1');
    await expectAction('discovery-clip', Screen.bandMedia, param: 'b1');
    // No published show yet, so the listing steps start a new gig.
    await expectAction('discovery-show', Screen.gigCreate);
    await expectAction('discovery-listing', Screen.gigCreate);
    await expectAction('discovery-revision', Screen.gigCreate);
    await expectAction('setup-preview', Screen.bandPreview, param: 'b1');
    await expectAction('setup-social', Screen.bandEdit, param: 'links');
    await expectAction('setup-members', Screen.bandDash, param: 'members');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('band-members-sheet')), findsOne);
    expect(find.byKey(const ValueKey('accepted-member-Band admin')), findsOne);
    Navigator.of(
      tester.element(find.byKey(const Key('band-members-sheet'))),
    ).pop();
    await tester.pumpAndSettle();
    harness.app.returnToBandDashboard();
    await tester.pumpAndSettle();

    // The same actions are reachable from the sheet the module opens.
    await _tapAfterScroll(
      tester,
      find.descendant(
        of: find.byKey(_readiness),
        matching: find.text('READINESS'),
      ),
    );
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('band-readiness-sheet'));
    expect(sheet, findsOne);
    final action = find.byKey(
      const ValueKey('readiness-action-band-setup-social'),
    );
    await tester.scrollUntilVisible(
      action,
      140,
      scrollable: find.descendant(of: sheet, matching: find.byType(Scrollable)),
    );
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(harness.app.current.screen, Screen.bandEdit);
    expect(harness.app.current.param, 'links');
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
    expect(find.text('VIEW PUBLIC PROFILE'), findsOne);
    expect(find.byKey(const Key('band-public-profile')), findsOne);
    expect(find.byKey(const Key('band-command-edit-profile')), findsNothing);
    expect(find.byKey(const Key('band-dash-payouts')), findsNothing);
    expect(find.text('DOOR MODE'), findsNothing);
    expect(find.byKey(const Key('band-next-public-gig')), findsOne);
    expect(find.byKey(_readiness), findsNothing);
    expect(find.byKey(const Key('band-readiness-retry')), findsNothing);
    expect(find.byKey(const Key('band-boost-next')), findsNothing);
    expect(find.text('PUBLISH A GIG'), findsNothing);
    expect(repository.setupStatusCalls, 0);

    await tester.tap(find.byKey(const Key('band-public-profile')));
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandPreview);
    expect(harness.app.current.param, 'b1');

    harness.app.openBandEditor();
    expect(harness.app.current.screen, Screen.bandPreview);

    await _tapAfterScroll(
      tester,
      find.byKey(const Key('band-command-members')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('band-members-sheet')), findsOne);
    expect(find.byKey(const ValueKey('accepted-member-Band admin')), findsOne);
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

    expect(find.text('SWITCH IDENTITY'), findsOne);
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
      repository: StubRepository(auth: auth)
        ..returnsStream(
          'myBands',
          () => Stream.value([
            BandMembership(band: DemoData.bands['b1']!, role: 'admin'),
            BandMembership(band: DemoData.bands['b2']!, role: 'member'),
          ]),
        ),
      home: const Scaffold(body: BandDashScreen()),
    );

    await tester.tap(find.text('FOGHORN DIET'));
    await tester.pumpAndSettle();

    expect(find.text('SWITCH IDENTITY'), findsOne);
    expect(find.text('Pigeon Court'), findsOne);
    await tester.tap(find.text('Pigeon Court'));
    await tester.pumpAndSettle();

    expect(harness.app.bandId, 'b2');
    expect(harness.app.current.screen, Screen.bandDash);
  });
}

class _DoorRepository extends DemoRepository {
  _DoorRepository({required super.auth, required this.ticketing});

  final Ticketing ticketing;
  final organizerRosterRequests = <String>[];
  final projectRosterRequests = <String>[];

  @override
  Stream<FeedSnapshot> feed() => super.feed().map(
    (snapshot) => FeedSnapshot(
      gigs: [
        for (final gig in snapshot.gigs)
          gig.id == 'g2' ? gig.copyWith(tix: ticketing) : gig,
      ],
      venues: snapshot.venues,
      bands: snapshot.bands,
    ),
  );

  @override
  Future<DoorCounts> organizerDoorRoster(String gigId) async {
    organizerRosterRequests.add(gigId);
    return const DoorCounts(
      rsvpTotal: 17,
      rsvpCheckedIn: 4,
      ticketsSold: 12,
      ticketsCheckedIn: 3,
      truncated: false,
    );
  }

  @override
  Future<DoorRoster> doorRoster(String projectId) async {
    projectRosterRequests.add(projectId);
    return super.doorRoster(projectId);
  }
}

/// A band with no published gigs, so the hero shows its empty state.
class _NoGigsRepository extends StubRepository {
  _NoGigsRepository({required super.auth, required String role}) {
    returnsStream(
      'feed',
      () => Stream.value(const FeedSnapshot(gigs: [], venues: {}, bands: {})),
    );
    returnsStream(
      'myBands',
      () => Stream.value([
        BandMembership(band: DemoData.bands['b1']!, role: role),
      ]),
    );
  }
}

class _BoundaryReadinessRepository extends StubRepository {
  _BoundaryReadinessRepository({required super.auth, required DateTime now})
    : opensAt = now.add(const Duration(seconds: 2)),
      closesAt = now.add(const Duration(seconds: 4)) {
    returnsStream(
      'feed',
      () => Stream.value(const FeedSnapshot(gigs: [], venues: {}, bands: {})),
    );
    returnsStream(
      'myBands',
      () => Stream.value([
        BandMembership(band: DemoData.bands['b1']!, role: 'admin'),
      ]),
    );
  }

  final DateTime opensAt;
  final DateTime closesAt;
  int readinessCalls = 0;

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

class _MemberRepository extends StubRepository {
  _MemberRepository({required super.auth}) {
    returnsStream(
      'myBands',
      () => Stream.value([
        BandMembership(band: DemoData.bands['b1']!, role: 'member'),
      ]),
    );
  }

  int setupStatusCalls = 0;

  @override
  Future<BandSetupStatus> bandSetupStatus(String bandId) async {
    setupStatusCalls++;
    return super.bandSetupStatus(bandId);
  }
}
