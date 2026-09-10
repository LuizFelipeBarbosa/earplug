import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/opportunity_edit.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';
import 'support/ui_test_helpers.dart';

void main() {
  testWidgets('draft save action stays above the organizer tab bar', (
    tester,
  ) async {
    final harness = await pumpApp(tester, home: const RootShell());
    await enterOrganizer(tester, harness, 'org1');
    harness.app.openOpportunityEditor('opp2');
    await tester.pumpAndSettle();

    expect(find.byType(OpportunityEditScreen), findsOneWidget);
    expect(find.byType(OrganizerTabBar), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('opp-edit-save'))).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(OrganizerTabBar)).top),
    );
  });

  testWidgets('new draft saves explicitly, then opens and locks slots', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'new');
    expect(find.byKey(const Key('opp-edit-venue')), findsOneWidget);
    final originalIds = (await repository.manageOpportunities(
      'org1',
    )).map((opportunity) => opportunity.id).toSet();
    expect(find.byType(StatusPill), findsNothing);
    expect(find.byKey(const Key('opp-edit-open')), findsNothing);
    expect(
      find.descendant(
        of: find.byType(EpCard),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );

    await _enterText(tester, 'opp-edit-title', 'Basement Saturday');
    await _tap(tester, 'opp-edit-venue-v1');
    final date = _futureDate(30);
    await _pickDate(tester, 'opp-edit-date', date);
    await _tap(tester, 'opp-edit-slot-add');
    await _tap(tester, 'opp-edit-slot-0-role-support');
    await _enterText(tester, 'opp-edit-slot-0-guarantee', '150');
    await _enterText(tester, 'opp-edit-slot-0-length', '45');
    await _tap(tester, 'opp-edit-slot-0-required');
    await _pickDate(tester, 'opp-edit-deadline', _futureDate(20));
    await _goToStep(tester, 4);
    await tester.pump(const Duration(seconds: 2));
    expect(
      (await repository.manageOpportunities(
        'org1',
      )).map((opportunity) => opportunity.id).toSet(),
      originalIds,
    );
    expect(_action(tester, 'open').onPrimary, isNull);

    await _tapAction(tester, 'save');
    final saved = (await repository.manageOpportunities(
      'org1',
    )).singleWhere((opportunity) => opportunity.title == 'Basement Saturday');
    expect(saved.status, OpportunityStatus.draft);
    expect(saved.venueId, 'v1');
    expect(saved.startsAt, DateTime(date.year, date.month, date.day, 21));
    expect(saved.doorsAt, DateTime(date.year, date.month, date.day, 20));
    expect(saved.slots.single.role, SlotRole.support);
    expect(saved.slots.single.guaranteeMinor, 15000);
    expect(saved.slots.single.setLengthMin, 45);
    expect(saved.slots.single.required, isTrue);
    expect(
      harness.app
          .opportunitiesFor('org1')
          .any((opportunity) => opportunity.id == saved.id),
      isTrue,
    );
    expect(_action(tester, 'open').onPrimary, isNotNull);

    // OPEN must persist edits made since the explicit save before transitioning.
    await _enterText(tester, 'opp-edit-title', 'Basement Saturday Live');
    await _tapAction(tester, 'open');
    final opened = (await repository.opportunity(saved.id))!;
    expect(opened.status, OpportunityStatus.open);
    expect(opened.title, 'Basement Saturday Live');
    await _goToField(tester, 'opp-edit-slot-0-guarantee');
    await _reveal(tester, find.byKey(const Key('opp-edit-slot-0-guarantee')));
    expect(_field(tester, 'opp-edit-slot-0-guarantee').enabled, isFalse);
    expect(_field(tester, 'opp-edit-slot-0-length').enabled, isFalse);
    expect(
      tester
          .widget<EpChip>(
            find.byKey(const ValueKey('opp-edit-slot-0-role-support')),
          )
          .onTap,
      isNull,
    );
    expect(
      tester
          .widget<SwitchRow>(
            find.byKey(const ValueKey('opp-edit-slot-0-required')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('opp-edit-slot-0-remove')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('opp-edit-slot-add')),
          )
          .onPressed,
      isNull,
    );
    await _reveal(
      tester,
      find.text('Slots are locked once applications are open.'),
    );
    expect(
      find.text('Slots are locked once applications are open.'),
      findsOneWidget,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets('promoter draft without a venue shows a disabled open action', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(
      tester,
      auth,
      repository,
      'new',
      organizationId: 'org3',
    );

    expect(harness.app.currentIsVenueOperator, isFalse);
    expect(find.byKey(const Key('opp-edit-venue')), findsOneWidget);
    expect(_venuePicker(tester).selected.contains('v1'), isFalse);
    await tester.tap(findUiText('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Enter title.'), findsOneWidget);
    expect(find.byKey(const Key('opp-edit-open')), findsNothing);

    await _disposeApp(tester, harness.app);
  });

  testWidgets('promoters search verified managed venues on a new draft', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(
      tester,
      auth,
      repository,
      'new',
      organizationId: 'org3',
    );
    await _openVenuePicker(tester);
    expect(
      findUiText('The Foghorn Club · Mission, San Francisco'),
      findsOneWidget,
    );
    expect(find.textContaining('Nightcrawler'), findsNothing);
    await tester.enterText(find.byType(TextField).last, '  FOGHORN  ');
    await tester.pumpAndSettle();
    expect(find.textContaining('The Foghorn Club'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Nightcrawler');
    await tester.pumpAndSettle();
    expect(find.textContaining('The Foghorn Club'), findsNothing);
    await tester.enterText(find.byType(TextField).last, '  MISSION  ');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('The Foghorn Club'));
    await tester.pumpAndSettle();
    expect(_venuePicker(tester).selected, {'v1'});
    expectNoFieldInCard(tester);
    await _disposeApp(tester, harness.app);
  });

  testWidgets('withdrawing pending approval unlocks the venue and dates', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(
      tester,
      auth,
      repository,
      'opp-promoter',
      organizationId: 'org3',
    );
    expect(_venuePicker(tester).onChanged != null, isFalse);
    expect(_venuePicker(tester).onChanged, isNull);
    final card = find.byKey(const Key('opp-edit-venue-approval'));
    await _reveal(tester, card);
    expect(
      find.descendant(of: card, matching: findUiText('PENDING APPROVAL')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<EpButton>(find.byKey(const Key('opp-edit-withdraw-approval')))
          .onTap,
      isNotNull,
    );
    expect(find.byKey(const Key('opp-edit-request-approval')), findsNothing);
    expect(_action(tester, 'open').primaryLabel, 'WAITING FOR VENUE APPROVAL');
    expect(_action(tester, 'open').onPrimary, isNull);
    await _goToField(tester, 'opp-edit-date');
    await _reveal(tester, find.byKey(const Key('opp-edit-date')));
    for (final key in ['date', 'doors', 'start', 'deadline']) {
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(Key('opp-edit-$key')))
            .onPressed,
        isNull,
      );
    }

    await _tap(tester, 'opp-edit-withdraw-approval');
    expect(await repository.venueConsentForOpportunity('opp-promoter'), isNull);
    await _reveal(tester, card);
    expect(
      find.descendant(of: card, matching: findUiText('NOT REQUESTED')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('opp-edit-withdraw-approval')), findsNothing);
    expect(
      tester
          .widget<EpButton>(find.byKey(const Key('opp-edit-request-approval')))
          .onTap,
      isNotNull,
    );
    await _goToField(tester, 'opp-edit-date');
    await _reveal(tester, find.byKey(const Key('opp-edit-date')));
    for (final key in ['date', 'doors', 'start', 'deadline']) {
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(Key('opp-edit-$key')))
            .onPressed,
        isNotNull,
      );
    }
    await _goToField(tester, 'opp-edit-venue');
    await _reveal(tester, find.byKey(const Key('opp-edit-venue')));
    expect(_venuePicker(tester).onChanged != null, isTrue);
    expect(_venuePicker(tester).onChanged, isNotNull);
    expect(_action(tester, 'open').onPrimary, isNull);
    await _disposeApp(tester, harness.app);
  });

  testWidgets('a newly saved promoter draft requests approval with a message', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(
      tester,
      auth,
      repository,
      'new',
      organizationId: 'org3',
    );
    await _enterText(tester, 'opp-edit-title', 'Promoter showcase');
    await _tap(tester, 'opp-edit-venue-v1');
    await _pickDate(tester, 'opp-edit-date', _futureDate(40));
    await _tapAction(tester, 'save');
    final saved = (await repository.manageOpportunities(
      'org3',
    )).singleWhere((opportunity) => opportunity.title == 'Promoter showcase');
    await _tap(tester, 'opp-edit-slot-add');
    await _goToStep(tester, 4);
    await _tap(tester, 'opp-edit-request-approval');
    final message = find.byKey(const Key('opp-edit-approval-message'));
    final submit = find.byKey(const Key('opp-edit-send-approval'));
    expectNoFieldInCard(tester);
    await tester.enterText(message, '  Please reserve the stage.  ');
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final consent = await repository.venueConsentForOpportunity(saved.id);
    expect(consent?.message, 'Please reserve the stage.');
    expect(consent?.status, VenueConsentStatus.pending);
    expect(message, findsNothing);
    await _goToField(tester, 'opp-edit-venue-approval');
    await _reveal(tester, find.byKey(const Key('opp-edit-venue-approval')));
    expect(findUiText('PENDING APPROVAL'), findsOneWidget);
    expect(find.byKey(const Key('opp-edit-withdraw-approval')), findsOneWidget);
    await _goToField(tester, 'opp-edit-title');
    await _reveal(tester, find.byKey(const Key('opp-edit-title')));
    expect(
      _field(tester, 'opp-edit-title').controller!.text,
      'Promoter showcase',
    );
    await _goToStep(tester, 4);
    expect(_action(tester, 'open').onPrimary, isNull);
    await _disposeApp(tester, harness.app);
  });

  testWidgets('a failed approval request preserves the message for retry', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    await repository.withdrawVenueConsent('consent-1');
    final harness = await _pumpEditor(
      tester,
      auth,
      repository,
      'opp-promoter',
      organizationId: 'org3',
    );
    await _tap(tester, 'opp-edit-request-approval');
    final message = find.byKey(const Key('opp-edit-approval-message'));
    final submit = find.byKey(const Key('opp-edit-send-approval'));
    final tooLong = List.filled(1001, 'x').join();
    await tester.enterText(message, tooLong);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(message).controller!.text, tooLong);
    expect(tester.widget<EpButton>(submit).onTap, isNotNull);
    expect(await repository.venueConsentForOpportunity('opp-promoter'), isNull);

    await tester.enterText(message, '   ');
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final consent = await repository.venueConsentForOpportunity('opp-promoter');
    expect(consent?.status, VenueConsentStatus.pending);
    expect(consent?.message, isNull);
    expect(message, findsNothing);
    await _disposeApp(tester, harness.app);
  });

  testWidgets(
    'granted approval enables opening while venue and dates stay locked',
    (tester) async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      await repository.decideVenueConsent(
        consentId: 'consent-1',
        granted: true,
      );
      final harness = await _pumpEditor(
        tester,
        auth,
        repository,
        'opp-promoter',
        organizationId: 'org3',
      );
      await _goToField(tester, 'opp-edit-venue-approval');
      await _reveal(tester, find.byKey(const Key('opp-edit-venue-approval')));
      expect(findUiText('APPROVED'), findsOneWidget);
      expect(find.byKey(const Key('opp-edit-request-approval')), findsNothing);
      expect(
        find.byKey(const Key('opp-edit-withdraw-approval')),
        findsOneWidget,
      );
      expect(_action(tester, 'open').primaryLabel, 'OPEN FOR APPLICATIONS');
      expect(_action(tester, 'open').onPrimary, isNotNull);
      await _goToField(tester, 'opp-edit-date');
      await _reveal(tester, find.byKey(const Key('opp-edit-date')));
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('opp-edit-date')))
            .onPressed,
        isNull,
      );
      await _tapAction(tester, 'open');
      expect(
        (await repository.opportunity('opp-promoter'))!.status,
        OpportunityStatus.open,
      );
      expect(_action(tester, 'close').onPrimary, isNotNull);
      await _goToField(tester, 'opp-edit-venue-approval');
      await _reveal(tester, find.byKey(const Key('opp-edit-venue-approval')));
      expect(find.byKey(const Key('opp-edit-withdraw-approval')), findsNothing);
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets(
    'paid ticketing discloses the configured percentage and fixed fee',
    (tester) async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      final harness = await _pumpEditor(tester, auth, repository, 'opp2');
      await _tap(tester, 'opp-edit-ticketing-paid');
      expect(
        tester
            .widget<EpChip>(find.byKey(const Key('opp-edit-ticketing-paid')))
            .active,
        isTrue,
      );
      final caption = find.text(
        r'Fans pay the EarPlug fee (5% + $1.00) on top · '
        'you receive the ticket price minus Stripe processing',
      );
      await _reveal(tester, caption);

      expect(caption, findsOneWidget);
      await _disposeApp(tester, harness.app);
    },
  );

  for (final fails in [false, true]) {
    testWidgets(
      'paid ticketing keeps its caption while fees load and ${fails ? 'fail' : 'are unconfigured'}',
      (tester) async {
        final auth = FakeAuthService();
        final repository = _FeeRatesRepository(auth: auth);
        final harness = await _pumpEditor(tester, auth, repository, 'opp2');
        await _tap(tester, 'opp-edit-ticketing-paid');
        final caption = find.text(
          'Fans pay the EarPlug fee on top · '
          'you receive the ticket price minus Stripe processing',
        );
        await _reveal(tester, caption);

        expect(caption, findsOneWidget);
        expect(repository.feeOrganizationId, harness.app.organizationId);
        expect(_field(tester, 'opp-edit-ticket-price').enabled, isTrue);

        if (fails) {
          repository.feeResult.completeError(StateError('Fees unavailable'));
        } else {
          repository.feeResult.complete(
            const FeeRates(
              bookingCommissionBps: 1000,
              ticketingFeeBps: 500,
              ticketingFeeFixedMinor: 100,
              configured: false,
            ),
          );
        }
        await tester.pumpAndSettle();

        expect(caption, findsOneWidget);
        expect(_field(tester, 'opp-edit-ticket-price').enabled, isTrue);
        expect(find.text('Fees unavailable'), findsNothing);
        expect(tester.takeException(), isNull);
        await _disposeApp(tester, harness.app);
      },
    );
  }

  testWidgets('paid tickets save dollar prices and validate before opening', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp2');
    await _enterText(tester, 'opp-edit-title', 'Paid Saturday');
    await _tap(tester, 'opp-edit-venue-v1');
    await _pickDate(tester, 'opp-edit-date', _futureDate(30));
    await _goToField(tester, 'opp-edit-ticketing-paid');
    await _reveal(tester, find.byKey(const Key('opp-edit-ticketing-paid')));

    for (final ticketing in ['none', 'rsvp', 'external', 'paid']) {
      expect(
        find.byKey(ValueKey('opp-edit-ticketing-$ticketing')),
        findsOneWidget,
      );
    }
    expect(find.byKey(const ValueKey('opp-edit-ticket-price')), findsNothing);
    expect(
      find.byKey(const ValueKey('opp-edit-ticket-capacity')),
      findsNothing,
    );
    expect(
      tester
          .widget<EpChip>(find.byKey(const ValueKey('opp-edit-ticketing-paid')))
          .onTap,
      isNotNull,
    );
    await _tap(tester, 'opp-edit-ticketing-paid');
    expect(_field(tester, 'opp-edit-ticket-price').enabled, isTrue);
    expect(_field(tester, 'opp-edit-ticket-capacity').enabled, isTrue);
    expect(_field(tester, 'opp-edit-ticket-price').controller!.text, isEmpty);
    expect(
      _field(tester, 'opp-edit-ticket-capacity').controller!.text,
      isEmpty,
    );
    expect(find.byKey(const ValueKey('opp-edit-external-url')), findsNothing);
    await _tapAction(tester, 'save');
    expect(find.text('Needs: ticket price, ticket capacity'), findsWidgets);
    expect(
      (await repository.manageOpportunities(
        'org1',
      )).where((opportunity) => opportunity.title == 'Paid Saturday'),
      isEmpty,
    );

    await _enterText(tester, 'opp-edit-ticket-price', '25');
    await _enterText(tester, 'opp-edit-ticket-capacity', '100');
    await _tapAction(tester, 'save');
    final saved = (await repository.manageOpportunities(
      'org1',
    )).singleWhere((opportunity) => opportunity.title == 'Paid Saturday');
    expect(saved.ticketing, OpportunityTicketing.paid);
    expect(saved.ticketPriceMinor, 2500);
    expect(saved.ticketCapacity, 100);
    expect(saved.ticketCurrency, 'usd');
    expect(_action(tester, 'open').onPrimary, isNotNull);

    for (final price in ['0.99', 'NaN', 'Infinity', '1e308']) {
      await _enterText(tester, 'opp-edit-ticket-price', price);
      expect(
        find.text('Enter a ticket price of at least \$1.00.'),
        findsOneWidget,
      );
      expect(_action(tester, 'open').onPrimary, isNull);
      await _tapAction(tester, 'save');
      expect(find.text('Needs: ticket price'), findsWidgets);
      expect(
        (await repository.opportunity(saved.id))!.revision,
        saved.revision,
      );
    }
    await _enterText(tester, 'opp-edit-ticket-price', '25');
    for (final capacity in ['0', '6000', '1.5']) {
      await _enterText(tester, 'opp-edit-ticket-capacity', capacity);
      expect(find.text('Enter a whole number from 1 to 5000.'), findsOneWidget);
      expect(_action(tester, 'open').onPrimary, isNull);
      await _tapAction(tester, 'save');
      expect(find.text('Needs: ticket capacity'), findsWidgets);
      final unchanged = (await repository.opportunity(saved.id))!;
      expect(unchanged.revision, saved.revision);
      expect(unchanged.status, OpportunityStatus.draft);
    }

    // Invalid paid inputs do not constrain other ticketing modes.
    for (final ticketing in ['external', 'none', 'rsvp']) {
      await _tap(tester, 'opp-edit-ticketing-$ticketing');
      expect(find.byKey(const ValueKey('opp-edit-ticket-price')), findsNothing);
      expect(
        find.byKey(const ValueKey('opp-edit-ticket-capacity')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('opp-edit-external-url')),
        ticketing == 'external' ? findsOneWidget : findsNothing,
      );
      expect(_action(tester, 'open').onPrimary, isNotNull);
    }
    await _tapAction(tester, 'save');
    expect(
      (await repository.opportunity(saved.id))!.ticketing,
      OpportunityTicketing.rsvp,
    );

    await _tap(tester, 'opp-edit-ticketing-paid');
    await _enterText(tester, 'opp-edit-ticket-price', '25.505');
    await _enterText(tester, 'opp-edit-ticket-capacity', '100');
    await _tapAction(tester, 'open');
    final opened = (await repository.opportunity(saved.id))!;
    expect(opened.status, OpportunityStatus.open);
    expect(opened.ticketing, OpportunityTicketing.paid);
    expect(opened.ticketPriceMinor, 2551);
    expect(opened.ticketCapacity, 100);
    expect(opened.ticketCurrency, 'usd');
    await _disposeApp(tester, harness.app);
  });

  for (final price in [2500, 2550]) {
    testWidgets('paid ticket fields hydrate $price minor units', (
      tester,
    ) async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      final fixture = (await repository.opportunity('opp2'))!;
      await repository.updateOpportunity(
        opportunityId: fixture.id,
        expectedRevision: fixture.revision,
        ticketing: OpportunityTicketing.paid,
        ticketPriceMinor: price,
        ticketCapacity: 100,
        ticketCurrency: 'usd',
      );
      if (price == 2550) await repository.cancelOpportunity(fixture.id);
      final harness = await _pumpEditor(tester, auth, repository, fixture.id);
      await _goToField(tester, 'opp-edit-ticket-price');
      await _reveal(tester, find.byKey(const Key('opp-edit-ticket-price')));
      expect(
        _field(tester, 'opp-edit-ticket-price').controller!.text,
        price == 2500 ? '25' : '25.50',
      );
      expect(
        _field(tester, 'opp-edit-ticket-capacity').controller!.text,
        '100',
      );
      expect(_field(tester, 'opp-edit-ticket-price').enabled, price == 2500);
      expect(_field(tester, 'opp-edit-ticket-capacity').enabled, price == 2500);
      expect(
        tester
            .widget<EpChip>(
              find.byKey(const ValueKey('opp-edit-ticketing-paid')),
            )
            .onTap,
        price == 2500 ? isNotNull : isNull,
      );
      await _disposeApp(tester, harness.app);
    });
  }

  testWidgets('paid ticketing requires Stripe charges to be enabled', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = StubRepository(auth: auth)
      ..wraps<OrganizationDashboard>('organizationDashboard', (real) {
        final verification = real.verification;
        return OrganizationDashboard(
          organization: real.organization,
          role: real.role,
          viaPlatformAdmin: real.viaPlatformAdmin,
          verification: OrganizationVerification(
            verified: verification.verified,
            stripeDetailsSubmitted: verification.stripeDetailsSubmitted,
            stripeChargesEnabled: false,
            stripePayoutsEnabled: verification.stripePayoutsEnabled,
            profileComplete: verification.profileComplete,
            teamInvited: verification.teamInvited,
          ),
          venues: real.venues,
          memberCount: real.memberCount,
          privateDetails: real.privateDetails,
        );
      });
    final harness = await _pumpEditor(tester, auth, repository, 'opp2');
    await _goToField(tester, 'opp-edit-ticketing-paid');
    await _reveal(tester, find.byKey(const Key('opp-edit-ticketing-paid')));
    expect(
      tester
          .widget<EpChip>(find.byKey(const ValueKey('opp-edit-ticketing-paid')))
          .onTap,
      isNull,
    );
    expect(
      find.text('Connect Stripe in SETTINGS to sell tickets'),
      findsOneWidget,
    );
    await _tap(tester, 'opp-edit-ticketing-paid');
    expect(find.byKey(const ValueKey('opp-edit-ticket-price')), findsNothing);
    expect(
      find.byKey(const ValueKey('opp-edit-ticket-capacity')),
      findsNothing,
    );
    expect(
      tester
          .widget<EpChip>(find.byKey(const ValueKey('opp-edit-ticketing-rsvp')))
          .onTap,
      isNotNull,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets('existing open opportunity is prefilled, saves and closes', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final fixture = (await repository.opportunity('opp1'))!;
    final harness = await _pumpEditor(tester, auth, repository, 'opp1');
    expect(_field(tester, 'opp-edit-title').controller!.text, fixture.title);
    expect(_venuePicker(tester).selected, {'v1'});
    expect(_venuePicker(tester).onChanged, isNull);
    await _goToField(tester, 'opp-edit-desc');
    await _reveal(tester, find.byKey(const Key('opp-edit-desc')));
    expect(_field(tester, 'opp-edit-desc').controller!.text, fixture.desc);
    await _enterText(
      tester,
      'opp-edit-desc',
      'Updated backline and load-in details.',
    );
    await _tapAction(tester, 'save');
    final updated = (await repository.opportunity('opp1'))!;
    expect(updated.desc, 'Updated backline and load-in details.');
    expect(updated.slots.map((slot) => slot.id), [
      'opp1-headliner',
      'opp1-support',
    ]);
    await _tapAction(tester, 'close');
    expect(
      (await repository.opportunity('opp1'))!.status,
      OpportunityStatus.applicationsClosed,
    );
    expect(_action(tester, 'reopen').onPrimary, isNotNull);
    expect(
      harness.app
          .opportunitiesFor('org1')
          .singleWhere((opportunity) => opportunity.id == 'opp1')
          .status,
      OpportunityStatus.applicationsClosed,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets('delete draft removes it and navigates back', (tester) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp2');
    await _goToField(tester, 'opp-edit-delete');
    await _reveal(tester, find.byKey(const Key('opp-edit-delete')));
    // DangerZone's caption makes its center fall outside the actual button.
    await tester.tap(findUiControl(TextButton, 'DELETE DRAFT'));
    await tester.pumpAndSettle();
    expect(await repository.opportunity('opp2'), isNull);
    expect(harness.app.current.screen, Screen.orgDash);
    expect(harness.app.canGoBack, isFalse);
    expect(
      harness.app
          .opportunitiesFor('org1')
          .any((opportunity) => opportunity.id == 'opp2'),
      isFalse,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets('saved opportunities invite and remove bands immediately', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp1');
    final band = (await repository.band('b1'))!;
    await _invite(tester, band);
    final chipFinder = find.byKey(const ValueKey('opp-edit-invite-b1'));
    await _reveal(tester, chipFinder);
    expect(tester.widget<EpChip>(chipFinder).label, band.name);
    expect(
      (await repository.opportunity('opp1'))!.invitedBandIds,
      contains('b1'),
    );
    await _removeInvite(tester, 'b1');
    expect(
      (await repository.opportunity('opp1'))!.invitedBandIds,
      isNot(contains('b1')),
    );
    expect(chipFinder, findsNothing);
    await _disposeApp(tester, harness.app);
  });

  testWidgets(
    'revision conflict reloads the last saved fields and shows feedback',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _ConflictOnceRepository(auth: auth);
      final harness = await _pumpEditor(tester, auth, repository, 'opp1');
      await _enterText(tester, 'opp-edit-title', 'First saved title');
      await _tapAction(tester, 'save');
      expect(
        (await repository.opportunity('opp1'))!.title,
        'First saved title',
      );
      await _enterText(tester, 'opp-edit-title', 'Conflicting title');
      await _tapAction(tester, 'save');
      expect(find.byKey(const ValueKey('opp-edit-feedback')), findsOneWidget);
      expect(find.textContaining('changed elsewhere'), findsOneWidget);
      await _goToField(tester, 'opp-edit-title');
      await _reveal(tester, find.byKey(const Key('opp-edit-title')));
      expect(
        _field(tester, 'opp-edit-title').controller!.text,
        'First saved title',
      );
      await _enterText(tester, 'opp-edit-title', 'Recovered title');
      await _tapAction(tester, 'save');
      expect((await repository.opportunity('opp1'))!.title, 'Recovered title');
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets('unsaved invitations stay local and leaving creates no draft', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'new');
    final originalCount = (await repository.manageOpportunities('org1')).length;
    await _enterText(tester, 'opp-edit-title', 'Never saved');
    await _tap(tester, 'opp-edit-venue-v1');
    await _pickDate(tester, 'opp-edit-date', _futureDate(30));
    await _tap(tester, 'opp-edit-slot-add');
    await _invite(tester, (await repository.band('b1'))!);
    await tester.pump(const Duration(seconds: 2));
    expect(
      (await repository.manageOpportunities('org1')).length,
      originalCount,
    );
    await _reveal(tester, find.byType(CircleIconButton));
    await tester.tap(find.byType(CircleIconButton));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await _enterText(tester, 'opp-edit-title', 'Never saved');
    expect(_field(tester, 'opp-edit-title').controller!.text, 'Never saved');
    await tester.ensureVisible(find.byType(CircleIconButton));
    await tester.tap(find.byType(CircleIconButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.orgDash);
    expect(
      (await repository.manageOpportunities('org1')).length,
      originalCount,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets('save needs only core fields and flushes queued invites', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'new');
    final originalCount = (await repository.manageOpportunities('org1')).length;
    await _tapAction(tester, 'save');
    expect(find.text('Needs: title, venue, date'), findsOneWidget);
    expect(
      (await repository.manageOpportunities('org1')).length,
      originalCount,
    );
    await _enterText(tester, 'opp-edit-title', 'Minimal draft');
    await _tap(tester, 'opp-edit-venue-v1');
    await _pickDate(tester, 'opp-edit-date', _futureDate(30));
    await _tap(tester, 'opp-edit-slot-add');
    // Saving is allowed even when the deadline would prevent opening.
    await _pickDate(tester, 'opp-edit-deadline', _futureDate(31));
    await _invite(tester, (await repository.band('b1'))!);
    await _invite(tester, (await repository.band('b2'))!);
    await _removeInvite(tester, 'b2');
    await _tapAction(tester, 'save');
    final saved = (await repository.manageOpportunities(
      'org1',
    )).singleWhere((opportunity) => opportunity.title == 'Minimal draft');
    expect(saved.status, OpportunityStatus.draft);
    expect(saved.invitedBandIds, ['b1']);
    expect(find.byKey(const Key('opp-edit-open')), findsNothing);
    expect(find.byKey(const Key('opp-edit-open')), findsNothing);
    await tester.tap(findUiText('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text('Choose an application deadline before the event starts.'),
      findsOneWidget,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets(
    'closed applications validate and reopen with the chosen deadline',
    (tester) async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      await repository.closeOpportunityApplications('opp1');
      final harness = await _pumpEditor(tester, auth, repository, 'opp1');
      final fixture = (await repository.opportunity('opp1'))!;
      await _pickDate(
        tester,
        'opp-edit-deadline',
        fixture.startsAt.add(const Duration(days: 1)),
      );
      await _tapAction(tester, 'reopen');
      expect(find.text('Needs: deadline before start'), findsWidgets);
      expect(
        (await repository.opportunity('opp1'))!.status,
        OpportunityStatus.applicationsClosed,
      );
      final deadline = _futureDate(7);
      await _pickDate(tester, 'opp-edit-deadline', deadline);
      await _tapAction(tester, 'reopen');
      final reopened = (await repository.opportunity('opp1'))!;
      expect(reopened.status, OpportunityStatus.open);
      expect(reopened.applicationsCloseAt, deadline);
      // A later save uses the revision returned by the transition's reload.
      await _enterText(tester, 'opp-edit-title', 'Reopened show');
      await _tapAction(tester, 'save');
      expect((await repository.opportunity('opp1'))!.title, 'Reopened show');
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets('cancellation requires confirmation and navigates back', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp1');
    await _goToField(tester, 'opp-edit-cancel');
    await _reveal(tester, find.byKey(const Key('opp-edit-cancel')));
    await tester.tap(findUiControl(TextButton, 'CANCEL OPPORTUNITY'));
    await tester.pumpAndSettle();
    await tester.tap(findUiControl(TextButton, 'KEEP'));
    await tester.pumpAndSettle();
    expect(
      (await repository.opportunity('opp1'))!.status,
      OpportunityStatus.open,
    );
    await tester.tap(findUiControl(TextButton, 'CANCEL OPPORTUNITY'));
    await tester.pumpAndSettle();
    await tester.tap(findUiControl(FilledButton, 'Cancel opportunity'));
    await tester.pumpAndSettle();
    expect(
      (await repository.opportunity('opp1'))!.status,
      OpportunityStatus.cancelled,
    );
    expect(harness.app.current.screen, Screen.orgDash);
    await _disposeApp(tester, harness.app);
  });

  testWidgets(
    'loaded invitations show band names and terminal fields are read only',
    (tester) async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      await repository.cancelOpportunity('opp3');
      final harness = await _pumpEditor(tester, auth, repository, 'opp3');
      expect(_field(tester, 'opp-edit-title').enabled, isFalse);
      expect(find.byType(StickyActionBar), findsNothing);
      final chipFinder = find.byKey(const ValueKey('opp-edit-invite-b1'));
      await _reveal(tester, chipFinder);
      final chip = tester.widget<EpChip>(chipFinder);
      expect(chip.label, (await repository.band('b1'))!.name);
      expect(chip.onRemoved, isNull);
      expect(find.byType(DangerZone), findsNothing);
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets(
    'ticket price and capacity stay editable on a confirmed paid opportunity, everything else is locked',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _ConfirmedPaidOpportunityRepository(auth: auth);
      final harness = await _pumpEditor(tester, auth, repository, 'opp1');

      expect(_field(tester, 'opp-edit-title').enabled, isFalse);
      await _goToField(tester, 'opp-edit-ticketing-paid');
      await _reveal(tester, find.byKey(const Key('opp-edit-ticketing-paid')));
      expect(
        tester
            .widget<EpChip>(find.byKey(const Key('opp-edit-ticketing-paid')))
            .onTap,
        isNull,
      );
      await _goToField(tester, 'opp-edit-ticket-price');
      await _reveal(tester, find.byKey(const Key('opp-edit-ticket-price')));
      expect(_field(tester, 'opp-edit-ticket-price').enabled, isTrue);
      expect(_field(tester, 'opp-edit-ticket-capacity').enabled, isTrue);
      await _goToField(tester, 'opp-edit-update-ticketing');
      await _reveal(tester, find.byKey(const Key('opp-edit-update-ticketing')));
      expect(
        find.byKey(const Key('opp-edit-update-ticketing')),
        findsOneWidget,
      );
      expect(find.byType(StickyActionBar), findsNothing);
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets(
    'update ticketing submits the new price and capacity for the current revision',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _ConfirmedPaidOpportunityRepository(auth: auth);
      final harness = await _pumpEditor(tester, auth, repository, 'opp1');

      await _enterText(tester, 'opp-edit-ticket-price', '30');
      await _enterText(tester, 'opp-edit-ticket-capacity', '55');
      await _tap(tester, 'opp-edit-update-ticketing');

      expect(repository.lastTicketingUpdate, (
        opportunityId: 'opp1',
        expectedRevision: 1,
        ticketPriceMinor: 3000,
        ticketCapacity: 55,
      ));
      expect(find.text('Ticketing updated.'), findsOneWidget);
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets('update ticketing surfaces the server error', (tester) async {
    final auth = FakeAuthService();
    final repository = _ConfirmedPaidOpportunityRepository(
      auth: auth,
      failNextTicketingUpdate: true,
    );
    final harness = await _pumpEditor(tester, auth, repository, 'opp1');

    await _tap(tester, 'opp-edit-update-ticketing');

    expect(
      find.text('Capacity cannot go below tickets already sold or held'),
      findsOneWidget,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets(
    'a non-paid confirmed opportunity has no update-ticketing button',
    (tester) async {
      final auth = FakeAuthService();
      final repository = StubRepository(auth: auth)
        ..wraps<Opportunity?>('opportunity', (real) {
          if (real == null || real.id != 'opp1') return real;
          return real.copyWith(status: OpportunityStatus.booking);
        });
      final harness = await _pumpEditor(tester, auth, repository, 'opp1');

      await _goToField(tester, 'opp-edit-ticketing-paid');

      await _reveal(tester, find.byKey(const Key('opp-edit-ticketing-paid')));
      expect(find.byKey(const Key('opp-edit-update-ticketing')), findsNothing);
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets(
    'new host requests show locations and omit all ticketing controls',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const OpportunityEditScreen(opportunityId: 'new'),
        beforePump: (app) => app.switchToOrganization('org2'),
      );

      expect(findUiText('Create private request'), findsOneWidget);
      expect(findUiText('LOCATION'), findsOneWidget);
      expect(find.byKey(const Key('opp-edit-location')), findsOneWidget);
      expect(findUiText('VENUE'), findsNothing);
      expect(
        find.text(
          'Artists see the area only. The exact address is shared after the deposit.',
        ),
        findsOneWidget,
      );
      await _enterText(tester, 'opp-edit-title', 'Private party');
      await _tap(tester, 'opp-location-private-location-org2');
      await _pickDate(tester, 'opp-edit-date', _futureDate(30));
      await _tap(tester, 'opp-edit-slot-add');
      await _enterText(tester, 'opp-edit-slot-0-guarantee', '150');
      await _goToField(tester, 'opp-edit-attendance');
      await _reveal(tester, find.byKey(const Key('opp-edit-attendance')));
      expect(findUiText('EXPECTED GUESTS'), findsOneWidget);
      expectNoFieldInCard(tester);
      // Inspect the section immediately after attendance so lazy scrolling
      // cannot make an offscreen ticketing section look absent.
      await _goToStep(tester, 3);
      await _reveal(tester, findUiText('VISIBILITY'));
      expect(findUiText('TICKETING'), findsNothing);
      for (final ticketing in ['none', 'rsvp', 'external', 'paid']) {
        expect(find.byKey(Key('opp-edit-ticketing-$ticketing')), findsNothing);
      }
      expect(find.byKey(const Key('opp-edit-ticket-price')), findsNothing);
      expect(find.byKey(const Key('opp-edit-ticket-capacity')), findsNothing);
      expect(find.byKey(const Key('opp-edit-external-url')), findsNothing);
      expect(
        find.text('Connect Stripe in SETTINGS to sell tickets'),
        findsNothing,
      );
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets(
    'private draft save requires a deadline and a fee for every slot',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      final beforeCount = (await repository.manageOpportunities('org2')).length;
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const OpportunityEditScreen(opportunityId: 'new'),
        beforePump: (app) => app.switchToOrganization('org2'),
      );

      await _tapAction(tester, 'save');
      expect(find.byKey(const Key('opp-edit-feedback')), findsOneWidget);
      expect(
        find.text(
          'Needs: title, location, date, deadline, a fee for every slot',
        ),
        findsWidgets,
      );
      await _enterText(tester, 'opp-edit-title', 'Private party');
      await _tap(tester, 'opp-location-private-location-org2');
      await _pickDate(tester, 'opp-edit-date', _futureDate(30));
      await _tap(tester, 'opp-edit-slot-add');
      await _tapAction(tester, 'save');
      expect(
        find.textContaining('deadline, a fee for every slot'),
        findsWidgets,
      );
      await _enterText(tester, 'opp-edit-slot-0-guarantee', '150');
      await _tap(tester, 'opp-edit-slot-add');
      await _tapAction(tester, 'save');
      expect(find.textContaining('a fee for every slot'), findsWidgets);
      await _enterText(tester, 'opp-edit-slot-1-guarantee', '50');
      await _tapAction(tester, 'save');
      expect(find.textContaining('a fee for every slot'), findsNothing);
      expect(find.text('Needs: deadline'), findsWidgets);
      expect(
        await repository.manageOpportunities('org2'),
        hasLength(beforeCount),
      );
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets(
    'complete private request saves its location and paid slot without tickets',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const OpportunityEditScreen(opportunityId: 'new'),
        beforePump: (app) => app.switchToOrganization('org2'),
      );
      final beforeCount = (await repository.manageOpportunities('org2')).length;

      await _enterText(tester, 'opp-edit-title', 'Courtyard birthday');
      await _tap(tester, 'opp-location-private-location-org2');
      final date = _futureDate(30);
      await _pickDate(tester, 'opp-edit-date', date);
      await _tap(tester, 'opp-edit-start');
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(findUiControl(TextButton, 'OK'));
      await tester.pumpAndSettle();
      await _tap(tester, 'opp-edit-slot-add');
      await _enterText(tester, 'opp-edit-slot-0-guarantee', '150');
      await _enterText(tester, 'opp-edit-attendance', '35');
      expectNoFieldInCard(tester);

      // Private deadlines must be explicit and strictly before the start.
      await _tapAction(tester, 'save');
      expect(find.text('Needs: deadline'), findsWidgets);
      expect(
        await repository.manageOpportunities('org2'),
        hasLength(beforeCount),
      );
      await _pickDate(tester, 'opp-edit-deadline', _futureDate(31));
      await _tapAction(tester, 'save');
      expect(find.text('Needs: deadline'), findsWidgets);
      expect(
        await repository.manageOpportunities('org2'),
        hasLength(beforeCount),
      );
      final deadline = _futureDate(20);
      await _pickDate(tester, 'opp-edit-deadline', deadline);
      await _tapAction(tester, 'save');

      final saved = (await repository.manageOpportunities('org2')).singleWhere(
        (opportunity) => opportunity.title == 'Courtyard birthday',
      );
      final loaded = (await repository.opportunity(saved.id))!;
      expect(loaded.mode, OpportunityMode.privateBooking);
      expect(loaded.privateEvent, isTrue);
      expect(loaded.privateLocationId, 'private-location-org2');
      expect(loaded.ticketing, OpportunityTicketing.none);
      expect(loaded.venueId, isNull);
      expect(loaded.venue, isNull);
      expect(loaded.expectedAttendance, 35);
      expect(loaded.slots.single.guaranteeMinor, 15000);
      expect(loaded.startsAt, DateTime(date.year, date.month, date.day, 21));
      expect(loaded.applicationsCloseAt, deadline);
      expect(loaded.status, OpportunityStatus.draft);
      expect(
        harness.app
            .opportunitiesFor('org2')
            .map((opportunity) => opportunity.id),
        contains(saved.id),
      );
      await _goToField(tester, 'opp-edit-title');
      await _reveal(tester, find.byKey(const Key('opp-edit-title')));
      expect(findUiText('Create private request'), findsNothing);
      expect(find.text('Courtyard birthday'), findsWidgets);
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets('adding a private location keeps the unsaved request mounted', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = StubRepository(auth: auth)
      ..wraps<List<PrivateLocation>>(
        'privateLocationsFor',
        (locations) => locations
            .where((location) => location.id != 'private-location-org2')
            .toList(),
      );
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const OpportunityEditScreen(opportunityId: 'new'),
      beforePump: (app) => app.switchToOrganization('org2'),
    );
    await _enterText(tester, 'opp-edit-title', 'Keep this private request');
    await _tap(tester, 'opp-add-location');
    expect(find.byKey(const Key('private-location-label')), findsOneWidget);
    await tester.tap(find.byType(CircleIconButton).last);
    await tester.pumpAndSettle();
    expect(
      _field(tester, 'opp-edit-title').controller!.text,
      'Keep this private request',
    );
    await _tap(tester, 'opp-add-location');
    await tester.enterText(
      find.byKey(const Key('private-location-label')),
      'Backyard',
    );
    await tester.enterText(
      find.byKey(const Key('private-location-address')),
      '22 Valencia',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final suggestion = find.byKey(const Key('private-location-suggestion-0'));
    await tester.ensureVisible(suggestion);
    await tester.tap(suggestion);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('private-location-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('private-location-label')), findsNothing);
    expect(
      _field(tester, 'opp-edit-title').controller!.text,
      'Keep this private request',
    );
    final picker = tester.widget<EpSelectionField<String>>(
      find.byKey(const Key('opp-edit-location')),
    );
    expect(picker.selected, {
      (await repository.privateLocationsFor('org2')).single.id,
    });
    expect(
      (await repository.manageOpportunities(
        'org2',
      )).where((o) => o.title == 'Keep this private request'),
      isEmpty,
    );
  });

  testWidgets(
    'existing private request retains its mode and location on update',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const OpportunityEditScreen(opportunityId: 'opp-private'),
        beforePump: (app) => app.switchToOrganization('org2'),
      );
      final location = tester.widget<EpSelectionField<String>>(
        find.byKey(const Key('opp-edit-location')),
      );
      expect(location.selected, {'private-location-org2'});
      expect(location.onChanged, isNull);
      await _enterText(tester, 'opp-edit-title', 'Updated courtyard request');
      await _tapAction(tester, 'save');

      final saved = (await repository.opportunity('opp-private'))!;
      expect(saved.title, 'Updated courtyard request');
      expect(saved.mode, OpportunityMode.privateBooking);
      expect(saved.privateLocationId, 'private-location-org2');
      expect(saved.venueId, isNull);
      expect(saved.ticketing, OpportunityTicketing.none);
      await _disposeApp(tester, harness.app);
    },
  );
}

Future<void> _disposeApp(WidgetTester tester, AppState app) async {
  // pumpApp's provider owns AppState. Unmount first so its disposal does not
  // happen after the test's explicit cleanup and raise a framework exception.
  await tester.pumpWidget(const SizedBox.shrink());
  try {
    app.dispose();
  } on FlutterError catch (error) {
    if (!error.message.contains('used after being disposed')) rethrow;
  }
}

Future<AppHarness> _pumpEditor(
  WidgetTester tester,
  FakeAuthService auth,
  DemoRepository repository,
  String id, {
  String organizationId = 'org1',
}) async {
  final harness = await pumpApp(
    tester,
    auth: auth,
    repository: repository,
    home: _EditorHost(opportunityId: id),
  );
  await enterOrganizer(tester, harness, organizationId);
  harness.app.openOpportunityEditor(id);
  await tester.pumpAndSettle();
  if (id != 'new') await openAllFormSections(tester);
  return harness;
}

// Mount the screen only after enterOrganizer, and observe app.back() without
// relying on the navigation placeholders in main.dart.
class _EditorHost extends StatelessWidget {
  const _EditorHost({required this.opportunityId});

  final String opportunityId;

  @override
  Widget build(BuildContext context) {
    final screen = context.select<AppState, Screen>(
      (app) => app.current.screen,
    );
    return screen == Screen.opportunityEdit
        ? OpportunityEditScreen(opportunityId: opportunityId)
        : const Material(child: SizedBox());
  }
}

TextField _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key)));

StickyActionBar _action(WidgetTester tester, String action) =>
    tester.widget<StickyActionBar>(find.byKey(ValueKey('opp-edit-$action')));

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final steps = tester
      .widgetList<EpFormStep>(find.byType(EpFormStep, skipOffstage: false))
      .toList();
  final hidden = find.descendant(
    of: find.byType(EpFormStep, skipOffstage: false),
    matching: finder,
    skipOffstage: false,
  );
  if (hidden.evaluate().length == 1) {
    EpFormStep? owner;
    tester.element(hidden).visitAncestorElements((element) {
      if (element.widget is EpFormStep) {
        owner = element.widget as EpFormStep;
        return false;
      }
      return true;
    });
    if (owner != null) await _goToStep(tester, steps.indexOf(owner!));
  }
  await openAllFormSections(tester);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _goToStep(WidgetTester tester, int target) async {
  final menu = find.byType(EpFormSteps);
  if (menu.evaluate().isEmpty) return;
  var step = tester.widget<EpFormSteps>(menu);
  if (target < step.current) {
    await tester.ensureVisible(menu);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(step.labels[target]).last);
    await tester.pumpAndSettle();
  } else {
    while (step.current < target) {
      final previous = step.current;
      await tester.tap(findUiControl(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      step = tester.widget<EpFormSteps>(menu);
      expect(
        step.current,
        previous + 1,
        reason: 'Required decisions must be completed before advancing',
      );
    }
  }
}

EpSelectionField<String> _venuePicker(WidgetTester tester) => tester
    .widget<EpSelectionField<String>>(find.byKey(const Key('opp-edit-venue')));
Future<void> _openVenuePicker(WidgetTester tester) async {
  final picker = find.byKey(const Key('opp-edit-venue'));
  await _reveal(tester, picker);
  await tester.tap(
    find.descendant(of: picker, matching: find.byType(OutlinedButton)),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  if (key == 'opp-edit-venue-v1' ||
      key == 'opp-location-private-location-org2') {
    final picker = find.byKey(
      Key(
        key.startsWith('opp-location') ? 'opp-edit-location' : 'opp-edit-venue',
      ),
    );
    await _reveal(tester, picker);
    final options = tester.widget<EpSelectionField<String>>(picker).options;
    final value = key == 'opp-edit-venue-v1' ? 'v1' : 'private-location-org2';
    await tester.tap(
      find.descendant(of: picker, matching: find.byType(OutlinedButton)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(options.singleWhere((o) => o.value == value).label).last,
    );
    await tester.pumpAndSettle();
    return;
  }
  await _goToField(tester, key);
  final finder = find.byKey(ValueKey(key));
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapAction(WidgetTester tester, String action) async {
  if (action == 'open') await _goToStep(tester, 4);
  await tester.ensureVisible(find.byKey(ValueKey('opp-edit-$action')));
  await tester.tap(find.byKey(ValueKey('opp-edit-$action')));
  await tester.pumpAndSettle();
}

Future<void> _enterText(WidgetTester tester, String key, String value) async {
  await _goToField(tester, key);
  final finder = find.byKey(ValueKey(key));
  await _reveal(tester, finder);
  await tester.enterText(finder, value);
  await tester.pumpAndSettle();
}

DateTime _futureDate(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days);
}

Future<void> _pickDate(WidgetTester tester, String key, DateTime date) async {
  await _tap(tester, key);
  await tester.tap(find.byTooltip('Switch to input'));
  await tester.pumpAndSettle();
  final dialog = find.byType(DatePickerDialog);
  final localizations = MaterialLocalizations.of(tester.element(dialog));
  await tester.enterText(
    find.descendant(of: dialog, matching: find.byType(TextField)),
    localizations.formatCompactDate(date),
  );
  await tester.tap(findUiControl(TextButton, 'OK'));
  await tester.pumpAndSettle();
}

Future<void> _invite(WidgetTester tester, Band band) async {
  await _tap(tester, 'opp-edit-invite-add');
  await tester.enterText(
    find.byKey(const ValueKey('opp-edit-invite-search')),
    band.name,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('opp-edit-invite-result-${band.id}')));
  await tester.pumpAndSettle();
}

Future<void> _removeInvite(WidgetTester tester, String bandId) async {
  final chip = find.byKey(ValueKey('opp-edit-invite-$bandId'));
  await _reveal(tester, chip);
  await tester.tap(
    find.descendant(of: chip, matching: find.byIcon(Icons.close)),
  );
  await tester.pumpAndSettle();
}

class _FeeRatesRepository extends DemoRepository {
  _FeeRatesRepository({required super.auth});

  final feeResult = Completer<FeeRates>();
  String? feeOrganizationId;

  @override
  Future<FeeRates> feeRates({String? organizationId}) {
    feeOrganizationId = organizationId;
    return feeResult.future;
  }
}

class _ConfirmedPaidOpportunityRepository extends StubRepository {
  _ConfirmedPaidOpportunityRepository({
    required super.auth,
    this.failNextTicketingUpdate = false,
  }) {
    wraps<Opportunity?>('opportunity', (real) {
      if (real == null || real.id != 'opp1') return real;
      return real.copyWith(
        ticketing: OpportunityTicketing.paid,
        ticketPriceMinor: 2500,
        ticketCapacity: 40,
        ticketCurrency: 'usd',
        status: OpportunityStatus.confirmed,
        revision: _revision,
      );
    });
  }

  final bool failNextTicketingUpdate;
  int _revision = 1;
  ({
    String opportunityId,
    int expectedRevision,
    int ticketPriceMinor,
    int ticketCapacity,
  })?
  lastTicketingUpdate;

  @override
  Future<int> updateOpportunityTicketing({
    required String opportunityId,
    required int expectedRevision,
    required int ticketPriceMinor,
    required int ticketCapacity,
  }) async {
    if (failNextTicketingUpdate) {
      throw Exception(
        '[Request ID: abc123] Server Error\n'
        'Uncaught Error: Capacity cannot go below tickets already sold or held\n'
        ' at handler (../../convex/opportunities.ts:1:1)\n',
      );
    }
    lastTicketingUpdate = (
      opportunityId: opportunityId,
      expectedRevision: expectedRevision,
      ticketPriceMinor: ticketPriceMinor,
      ticketCapacity: ticketCapacity,
    );
    _revision++;
    return _revision;
  }
}

class _ConflictOnceRepository extends DemoRepository {
  _ConflictOnceRepository({required super.auth});

  int _updates = 0;

  @override
  Future<int> updateOpportunity({
    required String opportunityId,
    required int expectedRevision,
    String? title,
    String? desc,
    String? venueId,
    String? privateLocationId,
    String? eventType,
    int? expectedAttendance,
    List<String>? genres,
    DateTime? startsAt,
    DateTime? doorsAt,
    DateTime? endsAt,
    AgeRequirement? ageRequirement,
    String? equipment,
    String? requirements,
    String? flyKey,
    String? flyStorageId,
    DateTime? applicationsCloseAt,
    OpportunityVisibility? visibility,
    OpportunityTicketing? ticketing,
    int? ticketPriceMinor,
    int? ticketCapacity,
    String? ticketCurrency,
    String? externalUrl,
    List<SlotInput>? slots,
  }) async {
    if (++_updates == 2) throw StateError('Opportunity changed elsewhere');
    return super.updateOpportunity(
      opportunityId: opportunityId,
      expectedRevision: expectedRevision,
      title: title,
      desc: desc,
      venueId: venueId,
      privateLocationId: privateLocationId,
      eventType: eventType,
      expectedAttendance: expectedAttendance,
      genres: genres,
      startsAt: startsAt,
      doorsAt: doorsAt,
      endsAt: endsAt,
      ageRequirement: ageRequirement,
      equipment: equipment,
      requirements: requirements,
      flyKey: flyKey,
      flyStorageId: flyStorageId,
      applicationsCloseAt: applicationsCloseAt,
      visibility: visibility,
      ticketing: ticketing,
      ticketPriceMinor: ticketPriceMinor,
      ticketCapacity: ticketCapacity,
      ticketCurrency: ticketCurrency,
      externalUrl: externalUrl,
      slots: slots,
    );
  }
}

Future<void> _goToField(WidgetTester tester, String key) async {
  final target = key.contains('slot-') || key == 'opp-edit-slot-add'
      ? 1
      : key.contains('desc') ||
            key.contains('equipment') ||
            key.contains('requirements') ||
            key.contains('attendance') ||
            key.contains('age-')
      ? 2
      : key.contains('deadline') ||
            key.contains('ticket') ||
            key.contains('external') ||
            key.contains('visibility') ||
            key.contains('invite')
      ? 3
      : key.contains('approval')
      ? 4
      : 0;
  await _goToStep(tester, target);
}
