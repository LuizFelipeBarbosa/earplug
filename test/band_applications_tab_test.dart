import 'package:earplug/app_state.dart';
import 'package:earplug/application_tracker.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/application_tracker_bar.dart';
import 'package:earplug/widgets/band_applications_tab.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('submitted applications show summary, applied step, and footer', (
    tester,
  ) async {
    await _pumpTab(tester);

    _expectSummary(tester, active: 1, shortlisted: 0, booked: 0);
    expect(find.text('IN PROGRESS · 1'), findsOneWidget);
    expect(find.textContaining('DECIDED ·'), findsNothing);
    final card = find.byKey(const ValueKey('band-app-app1'));
    final pill = tester.widget<StatusPill>(
      find.descendant(of: card, matching: find.byType(StatusPill)),
    );
    expect(pill.label, 'IN REVIEW');
    expect(pill.tone, EpStatusPillTone.neutral);
    final tracker = _tracker(tester, 'app1');
    expect(tracker.reached, {ApplicationTrackerStep.applied});
    expect(tracker.outcome, ApplicationOutcome.pending);
    final colors = tester.element(card).epColors;
    _expectStepColor(tester, 'app1', 'APPLIED', colors.accent);
    for (final label in ['VIEWED', 'SHORTLISTED', 'DECISION']) {
      _expectStepColor(tester, 'app1', label, colors.contentDisabled);
    }
    expect(find.byKey(const Key('band-app-app1-note')), findsNothing);
    expect(find.textContaining('applications close '), findsOneWidget);
    expect(
      tester
          .widget<EpMonoText>(find.byKey(const Key('applications-footer-hint')))
          .text,
      'Accepted applications move to MY GIGS automatically.',
    );
  });

  testWidgets(
    'shortlisted and declined demo applications show notes and decisions',
    (tester) async {
      final harness = await _pumpTab(tester, bandId: 'b2');

      _expectSummary(tester, active: 1, shortlisted: 1, booked: 0);
      expect(find.text('IN PROGRESS · 1'), findsOneWidget);
      expect(_tracker(tester, 'app2').reached, {
        ApplicationTrackerStep.applied,
        ApplicationTrackerStep.viewed,
        ApplicationTrackerStep.shortlisted,
      });
      final colors = tester.element(find.byType(BandApplicationsTab)).epColors;
      for (final label in ['APPLIED', 'VIEWED', 'SHORTLISTED']) {
        _expectStepColor(tester, 'app2', label, colors.accent);
      }
      final note = tester.widget<EpMonoText>(
        find.byKey(const ValueKey('band-app-app2-note')),
      );
      expect(note.text, contains('Host replied 2h ago — Sound check is at 6'));
      expect(note.text, contains(' · applications close '));

      final reason = find.byKey(const ValueKey('band-app-app3-reason'));
      await tester.ensureVisible(reason);
      await tester.pumpAndSettle();
      expect(find.text('DECIDED · 1'), findsOneWidget);
      final declined = find.byKey(const ValueKey('band-app-app3'));
      expect(
        tester.getTopLeft(find.text('DECIDED · 1')).dy,
        lessThan(tester.getTopLeft(declined).dy),
      );
      final pill = tester.widget<StatusPill>(
        find.descendant(of: declined, matching: find.byType(StatusPill)),
      );
      expect(pill.label, 'DECLINED');
      expect(pill.tone, EpStatusPillTone.neutral);
      _expectStepColor(tester, 'app3', 'DECLINED', colors.destructive);
      expect(
        tester.widget<EpMonoText>(reason).text,
        ApplicationDeclineReason.slotFilled.label,
      );
      expect(_tracker(tester, 'app3').outcome, ApplicationOutcome.declined);
      expect(
        find.descendant(of: declined, matching: find.byType(EpPill)),
        findsNothing,
      );
      expect(
        harness.app.myApplications.map((row) => row.application.id),
        containsAll(['app2', 'app3']),
      );
    },
  );

  testWidgets(
    'withdraw preserves confirmation copy, cancels, then updates both lists',
    (tester) async {
      final harness = await _pumpTab(tester);
      final withdraw = find.byKey(const ValueKey('band-app-app1-withdraw'));
      expect(tester.getSize(withdraw).height, greaterThanOrEqualTo(44));

      await tester.tap(withdraw);
      await tester.pumpAndSettle();
      expect(find.text('Withdraw application?'), findsOneWidget);
      expect(
        find.text(
          'Your band will no longer be considered for this opportunity.',
        ),
        findsOneWidget,
      );
      expect(find.text('CONFIRM'), findsOneWidget);
      await tester.tap(find.text('KEEP'));
      await tester.pumpAndSettle();
      expect(
        harness.app.myApplications.single.application.status,
        ArtistApplicationStatus.submitted,
      );
      expect(tester.widget<EpPill>(withdraw).onPressed, isNotNull);

      // Two taps before the next frame must still open only one dialog.
      await tester.tap(withdraw);
      await tester.tap(withdraw, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('CONFIRM'));
      await tester.pumpAndSettle();

      expect(
        (await harness.app.repository.myApplications(
          'b1',
        )).single.application.status,
        ArtistApplicationStatus.withdrawn,
      );
      expect(
        harness.app.myApplications.single.application.status,
        ArtistApplicationStatus.withdrawn,
      );
      _expectSummary(tester, active: 0, shortlisted: 0, booked: 0);
      expect(find.text('IN PROGRESS · 0'), findsOneWidget);
      expect(find.text('Your applications will appear here.'), findsOneWidget);
      expect(find.text('DECIDED · 1'), findsOneWidget);
      expect(withdraw, findsNothing);
      expect(
        tester
            .widget<EpMonoText>(
              find.byKey(const ValueKey('band-app-app1-reason')),
            )
            .text,
        'You withdrew this application',
      );
      expect(_tracker(tester, 'app1').outcome, ApplicationOutcome.withdrawn);
      expect(
        harness.app.browse.items
                .firstWhere((item) => item.opportunity.id == 'opp1')
                .myApplicationStatus
                ?.isActive ??
            false,
        isFalse,
      );
      expect(harness.app.current.screen, isNot(Screen.opportunityDetail));
    },
  );

  testWidgets(
    'Respond appears only when the matching offer booking has loaded',
    (tester) async {
      final harness = await _pumpTab(tester);
      final repository = harness.app.repository as DemoRepository;
      repository.demoPaymentsEnabled = true;
      await repository.reviewApplication(
        applicationId: 'app1',
        action: ArtistApplicationReviewAction.shortlisted,
      );
      final sent = await repository.sendOffer(
        applicationId: 'app1',
        grossMinor: 0,
        cancellationTemplate: CancellationTemplate.standard,
      );
      await harness.app.refreshMyApplications();
      await tester.pumpAndSettle();

      _expectSummary(tester, active: 1, shortlisted: 1, booked: 0);
      expect(find.text('OFFER RECEIVED'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('band-app-app1-withdraw')),
        findsNothing,
      );
      final respond = find.byKey(const ValueKey('band-app-app1-respond'));
      expect(respond, findsNothing);

      await harness.app.refreshBandBookings();
      await tester.pumpAndSettle();
      expect(respond, findsOneWidget);
      expect(tester.getSize(respond).height, greaterThanOrEqualTo(44));
      await tester.tap(respond);
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.bookingDetail);
      expect(harness.app.current.param, sent.bookingId);
      expect(
        harness.app.bookingById(sent.bookingId)?.viewerSide,
        BookingSide.artist,
      );
    },
  );

  testWidgets(
    'booked applications count in the summary but appear in neither section',
    (tester) async {
      final harness = await _pumpTab(tester);
      final repository = harness.app.repository as DemoRepository;
      await repository.reviewApplication(
        applicationId: 'app1',
        action: ArtistApplicationReviewAction.shortlisted,
      );
      final sent = await repository.sendOffer(
        applicationId: 'app1',
        grossMinor: 0,
        cancellationTemplate: CancellationTemplate.standard,
      );
      await repository.respondToOffer(
        bookingId: sent.bookingId,
        accept: true,
        expectedRevision: sent.revision,
      );
      await harness.app.refreshMyApplications();
      await tester.pumpAndSettle();

      expect(
        harness.app.myApplications.single.application.status,
        ArtistApplicationStatus.booked,
      );
      _expectSummary(tester, active: 0, shortlisted: 0, booked: 1);
      expect(find.byKey(const ValueKey('band-app-app1')), findsNothing);
      expect(find.text('IN PROGRESS · 0'), findsOneWidget);
      expect(find.textContaining('DECIDED ·'), findsNothing);
      expect(find.text('Your applications will appear here.'), findsOneWidget);
    },
  );

  testWidgets('tapping the card opens its opportunity by slug', (tester) async {
    final harness = await _pumpTab(tester);
    await tester.tap(find.byType(EpDisplay).last);
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.opportunityDetail);
    expect(harness.app.current.param, 'friday-night-live');
  });

  testWidgets('pull to refresh reflects a host review', (tester) async {
    final harness = await _pumpTab(tester);
    await harness.app.repository.reviewApplication(
      applicationId: 'app1',
      action: ArtistApplicationReviewAction.underReview,
    );
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();

    expect(_tracker(tester, 'app1').reached, {
      ApplicationTrackerStep.applied,
      ApplicationTrackerStep.viewed,
    });
    expect(find.text('IN REVIEW'), findsOneWidget);
  });

  testWidgets('the tab fits a 390px phone at 1.3x text scale', (tester) async {
    await _pumpTab(tester, bandId: 'b2', textScale: 1.3);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('applications-footer-hint')),
      250,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('applications-footer-hint')), findsOneWidget);
  });

  for (final status in ArtistApplicationStatus.values) {
    testWidgets('350px tracker fits $status at 1.3x and announces its state', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final tracker = ApplicationTracker.of(
          DemoData.artistApplications['app1']!.copyWith(status: status),
        );
        tester.view.physicalSize = const Size(390, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildEpTheme(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 350,
                    child: ApplicationTrackerBar(tracker: tracker),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(ApplicationTrackerBar)).width, 350);
        final colors = tester
            .element(find.byType(ApplicationTrackerBar))
            .epColors;
        final (label, color, spoken) = switch (status) {
          ArtistApplicationStatus.offered => (
            'OFFER',
            colors.accent,
            'offer received',
          ),
          ArtistApplicationStatus.booked => (
            'BOOKED',
            colors.success,
            'booked',
          ),
          ArtistApplicationStatus.declined => (
            'DECLINED',
            colors.destructive,
            'declined',
          ),
          ArtistApplicationStatus.withdrawn => (
            'WITHDRAWN',
            colors.contentSecondary,
            'withdrawn',
          ),
          ArtistApplicationStatus.expired => (
            'EXPIRED',
            colors.contentSecondary,
            'expired',
          ),
          _ => ('DECISION', colors.contentDisabled, 'decision pending'),
        };
        expect(tester.widget<Text>(find.text(label)).style?.color, color);
        final announcement = tester
            .getSemantics(find.byType(ApplicationTrackerBar))
            .label;
        expect(announcement, startsWith('Applied, '));
        expect(announcement, endsWith(spoken));
        if (status == ArtistApplicationStatus.submitted) {
          expect(
            announcement,
            'Applied, viewed pending, shortlisted pending, decision pending',
          );
        }
        final decisionBar = tester
            .widgetList<ColoredBox>(
              find.descendant(
                of: find.byType(ApplicationTrackerBar),
                matching: find.byType(ColoredBox),
              ),
            )
            .last;
        expect(
          decisionBar.color,
          tracker.reached.contains(ApplicationTrackerStep.decision)
              ? color
              : colors.border,
        );
      } finally {
        semantics.dispose();
      }
    });
  }
}

Future<AppHarness> _pumpTab(
  WidgetTester tester, {
  String bandId = 'b1',
  double textScale = 1,
}) async {
  final harness = await pumpApp(
    tester,
    size: const Size(390, 900),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: const Scaffold(body: BandApplicationsTab()),
      ),
    ),
  );
  await harness.auth.signInDemo();
  await tester.pumpAndSettle();
  if (bandId == 'b2') {
    final invite = await harness.app.repository.createBandInvite(bandId);
    await harness.app.repository.acceptBandInvite(invite.token);
    await tester.pumpAndSettle();
  }
  harness.app.switchToBand(bandId);
  await harness.app.refreshMyApplications();
  await tester.pumpAndSettle();
  return harness;
}

void _expectSummary(
  WidgetTester tester, {
  required int active,
  required int shortlisted,
  required int booked,
}) {
  final summary = find.byKey(const Key('applications-summary'));
  expect(
    tester
        .widgetList<EpDisplay>(
          find.descendant(of: summary, matching: find.byType(EpDisplay)),
        )
        .map((text) => text.text),
    ['$active', '$shortlisted', '$booked'],
  );
  expect(
    tester
        .widgetList<EpEyebrow>(
          find.descendant(of: summary, matching: find.byType(EpEyebrow)),
        )
        .map((text) => text.text),
    ['ACTIVE', 'SHORTLISTED', 'BOOKED'],
  );
  expect(
    find.descendant(of: summary, matching: find.byType(ColoredBox)),
    findsNWidgets(2),
  );
}

ApplicationTracker _tracker(WidgetTester tester, String id) => tester
    .widget<ApplicationTrackerBar>(find.byKey(ValueKey('band-app-$id-tracker')))
    .tracker;

void _expectStepColor(
  WidgetTester tester,
  String id,
  String label,
  Color color,
) {
  final text = find.descendant(
    of: find.byKey(ValueKey('band-app-$id-tracker')),
    matching: find.text(label),
  );
  expect(tester.widget<Text>(text).style?.color, color);
}
