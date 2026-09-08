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
    expect(find.byKey(const Key('opp-edit-venue-search')), findsNothing);
    expect(find.byKey(const Key('opp-edit-venue-v1')), findsOneWidget);
    final originalIds = (await repository.manageOpportunities(
      'org1',
    )).map((opportunity) => opportunity.id).toSet();
    expect(find.byType(StatusPill), findsNothing);
    expect(_action(tester, 'open').onPrimary, isNull);
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
    await _pickDate(tester, 'opp-edit-deadline', _futureDate(20));
    await _tap(tester, 'opp-edit-slot-add');
    await _tap(tester, 'opp-edit-slot-0-role-support');
    await _enterText(tester, 'opp-edit-slot-0-guarantee', '150');
    await _enterText(tester, 'opp-edit-slot-0-length', '45');
    await _tap(tester, 'opp-edit-slot-0-required');
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
    await _reveal(
      tester,
      find.byKey(const ValueKey('opp-edit-slot-0-guarantee')),
    );
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
    expect(find.byKey(const Key('opp-edit-venue-search')), findsOneWidget);
    expect(
      tester.widget<EpChip>(find.byKey(const Key('opp-edit-venue-v1'))).active,
      isFalse,
    );
    expect(_action(tester, 'open').primaryLabel, 'OPEN FOR APPLICATIONS');
    expect(_action(tester, 'open').onPrimary, isNull);
    expect(find.text('OPEN FOR APPLICATIONS'), findsOneWidget);
    expect(find.text('WAITING FOR VENUE APPROVAL'), findsNothing);

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
    expect(find.byKey(const Key('opp-edit-venue-search')), findsOneWidget);
    expect(find.byKey(const Key('opp-edit-venue-v1')), findsOneWidget);
    expect(find.byKey(const Key('opp-edit-venue-v2')), findsNothing);
    expect(find.byKey(const Key('opp-edit-venue-v3')), findsNothing);
    expect(find.byKey(const Key('opp-edit-venue-approval')), findsNothing);

    await _enterText(tester, 'opp-edit-venue-search', '  FOGHORN  ');
    expect(find.byKey(const Key('opp-edit-venue-v1')), findsOneWidget);
    await _enterText(tester, 'opp-edit-venue-search', 'Nightcrawler');
    expect(find.byKey(const Key('opp-edit-venue-v1')), findsNothing);
    expect(find.byKey(const Key('opp-edit-venue-v2')), findsNothing);
    await _enterText(tester, 'opp-edit-venue-search', '  MISSION  ');
    await _tap(tester, 'opp-edit-venue-v1');
    expect(
      tester.widget<EpChip>(find.byKey(const Key('opp-edit-venue-v1'))).active,
      isTrue,
    );
    await _enterText(tester, 'opp-edit-venue-search', 'No matching venue');
    expect(find.byKey(const Key('opp-edit-venue-v1')), findsNothing);
    expect(
      find.text('The Foghorn Club · Mission, San Francisco'),
      findsOneWidget,
    );
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
    expect(_field(tester, 'opp-edit-venue-search').enabled, isFalse);
    expect(
      tester.widget<EpChip>(find.byKey(const Key('opp-edit-venue-v1'))).onTap,
      isNull,
    );
    final card = find.byKey(const Key('opp-edit-venue-approval'));
    await _reveal(tester, card);
    expect(
      find.descendant(of: card, matching: find.text('PENDING APPROVAL')),
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
      find.descendant(of: card, matching: find.text('NOT REQUESTED')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('opp-edit-withdraw-approval')), findsNothing);
    expect(
      tester
          .widget<EpButton>(find.byKey(const Key('opp-edit-request-approval')))
          .onTap,
      isNotNull,
    );
    await _reveal(tester, find.byKey(const Key('opp-edit-date')));
    for (final key in ['date', 'doors', 'start', 'deadline']) {
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(Key('opp-edit-$key')))
            .onPressed,
        isNotNull,
      );
    }
    await _reveal(tester, find.byKey(const Key('opp-edit-venue-search')));
    expect(_field(tester, 'opp-edit-venue-search').enabled, isTrue);
    expect(
      tester.widget<EpChip>(find.byKey(const Key('opp-edit-venue-v1'))).onTap,
      isNotNull,
    );
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
    await _reveal(tester, find.byKey(const Key('opp-edit-venue-approval')));
    expect(find.text('PENDING APPROVAL'), findsOneWidget);
    expect(find.byKey(const Key('opp-edit-withdraw-approval')), findsOneWidget);
    await _reveal(tester, find.byKey(const Key('opp-edit-title')));
    expect(
      _field(tester, 'opp-edit-title').controller!.text,
      'Promoter showcase',
    );
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
      await _reveal(tester, find.byKey(const Key('opp-edit-venue-approval')));
      expect(find.text('APPROVED'), findsOneWidget);
      expect(find.byKey(const Key('opp-edit-request-approval')), findsNothing);
      expect(
        find.byKey(const Key('opp-edit-withdraw-approval')),
        findsOneWidget,
      );
      expect(_action(tester, 'open').primaryLabel, 'OPEN FOR APPLICATIONS');
      expect(_action(tester, 'open').onPrimary, isNotNull);
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
      await _reveal(tester, find.byKey(const Key('opp-edit-venue-approval')));
      expect(find.byKey(const Key('opp-edit-withdraw-approval')), findsNothing);
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets('paid tickets save dollar prices and validate before opening', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'new');
    await _enterText(tester, 'opp-edit-title', 'Paid Saturday');
    await _tap(tester, 'opp-edit-venue-v1');
    await _pickDate(tester, 'opp-edit-date', _futureDate(30));
    await _tap(tester, 'opp-edit-slot-add');
    await _reveal(
      tester,
      find.byKey(const ValueKey('opp-edit-ticketing-paid')),
    );

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
      await _reveal(
        tester,
        find.byKey(const ValueKey('opp-edit-ticket-price')),
      );
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
    final repository = _StripeDisconnectedRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp2');
    await _reveal(
      tester,
      find.byKey(const ValueKey('opp-edit-ticketing-paid')),
    );
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
    final venue = tester.widget<EpChip>(
      find.byKey(const ValueKey('opp-edit-venue-v1')),
    );
    expect(venue.active, isTrue);
    expect(venue.onTap, isNull);
    await _reveal(tester, find.byKey(const ValueKey('opp-edit-desc')));
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
    await _reveal(tester, find.byKey(const ValueKey('opp-edit-delete')));
    // DangerZone's caption makes its center fall outside the actual button.
    await tester.tap(find.widgetWithText(TextButton, 'DELETE DRAFT'));
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
      await _reveal(tester, find.byKey(const ValueKey('opp-edit-title')));
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
    await _invite(tester, (await repository.band('b1'))!);
    await tester.pump(const Duration(seconds: 2));
    expect(
      (await repository.manageOpportunities('org1')).length,
      originalCount,
    );
    await _reveal(tester, find.byType(CircleIconButton));
    await tester.tap(find.byType(CircleIconButton));
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
    expect(_action(tester, 'open').onPrimary, isNull);
    expect(
      find.text('Needs: at least one slot, deadline before start'),
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
    await _reveal(tester, find.byKey(const ValueKey('opp-edit-cancel')));
    await tester.tap(find.widgetWithText(TextButton, 'CANCEL OPPORTUNITY'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'KEEP'));
    await tester.pumpAndSettle();
    expect(
      (await repository.opportunity('opp1'))!.status,
      OpportunityStatus.open,
    );
    await tester.tap(find.widgetWithText(TextButton, 'CANCEL OPPORTUNITY'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'CONFIRM'));
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
      await _reveal(tester, find.byKey(const Key('opp-edit-ticket-price')));
      expect(_field(tester, 'opp-edit-ticket-price').enabled, isTrue);
      expect(_field(tester, 'opp-edit-ticket-capacity').enabled, isTrue);
      expect(
        tester
            .widget<EpChip>(find.byKey(const Key('opp-edit-ticketing-paid')))
            .onTap,
        isNull,
      );
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
      final repository = _BookingStatusRepository(auth: auth);
      final harness = await _pumpEditor(tester, auth, repository, 'opp1');

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

      expect(find.text('NEW REQUEST'), findsOneWidget);
      expect(find.text('LOCATION'), findsOneWidget);
      expect(
        find.byKey(const Key('opp-location-private-location-org2')),
        findsOneWidget,
      );
      expect(find.text('VENUE'), findsNothing);
      expect(
        find.text(
          'Artists see the area only. The exact address is shared after the deposit.',
        ),
        findsOneWidget,
      );
      await _reveal(tester, find.byKey(const Key('opp-edit-attendance')));
      expect(find.text('EXPECTED GUESTS'), findsOneWidget);
      expectNoFieldInCard(tester);
      // Inspect the section immediately after attendance so lazy scrolling
      // cannot make an offscreen ticketing section look absent.
      await _reveal(tester, find.text('VISIBILITY'));
      expect(find.text('TICKETING'), findsNothing);
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
      expect(find.text('Needs: title, location, date, deadline'), findsWidgets);
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
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
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
      await _reveal(tester, find.byKey(const Key('opp-edit-title')));
      expect(find.text('NEW REQUEST'), findsNothing);
      expect(find.text('Courtyard birthday'), findsWidgets);
      await _disposeApp(tester, harness.app);
    },
  );

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
      final location = tester.widget<EpChip>(
        find.byKey(const Key('opp-location-private-location-org2')),
      );
      expect(location.active, isTrue);
      expect(location.onTap, isNull);
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
  final list = find
      .descendant(
        of: find.byType(OpportunityEditScreen),
        matching: find.byType(ListView),
      )
      .first;
  tester.widget<ListView>(list).controller!.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first,
    maxScrolls: 50,
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapAction(WidgetTester tester, String action) async {
  await tester.tap(find.byKey(ValueKey('opp-edit-$action')));
  await tester.pumpAndSettle();
}

Future<void> _enterText(WidgetTester tester, String key, String value) async {
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
  await tester.tap(find.widgetWithText(TextButton, 'OK'));
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

class _ConfirmedPaidOpportunityRepository extends DemoRepository {
  _ConfirmedPaidOpportunityRepository({
    required super.auth,
    this.failNextTicketingUpdate = false,
  });

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
  Future<Opportunity?> opportunity(String opportunityId) async {
    final existing = await super.opportunity(opportunityId);
    if (existing == null || opportunityId != 'opp1') return existing;
    return Opportunity(
      id: existing.id,
      organizationId: existing.organizationId,
      mode: existing.mode,
      venueId: existing.venueId,
      venue: existing.venue,
      title: existing.title,
      desc: existing.desc,
      eventType: existing.eventType,
      expectedAttendance: existing.expectedAttendance,
      genres: existing.genres,
      startsAt: existing.startsAt,
      doorsAt: existing.doorsAt,
      endsAt: existing.endsAt,
      ageRequirement: existing.ageRequirement,
      equipment: existing.equipment,
      requirements: existing.requirements,
      flyKey: existing.flyKey,
      flyerUrl: existing.flyerUrl,
      applicationsCloseAt: existing.applicationsCloseAt,
      visibility: existing.visibility,
      ticketing: OpportunityTicketing.paid,
      ticketPriceMinor: 2500,
      ticketCapacity: 40,
      ticketCurrency: 'usd',
      externalUrl: existing.externalUrl,
      status: OpportunityStatus.confirmed,
      slug: existing.slug,
      revision: _revision,
      applicationCount: existing.applicationCount,
      slots: existing.slots,
      invitedBandIds: existing.invitedBandIds,
      createdAt: existing.createdAt,
      updatedAt: existing.updatedAt,
      area: existing.area,
      venueType: existing.venueType,
      currency: existing.currency,
    );
  }

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

class _BookingStatusRepository extends DemoRepository {
  _BookingStatusRepository({required super.auth});

  @override
  Future<Opportunity?> opportunity(String opportunityId) async {
    final existing = await super.opportunity(opportunityId);
    if (existing == null || opportunityId != 'opp1') return existing;
    return Opportunity(
      id: existing.id,
      organizationId: existing.organizationId,
      mode: existing.mode,
      venueId: existing.venueId,
      venue: existing.venue,
      title: existing.title,
      desc: existing.desc,
      eventType: existing.eventType,
      expectedAttendance: existing.expectedAttendance,
      genres: existing.genres,
      startsAt: existing.startsAt,
      doorsAt: existing.doorsAt,
      endsAt: existing.endsAt,
      ageRequirement: existing.ageRequirement,
      equipment: existing.equipment,
      requirements: existing.requirements,
      flyKey: existing.flyKey,
      flyerUrl: existing.flyerUrl,
      applicationsCloseAt: existing.applicationsCloseAt,
      visibility: existing.visibility,
      ticketing: existing.ticketing,
      ticketPriceMinor: existing.ticketPriceMinor,
      ticketCapacity: existing.ticketCapacity,
      ticketCurrency: existing.ticketCurrency,
      externalUrl: existing.externalUrl,
      status: OpportunityStatus.booking,
      slug: existing.slug,
      revision: existing.revision,
      applicationCount: existing.applicationCount,
      slots: existing.slots,
      invitedBandIds: existing.invitedBandIds,
      createdAt: existing.createdAt,
      updatedAt: existing.updatedAt,
      area: existing.area,
      venueType: existing.venueType,
      currency: existing.currency,
    );
  }
}

class _StripeDisconnectedRepository extends DemoRepository {
  _StripeDisconnectedRepository({required super.auth});

  @override
  Future<OrganizationDashboard> organizationDashboard(
    String organizationId,
  ) async {
    final dashboard = await super.organizationDashboard(organizationId);
    final verification = dashboard.verification;
    return OrganizationDashboard(
      organization: dashboard.organization,
      role: dashboard.role,
      viaPlatformAdmin: dashboard.viaPlatformAdmin,
      verification: OrganizationVerification(
        verified: verification.verified,
        stripeDetailsSubmitted: verification.stripeDetailsSubmitted,
        stripeChargesEnabled: false,
        stripePayoutsEnabled: verification.stripePayoutsEnabled,
        profileComplete: verification.profileComplete,
        teamInvited: verification.teamInvited,
      ),
      venues: dashboard.venues,
      memberCount: dashboard.memberCount,
      privateDetails: dashboard.privateDetails,
    );
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
