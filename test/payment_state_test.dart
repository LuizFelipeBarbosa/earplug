import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/async.dart';

void main() {
  late _ControlledPaymentRepository repository;
  late AppState app;
  late List<String> launched;

  setUp(() async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    repository = _ControlledPaymentRepository(auth: auth);
    app = AppState.demo(
      auth: auth,
      repository: repository,
      now: () => DateTime(2020),
    );
    addTearDown(app.dispose);
    launched = [];
    app.hostedUrlLauncher = (url) async {
      launched.add(url);
    };
    await flushAsyncWork();
  });

  test(
    'band onboarding launches the repository URL for the current band',
    () async {
      app.switchToBand('b1');

      await app.startBandOnboarding();

      expect(repository.bandOnboardingRequests, ['b1']);
      expect(launched, ['https://demo.stripe/onboard/b1']);
    },
  );

  test('organization onboarding launches the repository URL', () async {
    app.switchToOrganization('org1');

    await app.startOrganizationOnboarding();

    expect(repository.organizationOnboardingRequests, ['org1']);
    expect(launched, ['https://demo.stripe/onboard/org1']);
  });

  test('Express dashboards launch for each current identity', () async {
    await app.handleStripeReturn(band: true, id: 'b1');
    await app.openBandExpressDashboard();
    await app.handleStripeReturn(band: false, id: 'org1');
    await app.openOrganizationExpressDashboard();

    expect(launched, [
      'https://demo.stripe/dashboard/b1',
      'https://demo.stripe/dashboard/org1',
    ]);
  });

  test('payInstallment launches Checkout and returns its session id', () async {
    final sessionId = await app.payInstallment('payment1');

    expect(repository.checkoutRequests, ['payment1']);
    expect(launched, [repository.checkoutLink.url]);
    expect(sessionId, repository.checkoutLink.sessionId);
  });

  test(
    'Checkout stops when paid and refreshes the booking and payments',
    () async {
      await app.loadBooking('bk1');
      repository.bookingRequests.clear();
      repository.completeCheckoutAfter = 3;

      final status = await app.awaitCheckout(
        'cs_123',
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 200),
      );
      await flushAsyncWork();

      expect(status?.paymentStatus, PaymentRecordStatus.paid);
      expect(repository.checkoutStatusRequests, ['cs_123', 'cs_123', 'cs_123']);
      expect(repository.bookingRequests, ['bk1']);
      expect(repository.paymentRequests, ['bk1']);
      expect(app.paymentsFor('bk1'), repository.payments);
    },
  );

  test(
    'Checkout keeps polling while confirmed until the payment record is paid',
    () async {
      repository.checkoutResult = const CheckoutStatus(
        bookingId: 'bk1',
        paymentStatus: PaymentRecordStatus.checkoutOpen,
        bookingStatus: BookingStatus.confirmed,
      );
      repository.completeCheckoutAfter = 3;

      final status = await app.awaitCheckout(
        'cs_123',
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 200),
      );
      await flushAsyncWork();

      expect(status?.paymentStatus, PaymentRecordStatus.paid);
      expect(repository.checkoutStatusRequests, ['cs_123', 'cs_123', 'cs_123']);
      expect(repository.bookingRequests, ['bk1']);
      expect(repository.paymentRequests, ['bk1']);
      expect(app.paymentsFor('bk1'), repository.payments);
    },
  );

  test('Checkout retries individual poll errors', () async {
    repository.failedCheckoutCalls = 1;
    repository.completeCheckoutAfter = 2;

    final status = await app.awaitCheckout(
      'cs_123',
      interval: const Duration(milliseconds: 5),
      timeout: const Duration(milliseconds: 200),
    );
    await flushAsyncWork();

    expect(status?.paymentStatus, PaymentRecordStatus.paid);
    expect(repository.checkoutStatusRequests, hasLength(2));
  });

  test('Checkout timeout still refreshes the last known booking', () async {
    final status = await app.awaitCheckout(
      'cs_123',
      interval: const Duration(milliseconds: 5),
      timeout: const Duration(milliseconds: 25),
    );
    await flushAsyncWork();

    expect(status, isNull);
    expect(repository.checkoutStatusRequests, isNotEmpty);
    expect(repository.bookingRequests, ['bk1']);
    expect(repository.paymentRequests, ['bk1']);
  });

  test(
    'unknown Checkout sessions time out without a booking refresh',
    () async {
      repository.checkoutResult = null;

      final status = await app.awaitCheckout(
        'unknown',
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 20),
      );

      expect(status, isNull);
      expect(repository.bookingRequests, isEmpty);
      expect(repository.paymentRequests, isEmpty);
    },
  );

  test('disposing during a Checkout poll prevents further work', () async {
    final disposedApp = AppState.demo(repository: repository);
    await flushAsyncWork();
    repository.pendingCheckout = Completer<CheckoutStatus?>();
    final poll = disposedApp.awaitCheckout('cs_123');
    disposedApp.dispose();
    repository.pendingCheckout!.complete(_paidCheckout);

    expect(await poll, isNull);
    await flushAsyncWork();
    expect(repository.checkoutStatusRequests, ['cs_123']);
    expect(repository.bookingRequests, isEmpty);
    expect(repository.paymentRequests, isEmpty);
  });

  test('Stripe return route selects the band or organizer identity', () {
    app.go(Screen.stripeReturn, 'band:b1');
    expect(
      app.identity,
      isA<BandIdentity>().having((identity) => identity.bandId, 'bandId', 'b1'),
    );

    app.go(Screen.stripeReturn, 'org:org1');
    expect(
      app.identity,
      isA<OrganizerIdentity>().having(
        (identity) => identity.organizationId,
        'organizationId',
        'org1',
      ),
    );
  });

  test(
    'band Stripe return switches identity, refreshes status, and routes',
    () async {
      app.switchToBand('b2');
      await flushAsyncWork();

      await app.handleStripeReturn(band: true, id: 'b1');
      await flushAsyncWork();

      expect(app.bandId, 'b1');
      expect(repository.bandAccountRequests, ['b1']);
      expect(app.bandPayoutStatus?.state, StripeAccountState.enabled);
      expect(app.bandPayoutStatus?.payoutsEnabled, isTrue);
      expect(app.current.screen, Screen.bandPayouts);
    },
  );

  test(
    'organization Stripe return switches identity and routes to settings',
    () async {
      app.switchToOrganization('previous-org');

      await app.handleStripeReturn(band: false, id: 'org1');

      expect(app.organizationId, 'org1');
      expect(repository.organizationAccountRequests, ['org1']);
      expect(app.organizationStripeStatus?.state, StripeAccountState.enabled);
      expect(app.current.screen, Screen.orgSettings);
    },
  );

  test(
    'band changes preserve the booking and opportunity hook chain',
    () async {
      app.switchToBand('b1');
      await flushAsyncWork();

      expect(repository.bandStatusRequests, ['b1']);
      expect(app.bandPayoutStatus, isNotNull);
      expect(app.bandBookings, isNotEmpty);
      expect(app.myApplications, isNotEmpty);

      app.resetTo(Screen.bandPayouts);
      await flushAsyncWork();
      expect(repository.bandStatusRequests, ['b1']);
    },
  );

  test(
    'empty identities do not request account status or band payouts',
    () async {
      app.bandId = '';
      app.organizationId = '';
      await app.refreshBandPayoutStatus();
      await app.refreshOrganizationStripeStatus();
      await app.refreshBandPayouts();

      expect(repository.bandStatusRequests, isEmpty);
      expect(repository.organizationStatusRequests, isEmpty);
      expect(repository.bandPayoutRequests, isEmpty);
      expect(app.bandPayoutStatus, isNull);
      expect(app.organizationStripeStatus, isNull);
      expect(app.bandPayouts, isEmpty);
    },
  );

  test(
    'cancellation previews forward both viewer sides and wall-clock time',
    () async {
      for (final side in BookingSide.values) {
        final booking = await app.loadBooking(
          'bk2',
          refresh: true,
          viewAs: side,
        );
        expect(booking?.viewerSide, side);
        final before = DateTime.now();

        final preview = await app.previewCancellation(booking!);

        expect(preview, isNotNull);
        expect(repository.previewRequest?.bookingId, booking.id);
        expect(repository.previewRequest?.side, side);
        expect(repository.previewRequest!.now.isBefore(before), isFalse);
        expect(repository.previewRequest!.now.isAfter(DateTime.now()), isFalse);
      }
    },
  );

  test('refresh errors retain cached data and previews return null', () async {
    app.switchToOrganization('org1');
    await app.refreshBandPayoutStatus();
    await app.refreshOrganizationStripeStatus();
    await app.refreshPayments('bk1');
    await app.refreshPayouts('bk1');
    await app.refreshBandPayouts();
    await app.refreshRefunds('bk1');
    final bandStatus = app.bandPayoutStatus;
    final organizationStatus = app.organizationStripeStatus;
    final booking = (await app.loadBooking('bk1'))!;
    repository.failLoads = true;

    await app.refreshBandPayoutStatus();
    await app.refreshOrganizationStripeStatus();
    await app.refreshPayments('bk1');
    await app.refreshPayouts('bk1');
    await app.refreshBandPayouts();
    await app.refreshRefunds('bk1');

    expect(app.bandPayoutStatus, same(bandStatus));
    expect(app.organizationStripeStatus, same(organizationStatus));
    expect(app.paymentsFor('bk1'), repository.payments);
    expect(app.payoutsFor('bk1'), repository.payouts);
    expect(app.bandPayouts, repository.payouts);
    expect(app.refundsFor('bk1'), repository.refunds);
    expect(await app.previewCancellation(booking), isNull);
  });

  test(
    'sign-out clears payment state and ignores late refreshes and polls',
    () async {
      app.switchToOrganization('org1');
      await app.refreshBandPayoutStatus();
      await app.refreshOrganizationStripeStatus();
      await app.refreshPayments('bk1');
      await app.refreshPayouts('bk1');
      await app.refreshBandPayouts();
      await app.refreshRefunds('bk1');
      expect(app.bandPayoutStatus, isNotNull);
      expect(app.organizationStripeStatus, isNotNull);
      expect(app.paymentsFor('bk1'), isNotEmpty);
      expect(app.payoutsFor('bk1'), isNotEmpty);
      expect(app.bandPayouts, isNotEmpty);
      expect(app.refundsFor('bk1'), isNotEmpty);

      repository.pendingLoads = Completer<void>();
      repository.pendingCheckout = Completer<CheckoutStatus?>();
      final refreshes = [
        app.refreshBandPayoutStatus(),
        app.refreshOrganizationStripeStatus(),
        app.refreshPayments('bk1'),
        app.refreshPayouts('bk1'),
        app.refreshBandPayouts(),
        app.refreshRefunds('bk1'),
      ];
      final poll = app.awaitCheckout('cs_123');
      await app.signOut();
      repository.pendingLoads!.complete();
      repository.pendingCheckout!.complete(_paidCheckout);
      await Future.wait(refreshes);
      expect(await poll, isNull);
      await flushAsyncWork();

      expect(app.bandPayoutStatus, isNull);
      expect(app.organizationStripeStatus, isNull);
      expect(app.paymentsFor('bk1'), isEmpty);
      expect(app.payoutsFor('bk1'), isEmpty);
      expect(app.bandPayouts, isEmpty);
      expect(app.refundsFor('bk1'), isEmpty);
      expect(repository.bookingRequests, isEmpty);
    },
  );

  test('late band status cannot replace the Stripe return refresh', () async {
    repository.pendingLoads = Completer<void>();
    app.switchToBand('b1');
    await app.handleStripeReturn(band: true, id: 'b1');
    repository.pendingLoads!.complete();
    await flushAsyncWork();

    expect(app.bandPayoutStatus?.state, StripeAccountState.enabled);
    expect(app.current.screen, Screen.bandPayouts);
  });
}

const _paidCheckout = CheckoutStatus(
  bookingId: 'bk1',
  paymentStatus: PaymentRecordStatus.paid,
  bookingStatus: BookingStatus.awaitingPayment,
);

class _ControlledPaymentRepository extends DemoRepository {
  _ControlledPaymentRepository({required super.auth});

  final bandOnboardingRequests = <String>[];
  final organizationOnboardingRequests = <String>[];
  final bandAccountRequests = <String>[];
  final organizationAccountRequests = <String>[];
  final bandStatusRequests = <String>[];
  final organizationStatusRequests = <String>[];
  final checkoutRequests = <String>[];
  final checkoutStatusRequests = <String>[];
  final bookingRequests = <String>[];
  final paymentRequests = <String>[];
  final bandPayoutRequests = <String>[];
  final checkoutLink = (
    url: 'https://demo.stripe/checkout/payment1',
    sessionId: 'cs_123',
  );
  CheckoutStatus? checkoutResult = const CheckoutStatus(
    bookingId: 'bk1',
    paymentStatus: PaymentRecordStatus.checkoutOpen,
    bookingStatus: BookingStatus.awaitingPayment,
  );
  int? completeCheckoutAfter;
  int failedCheckoutCalls = 0;
  bool failLoads = false;
  Completer<void>? pendingLoads;
  Completer<CheckoutStatus?>? pendingCheckout;
  ({String bookingId, BookingSide? side, DateTime now})? previewRequest;
  final payments = [
    PaymentRecord(
      id: 'payment1',
      installmentIndex: 0,
      label: 'Deposit',
      amountMinor: 10000,
      currency: 'USD',
      dueAt: DateTime(2026, 9, 10),
      status: PaymentRecordStatus.pending,
      canPay: true,
    ),
  ];
  final payouts = [
    Payout(
      id: 'payout1',
      kind: PayoutKind.completion,
      amountMinor: 9000,
      currency: 'USD',
      status: PayoutStatus.scheduled,
      scheduledFor: DateTime(2026, 10, 3),
    ),
  ];
  final refunds = [
    RefundRecord(
      id: 'refund1',
      amountMinor: 1000,
      currency: 'USD',
      status: RefundStatus.succeeded,
      reason: RefundReason.organizerCancel,
      createdAt: DateTime(2026, 9, 2),
    ),
  ];

  @override
  Future<String> startBandOnboarding(String bandId) {
    bandOnboardingRequests.add(bandId);
    return super.startBandOnboarding(bandId);
  }

  @override
  Future<String> startOrganizationOnboarding(String organizationId) {
    organizationOnboardingRequests.add(organizationId);
    return super.startOrganizationOnboarding(organizationId);
  }

  @override
  Future<StripeAccountStatus> bandPayoutStatus(String bandId) async {
    bandStatusRequests.add(bandId);
    if (failLoads) throw StateError('bandPayoutStatus failed');
    final status = await super.bandPayoutStatus(bandId);
    await pendingLoads?.future;
    return status;
  }

  @override
  Future<StripeAccountStatus> organizationStripeStatus(
    String organizationId,
  ) async {
    organizationStatusRequests.add(organizationId);
    if (failLoads) throw StateError('organizationStripeStatus failed');
    final status = await super.organizationStripeStatus(organizationId);
    await pendingLoads?.future;
    return status;
  }

  @override
  Future<StripeAccountStatus> refreshBandAccountStatus(String bandId) {
    bandAccountRequests.add(bandId);
    return super.refreshBandAccountStatus(bandId);
  }

  @override
  Future<StripeAccountStatus> refreshOrganizationAccountStatus(
    String organizationId,
  ) {
    organizationAccountRequests.add(organizationId);
    return super.refreshOrganizationAccountStatus(organizationId);
  }

  @override
  Future<({String url, String sessionId})> startInstallmentCheckout(
    String paymentRecordId,
  ) async {
    checkoutRequests.add(paymentRecordId);
    return checkoutLink;
  }

  @override
  Future<CheckoutStatus?> checkoutStatus(String sessionId) async {
    checkoutStatusRequests.add(sessionId);
    if (failedCheckoutCalls > 0) {
      failedCheckoutCalls--;
      throw StateError('checkoutStatus failed');
    }
    if (pendingCheckout != null) return pendingCheckout!.future;
    final completeAfter = completeCheckoutAfter;
    if (completeAfter != null &&
        checkoutStatusRequests.length >= completeAfter) {
      return _paidCheckout;
    }
    return checkoutResult;
  }

  @override
  Future<Booking?> booking(String bookingId, {BookingSide? viewAs}) {
    bookingRequests.add(bookingId);
    return super.booking(bookingId, viewAs: viewAs);
  }

  @override
  Future<List<PaymentRecord>> paymentsForBooking(String bookingId) async {
    paymentRequests.add(bookingId);
    if (failLoads) throw StateError('paymentsForBooking failed');
    await pendingLoads?.future;
    return payments;
  }

  @override
  Future<List<Payout>> payoutsForBooking(String bookingId) async {
    if (failLoads) throw StateError('payoutsForBooking failed');
    await pendingLoads?.future;
    return payouts;
  }

  @override
  Future<List<Payout>> payoutsForBand(String bandId) async {
    bandPayoutRequests.add(bandId);
    if (failLoads) throw StateError('payoutsForBand failed');
    await pendingLoads?.future;
    return payouts;
  }

  @override
  Future<List<RefundRecord>> refundsForBooking(String bookingId) async {
    if (failLoads) throw StateError('refundsForBooking failed');
    await pendingLoads?.future;
    return refunds;
  }

  @override
  Future<RefundPreview> previewCancellation(
    String bookingId, {
    BookingSide? side,
    required DateTime now,
  }) {
    previewRequest = (bookingId: bookingId, side: side, now: now);
    if (failLoads) throw StateError('previewCancellation failed');
    return super.previewCancellation(bookingId, side: side, now: now);
  }
}
