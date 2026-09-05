part of '../app_state.dart';

mixin _PaymentState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  String get bandId;
  String get organizationId;
  void switchToBand(String id);
  void switchToOrganization(String id);
  void resetTo(Screen s);
  Future<Booking?> loadBooking(
    String id, {
    bool refresh = false,
    BookingSide? viewAs,
  });

  // ---- hosted pages
  Future<void> Function(String url) hostedUrlLauncher = (url) => launchUrl(
    Uri.parse(url),
    mode: LaunchMode.platformDefault,
    webOnlyWindowName: '_self',
  );

  // Invalidate pending refreshes and polls when the session is cleared.
  Object _paymentSessionToken = Object();

  // ---- Stripe accounts
  StripeAccountStatus? bandPayoutStatus;
  StripeAccountStatus? organizationStripeStatus;
  Object? _bandPayoutStatusLoadToken;
  Object? _organizationStripeStatusLoadToken;

  Future<void> refreshBandPayoutStatus() async {
    if (_disposed) return;
    final target = bandId;
    final token = Object();
    _bandPayoutStatusLoadToken = token;
    if (target.isEmpty) {
      bandPayoutStatus = null;
      notifyListeners();
      return;
    }
    try {
      final status = await repository.bandPayoutStatus(target);
      if (_disposed ||
          bandId != target ||
          !identical(_bandPayoutStatusLoadToken, token)) {
        return;
      }
      bandPayoutStatus = status;
      notifyListeners();
    } catch (error) {
      logError('bandPayoutStatus', error);
    }
  }

  Future<void> refreshOrganizationStripeStatus() async {
    if (_disposed) return;
    final target = organizationId;
    final token = Object();
    _organizationStripeStatusLoadToken = token;
    if (target.isEmpty) {
      organizationStripeStatus = null;
      notifyListeners();
      return;
    }
    try {
      final status = await repository.organizationStripeStatus(target);
      if (_disposed ||
          organizationId != target ||
          !identical(_organizationStripeStatusLoadToken, token)) {
        return;
      }
      organizationStripeStatus = status;
      notifyListeners();
    } catch (error) {
      logError('organizationStripeStatus', error);
    }
  }

  Future<void> startBandOnboarding() async {
    final url = await repository.startBandOnboarding(bandId);
    if (_disposed) return;
    await hostedUrlLauncher(url);
  }

  Future<void> startOrganizationOnboarding() async {
    final url = await repository.startOrganizationOnboarding(organizationId);
    if (_disposed) return;
    await hostedUrlLauncher(url);
  }

  Future<void> openBandExpressDashboard() async {
    final url = await repository.bandExpressDashboardLink(bandId);
    if (_disposed) return;
    await hostedUrlLauncher(url);
  }

  Future<void> openOrganizationExpressDashboard() async {
    final url = await repository.organizationExpressDashboardLink(
      organizationId,
    );
    if (_disposed) return;
    await hostedUrlLauncher(url);
  }

  Future<void> handleStripeReturn({
    required bool band,
    required String id,
  }) async {
    if (_disposed) return;
    if (band) {
      if (bandId != id) switchToBand(id);
      final token = Object();
      _bandPayoutStatusLoadToken = token;
      final status = await repository.refreshBandAccountStatus(id);
      if (_disposed ||
          bandId != id ||
          !identical(_bandPayoutStatusLoadToken, token)) {
        return;
      }
      bandPayoutStatus = status;
      resetTo(Screen.bandPayouts);
    } else {
      if (organizationId != id) switchToOrganization(id);
      final token = Object();
      _organizationStripeStatusLoadToken = token;
      final status = await repository.refreshOrganizationAccountStatus(id);
      if (_disposed ||
          organizationId != id ||
          !identical(_organizationStripeStatusLoadToken, token)) {
        return;
      }
      organizationStripeStatus = status;
      resetTo(Screen.orgSettings);
    }
    notifyListeners();
  }

  // ---- payments and Checkout
  final Map<String, List<PaymentRecord>> _paymentsByBooking = {};

  List<PaymentRecord> paymentsFor(String bookingId) =>
      _paymentsByBooking[bookingId] ?? const [];

  Future<void> refreshPayments(String bookingId) async {
    if (_disposed) return;
    final token = _paymentSessionToken;
    try {
      final payments = await repository.paymentsForBooking(bookingId);
      if (_disposed || !identical(_paymentSessionToken, token)) return;
      _paymentsByBooking[bookingId] = payments;
      notifyListeners();
    } catch (error) {
      logError('paymentsForBooking', error);
    }
  }

  Future<String> payInstallment(String paymentRecordId) async {
    final result = await repository.startInstallmentCheckout(paymentRecordId);
    if (!_disposed) await hostedUrlLauncher(result.url);
    return result.sessionId;
  }

  Future<CheckoutStatus?> awaitCheckout(
    String sessionId, {
    Duration timeout = const Duration(seconds: 60),
    Duration interval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    final token = _paymentSessionToken;
    String? bookingId;
    CheckoutStatus? completed;
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed || !identical(_paymentSessionToken, token)) return null;
      try {
        final status = await repository.checkoutStatus(sessionId);
        if (_disposed || !identical(_paymentSessionToken, token)) return null;
        if (status != null) {
          if (status.bookingId.isNotEmpty) bookingId = status.bookingId;
          if (status.paymentStatus == PaymentRecordStatus.paid) {
            completed = status;
            break;
          }
        }
      } catch (error) {
        logError('checkoutStatus', error);
      }
      if (_disposed || !identical(_paymentSessionToken, token)) return null;
      if (!DateTime.now().isBefore(deadline)) break;
      await Future<void>.delayed(interval);
    }
    if (_disposed || !identical(_paymentSessionToken, token)) return null;
    if (bookingId != null) {
      unawaited(loadBooking(bookingId, refresh: true));
      unawaited(refreshPayments(bookingId));
    }
    return completed;
  }

  // ---- payouts and refunds
  final Map<String, List<Payout>> _payoutsByBooking = {};

  List<Payout> payoutsFor(String bookingId) =>
      _payoutsByBooking[bookingId] ?? const [];

  Future<void> refreshPayouts(String bookingId) async {
    if (_disposed) return;
    final token = _paymentSessionToken;
    try {
      final payouts = await repository.payoutsForBooking(bookingId);
      if (_disposed || !identical(_paymentSessionToken, token)) return;
      _payoutsByBooking[bookingId] = payouts;
      notifyListeners();
    } catch (error) {
      logError('payoutsForBooking', error);
    }
  }

  List<Payout> bandPayouts = const [];

  Future<void> refreshBandPayouts() async {
    if (_disposed) return;
    final target = bandId;
    if (target.isEmpty) {
      bandPayouts = const [];
      notifyListeners();
      return;
    }
    final token = _paymentSessionToken;
    try {
      final payouts = await repository.payoutsForBand(target);
      if (_disposed ||
          bandId != target ||
          !identical(_paymentSessionToken, token)) {
        return;
      }
      bandPayouts = payouts;
      notifyListeners();
    } catch (error) {
      logError('payoutsForBand', error);
    }
  }

  final Map<String, List<RefundRecord>> _refundsByBooking = {};

  List<RefundRecord> refundsFor(String bookingId) =>
      _refundsByBooking[bookingId] ?? const [];

  Future<void> refreshRefunds(String bookingId) async {
    if (_disposed) return;
    final token = _paymentSessionToken;
    try {
      final refunds = await repository.refundsForBooking(bookingId);
      if (_disposed || !identical(_paymentSessionToken, token)) return;
      _refundsByBooking[bookingId] = refunds;
      notifyListeners();
    } catch (error) {
      logError('refundsForBooking', error);
    }
  }

  Future<RefundPreview?> previewCancellation(Booking booking) async {
    try {
      return await repository.previewCancellation(
        booking.id,
        side: booking.viewerSide,
        now: DateTime.now(),
      );
    } catch (error) {
      logError('previewCancellation', error);
      return null;
    }
  }

  // ---- band changes (chained after _BookingState)
  String _lastKnownBandIdForPayments = '';

  @override
  void _onBandChanged() {
    super._onBandChanged();
    if (_lastKnownBandIdForPayments == bandId) return;
    _lastKnownBandIdForPayments = bandId;
    unawaited(refreshBandPayoutStatus());
  }

  // ---- sign-out cleanup
  void _clearPaymentState() {
    _paymentSessionToken = Object();
    _bandPayoutStatusLoadToken = null;
    _organizationStripeStatusLoadToken = null;
    bandPayoutStatus = null;
    organizationStripeStatus = null;
    _paymentsByBooking.clear();
    _payoutsByBooking.clear();
    _refundsByBooking.clear();
    bandPayouts = const [];
    _lastKnownBandIdForPayments = '';
  }
}
