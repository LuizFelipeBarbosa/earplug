import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/dispute_sheet.dart';
import 'package:earplug/widgets/ep_sheet.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';

void main() {
  testWidgets('organizer validates text and amount then submits minor units', (
    tester,
  ) async {
    final (:harness, :booking, :repository) = await _openDisputeSheet(
      tester,
      side: BookingSide.organizer,
    );
    expect(find.text('REQUEST A REFUND'), findsOneWidget);
    _expectCategories(tester);
    final amount = find.byKey(const Key('dispute-amount'));
    expect(
      tester.widget<TextField>(amount).controller!.text,
      (booking.paidMinor / 100).toStringAsFixed(2),
    );
    final text = find.byKey(const Key('dispute-text'));
    expect(tester.widget<TextField>(text).minLines, 3);
    expect(tester.widget<TextField>(text).maxLength, 2000);
    expect(find.text('0/2000'), findsOneWidget);
    expectNoFieldInCard(tester);

    for (final invalidText in ['', '  too short  ', 'x' * 2001]) {
      // Set the controller for the upper-bound case to bypass input limiting.
      tester.widget<TextField>(text).controller!.text = invalidText;
      await tester.pump();
      await _submit(tester);
      expect(
        tester
            .widget<InlineFormFeedback>(find.byType(InlineFormFeedback))
            .error,
        'Dispute details must be between 10 and 2000 characters',
      );
      expect(harness.app.disputesFor(booking.id), isEmpty);
      expect(await repository.disputesForBooking(booking.id), isEmpty);
      expect(find.byType(EpFormSheet), findsOneWidget);
    }

    const details = 'The artist left before the agreed end of the set.';
    await tester.enterText(text, '  $details  ');
    for (final invalidAmount in [
      '0',
      '-1',
      '100.06',
      'abc',
      'NaN',
      'Infinity',
    ]) {
      await tester.enterText(amount, invalidAmount);
      await _submit(tester);
      expect(
        tester
            .widget<InlineFormFeedback>(find.byType(InlineFormFeedback))
            .error,
        'The refund amount must be positive and no more than the amount paid',
      );
      expect(await repository.disputesForBooking(booking.id), isEmpty);
      expect(find.byType(EpFormSheet), findsOneWidget);
    }

    final category = find.byKey(
      const Key('dispute-category-late_or_short_set'),
    );
    await tester.ensureVisible(category);
    await tester.tap(category);
    await tester.pumpAndSettle();
    expect(tester.widget<EpChip>(category).active, isTrue);
    await tester.enterText(amount, '25.37');
    await _submit(tester);

    expect(find.byType(EpFormSheet), findsNothing);
    final dispute = harness.app.disputesFor(booking.id).single;
    expect(dispute.side, DisputeSide.organizer);
    expect(dispute.category, DisputeCategory.lateOrShortSet);
    expect(dispute.text, details);
    expect(dispute.requestedRefundMinor, 2537);
    expect(dispute.status, DisputeStatus.open);
    expect(tester.takeException(), isNull);
  });

  testWidgets('artist sees all categories and submits without a refund amount', (
    tester,
  ) async {
    final (:harness, :booking, repository: _) = await _openDisputeSheet(
      tester,
      side: BookingSide.artist,
    );
    expect(find.text('OPEN A DISPUTE'), findsOneWidget);
    expect(find.byKey(const Key('dispute-amount')), findsNothing);
    _expectCategories(tester);
    expect(
      find.text(
        'EarPlug reviews every dispute. Payouts are held until it is resolved.',
      ),
      findsOneWidget,
    );
    expectNoFieldInCard(tester);

    final category = find.byKey(const Key('dispute-category-payment'));
    await tester.ensureVisible(category);
    await tester.tap(category);
    await tester.enterText(find.byKey(const Key('dispute-text')), 'x' * 2000);
    await _submit(tester);

    expect(find.byType(EpFormSheet), findsNothing);
    final dispute = harness.app.disputesFor(booking.id).single;
    expect(dispute.side, DisputeSide.artist);
    expect(dispute.category, DisputeCategory.payment);
    expect(dispute.text.length, 2000);
    expect(dispute.requestedRefundMinor, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'repository errors stay inline and preserve the entered details',
    (tester) async {
      final (:harness, :booking, :repository) = await _openDisputeSheet(
        tester,
        side: BookingSide.organizer,
      );
      await repository.openDispute(
        bookingId: booking.id,
        category: DisputeCategory.noShow,
        text: 'A request opened in another session.',
        requestedRefundMinor: 1000,
      );
      const details = 'Please review the missed performance.';
      final text = find.byKey(const Key('dispute-text'));
      await tester.enterText(text, details);
      await _submit(tester);

      expect(find.byType(EpFormSheet), findsOneWidget);
      expect(
        find.text('This booking already has an open dispute'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(text).controller!.text, details);
      expect(
        tester.widget<EpButton>(find.byKey(const Key('dispute-submit'))).onTap,
        isNotNull,
      );
      expect(await repository.disputesForBooking(booking.id), hasLength(1));
      expect(harness.app.disputesFor(booking.id), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

void _expectCategories(WidgetTester tester) {
  for (final category in DisputeCategory.values) {
    final chip = find.byKey(Key('dispute-category-${category.wireValue}'));
    if (category == DisputeCategory.unknown) {
      expect(chip, findsNothing);
    } else {
      expect(tester.widget<EpChip>(chip).label, category.label.toUpperCase());
      expect(
        tester.widget<EpChip>(chip).active,
        category == DisputeCategory.noShow,
      );
    }
  }
}

Future<void> _submit(WidgetTester tester) async {
  final submit = find.byKey(const Key('dispute-submit'));
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

Future<({AppHarness harness, Booking booking, DemoRepository repository})>
_openDisputeSheet(WidgetTester tester, {required BookingSide side}) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  final repository = DemoRepository(auth: auth)..demoPaymentsEnabled = true;
  final created = await repository.createOpportunity(
    organizationId: 'org1',
    title: 'Dispute sheet show',
    venueId: 'v1',
    startsAt: DateTime.now().subtract(const Duration(hours: 2)),
    slots: const [
      SlotInput(role: SlotRole.headliner, guaranteeMinor: 0, required: true),
    ],
  );
  await repository.openOpportunity(
    opportunityId: created.opportunityId,
    expectedRevision: 1,
  );
  final opportunity = (await repository.opportunity(created.opportunityId))!;
  // The demo gives band admins precedence over organizer membership.
  final bandId = side == BookingSide.organizer ? 'b2' : 'b1';
  final applicationId = await repository.applyToOpportunity(
    opportunityId: opportunity.id,
    slotId: opportunity.slots.single.id,
    bandId: bandId,
    message: 'Ready to play.',
  );
  await repository.reviewApplication(
    applicationId: applicationId,
    action: ArtistApplicationReviewAction.shortlisted,
  );
  final sent = await repository.sendOffer(
    applicationId: applicationId,
    grossMinor: 10005,
    cancellationTemplate: CancellationTemplate.standard,
  );
  await repository.respondToOffer(
    bookingId: sent.bookingId,
    accept: true,
    expectedRevision: sent.revision,
  );
  final payment = (await repository.paymentsForBooking(sent.bookingId)).single;
  final checkout = await repository.startInstallmentCheckout(payment.id);
  await repository.simulateCheckoutCompleted(checkout.sessionId);
  final booking = (await repository.booking(sent.bookingId, viewAs: side))!;
  final harness = await pumpApp(
    tester,
    auth: auth,
    repository: repository,
    beforePump: (app) async {
      if (side == BookingSide.artist) {
        app.switchToBand(bandId);
      } else {
        app.switchToOrganization('org1');
      }
      await app.loadBooking(booking.id, viewAs: side);
    },
    home: Scaffold(
      body: Builder(
        builder: (context) => EpButton(
          'OPEN',
          key: const Key('open-sheet'),
          onTap: () => showEpSheet(
            context,
            (_) =>
                DisputeSheet(app: context.read<AppState>(), booking: booking),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-sheet')));
  await tester.pumpAndSettle();
  return (harness: harness, booking: booking, repository: repository);
}
