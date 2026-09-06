import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/money.dart';
import 'package:earplug/screens/gig_detail.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';

void main() {
  testWidgets('quantity starts at one and stays between one and ten', (
    tester,
  ) async {
    await _openPurchaseSheet(tester);
    final quantity = find.byKey(const Key('ticket-qty'));

    expect(tester.widget<Text>(quantity).data, '1');
    await tester.tap(find.byKey(const Key('ticket-qty-minus')));
    await tester.pump();
    expect(tester.widget<Text>(quantity).data, '1');

    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byKey(const Key('ticket-qty-plus')));
      await tester.pump();
    }
    expect(tester.widget<Text>(quantity).data, '10');
    expect(find.text(r'10 × $25.00'), findsOne);
    expectNoFieldInCard(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('holding tickets shows the repository subtotal, fee and total', (
    tester,
  ) async {
    final harness = await _openPurchaseSheet(tester);
    expect(find.byKey(const Key('ticket-error')), findsNothing);
    expect(find.text('EarPlug fee and total shown after the hold'), findsOne);
    await tester.tap(find.byKey(const Key('ticket-qty-plus')));
    await tester.pump();
    expect(find.text(r'2 × $25.00'), findsOne);

    await tester.tap(find.byKey(const Key('ticket-hold')));
    await tester.pumpAndSettle();

    final reservation = harness.app.pendingReservation!;
    expect(reservation.quantity, 2);
    expect(find.text('YOUR HOLD'), findsOne);
    expect(find.text('Held for 30 minutes'), findsOne);
    final amounts = {
      'Tickets': reservation.subtotalMinor,
      'EarPlug fee': reservation.feeMinor,
      'Total': reservation.totalMinor,
    };
    for (final entry in amounts.entries) {
      final row = find.ancestor(
        of: find.text(entry.key),
        matching: find.byType(Row),
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(Money(entry.value, reservation.currency).label),
        ),
        findsOne,
      );
    }
    expectNoFieldInCard(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('continue to payment launches checkout and closes the sheet', (
    tester,
  ) async {
    final launched = <String>[];
    final harness = await _openPurchaseSheet(
      tester,
      beforePump: (app) {
        app.hostedUrlLauncher = (url) async {
          launched.add(url);
        };
      },
    );
    await tester.tap(find.byKey(const Key('ticket-hold')));
    await tester.pumpAndSettle();
    final reservation = harness.app.pendingReservation!;

    await tester.tap(find.byKey(const Key('ticket-pay')));
    await tester.pumpAndSettle();

    expect(launched, ['https://demo.stripe/tickets/${reservation.orderId}']);
    expect(find.byKey(const Key('ticket-pay')), findsNothing);
    expect(find.byType(EpSheetShell), findsNothing);
    expect(harness.app.pendingReservation, same(reservation));
  });

  testWidgets('release hold clears the reservation and closes the sheet', (
    tester,
  ) async {
    final harness = await _openPurchaseSheet(tester);
    await tester.tap(find.byKey(const Key('ticket-hold')));
    await tester.pumpAndSettle();
    expect(harness.app.pendingReservation, isNotNull);

    await tester.tap(find.byKey(const Key('ticket-release')));
    await tester.pumpAndSettle();

    expect(harness.app.pendingReservation, isNull);
    expect(find.byKey(const Key('ticket-release')), findsNothing);
    expect(find.byType(EpSheetShell), findsNothing);
  });

  testWidgets('sold-out gigs show the clean reservation error inline', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    for (var i = 0; i < 4; i++) {
      await repository.reserveTickets(gigId: 'g8', quantity: 10);
    }
    final harness = await _openPurchaseSheet(
      tester,
      auth: auth,
      repository: repository,
    );

    await tester.tap(find.byKey(const Key('ticket-hold')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('ticket-error'))).data,
      'Not enough tickets available',
    );
    expect(harness.app.pendingReservation, isNull);
    expect(find.byKey(const Key('ticket-hold')), findsOne);
    expect(find.byKey(const Key('ticket-pay')), findsNothing);
  });

  testWidgets('an existing reservation opens directly on your hold', (
    tester,
  ) async {
    final harness = await _openPurchaseSheet(
      tester,
      beforePump: (app) async {
        await app.reserveTickets('g8', 3);
      },
    );
    final reservation = harness.app.pendingReservation!;

    expect(find.text('YOUR HOLD'), findsOne);
    expect(find.byKey(const Key('ticket-hold')), findsNothing);
    expect(find.byKey(const Key('ticket-pay')), findsOne);
    expect(find.text(reservation.total.label), findsOne);
  });

  testWidgets('dismissing a hold preserves it for the next sheet opening', (
    tester,
  ) async {
    final harness = await _openPurchaseSheet(tester);
    await tester.tap(find.byKey(const Key('ticket-hold')));
    await tester.pumpAndSettle();
    final reservation = harness.app.pendingReservation!;

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byType(EpSheetShell), findsNothing);
    expect(harness.app.pendingReservation, same(reservation));
    await tester.tap(find.byKey(const Key('gig-buy-tickets')));
    await tester.pumpAndSettle();
    expect(find.text('YOUR HOLD'), findsOne);
    expect(find.byKey(const Key('ticket-pay')), findsOne);
    expect(harness.app.pendingReservation, same(reservation));
  });

  testWidgets('a failed checkout launch keeps the hold available for retry', (
    tester,
  ) async {
    final harness = await _openPurchaseSheet(
      tester,
      beforePump: (app) {
        app.hostedUrlLauncher = (_) async {
          throw StateError('Could not open checkout');
        };
      },
    );
    await tester.tap(find.byKey(const Key('ticket-hold')));
    await tester.pumpAndSettle();
    final reservation = harness.app.pendingReservation!;

    await tester.tap(find.byKey(const Key('ticket-pay')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('ticket-error'))).data,
      'Could not open checkout',
    );
    expect(find.byKey(const Key('ticket-pay')), findsOne);
    expect(harness.app.pendingReservation, same(reservation));

    final launched = <String>[];
    harness.app.hostedUrlLauncher = (url) async {
      launched.add(url);
    };
    await tester.tap(find.byKey(const Key('ticket-pay')));
    await tester.pumpAndSettle();
    expect(launched, hasLength(1));
    expect(find.byType(EpSheetShell), findsNothing);
  });
}

Future<AppHarness> _openPurchaseSheet(
  WidgetTester tester, {
  FakeAuthService? auth,
  DemoRepository? repository,
  FutureOr<void> Function(AppState app)? beforePump,
}) async {
  final resolvedAuth = auth ?? FakeAuthService();
  if (!resolvedAuth.signedIn) await resolvedAuth.signInDemo();
  final harness = await pumpApp(
    tester,
    auth: resolvedAuth,
    repository: repository,
    home: const Scaffold(body: GigDetailScreen(gigId: 'g8')),
    beforePump: beforePump,
  );
  await tester.tap(find.byKey(const Key('gig-buy-tickets')));
  await tester.pumpAndSettle();
  return harness;
}
