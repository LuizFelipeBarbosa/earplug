import 'dart:typed_data';

import 'package:earplug/models.dart';
import 'package:earplug/money.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds an organizer statement using package:pdf's asynchronous serializer.
Future<Uint8List> buildOrganizerStatement({
  required String organizationName,
  required DateTime from,
  required DateTime to,
  required StatementExport export,
  required DateTime generatedAt,
}) {
  // StatementTotal has no currency; use the statement's transaction currency.
  final currency = export.transactions.isEmpty
      ? 'usd'
      : export.transactions.first.currency;
  return _buildStatement(
    name: organizationName,
    from: from,
    to: to,
    generatedAt: generatedAt,
    rowCount: export.totalsByKind.length + export.transactions.length,
    body: [
      _sectionHeading('SUMMARY'),
      if (export.totalsByKind.isNotEmpty)
        _table(
          headers: const ['Kind', 'Amount'],
          rows: [
            for (final total in export.totalsByKind)
              [
                _ledgerLabel(total.kind),
                Money(total.amountMinor, currency).label,
              ],
          ],
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1),
          },
          moneyColumns: const {1},
        ),
      pw.SizedBox(height: 18),
      _sectionHeading('TRANSACTIONS'),
      if (export.transactions.isNotEmpty)
        _table(
          headers: const [
            'Date',
            'Description',
            'Kind',
            'Amount',
            'Funds state',
            'Reference',
          ],
          rows: [
            for (final transaction in export.transactions)
              [
                _formatDate(transaction.occurredAt),
                transaction.label,
                _ledgerLabel(transaction.kind),
                Money(transaction.amountMinor, transaction.currency).label,
                _enumLabel(transaction.fundsState.name),
                transaction.stripeRef ?? '',
              ],
          ],
          columnWidths: const {
            0: pw.FlexColumnWidth(1.1),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(1.3),
            3: pw.FlexColumnWidth(1.2),
            4: pw.FlexColumnWidth(1.1),
            5: pw.FlexColumnWidth(1.6),
          },
          moneyColumns: const {3},
        ),
      if (export.truncated) ...[
        pw.SizedBox(height: 10),
        pw.Text('Showing a truncated set of transactions.'),
      ],
    ],
  );
}

/// Builds a band payout statement using package:pdf's asynchronous serializer.
Future<Uint8List> buildPayoutStatement({
  required String bandName,
  required DateTime from,
  required DateTime to,
  required PayoutStatement statement,
  required DateTime generatedAt,
}) {
  final currency = statement.payouts.isEmpty
      ? 'usd'
      : statement.payouts.first.currency;
  return _buildStatement(
    name: bandName,
    from: from,
    to: to,
    generatedAt: generatedAt,
    rowCount: statement.payouts.length,
    pageFormat: PdfPageFormat.a4.landscape,
    body: [
      _sectionHeading(
        'TOTAL PAID OUT  ${Money(statement.totalNetMinor, currency).label}',
      ),
      if (statement.payouts.isNotEmpty)
        _table(
          headers: const [
            'Paid date',
            'Event',
            'Organizer',
            'Kind',
            'Gross',
            'Commission',
            'Net',
            'Transfer',
          ],
          rows: [
            for (final payout in statement.payouts)
              [
                _formatDate(payout.paidAt),
                payout.bookingTitle,
                payout.organizationName,
                _enumLabel(payout.kind.name),
                if (payout.grossMinor case final gross?)
                  Money(gross, payout.currency).label
                else
                  '',
                if (payout.commissionMinor case final commission?)
                  Money(commission, payout.currency).label
                else
                  '',
                Money(payout.netMinor, payout.currency).label,
                payout.stripeTransferId ?? '',
              ],
          ],
          columnWidths: const {
            0: pw.FlexColumnWidth(1.1),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(1.8),
            3: pw.FlexColumnWidth(1.2),
            4: pw.FlexColumnWidth(1.1),
            5: pw.FlexColumnWidth(1.2),
            6: pw.FlexColumnWidth(1.1),
            7: pw.FlexColumnWidth(1.8),
          },
          moneyColumns: const {4, 5, 6},
        ),
      if (statement.truncated) ...[
        pw.SizedBox(height: 10),
        pw.Text('Showing a truncated set of payouts.'),
      ],
    ],
  );
}

Future<Uint8List> _buildStatement({
  required String name,
  required DateTime from,
  required DateTime to,
  required DateTime generatedAt,
  required List<pw.Widget> body,
  required int rowCount,
  PdfPageFormat pageFormat = PdfPageFormat.a4,
}) {
  final document = pw.Document(
    theme: pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    ),
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(36),
      // Allow long statements to exceed MultiPage's default 20-page limit.
      maxPages: rowCount + 20,
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'EarPlug statement',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(_latin1Safe(name), style: const pw.TextStyle(fontSize: 14)),
          pw.SizedBox(height: 4),
          pw.Text('${_formatDate(from)} - ${_formatDate(to)}'),
          pw.Text(
            'Generated ${generatedAt.toIso8601String()}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 18),
        ],
      ),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12),
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ),
      build: (_) => body,
    ),
  );
  return document.save();
}

pw.Widget _sectionHeading(String title) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 8),
  child: pw.Text(
    _latin1Safe(title),
    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
  ),
);

pw.Table _table({
  required List<String> headers,
  required List<List<String>> rows,
  required Map<int, pw.TableColumnWidth> columnWidths,
  required Set<int> moneyColumns,
}) => pw.TableHelper.fromTextArray(
  headers: headers.map(_latin1Safe).toList(),
  data: [for (final row in rows) row.map(_latin1Safe).toList()],
  columnWidths: columnWidths,
  cellPadding: const pw.EdgeInsets.all(5),
  cellAlignment: pw.Alignment.topLeft,
  headerAlignment: pw.Alignment.topLeft,
  cellAlignments: {
    for (final column in moneyColumns) column: pw.Alignment.topRight,
  },
  cellStyle: const pw.TextStyle(fontSize: 9),
  headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
  border: const pw.TableBorder(
    bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
    horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
  ),
);

String _ledgerLabel(LedgerKind kind) => switch (kind) {
  LedgerKind.charge => 'Booking payments',
  LedgerKind.refund => 'Refunds',
  LedgerKind.ticketSale => 'Ticket sales',
  LedgerKind.ticketFee => 'Ticketing fees',
  LedgerKind.ticketRefund => 'Ticket refunds',
  _ => _enumLabel(kind.name),
};

String _enumLabel(String name) {
  final words = name.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match[1]} ${match[2]}',
  );
  if (words.isEmpty) return words;
  return '${words[0].toUpperCase()}${words.substring(1).toLowerCase()}';
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String _latin1Safe(String input) => String.fromCharCodes(
  input.codeUnits.map((codeUnit) => codeUnit <= 0xff ? codeUnit : 0x3f),
);
