import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/opportunity_detail.dart';
import 'package:earplug/screens/opportunity_edit.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  testWidgets('the pinned action zone stays above the organizer tab bar', (
    tester,
  ) async {
    final harness = await pumpApp(tester, home: const RootShell());
    await enterOrganizer(tester, harness, 'org1');
    harness.app.openOpportunityEditor('opp2');
    await tester.pumpAndSettle();

    expect(find.byType(OpportunityEditScreen), findsOneWidget);
    expect(find.byType(OrganizerTabBar), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('opp-edit-publish'))).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(OrganizerTabBar)).top),
    );
    expect(find.byKey(const ValueKey('opp-edit-preview')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('opp-edit-autosave-note')),
        matching: find.text(
          'Saves as a draft automatically — no separate save step.',
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('opp-edit-save')), findsNothing);
    expect(find.byKey(const ValueKey('opp-edit-missing')), findsNothing);
  });

  testWidgets(
    'editing autosaves: one create once the server can take it, updates after',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _CountingRepository(auth: auth);
      final harness = await _pumpEditor(tester, auth, repository, 'new');
      expect(find.byKey(const Key('opp-edit-venue-search')), findsNothing);
      expect(find.byKey(const Key('opp-edit-venue-v1')), findsOneWidget);
      expect(find.byType(StatusPill), findsNothing);
      expect(find.byKey(const ValueKey('opp-edit-save-state')), findsNothing);
      expect(_action(tester, 'publish').onPressed, isNotNull);
      expect(_action(tester, 'publish').label, 'Review & publish');
      expect(
        find.descendant(
          of: find.byType(EpCard),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );

      // A title alone is not a draft the server accepts: it stays local.
      await _enterText(tester, 'opp-edit-title', 'Basement Saturday');
      await _settleAutosave(tester);
      expect(repository.creates, 0);
      await _expectSaveState(tester, 'DRAFT · UNSAVED');

      await _tap(tester, 'opp-edit-venue-v1');
      final date = _futureDate(30);
      await _pickWhen(tester, date: date, deadline: _futureDate(20));
      await _settleAutosave(tester);
      expect(repository.creates, 1);
      expect(repository.updates, 0);
      await _expectSaveState(tester, 'DRAFT · SAVED');
      final saved = (await repository.manageOpportunities(
        'org1',
      )).singleWhere((opportunity) => opportunity.title == 'Basement Saturday');
      expect(saved.status, OpportunityStatus.draft);
      expect(saved.venueId, 'v1');
      expect(saved.startsAt, DateTime(date.year, date.month, date.day, 21));
      expect(saved.doorsAt, DateTime(date.year, date.month, date.day, 20));
      expect(saved.applicationsCloseAt, _futureDate(20));
      expect(
        harness.app
            .opportunitiesFor('org1')
            .any((opportunity) => opportunity.id == saved.id),
        isTrue,
      );
      await _reveal(tester, find.byType(CircleIconButton));
      expect(find.byType(StatusPill), findsOneWidget);

      await _tap(tester, 'opp-edit-slot-add');
      await _tap(tester, 'opp-edit-slot-0-role-support');
      await _enterText(tester, 'opp-edit-slot-0-guarantee', '150');
      await _enterText(tester, 'opp-edit-slot-0-length', '45');
      await _tap(tester, 'opp-edit-slot-0-required');
      await _settleAutosave(tester);
      expect(repository.creates, 1);
      expect(repository.updates, greaterThanOrEqualTo(1));
      final updated = (await repository.opportunity(saved.id))!;
      expect(updated.slots.single.role, SlotRole.support);
      expect(updated.slots.single.guaranteeMinor, 15000);
      expect(updated.slots.single.setLengthMin, 45);
      expect(updated.slots.single.required, isTrue);
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets(
    'publish with no manual save creates, opens in one flow and locks slots',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _CountingRepository(auth: auth);
      final harness = await _pumpEditor(tester, auth, repository, 'new');
      final originalIds = (await repository.manageOpportunities(
        'org1',
      )).map((opportunity) => opportunity.id).toSet();

      await _enterText(tester, 'opp-edit-title', 'Basement Saturday Live');
      await _tap(tester, 'opp-edit-venue-v1');
      final date = _futureDate(30);
      await _pickWhen(tester, date: date, deadline: _futureDate(20));
      await _tap(tester, 'opp-edit-slot-add');
      await _enterText(tester, 'opp-edit-slot-0-guarantee', '150');
      // Straight to publish: whether or not the debounce has fired yet, the
      // draft is created exactly once and never through a save button.
      await _tapAction(tester, 'publish');
      expect(find.byKey(const ValueKey('opp-verify-sheet')), findsOneWidget);
      await _tap(tester, 'opp-verify-publish');

      expect(repository.creates, 1);
      final opened = (await repository.manageOpportunities(
        'org1',
      )).singleWhere((opportunity) => !originalIds.contains(opportunity.id));
      expect(opened.status, OpportunityStatus.open);
      expect(opened.title, 'Basement Saturday Live');
      expect(opened.slots.single.guaranteeMinor, 15000);
      expect(_action(tester, 'publish').label, 'Review & save');
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
    },
  );

  testWidgets(
    'REVIEW & PUBLISH with pending rows scrolls to the first one and pulses it',
    (tester) async {
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
        tester
            .widget<EpChip>(find.byKey(const Key('opp-edit-venue-v1')))
            .active,
        isFalse,
      );
      expect(find.text('Choose a venue'), findsOneWidget);
      expect(find.text('REQUIRED — 0 OF 4 DONE'), findsOneWidget);
      for (final row in ['title', 'when', 'location', 'slots']) {
        expect(find.byKey(ValueKey('opp-edit-pulse-$row')), findsOneWidget);
        expect(find.byKey(ValueKey('opp-edit-done-$row')), findsNothing);
      }
      expect(_action(tester, 'publish').onPressed, isNotNull);

      // Scroll away first so the scroll back is observable.
      await _reveal(tester, find.byKey(const ValueKey('opp-edit-slot-add')));
      final pulse = find.byKey(const ValueKey('opp-edit-pulse-title'));
      expect(pulse.hitTestable(), findsNothing);
      await tester.tap(find.byKey(const ValueKey('opp-edit-publish')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('opp-verify-sheet')), findsNothing);
      expect(pulse.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(pulse).top,
        lessThan(tester.getRect(find.byType(OpportunityEditScreen)).height),
      );
      expect(tester.getRect(pulse).top, greaterThan(0));

      // Pressing again with the row on screen replays the 600 ms pulse.
      await tester.tap(find.byKey(const ValueKey('opp-edit-publish')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final scale = tester.widget<ScaleTransition>(
        find.descendant(of: pulse, matching: find.byType(ScaleTransition)),
      );
      expect(scale.scale.value, greaterThan(1.2));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ScaleTransition>(
              find.descendant(
                of: pulse,
                matching: find.byType(ScaleTransition),
              ),
            )
            .scale
            .value,
        1,
      );
      await _disposeApp(tester, harness.app);
    },
  );

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
    // The chosen venue reads on the VENUE row above the search field.
    await _reveal(tester, find.byKey(const ValueKey('opp-edit-location')));
    expect(
      find.text('The Foghorn Club · Mission, San Francisco'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('opp-edit-done-location')), findsOne);
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
    // A loaded draft folds its filled rows; open the one under test.
    await _tap(tester, 'opp-edit-location');
    expect(_field(tester, 'opp-edit-venue-search').enabled, isFalse);
    expect(
      tester.widget<EpChip>(find.byKey(const Key('opp-edit-venue-v1'))).onTap,
      isNull,
    );
    expect(
      find.text(
        'Withdraw the venue request before changing the venue or date.',
      ),
      findsOneWidget,
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
    // The WHEN row is locked while the venue request is pending.
    await _tap(tester, 'opp-edit-when');
    expect(find.byKey(const ValueKey('opp-edit-when-sheet')), findsNothing);

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
    await _tap(tester, 'opp-edit-when');
    expect(find.byKey(const ValueKey('opp-edit-when-sheet')), findsOneWidget);
    await _done(tester);
    await _reveal(tester, find.byKey(const Key('opp-edit-venue-search')));
    expect(_field(tester, 'opp-edit-venue-search').enabled, isTrue);
    expect(
      tester.widget<EpChip>(find.byKey(const Key('opp-edit-venue-v1'))).onTap,
      isNotNull,
    );

    // Complete the slot fee; publishing then still waits for the venue.
    await _enterText(tester, 'opp-edit-slot-0-guarantee', '200');
    await _expectProgress(tester, 'REQUIRED — 4 OF 4 DONE');
    await _tapAction(tester, 'publish');
    expect(find.byKey(const ValueKey('opp-verify-sheet')), findsNothing);
    await _reveal(tester, find.byKey(const ValueKey('opp-edit-feedback')));
    expect(find.text('Still needs venue approval.'), findsOneWidget);
    expect(
      (await repository.opportunity('opp-promoter'))!.status,
      OpportunityStatus.draft,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets(
    'a newly autosaved promoter draft requests approval with a message',
    (tester) async {
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
      expect(find.byKey(const Key('opp-edit-request-approval')), findsNothing);
      await _pickWhen(tester, date: _futureDate(40));
      await _settleAutosave(tester);
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
      expect(
        find.byKey(const Key('opp-edit-withdraw-approval')),
        findsOneWidget,
      );
      await _reveal(tester, find.byKey(const Key('opp-edit-title')));
      expect(
        _field(tester, 'opp-edit-title').controller!.text,
        'Promoter showcase',
      );
      await _disposeApp(tester, harness.app);
    },
  );

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
    await _tap(tester, 'opp-edit-location');
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
    'granted approval lets the verify sheet publish while venue and dates stay locked',
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
      await _tap(tester, 'opp-edit-location');
      await _reveal(tester, find.byKey(const Key('opp-edit-venue-approval')));
      expect(find.text('APPROVED'), findsOneWidget);
      expect(find.byKey(const Key('opp-edit-request-approval')), findsNothing);
      expect(
        find.byKey(const Key('opp-edit-withdraw-approval')),
        findsOneWidget,
      );
      await _tap(tester, 'opp-edit-when');
      expect(find.byKey(const ValueKey('opp-edit-when-sheet')), findsNothing);
      // The fixture's slot has no fee yet, so the SLOTS row is the gate.
      await _tapAction(tester, 'publish');
      expect(find.byKey(const ValueKey('opp-verify-sheet')), findsNothing);
      expect(find.byKey(const ValueKey('opp-edit-pulse-slots')), findsOne);
      await _enterText(tester, 'opp-edit-slot-0-guarantee', '200');
      await _tapAction(tester, 'publish');
      expect(find.byKey(const ValueKey('opp-verify-sheet')), findsOneWidget);
      await _tap(tester, 'opp-verify-publish');
      expect(
        (await repository.opportunity('opp-promoter'))!.status,
        OpportunityStatus.open,
      );
      await _reveal(tester, find.byKey(const ValueKey('opp-edit-close')));
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('opp-edit-close')))
            .onPressed,
        isNotNull,
      );
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
      await repository.refreshOrganizationAccountStatus('org1');
      final harness = await _pumpEditor(tester, auth, repository, 'opp2');
      await _tap(tester, 'opp-edit-ticketing-paid');
      expect(_ticketingPill(tester, 'paid').selected, isTrue);
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
        await repository.refreshOrganizationAccountStatus('org1');
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

  testWidgets(
    'paid tickets save dollar prices and validate before publishing',
    (tester) async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      await repository.refreshOrganizationAccountStatus('org1');
      final harness = await _pumpEditor(tester, auth, repository, 'new');
      await _enterText(tester, 'opp-edit-title', 'Paid Saturday');
      await _tap(tester, 'opp-edit-venue-v1');
      await _pickWhen(tester, date: _futureDate(30));
      await _tap(tester, 'opp-edit-slot-add');
      await _enterText(tester, 'opp-edit-slot-0-guarantee', '100');
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
      expect(find.byKey(const ValueKey('opp-edit-paid-locked')), findsNothing);
      expect(find.byKey(const ValueKey('opp-edit-ticket-price')), findsNothing);
      expect(
        find.byKey(const ValueKey('opp-edit-ticket-capacity')),
        findsNothing,
      );
      expect(_ticketingPill(tester, 'paid').onPressed, isNotNull);
      await _tap(tester, 'opp-edit-ticketing-paid');
      expect(_field(tester, 'opp-edit-ticket-price').enabled, isTrue);
      expect(_field(tester, 'opp-edit-ticket-capacity').enabled, isTrue);
      expect(_field(tester, 'opp-edit-ticket-price').controller!.text, isEmpty);
      expect(
        _field(tester, 'opp-edit-ticket-capacity').controller!.text,
        isEmpty,
      );
      expect(find.byKey(const ValueKey('opp-edit-external-url')), findsNothing);
      // The RSVP draft autosaved earlier; invalid paid fields hold every
      // further save and the publish.
      await _settleAutosave(tester);
      expect(
        (await repository.manageOpportunities('org1'))
            .singleWhere((opportunity) => opportunity.title == 'Paid Saturday')
            .ticketing,
        OpportunityTicketing.rsvp,
      );
      await _expectSaveState(tester, 'DRAFT · UNSAVED');
      await _tapAction(tester, 'publish');
      expect(find.byKey(const ValueKey('opp-verify-sheet')), findsNothing);
      await _reveal(tester, find.byKey(const ValueKey('opp-edit-feedback')));
      expect(
        find.text('Still needs a ticket price + a ticket capacity.'),
        findsOneWidget,
      );

      await _enterText(tester, 'opp-edit-ticket-price', '25');
      await _enterText(tester, 'opp-edit-ticket-capacity', '100');
      await _settleAutosave(tester);
      final saved = (await repository.manageOpportunities(
        'org1',
      )).singleWhere((opportunity) => opportunity.title == 'Paid Saturday');
      expect(saved.ticketing, OpportunityTicketing.paid);
      expect(saved.ticketPriceMinor, 2500);
      expect(saved.ticketCapacity, 100);
      expect(saved.ticketCurrency, 'usd');

      for (final price in ['0.99', 'NaN', 'Infinity', '1e308']) {
        await _enterText(tester, 'opp-edit-ticket-price', price);
        expect(
          find.text('Enter a ticket price of at least \$1.00.'),
          findsOneWidget,
        );
        await _settleAutosave(tester);
        expect(
          (await repository.opportunity(saved.id))!.revision,
          saved.revision,
        );
        await _tapAction(tester, 'publish');
        expect(find.byKey(const ValueKey('opp-verify-sheet')), findsNothing);
        await _reveal(tester, find.byKey(const ValueKey('opp-edit-feedback')));
        expect(find.text('Still needs a ticket price.'), findsOneWidget);
      }
      await _enterText(tester, 'opp-edit-ticket-price', '25');
      for (final capacity in ['0', '6000', '1.5']) {
        await _enterText(tester, 'opp-edit-ticket-capacity', capacity);
        expect(
          find.text('Enter a whole number from 1 to 5000.'),
          findsOneWidget,
        );
        await _tapAction(tester, 'publish');
        expect(find.byKey(const ValueKey('opp-verify-sheet')), findsNothing);
        await _reveal(tester, find.byKey(const ValueKey('opp-edit-feedback')));
        expect(find.text('Still needs a ticket capacity.'), findsOneWidget);
        final unchanged = (await repository.opportunity(saved.id))!;
        expect(unchanged.status, OpportunityStatus.draft);
      }

      // Invalid paid inputs do not constrain other ticketing modes.
      for (final ticketing in ['external', 'none', 'rsvp']) {
        await _tap(tester, 'opp-edit-ticketing-$ticketing');
        expect(
          find.byKey(const ValueKey('opp-edit-ticket-price')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('opp-edit-ticket-capacity')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('opp-edit-external-url')),
          ticketing == 'external' ? findsOneWidget : findsNothing,
        );
      }
      await _settleAutosave(tester);
      expect(
        (await repository.opportunity(saved.id))!.ticketing,
        OpportunityTicketing.rsvp,
      );

      await _tap(tester, 'opp-edit-ticketing-paid');
      await _enterText(tester, 'opp-edit-ticket-price', '25.505');
      await _enterText(tester, 'opp-edit-ticket-capacity', '100');
      await _tapAction(tester, 'publish');
      expect(find.byKey(const ValueKey('opp-verify-sheet')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('opp-verify-ticketing')),
          matching: find.text(r'Paid · $25.505 · 100 cap'),
        ),
        findsOneWidget,
      );
      await _tap(tester, 'opp-verify-publish');
      final opened = (await repository.opportunity(saved.id))!;
      expect(opened.status, OpportunityStatus.open);
      expect(opened.ticketing, OpportunityTicketing.paid);
      expect(opened.ticketPriceMinor, 2551);
      expect(opened.ticketCapacity, 100);
      expect(opened.ticketCurrency, 'usd');
      await _disposeApp(tester, harness.app);
    },
  );

  for (final price in [2500, 2550]) {
    testWidgets('paid ticket fields hydrate $price minor units', (
      tester,
    ) async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      await repository.refreshOrganizationAccountStatus('org1');
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
        _ticketingPill(tester, 'paid').onPressed,
        price == 2500 ? isNotNull : isNull,
      );
      await _disposeApp(tester, harness.app);
    });
  }

  testWidgets('PAID stays locked until the organization can sell tickets', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp2');
    final paid = find.byKey(const ValueKey('opp-edit-ticketing-paid'));
    await _reveal(tester, paid);
    expect(_ticketingPill(tester, 'paid').onPressed, isNull);
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: paid, matching: find.byType(Opacity)).first,
          )
          .opacity,
      closeTo(.45, .01),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('opp-edit-paid-locked')),
        matching: find.text(
          'PAID unlocks after Stripe — finish in ORGANIZATION › FINANCE',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(paid, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_ticketingPill(tester, 'paid').selected, isFalse);
    expect(find.byKey(const ValueKey('opp-edit-ticket-price')), findsNothing);
    expect(
      find.byKey(const ValueKey('opp-edit-ticket-capacity')),
      findsNothing,
    );
    expect(_ticketingPill(tester, 'rsvp').onPressed, isNotNull);
    await _disposeApp(tester, harness.app);
  });

  testWidgets('PAID unlocks once the Stripe account is enabled', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    await repository.refreshOrganizationAccountStatus('org1');
    final harness = await _pumpEditor(tester, auth, repository, 'opp2');
    final paid = find.byKey(const ValueKey('opp-edit-ticketing-paid'));
    await _reveal(tester, paid);
    expect(
      harness.app.organizationStripeStatusFor('org1')?.state,
      StripeAccountState.enabled,
    );
    expect(_ticketingPill(tester, 'paid').onPressed, isNotNull);
    expect(
      find.ancestor(of: paid, matching: find.byType(Opacity)),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('opp-edit-paid-locked')), findsNothing);
    await _tap(tester, 'opp-edit-ticketing-paid');
    expect(find.byKey(const ValueKey('opp-edit-ticket-price')), findsOneWidget);
    await _disposeApp(tester, harness.app);
  });

  testWidgets('existing open opportunity is prefilled, autosaves and closes', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final fixture = (await repository.opportunity('opp1'))!;
    final harness = await _pumpEditor(tester, auth, repository, 'opp1');
    expect(_field(tester, 'opp-edit-title').controller!.text, fixture.title);
    await _expectSaveState(tester, 'SAVED');
    expect(_action(tester, 'publish').label, 'Review & save');
    await _tap(tester, 'opp-edit-location');
    final venue = tester.widget<EpChip>(
      find.byKey(const ValueKey('opp-edit-venue-v1')),
    );
    expect(venue.active, isTrue);
    expect(venue.onTap, isNull);
    await _tap(tester, 'opp-edit-details-toggle');
    await _reveal(tester, find.byKey(const ValueKey('opp-edit-desc')));
    expect(_field(tester, 'opp-edit-desc').controller!.text, fixture.desc);
    await _enterText(
      tester,
      'opp-edit-desc',
      'Updated backline and load-in details.',
    );
    await _settleAutosave(tester);
    final updated = (await repository.opportunity('opp1'))!;
    expect(updated.desc, 'Updated backline and load-in details.');
    expect(updated.slots.map((slot) => slot.id), [
      'opp1-headliner',
      'opp1-support',
    ]);
    await _tap(tester, 'opp-edit-close');
    expect(
      (await repository.opportunity('opp1'))!.status,
      OpportunityStatus.applicationsClosed,
    );
    await _reveal(tester, find.byKey(const ValueKey('opp-edit-reopen')));
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('opp-edit-reopen')))
          .onPressed,
      isNotNull,
    );
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
    await _tap(tester, 'opp-edit-delete');
    expect(await repository.opportunity('opp2'), isNull);
    expect(harness.app.current.screen, Screen.orgOpportunities);
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
    expect(find.byKey(const ValueKey('opp-edit-invite-add')), findsNothing);
    await _tap(tester, 'opp-edit-visibility-invite');
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
      await _settleAutosave(tester);
      expect(
        (await repository.opportunity('opp1'))!.title,
        'First saved title',
      );
      await _enterText(tester, 'opp-edit-title', 'Conflicting title');
      await _settleAutosave(tester);
      await _reveal(tester, find.byKey(const ValueKey('opp-edit-feedback')));
      expect(find.byKey(const ValueKey('opp-edit-feedback')), findsOneWidget);
      expect(find.textContaining('changed elsewhere'), findsOneWidget);
      await _reveal(tester, find.byKey(const ValueKey('opp-edit-title')));
      expect(
        _field(tester, 'opp-edit-title').controller!.text,
        'First saved title',
      );
      await _enterText(tester, 'opp-edit-title', 'Recovered title');
      await _settleAutosave(tester);
      expect((await repository.opportunity('opp1'))!.title, 'Recovered title');
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets('a failed autosave offers RETRY and the retry saves', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _FailOnceRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp1');
    await _enterText(tester, 'opp-edit-title', 'Flaky network title');
    await _settleAutosave(tester);
    expect(
      (await repository.opportunity('opp1'))!.title,
      isNot('Flaky network title'),
    );
    await _expectSaveState(tester, 'SAVE FAILED · RETRY');
    await tester.tap(find.byKey(const ValueKey('opp-edit-save-state')));
    await tester.pumpAndSettle();
    expect(
      (await repository.opportunity('opp1'))!.title,
      'Flaky network title',
    );
    await _expectSaveState(tester, 'SAVED');
    await _disposeApp(tester, harness.app);
  });

  testWidgets('unsaved invitations stay local and leaving creates no draft', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'new');
    final originalCount = (await repository.manageOpportunities('org1')).length;
    await _enterText(tester, 'opp-edit-title', 'Never saved');
    await _tap(tester, 'opp-edit-visibility-invite');
    await _invite(tester, (await repository.band('b1'))!);
    await _settleAutosave(tester);
    expect(
      (await repository.manageOpportunities('org1')).length,
      originalCount,
    );
    await _reveal(tester, find.byType(CircleIconButton));
    await tester.tap(find.byType(CircleIconButton));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.orgOpportunities);
    expect(
      (await repository.manageOpportunities('org1')).length,
      originalCount,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets('leaving flushes a pending autosave before going back', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp1');
    await _enterText(tester, 'opp-edit-title', 'Flushed on the way out');
    // No debounce wait: the back chevron must save first.
    await _reveal(tester, find.byType(CircleIconButton));
    await tester.tap(find.byType(CircleIconButton));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.orgOpportunities);
    expect(
      (await repository.opportunity('opp1'))!.title,
      'Flushed on the way out',
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets(
    'autosave waits for a valid deadline and flushes queued invites on create',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _CountingRepository(auth: auth);
      final harness = await _pumpEditor(tester, auth, repository, 'new');
      await _enterText(tester, 'opp-edit-title', 'Minimal draft');
      await _tap(tester, 'opp-edit-venue-v1');
      // A deadline after the start is rejected by the server, so nothing
      // saves and the WHEN row stays pending.
      await _pickWhen(tester, date: _futureDate(30), deadline: _futureDate(31));
      await _settleAutosave(tester);
      expect(repository.creates, 0);
      expect(find.byKey(const ValueKey('opp-edit-pulse-when')), findsOne);
      await _reveal(tester, find.byKey(const ValueKey('opp-edit-when')));
      expect(find.textContaining('MUST BE BEFORE START'), findsOneWidget);
      await _pickWhen(tester, deadline: _futureDate(20));
      await _tap(tester, 'opp-edit-visibility-invite');
      await _invite(tester, (await repository.band('b1'))!);
      await _invite(tester, (await repository.band('b2'))!);
      await _removeInvite(tester, 'b2');
      await _settleAutosave(tester);
      expect(repository.creates, 1);
      final saved = (await repository.manageOpportunities(
        'org1',
      )).singleWhere((opportunity) => opportunity.title == 'Minimal draft');
      expect(saved.status, OpportunityStatus.draft);
      expect(saved.invitedBandIds, ['b1']);
      await _expectProgress(tester, 'REQUIRED — 3 OF 4 DONE');
      await _tapAction(tester, 'publish');
      expect(find.byKey(const ValueKey('opp-verify-sheet')), findsNothing);
      expect(find.byKey(const ValueKey('opp-edit-pulse-slots')), findsOne);
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets(
    'closed applications validate and reopen with the chosen deadline',
    (tester) async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      await repository.closeOpportunityApplications('opp1');
      final harness = await _pumpEditor(tester, auth, repository, 'opp1');
      final fixture = (await repository.opportunity('opp1'))!;
      await _pickWhen(
        tester,
        deadline: fixture.startsAt.add(const Duration(days: 1)),
      );
      await _tap(tester, 'opp-edit-reopen');
      await _reveal(tester, find.byKey(const ValueKey('opp-edit-feedback')));
      expect(find.text('Still needs a deadline before start.'), findsOneWidget);
      expect(
        (await repository.opportunity('opp1'))!.status,
        OpportunityStatus.applicationsClosed,
      );
      final deadline = _futureDate(7);
      await _pickWhen(tester, deadline: deadline);
      await _tap(tester, 'opp-edit-reopen');
      final reopened = (await repository.opportunity('opp1'))!;
      expect(reopened.status, OpportunityStatus.open);
      expect(reopened.applicationsCloseAt, deadline);
      // A later autosave uses the revision returned by the transition's reload.
      await _enterText(tester, 'opp-edit-title', 'Reopened show');
      await _settleAutosave(tester);
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
    await _tap(tester, 'opp-edit-cancel');
    await tester.tap(find.widgetWithText(TextButton, 'KEEP'));
    await tester.pumpAndSettle();
    expect(
      (await repository.opportunity('opp1'))!.status,
      OpportunityStatus.open,
    );
    await _tap(tester, 'opp-edit-cancel');
    await tester.tap(find.widgetWithText(FilledButton, 'CONFIRM'));
    await tester.pumpAndSettle();
    expect(
      (await repository.opportunity('opp1'))!.status,
      OpportunityStatus.cancelled,
    );
    expect(harness.app.current.screen, Screen.orgOpportunities);
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
      expect(find.byType(EpBottomCta), findsNothing);
      expect(find.byKey(const ValueKey('opp-edit-publish')), findsNothing);
      expect(find.byKey(const ValueKey('opp-edit-preview')), findsNothing);
      final chipFinder = find.byKey(const ValueKey('opp-edit-invite-b1'));
      await _reveal(tester, chipFinder);
      final chip = tester.widget<EpChip>(chipFinder);
      expect(chip.label, (await repository.band('b1'))!.name);
      expect(chip.onRemoved, isNull);
      expect(find.byKey(const ValueKey('opp-edit-cancel')), findsNothing);
      expect(find.byKey(const ValueKey('opp-edit-delete')), findsNothing);
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
      await _reveal(tester, find.byKey(const Key('opp-edit-ticketing-paid')));
      expect(_ticketingPill(tester, 'paid').onPressed, isNull);
      await _reveal(tester, find.byKey(const Key('opp-edit-ticket-price')));
      expect(_field(tester, 'opp-edit-ticket-price').enabled, isTrue);
      expect(_field(tester, 'opp-edit-ticket-capacity').enabled, isTrue);
      await _reveal(tester, find.byKey(const Key('opp-edit-update-ticketing')));
      expect(
        find.byKey(const Key('opp-edit-update-ticketing')),
        findsOneWidget,
      );
      expect(find.byType(EpBottomCta), findsNothing);
      expect(find.byKey(const ValueKey('opp-edit-publish')), findsNothing);
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
      await _tap(tester, 'opp-edit-details-toggle');
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
      expect(find.byKey(const Key('opp-edit-paid-locked')), findsNothing);
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets(
    'a private request stays local until every slot has a fee and a deadline is set',
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

      await _enterText(tester, 'opp-edit-title', 'Fee and deadline');
      await _tap(tester, 'opp-location-private-location-org2');
      // A private request names its own deadline: no default from the date.
      await _pickWhen(tester, date: _futureDate(30));
      await _tap(tester, 'opp-edit-slot-add');
      await _settleAutosave(tester);
      expect(
        await repository.manageOpportunities('org2'),
        hasLength(beforeCount),
      );
      await _expectProgress(tester, 'REQUIRED — 2 OF 4 DONE');
      expect(find.byKey(const ValueKey('opp-edit-pulse-when')), findsOne);
      expect(find.byKey(const ValueKey('opp-edit-pulse-slots')), findsOne);

      await _enterText(tester, 'opp-edit-slot-0-guarantee', '150');
      await _tap(tester, 'opp-edit-slot-add');
      await _settleAutosave(tester);
      expect(
        await repository.manageOpportunities('org2'),
        hasLength(beforeCount),
      );
      await _reveal(tester, find.byKey(const ValueKey('opp-edit-slots')));
      expect(find.textContaining('EVERY SLOT NEEDS A FEE'), findsOneWidget);
      await _enterText(tester, 'opp-edit-slot-1-guarantee', '50');
      await _settleAutosave(tester);
      expect(
        await repository.manageOpportunities('org2'),
        hasLength(beforeCount),
      );
      await _expectProgress(tester, 'REQUIRED — 3 OF 4 DONE');

      await _pickWhen(tester, deadline: _futureDate(20));
      await _settleAutosave(tester);
      expect(
        await repository.manageOpportunities('org2'),
        hasLength(beforeCount + 1),
      );
      await _expectProgress(tester, 'REQUIRED — 4 OF 4 DONE');
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
      // Private deadlines must be explicit and strictly before the start.
      await _pickWhen(tester, date: date, deadline: _futureDate(31));
      await _tap(tester, 'opp-edit-slot-add');
      await _enterText(tester, 'opp-edit-slot-0-guarantee', '150');
      await _tap(tester, 'opp-edit-details-toggle');
      await _enterText(tester, 'opp-edit-attendance', '35');
      expectNoFieldInCard(tester);
      await _settleAutosave(tester);
      expect(
        await repository.manageOpportunities('org2'),
        hasLength(beforeCount),
      );
      await _tapAction(tester, 'publish');
      expect(find.byKey(const ValueKey('opp-verify-sheet')), findsNothing);
      expect(find.byKey(const ValueKey('opp-edit-pulse-when')), findsOne);

      final deadline = _futureDate(20);
      await _pickWhen(tester, deadline: deadline);
      await _settleAutosave(tester);

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
      await _reveal(tester, find.byType(CircleIconButton));
      expect(find.text('NEW REQUEST'), findsNothing);
      expect(find.text('COURTYARD BIRTHDAY'), findsOneWidget);
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
      await _tap(tester, 'opp-edit-location');
      final location = tester.widget<EpChip>(
        find.byKey(const Key('opp-location-private-location-org2')),
      );
      expect(location.active, isTrue);
      expect(location.onTap, isNull);
      await _enterText(tester, 'opp-edit-title', 'Updated courtyard request');
      await _settleAutosave(tester);

      final saved = (await repository.opportunity('opp-private'))!;
      expect(saved.title, 'Updated courtyard request');
      expect(saved.mode, OpportunityMode.privateBooking);
      expect(saved.privateLocationId, 'private-location-org2');
      expect(saved.venueId, isNull);
      expect(saved.ticketing, OpportunityTicketing.none);
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets(
    'required progress counts filled rows and the verify sheet opens at four',
    (tester) async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      final harness = await _pumpEditor(tester, auth, repository, 'new');
      expect(
        find.byKey(const ValueKey('opp-edit-required-progress')),
        findsOne,
      );
      expect(find.text('REQUIRED — 0 OF 4 DONE'), findsOneWidget);
      expect(find.text('Name the night'), findsOneWidget);
      expect(find.text('Pick date, doors and start'), findsOneWidget);
      expect(find.text('Choose a venue'), findsOneWidget);
      expect(find.text('Add a slot — headliner, opener, DJ…'), findsOneWidget);
      expect(find.byType(EpReadinessBar), findsNothing);

      await _enterText(tester, 'opp-edit-title', 'Three of four');
      await _tap(tester, 'opp-edit-venue-v1');
      await _pickWhen(tester, date: _futureDate(30));
      await _expectProgress(tester, 'REQUIRED — 3 OF 4 DONE');
      for (final row in ['title', 'when', 'location']) {
        expect(find.byKey(ValueKey('opp-edit-done-$row')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('opp-edit-pulse-slots')), findsOne);
      await _tapAction(tester, 'publish');
      expect(find.byKey(const ValueKey('opp-verify-sheet')), findsNothing);

      // A slot without a fee still leaves the row pending.
      await _tap(tester, 'opp-edit-slot-add');
      await _expectProgress(tester, 'REQUIRED — 3 OF 4 DONE');
      await _enterText(tester, 'opp-edit-slot-0-guarantee', '150');
      await _expectProgress(tester, 'REQUIRED — 4 OF 4 DONE');
      expect(find.byKey(const ValueKey('opp-edit-done-slots')), findsOne);
      await _tapAction(tester, 'publish');
      expect(find.byKey(const ValueKey('opp-verify-sheet')), findsOneWidget);
      await _tap(tester, 'opp-verify-keep');
      expect(find.byKey(const ValueKey('opp-verify-sheet')), findsNothing);
      expect(
        (await repository.manageOpportunities('org1'))
            .where((opportunity) => opportunity.title == 'Three of four')
            .map((opportunity) => opportunity.status),
        everyElement(OpportunityStatus.draft),
      );
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets('a private slot without a fee keeps the slots row pending', (
    tester,
  ) async {
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
    expect(find.text('Choose a location'), findsOneWidget);
    expect(find.text('Add a slot — headliner, opener, DJ…'), findsOneWidget);

    await _enterText(tester, 'opp-edit-title', 'Fee check');
    await _tap(tester, 'opp-location-private-location-org2');
    await _pickWhen(tester, date: _futureDate(30), deadline: _futureDate(20));
    await _tap(tester, 'opp-edit-slot-add');
    await _expectProgress(tester, 'REQUIRED — 3 OF 4 DONE');
    expect(find.byKey(const ValueKey('opp-edit-pulse-slots')), findsOne);
    await _tapAction(tester, 'publish');
    expect(find.byKey(const ValueKey('opp-verify-sheet')), findsNothing);

    await _enterText(tester, 'opp-edit-slot-0-guarantee', '150');
    await _expectProgress(tester, 'REQUIRED — 4 OF 4 DONE');
    expect(find.byKey(const ValueKey('opp-edit-done-slots')), findsOne);
    await _disposeApp(tester, harness.app);
  });

  testWidgets('the details row reveals the six optional fields', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp2');
    await _reveal(
      tester,
      find.byKey(const ValueKey('opp-edit-details-toggle')),
    );
    expect(find.text('STYLE · AGE · EQUIPMENT +3'), findsOneWidget);
    expect(find.byKey(const ValueKey('opp-edit-details-body')), findsNothing);
    expect(find.byKey(const ValueKey('opp-edit-desc')), findsNothing);

    await _tap(tester, 'opp-edit-details-toggle');
    expect(find.byKey(const ValueKey('opp-edit-details-body')), findsOneWidget);
    for (final key in [
      'opp-edit-genre-punk',
      'opp-edit-age-allAges',
      'opp-edit-desc',
      'opp-edit-equipment',
      'opp-edit-requirements',
      'opp-edit-attendance',
    ]) {
      await _reveal(tester, find.byKey(ValueKey(key)));
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expectNoFieldInCard(tester);
    await _disposeApp(tester, harness.app);
  });

  testWidgets('visibility explains that public never reaches the fan map', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp2');
    final note = find.byKey(const ValueKey('opp-edit-visibility-note'));
    await _reveal(tester, note);
    expect(
      find.descendant(
        of: note,
        matching: find.text(
          'Public means visible to artists in Discover — never on the fan map.',
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('opp-edit-invite-add')), findsNothing);
    await _tap(tester, 'opp-edit-visibility-invite');
    expect(find.byKey(const ValueKey('opp-edit-invite-add')), findsOneWidget);
    await _disposeApp(tester, harness.app);
  });

  testWidgets('a saved draft offers a red delete action and no save pill', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp2');
    expect(find.byKey(const ValueKey('opp-edit-save')), findsNothing);
    await _expectSaveState(tester, 'DRAFT · SAVED');

    final delete = find.byKey(const ValueKey('opp-edit-delete'));
    await _reveal(tester, delete);
    expect(
      find.descendant(of: delete, matching: find.text('DELETE DRAFT')),
      findsOneWidget,
    );
    final deleteText = tester.widget<EpMonoText>(
      find.descendant(of: delete, matching: find.byType(EpMonoText)),
    );
    expect(deleteText.color, tester.element(delete).epColors.destructive);
    expect(find.byType(DangerZone), findsNothing);
    expect(find.byType(StickyActionBar), findsNothing);
    expect(find.byKey(const ValueKey('opp-edit-cancel')), findsNothing);
    expect(find.byKey(const ValueKey('opp-edit-close')), findsNothing);
    await _disposeApp(tester, harness.app);
  });

  testWidgets('the WHEN sheet sets date, doors, start and deadline', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'new');
    await _enterText(tester, 'opp-edit-title', 'When flow');
    await _tap(tester, 'opp-edit-venue-v1');
    // The old stacked pickers are gone from the form itself.
    for (final key in ['date', 'doors', 'start', 'deadline']) {
      expect(find.byKey(ValueKey('opp-edit-$key')), findsNothing);
    }
    await _tap(tester, 'opp-edit-when');
    expect(find.byKey(const ValueKey('opp-edit-when-sheet')), findsOneWidget);
    for (final key in ['date', 'doors', 'start', 'deadline']) {
      expect(find.byKey(ValueKey('opp-edit-$key')), findsOneWidget);
    }
    final date = _futureDate(30);
    await _pickDay(tester, date);
    // One notch on each wheel: five minutes later.
    await tester.drag(
      find.byKey(const ValueKey('opp-edit-doors')),
      const Offset(0, -32),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('opp-edit-start')),
      const Offset(0, -32),
    );
    await tester.pumpAndSettle();
    final deadline = _futureDate(20);
    await _pickDeadline(tester, deadline);
    await _done(tester);
    expect(find.byKey(const ValueKey('opp-edit-when-sheet')), findsNothing);

    await _reveal(tester, find.byKey(const ValueKey('opp-edit-when')));
    expect(
      find.text('${dateLabel(date).toUpperCase()} · START 9:05 PM'),
      findsOneWidget,
    );
    expect(
      find.text(
        'DOORS 8:05 PM · APPLY DEADLINE ${dateLabel(deadline).toUpperCase()}',
      ),
      findsOneWidget,
    );
    await _settleAutosave(tester);
    final saved = (await repository.manageOpportunities(
      'org1',
    )).singleWhere((opportunity) => opportunity.title == 'When flow');
    expect(saved.startsAt, DateTime(date.year, date.month, date.day, 21, 5));
    expect(saved.doorsAt, DateTime(date.year, date.month, date.day, 20, 5));
    expect(saved.applicationsCloseAt, deadline);
    await _disposeApp(tester, harness.app);
  });

  testWidgets('the verify sheet summarizes the draft and rows jump back', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp2');
    final fixture = (await repository.opportunity('opp2'))!;
    await _enterText(tester, 'opp-edit-slot-0-guarantee', '120');
    await _tapAction(tester, 'publish');
    final sheet = find.byKey(const ValueKey('opp-verify-sheet'));
    expect(sheet, findsOneWidget);
    expect(find.text('VERIFY & PUBLISH'), findsOneWidget);
    expect(
      find.text(
        'Check it once. This is exactly what artists see when it goes live.',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('opp-verify-title')),
        matching: find.text(fixture.title),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('opp-verify-when')),
        matching: find.text(
          '${dateLabel(fixture.startsAt).toUpperCase()} · Doors 8:00 PM · Start 6:00 PM',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('opp-verify-deadline')),
        matching: find.text(
          dateLabel(fixture.applicationsCloseAt).toUpperCase(),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('opp-verify-venue')),
        matching: find.textContaining('The Foghorn Club'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('opp-verify-slots')),
        matching: find.text(r'1 · opener $120.00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('opp-verify-ticketing')),
        matching: find.text('RSVP'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('opp-verify-visibility')),
        matching: find.text('Public'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Publishing saves everything in one step — no draft gate, no going back to save first.',
      ),
      findsOneWidget,
    );

    // Tapping a row keeps editing and lands on that row's controls.
    expect(find.byKey(const Key('opp-edit-venue-v1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('opp-verify-venue')));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(find.byKey(const Key('opp-edit-venue-v1')), findsOneWidget);
    expect(
      (await repository.opportunity('opp2'))!.status,
      OpportunityStatus.draft,
    );

    await _tapAction(tester, 'publish');
    await _tap(tester, 'opp-verify-keep');
    expect(sheet, findsNothing);
    expect(
      (await repository.opportunity('opp2'))!.status,
      OpportunityStatus.draft,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets('a failed publish shows the server message and keeps the form', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _PublishFailsRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp2');
    await _enterText(tester, 'opp-edit-slot-0-guarantee', '120');
    await _tapAction(tester, 'publish');
    await _tap(tester, 'opp-verify-publish');
    await _reveal(tester, find.byKey(const ValueKey('opp-edit-feedback')));
    expect(find.text('The venue is closed that night'), findsOneWidget);
    expect(find.byType(OpportunityEditScreen), findsOneWidget);
    expect(
      (await repository.opportunity('opp2'))!.status,
      OpportunityStatus.draft,
    );
    expect(
      (await repository.opportunity('opp2'))!.slots.single.guaranteeMinor,
      12000,
    );
    expect(_action(tester, 'publish').onPressed, isNotNull);
    await _disposeApp(tester, harness.app);
  });

  testWidgets('PREVIEW renders the artist-facing presentation of the draft', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp2');
    // Unsaved edits show up in the preview too.
    await _enterText(tester, 'opp-edit-title', 'Patio Sessions Preview');
    await _tapAction(tester, 'preview');
    final sheet = find.byKey(const ValueKey('opp-edit-preview-sheet'));
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(
        of: sheet,
        matching: find.byType(OpportunityDetailPresentation),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('opp-preview-badge')), findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Patio Sessions Preview')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('opp-detail-slot-preview-0')), findsOneWidget);
    expect(find.byKey(const Key('opp-detail-apply')), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    await _disposeApp(tester, harness.app);
  });
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

/// The pinned PREVIEW / REVIEW & PUBLISH pills.
EpPill _action(WidgetTester tester, String action) =>
    tester.widget<EpPill>(find.byKey(ValueKey('opp-edit-$action')));

EpPill _ticketingPill(WidgetTester tester, String mode) =>
    tester.widget<EpPill>(find.byKey(ValueKey('opp-edit-ticketing-$mode')));

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

// The preview / publish pills are pinned; the rest scrolls with the form.
Future<void> _tapAction(WidgetTester tester, String action) =>
    _tap(tester, 'opp-edit-$action');

/// Lets the 600 ms debounce fire and the resulting save settle.
Future<void> _settleAutosave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

/// The progress and save-state line sits at the top of the form.
Future<void> _expectProgress(WidgetTester tester, String text) async {
  await _reveal(
    tester,
    find.byKey(const ValueKey('opp-edit-required-progress')),
  );
  expect(find.text(text), findsOneWidget);
}

Future<void> _expectSaveState(WidgetTester tester, String text) async {
  final state = find.byKey(const ValueKey('opp-edit-save-state'));
  await _reveal(tester, state);
  expect(find.descendant(of: state, matching: find.text(text)), findsOneWidget);
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

/// Opens the WHEN sheet from the row, applies what is given, and closes it.
Future<void> _pickWhen(
  WidgetTester tester, {
  DateTime? date,
  DateTime? deadline,
}) async {
  await _tap(tester, 'opp-edit-when');
  expect(find.byKey(const ValueKey('opp-edit-when-sheet')), findsOneWidget);
  // The deadline goes first: once touched it survives the date's default,
  // so an autosave firing mid-sheet never sees a deadline the test did not
  // choose.
  if (deadline != null) await _pickDeadline(tester, deadline);
  if (date != null) await _pickDay(tester, date);
  await _done(tester);
}

/// Taps a day on the sheet's rolling calendar.
Future<void> _pickDay(WidgetTester tester, DateTime date) async {
  final cell = find.byKey(
    ValueKey('opp-edit-day-${date.year}-${date.month}-${date.day}'),
  );
  await tester.scrollUntilVisible(
    cell,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('opp-edit-date')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(cell);
  await tester.pumpAndSettle();
}

/// Opens the sheet's deadline row and types the date into the picker.
Future<void> _pickDeadline(WidgetTester tester, DateTime date) async {
  await tester.tap(find.byKey(const ValueKey('opp-edit-deadline')));
  await tester.pumpAndSettle();
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

Future<void> _done(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'DONE'));
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

/// Counts the create and update calls the autosave makes.
class _CountingRepository extends DemoRepository {
  _CountingRepository({required super.auth});

  int creates = 0;
  int updates = 0;

  @override
  Future<({String opportunityId, String slug})> createOpportunity({
    required String organizationId,
    required String title,
    String? desc,
    String? venueId,
    OpportunityMode mode = OpportunityMode.publicEvent,
    String? privateLocationId,
    String? eventType,
    int? expectedAttendance,
    List<String>? genres,
    required DateTime startsAt,
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
  }) {
    creates++;
    return super.createOpportunity(
      organizationId: organizationId,
      title: title,
      desc: desc,
      venueId: venueId,
      mode: mode,
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
  }) {
    updates++;
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

/// Throws on the [failing]th update call and passes every other one through.
class _UpdateRepository extends DemoRepository {
  _UpdateRepository({
    required super.auth,
    required this.failing,
    required this.error,
  });

  final int failing;
  final Object error;
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
    if (++_updates == failing) throw error;
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

/// Accepts every save but refuses to open, like a server-side publish rule.
class _PublishFailsRepository extends DemoRepository {
  _PublishFailsRepository({required super.auth});

  @override
  Future<({int revision, DateTime applicationsCloseAt})> openOpportunity({
    required String opportunityId,
    required int expectedRevision,
  }) async => throw StateError('The venue is closed that night');
}

class _ConflictOnceRepository extends _UpdateRepository {
  _ConflictOnceRepository({required super.auth})
    : super(failing: 2, error: StateError('Opportunity changed elsewhere'));
}

class _FailOnceRepository extends _UpdateRepository {
  _FailOnceRepository({required super.auth})
    : super(failing: 1, error: StateError('Network unavailable'));
}
