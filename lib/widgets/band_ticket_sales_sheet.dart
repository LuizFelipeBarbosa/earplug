import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../money.dart';
import '../theme.dart';
import 'ep_sheet.dart';
import 'sheets.dart';

Future<void> showBandTicketSalesSheet(
  BuildContext context, {
  required String gigId,
  required String title,
}) => showEpSheet(
  context,
  (_) => _BandTicketSalesSheet(gigId: gigId, title: title),
);

class _BandTicketSalesSheet extends StatefulWidget {
  const _BandTicketSalesSheet({required this.gigId, required this.title});

  final String gigId;
  final String title;

  @override
  State<_BandTicketSalesSheet> createState() => _BandTicketSalesSheetState();
}

class _BandTicketSalesSheetState extends State<_BandTicketSalesSheet> {
  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    if (app.salesFor(widget.gigId) == null) {
      unawaited(app.loadTicketSales(widget.gigId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<AppState>().salesFor(widget.gigId);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      key: const Key('band-ticket-sales-sheet'),
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
                widget.title.toUpperCase(),
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
          if (sales == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            _SalesRow(label: 'Sold', value: '${sales.sold}/${sales.capacity}'),
            _SalesRow(
              label: 'Gross',
              value: Money(sales.grossMinor, sales.currency).label,
            ),
            _SalesRow(
              label: 'EarPlug fee',
              value: Money(sales.feeMinor, sales.currency).label,
            ),
            if (sales.refundedMinor > 0)
              _SalesRow(
                label: 'Refunds',
                value: Money(sales.refundedMinor, sales.currency).label,
              ),
            const Divider(),
            _SalesRow(
              label: 'Net',
              value: Money(sales.netMinor, sales.currency).label,
              valueKey: const Key('band-ticket-sales-net'),
              isTotal: true,
            ),
            _SalesRow(label: 'Orders', value: '${sales.ordersPaid}'),
          ],
        ],
      ),
    );
  }
}

class _SalesRow extends StatelessWidget {
  const _SalesRow({
    required this.label,
    required this.value,
    this.valueKey,
    this.isTotal = false,
  });

  final String label;
  final String value;
  final Key? valueKey;
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
          Text(value, key: valueKey, style: style),
        ],
      ),
    );
  }
}
