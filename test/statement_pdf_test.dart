import 'dart:convert';
import 'dart:io';

import 'package:earplug/models.dart';
import 'package:earplug/services/statement_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('organizer statement with transactions returns PDF bytes', () async {
    final bytes = await buildOrganizerStatement(
      organizationName: 'Local music collective',
      from: _from,
      to: _to,
      export: _organizerExport(),
      generatedAt: _generatedAt,
    );

    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(_pdfText(bytes), contains('Generated 1 Sep 2026, 04:05'));
  });

  for (final entry in const {
    FundsState.pending: 'Pending',
    FundsState.available: 'Available',
    FundsState.reserved: 'Reserved',
    FundsState.paid: 'Paid',
    FundsState.refunded: 'Refunded',
    FundsState.disputed: 'Disputed',
    FundsState.unknown: 'Unknown',
  }.entries) {
    test('organizer statement labels ${entry.key.name} funds', () async {
      final bytes = await buildOrganizerStatement(
        organizationName: 'Local music collective',
        from: _from,
        to: _to,
        export: StatementExport(
          transactions: [
            StatementTransaction(
              id: 'transaction-1',
              kind: LedgerKind.charge,
              amountMinor: 15000,
              currency: 'usd',
              fundsState: entry.key,
              occurredAt: _from,
              label: 'Summer session',
            ),
          ],
          totalsByKind: const [],
          csv: '',
          rows: 1,
          truncated: false,
        ),
        generatedAt: _generatedAt,
      );

      final text = _pdfText(bytes);
      expect(text, contains(entry.value));
      if (entry.key != FundsState.unknown) {
        expect(text, isNot(contains('Unknown')));
      }
    });
  }

  test('generated timestamp converts UTC to local 24-hour time', () async {
    final generatedAt = DateTime(2026, 9, 1, 14, 5).toUtc();
    final bytes = await buildOrganizerStatement(
      organizationName: 'Local music collective',
      from: _from,
      to: _to,
      export: _organizerExport(),
      generatedAt: generatedAt,
    );

    final text = _pdfText(bytes);
    expect(text, contains('Generated 1 Sep 2026, 14:05'));
    expect(text, isNot(contains(generatedAt.toIso8601String())));
  });

  test('payout statement with payouts returns PDF bytes', () async {
    final bytes = await buildPayoutStatement(
      bandName: 'The house band',
      from: _from,
      to: _to,
      statement: _payoutStatement(),
      generatedAt: _generatedAt,
    );

    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(_pdfText(bytes), contains('Generated 1 Sep 2026, 04:05'));
  });

  test('organizer statement accepts Latin-1, CJK, and emoji text', () async {
    final bytes = await buildOrganizerStatement(
      organizationName: 'Café Résonance 東京 🎶',
      from: _from,
      to: _to,
      export: _organizerExport(unicode: true),
      generatedAt: _generatedAt,
    );

    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('payout statement accepts Latin-1, CJK, and emoji text', () async {
    final bytes = await buildPayoutStatement(
      bandName: 'Böse Ünderground 東京 🎸',
      from: _from,
      to: _to,
      statement: _payoutStatement(unicode: true),
      generatedAt: _generatedAt,
    );

    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('empty organizer statement returns PDF bytes', () async {
    final bytes = await buildOrganizerStatement(
      organizationName: 'Local music collective',
      from: _from,
      to: _to,
      export: const StatementExport(
        transactions: [],
        totalsByKind: [],
        csv: '',
        rows: 0,
        truncated: false,
      ),
      generatedAt: _generatedAt,
    );

    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('empty payout statement returns PDF bytes', () async {
    final bytes = await buildPayoutStatement(
      bandName: 'The house band',
      from: _from,
      to: _to,
      statement: const PayoutStatement(
        payouts: [],
        totalNetMinor: 0,
        truncated: false,
      ),
      generatedAt: _generatedAt,
    );

    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('organizer transactions can span more than 20 pages', () async {
    final fixture = _organizerExport();
    final bytes = await buildOrganizerStatement(
      organizationName: 'Local music collective',
      from: _from,
      to: _to,
      export: StatementExport(
        transactions: List.generate(750, (_) => fixture.transactions.first),
        totalsByKind: const [
          StatementTotal(
            kind: LedgerKind.charge,
            amountMinor: 11250000,
            count: 750,
          ),
        ],
        csv: '',
        rows: 750,
        truncated: false,
      ),
      generatedAt: _generatedAt,
    );

    final pageCount = RegExp(
      r'/Type\s*/Page\b',
    ).allMatches(latin1.decode(bytes)).length;
    expect(pageCount, greaterThan(20));
  });

  test('payout rows flow across pages', () async {
    final fixture = _payoutStatement();
    final bytes = await buildPayoutStatement(
      bandName: 'The house band',
      from: _from,
      to: _to,
      statement: PayoutStatement(
        payouts: List.generate(80, (_) => fixture.payouts.first),
        totalNetMinor: 1440000,
        truncated: false,
      ),
      generatedAt: _generatedAt,
    );

    final pageCount = RegExp(
      r'/Type\s*/Page\b',
    ).allMatches(latin1.decode(bytes)).length;
    expect(pageCount, greaterThan(1));
  });
}

final _from = DateTime.utc(2026, 8, 1);
final _to = DateTime.utc(2026, 8, 31);
final _generatedAt = DateTime(2026, 9, 1, 4, 5).toUtc();

// Probe the simple Helvetica text in these fixtures. PDF streams may be
// compressed, and each word is written as a separate literal text operand.
String _pdfText(List<int> bytes) {
  final pdf = latin1.decode(bytes);
  final words = <String>[];
  for (final stream in RegExp(r'<<([^<>]*)>>\s*stream\r?\n').allMatches(pdf)) {
    final dictionary = stream.group(1)!;
    final length = int.parse(
      RegExp(r'/Length\s+(\d+)').firstMatch(dictionary)!.group(1)!,
    );
    final data = bytes.sublist(stream.end, stream.end + length);
    final content = latin1.decode(
      dictionary.contains('/FlateDecode') ? zlib.decode(data) : data,
    );
    words.addAll(
      RegExp(r'\(([^()]*)\)').allMatches(content).map((word) => word.group(1)!),
    );
  }
  return words.join(' ');
}

StatementExport _organizerExport({bool unicode = false}) => StatementExport(
  csv: '',
  rows: 2,
  truncated: true,
  totalsByKind: const [
    StatementTotal(kind: LedgerKind.charge, amountMinor: 15000, count: 1),
    StatementTotal(kind: LedgerKind.ticketRefund, amountMinor: -2500, count: 1),
  ],
  transactions: [
    StatementTransaction(
      id: 'transaction-1',
      kind: LedgerKind.charge,
      amountMinor: 15000,
      currency: 'usd',
      fundsState: FundsState.available,
      occurredAt: DateTime.utc(2026, 8, 12),
      label: unicode ? 'Café Résonance 東京 🎶' : 'Summer session',
      stripeRef: unicode ? 'pi_東京🎶' : 'pi_booking_123',
    ),
    StatementTransaction(
      id: 'transaction-2',
      kind: LedgerKind.ticketRefund,
      amountMinor: -2500,
      currency: 'usd',
      fundsState: FundsState.refunded,
      occurredAt: DateTime.utc(2026, 8, 20),
      label: 'Ticket refund',
    ),
  ],
);

PayoutStatement _payoutStatement({bool unicode = false}) => PayoutStatement(
  totalNetMinor: 23000,
  truncated: true,
  payouts: [
    PayoutStatementRow(
      payoutId: 'payout-1',
      bookingId: 'booking-1',
      bookingTitle: unicode ? 'Böse Ünderground 東京 🎸' : 'Summer session',
      organizationName: unicode ? 'Café 東京 🎶' : 'Local music collective',
      kind: PayoutKind.completion,
      status: PayoutStatus.paid,
      paidAt: DateTime.utc(2026, 8, 15),
      grossMinor: 20000,
      commissionMinor: 2000,
      netMinor: 18000,
      reversedMinor: 0,
      currency: 'usd',
      stripeTransferId: unicode ? 'tr_東京🎶' : 'tr_completion_123',
    ),
    PayoutStatementRow(
      payoutId: 'payout-2',
      bookingId: 'booking-2',
      bookingTitle: 'Cancelled session',
      organizationName: 'Downtown venue',
      kind: PayoutKind.forfeit,
      status: PayoutStatus.paid,
      paidAt: DateTime.utc(2026, 8, 20),
      netMinor: 5000,
      reversedMinor: 0,
      currency: 'usd',
    ),
  ],
);
