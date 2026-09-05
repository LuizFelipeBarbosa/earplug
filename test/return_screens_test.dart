import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/checkout_return.dart';
import 'package:earplug/screens/stripe_return.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  late FakeAuthService auth;
  late _ControlledReturnRepository repository;

  setUp(() async {
    auth = FakeAuthService();
    await auth.signInDemo();
    repository = _ControlledReturnRepository(auth: auth);
  });

  testWidgets('CheckoutReturn waits, receives payment, and opens the booking', (
    tester,
  ) async {
    final pending = Completer<CheckoutStatus?>();
    repository.pendingCheckout = pending;
    final harness = await pumpApp(
      tester,
      home: const CheckoutReturnScreen(
        sessionId: 'cs_paid',
        interval: Duration(milliseconds: 5),
        timeout: Duration(milliseconds: 25),
      ),
      auth: auth,
      repository: repository,
      pumpFor: Duration.zero,
    );

    expect(find.text('Confirming your payment…'), findsOneWidget);
    expect(find.text('This usually takes a few seconds.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(repository.checkoutRequests, ['cs_paid']);

    pending.complete(_paidCheckout);
    // enterOrganizer switches synchronously, then pumps the queued completion.
    await enterOrganizer(tester, harness, 'org1');
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byKey(const Key('checkout-return-booking')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bookingDetail);
    expect(harness.app.current.param, 'bk1');
    expect(harness.app.bookingById('bk1')?.viewerSide, BookingSide.organizer);
  });

  testWidgets('CheckoutReturn accepts a confirmed booking before paid status', (
    tester,
  ) async {
    repository.checkoutResult = const CheckoutStatus(
      bookingId: 'bk1',
      paymentStatus: PaymentRecordStatus.checkoutOpen,
      bookingStatus: BookingStatus.confirmed,
    );
    await pumpApp(
      tester,
      home: const CheckoutReturnScreen(
        sessionId: 'cs_confirmed',
        interval: Duration(milliseconds: 5),
        timeout: Duration(milliseconds: 25),
      ),
      auth: auth,
      repository: repository,
    );

    expect(find.text('Payment received'), findsOneWidget);
    expect(find.byKey(const Key('checkout-return-retry')), findsNothing);
  });

  testWidgets('CheckoutReturn timeout offers the booking and retries polling', (
    tester,
  ) async {
    repository.checkoutResult = const CheckoutStatus(
      bookingId: 'bk1',
      paymentStatus: PaymentRecordStatus.checkoutOpen,
      bookingStatus: BookingStatus.awaitingPayment,
    );
    final harness = await pumpApp(
      tester,
      home: const CheckoutReturnScreen(
        sessionId: 'cs_open',
        interval: Duration(milliseconds: 5),
        timeout: Duration(milliseconds: 25),
      ),
      auth: auth,
      repository: repository,
    );
    await enterOrganizer(tester, harness, 'org1');

    expect(find.text("We haven't heard from Stripe yet"), findsOneWidget);
    expect(
      find.text(
        'Your payment may still be processing. Check the booking in a minute.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('checkout-return-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('checkout-return-booking')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bookingDetail);
    expect(harness.app.current.param, 'bk1');
    expect(harness.app.bookingById('bk1')?.viewerSide, BookingSide.organizer);

    final requestsBeforeRetry = repository.checkoutRequests.length;
    final pending = Completer<CheckoutStatus?>();
    repository.pendingCheckout = pending;
    await tester.tap(find.byKey(const Key('checkout-return-retry')));
    await tester.pump();
    expect(find.text('Confirming your payment…'), findsOneWidget);
    expect(repository.checkoutRequests.length, requestsBeforeRetry + 1);

    pending.complete(_paidCheckout);
    await tester.pumpAndSettle();
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.byKey(const Key('checkout-return-retry')), findsNothing);
  });

  testWidgets('CheckoutReturn unknown session offers a terminal back action', (
    tester,
  ) async {
    repository.checkoutResult = null;
    final harness = await pumpApp(
      tester,
      home: const CheckoutReturnScreen(
        sessionId: 'unknown',
        interval: Duration(milliseconds: 5),
        timeout: Duration(milliseconds: 25),
      ),
      auth: auth,
      repository: repository,
      beforePump: (app) => app.resetTo(Screen.checkoutReturn),
    );

    expect(find.text("This checkout isn't available."), findsOneWidget);
    expect(find.byKey(const Key('checkout-return-booking')), findsNothing);
    expect(find.byKey(const Key('checkout-return-retry')), findsNothing);
    await tester.tap(find.byKey(const Key('checkout-return-back')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.home);
  });

  testWidgets('CheckoutCancel explains cancellation and opens the booking', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const CheckoutCancelScreen(bookingId: 'bk1'),
      auth: auth,
      repository: repository,
    );
    await enterOrganizer(tester, harness, 'org1');

    expect(find.text('Payment not completed'), findsOneWidget);
    expect(
      find.text('No charge was made. You can pay again from the booking.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('checkout-cancel-booking')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bookingDetail);
    expect(harness.app.current.param, 'bk1');
    expect(harness.app.bookingById('bk1')?.viewerSide, BookingSide.organizer);
  });

  for (final band in [true, false]) {
    final kind = band ? 'band' : 'org';
    final id = band ? 'b1' : 'org1';
    final destination = band ? Screen.bandPayouts : Screen.orgSettings;

    testWidgets('StripeReturn $kind checks setup and lets AppState navigate', (
      tester,
    ) async {
      final pending = Completer<void>();
      repository.pendingAccountRefresh = pending;
      final harness = await pumpApp(
        tester,
        home: StripeReturnScreen(param: '$kind:$id'),
        auth: auth,
        repository: repository,
        beforePump: (app) => app.switchToBand('b2'),
        pumpFor: Duration.zero,
      );

      expect(find.text('Checking your Stripe setup…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        band
            ? repository.bandAccountRequests
            : repository.organizationAccountRequests,
        [id],
      );
      expect(harness.app.current.screen, isNot(destination));

      pending.complete();
      // The fixed home keeps its spinner even after AppState has navigated.
      await tester.pump();
      expect(harness.app.current.screen, destination);
      expect(band ? harness.app.bandId : harness.app.organizationId, id);
    });

    testWidgets(
      'StripeReturn $kind refresh waits for a tap and blocks repeats',
      (tester) async {
        final launched = <String>[];
        final pending = Completer<void>();
        repository.pendingAccountRefresh = pending;
        final harness = await pumpApp(
          tester,
          home: StripeReturnScreen(param: '$kind-refresh:$id'),
          auth: auth,
          repository: repository,
          beforePump: (app) {
            app.switchToBand('b2');
            app.hostedUrlLauncher = (url) async {
              launched.add(url);
            };
          },
        );

        expect(find.text('Your Stripe link expired'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(repository.bandAccountRequests, isEmpty);
        expect(repository.organizationAccountRequests, isEmpty);
        expect(launched, isEmpty);
        final button = find.byKey(const Key('stripe-return-continue'));
        expect(button, findsOneWidget);

        await tester.tap(button);
        await tester.tap(button);
        await tester.pump();
        expect(tester.widget<EpButton>(button).kind, EpButtonKind.disabled);
        expect(
          band
              ? repository.bandAccountRequests
              : repository.organizationAccountRequests,
          [id],
        );
        expect(launched, isEmpty);

        pending.complete();
        await tester.pumpAndSettle();
        expect(harness.app.current.screen, destination);
        expect(band ? harness.app.bandId : harness.app.organizationId, id);
        expect(launched, ['https://demo.stripe/onboard/$id']);
      },
    );
  }

  for (final param in [
    'nonsense',
    'band:',
    'org-refresh:',
    'other:b1',
    'band:b1:extra',
  ]) {
    testWidgets('StripeReturn rejects malformed param "$param"', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        home: StripeReturnScreen(param: param),
        auth: auth,
        repository: repository,
        beforePump: (app) => app.resetTo(Screen.stripeReturn),
      );

      expect(find.text("This link isn't valid."), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(repository.bandAccountRequests, isEmpty);
      expect(repository.organizationAccountRequests, isEmpty);
      await tester.tap(find.byKey(const Key('stripe-return-back')));
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.home);
    });
  }
}

const _paidCheckout = CheckoutStatus(
  bookingId: 'bk1',
  paymentStatus: PaymentRecordStatus.paid,
  bookingStatus: BookingStatus.awaitingPayment,
);

class _ControlledReturnRepository extends DemoRepository {
  _ControlledReturnRepository({required super.auth});

  CheckoutStatus? checkoutResult;
  Completer<CheckoutStatus?>? pendingCheckout;
  Completer<void>? pendingAccountRefresh;
  final checkoutRequests = <String>[];
  final bandAccountRequests = <String>[];
  final organizationAccountRequests = <String>[];

  @override
  Future<CheckoutStatus?> checkoutStatus(String sessionId) async {
    checkoutRequests.add(sessionId);
    final pending = pendingCheckout;
    if (pending != null) return pending.future;
    return checkoutResult;
  }

  @override
  Future<StripeAccountStatus> refreshBandAccountStatus(String bandId) async {
    bandAccountRequests.add(bandId);
    await pendingAccountRefresh?.future;
    return super.refreshBandAccountStatus(bandId);
  }

  @override
  Future<StripeAccountStatus> refreshOrganizationAccountStatus(
    String organizationId,
  ) async {
    organizationAccountRequests.add(organizationId);
    await pendingAccountRefresh?.future;
    return super.refreshOrganizationAccountStatus(organizationId);
  }
}
