import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class CheckoutReturnScreen extends StatefulWidget {
  const CheckoutReturnScreen({
    super.key,
    required this.sessionId,
    this.timeout = const Duration(seconds: 60),
    this.interval = const Duration(seconds: 2),
  });

  final String sessionId;
  final Duration timeout;
  final Duration interval;

  @override
  State<CheckoutReturnScreen> createState() => _CheckoutReturnScreenState();
}

class _CheckoutReturnScreenState extends State<CheckoutReturnScreen> {
  late Future<({CheckoutStatus? status, bool alreadyConfirmed})> _checkout;

  @override
  void initState() {
    super.initState();
    _checkout = _confirmPayment(context.read<AppState>());
  }

  Future<({CheckoutStatus? status, bool alreadyConfirmed})> _confirmPayment(
    AppState app,
  ) async {
    final completed = await app.awaitCheckout(
      widget.sessionId,
      timeout: widget.timeout,
      interval: widget.interval,
    );
    // Read before another await lets the background refresh update the cache.
    final alreadyConfirmed =
        completed != null &&
        app.bookingById(completed.bookingId)?.status == BookingStatus.confirmed;
    if (!mounted) {
      return (status: completed, alreadyConfirmed: alreadyConfirmed);
    }
    final status =
        completed ?? await app.repository.checkoutStatus(widget.sessionId);
    return (status: status, alreadyConfirmed: alreadyConfirmed);
  }

  void _retry() {
    final checkout = _confirmPayment(context.read<AppState>());
    setState(() {
      _checkout = checkout;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final textTheme = Theme.of(context).textTheme;
    return FutureBuilder(
      future: _checkout,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _CheckoutPage(
            children: [
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 24),
              Text('Confirming your payment…', style: textTheme.epPageHeading),
              const SizedBox(height: 12),
              Text(
                'This usually takes a few seconds.',
                style: textTheme.epCaption,
              ),
            ],
          );
        }

        if (snapshot.hasError) {
          return _CheckoutPage(
            children: [
              Text(
                "We couldn't check your payment.",
                style: textTheme.epPageHeading,
              ),
              const SizedBox(height: 24),
              EpButton(
                'RETRY',
                key: const Key('checkout-return-retry'),
                onTap: _retry,
              ),
            ],
          );
        }

        final result = snapshot.requireData;
        final status = result.status;
        if (status == null) {
          return _CheckoutPage(
            children: [
              Text(
                "This checkout isn't available.",
                style: textTheme.epPageHeading,
              ),
              const SizedBox(height: 24),
              EpButton(
                'BACK',
                key: const Key('checkout-return-back'),
                onTap: () => app.resetTo(Screen.home),
              ),
            ],
          );
        }

        final paid =
            status.paymentStatus == PaymentRecordStatus.paid ||
            status.bookingStatus == BookingStatus.confirmed;
        return _CheckoutPage(
          children: [
            Text(
              paid ? 'Payment received' : "We haven't heard from Stripe yet",
              style: textTheme.epPageHeading,
            ),
            const SizedBox(height: 12),
            Text(
              paid
                  ? result.alreadyConfirmed
                        ? 'Installment recorded'
                        : 'Your booking is confirmed.'
                  : 'Your payment may still be processing. '
                        'Check the booking in a minute.',
              style: paid ? textTheme.epBody : textTheme.epCaption,
            ),
            const SizedBox(height: 24),
            EpButton(
              'VIEW BOOKING',
              key: const Key('checkout-return-booking'),
              onTap: () => app.openBooking(
                status.bookingId,
                viewAs: BookingSide.organizer,
              ),
            ),
            if (!paid) ...[
              const SizedBox(height: 12),
              EpButton(
                'RETRY',
                key: const Key('checkout-return-retry'),
                kind: EpButtonKind.outline,
                onTap: _retry,
              ),
            ],
          ],
        );
      },
    );
  }
}

class CheckoutCancelScreen extends StatelessWidget {
  const CheckoutCancelScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _CheckoutPage(
      children: [
        Text('Payment not completed', style: textTheme.epPageHeading),
        const SizedBox(height: 12),
        Text(
          'No charge was made. You can pay again from the booking.',
          style: textTheme.epBody,
        ),
        const SizedBox(height: 24),
        EpButton(
          'VIEW BOOKING',
          key: const Key('checkout-cancel-booking'),
          onTap: () => context.read<AppState>().openBooking(
            bookingId,
            viewAs: BookingSide.organizer,
          ),
        ),
      ],
    );
  }
}

class _CheckoutPage extends StatelessWidget {
  const _CheckoutPage({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.epColors.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
