import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_sheet.dart';
import 'form_bits.dart';
import 'sheets.dart';

Future<void> showTicketPurchaseSheet(BuildContext context, Gig gig) async {
  await showEpSheet(context, (_) => _TicketPurchaseSheet(gig: gig));
}

class _TicketPurchaseSheet extends StatefulWidget {
  const _TicketPurchaseSheet({required this.gig});

  final Gig gig;

  @override
  State<_TicketPurchaseSheet> createState() => _TicketPurchaseSheetState();
}

class _TicketPurchaseSheetState extends State<_TicketPurchaseSheet> {
  int _quantity = 1;
  bool _submitting = false;
  String? _error;

  Future<void> _holdTickets() async {
    if (_submitting) return;
    final app = context.read<AppState>();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await app.reserveTickets(
        widget.gig.id,
        _quantity,
        referralBandSlug: app.ticketReferralBandSlug,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error =
            serverErrorMessage(error) ??
            'Could not hold tickets. Please retry.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _continueToPayment(TicketReservation reservation) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<AppState>().startTicketCheckout(reservation.orderId);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error =
            serverErrorMessage(error) ??
            'Could not start payment. Please retry.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _releaseHold() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    await context.read<AppState>().releaseReservation();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final reservation = app.pendingReservation;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: EpSheetShell(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        maxHeightFactor: .9,
        scrollable: true,
        mainAxisSize: MainAxisSize.min,
        header: Row(
          children: [
            Expanded(
              child: Text(
                reservation == null ? 'TICKETS' : 'YOUR HOLD',
                style: textTheme.epSectionHeading,
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        children: [
          const SizedBox(height: 12),
          if (reservation == null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  key: const Key('ticket-qty-minus'),
                  tooltip: 'Fewer tickets',
                  onPressed: _submitting || _quantity == 1
                      ? null
                      : () => setState(() => _quantity--),
                  icon: const Icon(Icons.remove),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '$_quantity',
                    key: const Key('ticket-qty'),
                    style: textTheme.epSectionHeading,
                  ),
                ),
                IconButton(
                  key: const Key('ticket-qty-plus'),
                  tooltip: 'More tickets',
                  onPressed: _submitting || _quantity == 10
                      ? null
                      : () => setState(() => _quantity++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '$_quantity × ${widget.gig.priceLabel}',
              textAlign: TextAlign.center,
              style: textTheme.epBody,
            ),
            const SizedBox(height: 12),
            Text(
              'EarPlug fee and total shown after the hold',
              style: textTheme.epCaption,
            ),
          ] else ...[
            _HoldSummaryRow(
              label: 'Tickets',
              amount: Money(reservation.subtotalMinor, reservation.currency),
            ),
            _HoldSummaryRow(
              label: 'EarPlug fee',
              amount: Money(reservation.feeMinor, reservation.currency),
            ),
            _HoldSummaryRow(
              label: 'Total',
              amount: Money(reservation.totalMinor, reservation.currency),
              isTotal: true,
            ),
            const SizedBox(height: 12),
            Text('Held for 30 minutes', style: textTheme.epCaption),
          ],
          InlineFormFeedback(
            error: _error,
            errorKey: const Key('ticket-error'),
          ),
          const SizedBox(height: 18),
          if (reservation == null)
            EpButton(
              'HOLD TICKETS',
              key: const Key('ticket-hold'),
              kind: _submitting ? EpButtonKind.disabled : EpButtonKind.filled,
              onTap: _submitting ? null : _holdTickets,
            )
          else ...[
            EpButton(
              'CONTINUE TO PAYMENT',
              key: const Key('ticket-pay'),
              kind: _submitting ? EpButtonKind.disabled : EpButtonKind.filled,
              onTap: _submitting ? null : () => _continueToPayment(reservation),
            ),
            const SizedBox(height: 8),
            EpButton(
              'RELEASE HOLD',
              key: const Key('ticket-release'),
              kind: EpButtonKind.ghost,
              onTap: _submitting ? null : _releaseHold,
            ),
          ],
        ],
      ),
    );
  }
}

class _HoldSummaryRow extends StatelessWidget {
  const _HoldSummaryRow({
    required this.label,
    required this.amount,
    this.isTotal = false,
  });

  final String label;
  final Money amount;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = isTotal
        ? textTheme.epSectionHeading.copyWith(fontWeight: FontWeight.w800)
        : textTheme.epBody;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(amount.label, style: style),
        ],
      ),
    );
  }
}
