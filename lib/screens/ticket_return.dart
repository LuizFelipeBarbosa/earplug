import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_states.dart';

class TicketCheckoutReturnScreen extends StatefulWidget {
  const TicketCheckoutReturnScreen({
    super.key,
    required this.sessionId,
    this.timeout = const Duration(seconds: 60),
    this.interval = const Duration(seconds: 2),
  });

  final String sessionId;
  final Duration timeout;
  final Duration interval;

  @override
  State<TicketCheckoutReturnScreen> createState() =>
      _TicketCheckoutReturnScreenState();
}

class _TicketCheckoutReturnScreenState
    extends State<TicketCheckoutReturnScreen> {
  late Future<TicketOrderState?> _checkout;

  @override
  void initState() {
    super.initState();
    _checkout = context.read<AppState>().awaitTicketCheckout(
      widget.sessionId,
      timeout: widget.timeout,
      interval: widget.interval,
    );
  }

  void _retry() {
    final checkout = context.read<AppState>().awaitTicketCheckout(
      widget.sessionId,
      timeout: widget.timeout,
      interval: widget.interval,
    );
    setState(() => _checkout = checkout);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final textTheme = Theme.of(context).textTheme;
    return FutureBuilder<TicketOrderState?>(
      future: _checkout,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return EpCenteredPage(
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
          return EpCenteredPage(
            children: [
              Text(
                "We couldn't check your payment.",
                style: textTheme.epPageHeading,
              ),
              const SizedBox(height: 24),
              EpButton(
                'RETRY',
                key: const Key('ticket-return-retry'),
                onTap: _retry,
              ),
            ],
          );
        }

        final status = snapshot.data;
        if (status?.status == TicketOrderStatus.paid) {
          final quantity = status!.quantity;
          final ticketLabel = quantity == 1 ? 'ticket' : 'tickets';
          final event = app.gig(status.gigId)?.title ?? 'the show';
          return EpCenteredPage(
            children: [
              Text("You're in", style: textTheme.epPageHeading),
              const SizedBox(height: 12),
              Text(
                '$quantity $ticketLabel for $event',
                style: textTheme.epBody,
              ),
              const SizedBox(height: 24),
              EpButton(
                'VIEW TICKETS',
                key: const Key('ticket-return-wallet'),
                onTap: app.openMyTickets,
              ),
            ],
          );
        }

        if (status != null &&
            (status.status == TicketOrderStatus.expired ||
                status.status == TicketOrderStatus.cancelled)) {
          return EpCenteredPage(
            children: [
              Text(
                'This hold expired before payment finished',
                style: textTheme.epPageHeading,
              ),
              const SizedBox(height: 24),
              EpButton(
                'BACK TO EVENT',
                key: const Key('ticket-return-event'),
                onTap: () => app.openGig(status.gigId),
              ),
            ],
          );
        }

        return EpCenteredPage(
          children: [
            Text(
              status?.status == TicketOrderStatus.refunded
                  ? 'This order was refunded'
                  : "This checkout isn't available",
              style: textTheme.epPageHeading,
            ),
            const SizedBox(height: 24),
            EpButton(
              'BACK',
              key: const Key('ticket-return-back'),
              onTap: () => app.resetTo(Screen.home),
            ),
          ],
        );
      },
    );
  }
}

class TicketCheckoutCancelScreen extends StatelessWidget {
  const TicketCheckoutCancelScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return EpCenteredPage(
      children: [
        Text('Payment cancelled', style: textTheme.epPageHeading),
        const SizedBox(height: 12),
        Text(
          'Your hold is still active for a few minutes',
          style: textTheme.epBody,
        ),
        const SizedBox(height: 24),
        EpButton(
          'TRY AGAIN',
          key: const Key('ticket-cancel-retry'),
          onTap: () => context.read<AppState>().startTicketCheckout(orderId),
        ),
        const SizedBox(height: 12),
        EpButton(
          'RELEASE HOLD',
          key: const Key('ticket-cancel-release'),
          kind: EpButtonKind.ghost,
          onTap: () async {
            final app = context.read<AppState>();
            await app.releaseReservation();
            app.resetTo(Screen.home);
          },
        ),
      ],
    );
  }
}
