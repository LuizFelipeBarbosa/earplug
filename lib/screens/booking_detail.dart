import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/map_view.dart';
import '../widgets/sheets.dart';
import '../widgets/status_timeline.dart';

class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

enum _OfferAction { accept, decline, withdraw }

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  late Future<Booking?> _future;
  late Future<BookingReviews?> _reviews;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BookingDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingId != widget.bookingId) {
      _error = null;
      _load();
    }
  }

  void _load({bool refresh = false}) {
    final app = context.read<AppState>();
    _future = app.loadBooking(widget.bookingId, refresh: refresh).then((
      booking,
    ) {
      if (booking != null && mounted && widget.bookingId == booking.id) {
        unawaited(app.refreshPayments(booking.id));
        unawaited(app.refreshRefunds(booking.id));
        if (booking.viewerSide == BookingSide.artist &&
            (booking.status == BookingStatus.completed ||
                booking.status == BookingStatus.paid)) {
          unawaited(app.refreshPayouts(booking.id));
        }
      }
      return booking;
    });
    // Tie reviews to this load, so rebuilds never start another request.
    _reviews = _future.then((booking) {
      if (booking == null ||
          (booking.status != BookingStatus.completed &&
              booking.status != BookingStatus.paid)) {
        return null;
      }
      return app.loadBookingReviews(booking.id);
    });
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _error = null;
      _load(refresh: true);
    });
  }

  Future<void> _handleOfferAction(Booking booking, _OfferAction action) async {
    if (_submitting) return;
    final app = context.read<AppState>();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      var acceptedTerms = false;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(switch (action) {
              _OfferAction.accept => 'Accept offer?',
              _OfferAction.decline => 'Decline offer?',
              _OfferAction.withdraw => 'Withdraw offer?',
            }),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(switch (action) {
                  _OfferAction.accept =>
                    'Accept the fee and cancellation terms shown in this booking.',
                  _OfferAction.decline =>
                    'The organizer will be told that you declined this offer.',
                  _OfferAction.withdraw =>
                    'The artist will no longer be able to accept this offer.',
                }),
                if (action == _OfferAction.accept)
                  CheckboxListTile(
                    key: const Key('booking-accept-terms'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('I accept these terms'),
                    value: acceptedTerms,
                    onChanged: (value) =>
                        setDialogState(() => acceptedTerms = value == true),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('KEEP'),
              ),
              FilledButton(
                onPressed: action == _OfferAction.accept && !acceptedTerms
                    ? null
                    : () => Navigator.pop(context, true),
                child: Text(
                  action == _OfferAction.accept ? 'ACCEPT' : 'CONFIRM',
                ),
              ),
            ],
          ),
        ),
      );
      if (!mounted || confirmed != true || widget.bookingId != booking.id) {
        return;
      }
      switch (action) {
        case _OfferAction.accept:
          await app.respondToOffer(booking, accept: true);
        case _OfferAction.decline:
          await app.respondToOffer(booking, accept: false);
        case _OfferAction.withdraw:
          await app.withdrawOffer(booking);
      }
      _reload();
    } catch (error) {
      if (mounted && widget.bookingId == booking.id) {
        setState(() {
          _error = _errorMessage(error);
          _load(refresh: true);
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showCancellation(Booking booking) async {
    setState(() => _error = null);
    final app = context.read<AppState>();
    await showEpSheet(
      context,
      (_) =>
          _CancelBookingSheet(app: app, booking: booking, onCancelled: _reload),
    );
  }

  Future<void> _payInstallment(Booking booking, PaymentRecord payment) async {
    if (_submitting) return;
    final app = context.read<AppState>();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await app.payInstallment(payment.id);
    } catch (error) {
      if (mounted && widget.bookingId == booking.id) {
        setState(() {
          _error = _errorMessage(error);
          _load(refresh: true);
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget? _stickyBar(Booking booking, List<PaymentRecord> payments) {
    final isOffer = booking.status == BookingStatus.offerSent;
    final awaitingPayment = booking.status == BookingStatus.awaitingPayment;
    if (!isOffer &&
        !awaitingPayment &&
        booking.status != BookingStatus.confirmed) {
      return null;
    }
    final organizerPayment =
        awaitingPayment && booking.viewerSide == BookingSide.organizer;
    final nextPayment = payments
        .where((record) => record.status.isOpen)
        .firstOrNull;
    final artistOffer = isOffer && booking.viewerSide == BookingSide.artist;
    final (key, label, VoidCallback onPressed) = isOffer
        ? (
            artistOffer ? 'booking-accept' : 'booking-withdraw',
            artistOffer ? 'ACCEPT OFFER' : 'WITHDRAW OFFER',
            () => _handleOfferAction(
              booking,
              artistOffer ? _OfferAction.accept : _OfferAction.withdraw,
            ),
          )
        : (
            'booking-cancel',
            'CANCEL BOOKING…',
            () => _showCancellation(booking),
          );

    // Match StickyActionBar's chrome while giving each button its own key.
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.epColors.tabBarBackground,
          border: Border(top: BorderSide(color: context.epColors.border)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (organizerPayment) ...[
                Expanded(
                  child: FilledButton(
                    key: const Key('booking-pay-now'),
                    onPressed: _submitting || nextPayment == null
                        ? null
                        : () => _payInstallment(booking, nextPayment),
                    child: const Text('PAY NOW', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (artistOffer) ...[
                Expanded(
                  child: OutlinedButton(
                    key: const Key('booking-decline'),
                    onPressed: _submitting
                        ? null
                        : () =>
                              _handleOfferAction(booking, _OfferAction.decline),
                    child: const Text('DECLINE', textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: artistOffer ? 2 : 1,
                child: FilledButton(
                  key: Key(key),
                  onPressed: _submitting ? null : onPressed,
                  child: Text(label, textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final textTheme = Theme.of(context).textTheme;
    return FutureBuilder<Booking?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final booking = snapshot.data;
        if (booking == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EmptyNote(message: "This booking isn't available."),
                TextButton(onPressed: _reload, child: const Text('RETRY')),
              ],
            ),
          );
        }
        final payments = app.paymentsFor(booking.id).toList()
          ..sort((a, b) => a.installmentIndex.compareTo(b.installmentIndex));
        final refunds = app.refundsFor(booking.id);
        final stickyBar = _stickyBar(booking, payments);
        final offerMessage = booking.currentOffer?.message;
        return Stack(
          children: [
            Positioned.fill(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  headerTopPad(context),
                  16,
                  tabBarClearance + 112 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      BackButton(onPressed: app.back),
                      IconButton(
                        key: const Key('booking-refresh'),
                        tooltip: 'Refresh booking',
                        onPressed: _submitting ? null : _reload,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  Text(
                    booking.opportunityTitle,
                    style: textTheme.epPageHeading,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      StatusPill(
                        label: booking.status.label,
                        tone: booking.status.isLive
                            ? EpStatusPillTone.success
                            : EpStatusPillTone.neutral,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusCaption(context, booking),
                          style: textTheme.epCaption,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  StatusTimeline(steps: _timelineSteps(booking)),
                  const SectionBar(label: 'WHEN & WHERE'),
                  EpCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            DateBlock.forDate(booking.startsAt.toLocal()),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    booking.venue.name,
                                    style: textTheme.epSectionHeading,
                                  ),
                                  if (booking.venue.approxLabel
                                      case final label?)
                                    Text(label, style: textTheme.epMeta),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        VenueMiniMap(
                          venue: app.venue(booking.venue.id),
                          approximate: booking.venue.exactAddress == null,
                        ),
                        if (booking.venue.exactAddress case final address?) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.lock_outline, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Exact address · shared with you: $address',
                                  key: const Key('booking-exact-address'),
                                  style: textTheme.epMeta,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SectionBar(label: 'SLOT'),
                  EpCard(
                    child: LedgerRow(
                      title: booking.slotRole.name.toUpperCase(),
                      trailing: Text(
                        booking.slotRequired ? 'REQUIRED' : 'OPTIONAL',
                      ),
                    ),
                  ),
                  const SectionBar(label: 'FEE'),
                  _FeeCard(fee: booking.fee, paidMinor: booking.paidMinor),
                  if (booking.fee.grossMinor > 0)
                    _BookingLedgerSection(
                      key: const Key('booking-payments'),
                      label: 'PAYMENTS',
                      children: [
                        for (final payment in payments)
                          _PaymentRow(
                            key: Key(
                              'booking-payment-${payment.installmentIndex}',
                            ),
                            payment: payment,
                            showPay:
                                booking.viewerSide == BookingSide.organizer &&
                                payment.canPay,
                            onPay: _submitting
                                ? null
                                : () => _payInstallment(booking, payment),
                          ),
                        if (booking.viewerSide == BookingSide.artist &&
                            payments.any((record) => record.status.isOpen))
                          Text(
                            "Waiting for the organizer's payment",
                            style: textTheme.epCaption,
                          ),
                      ],
                    ),
                  if (booking.viewerSide == BookingSide.artist &&
                      (booking.status == BookingStatus.completed ||
                          booking.status == BookingStatus.paid))
                    _BookingLedgerSection(
                      key: const Key('booking-payouts'),
                      label: 'PAYOUTS',
                      children: [
                        for (final payout in app.payoutsFor(booking.id))
                          _PayoutRow(
                            key: Key('booking-payout-${payout.id}'),
                            payout: payout,
                          ),
                      ],
                    ),
                  if (refunds.isNotEmpty)
                    _BookingLedgerSection(
                      key: const Key('booking-refunds'),
                      label: 'REFUNDS',
                      children: [
                        for (final refund in refunds)
                          _RefundRow(refund: refund),
                      ],
                    ),
                  const SectionBar(label: 'TERMS'),
                  EpCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          booking.cancellationTemplate.label,
                          style: textTheme.epSectionHeading,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          booking.cancellationTemplate.description,
                          style: textTheme.epBody,
                        ),
                        if (booking.termsNotes?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Text(booking.termsNotes!, style: textTheme.epBody),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          'Organizer accepted ${_fullDate(context, booking.organizerAcceptedTermsAt)}',
                          style: textTheme.epMeta,
                        ),
                        if (booking.artistAcceptedTermsAt case final date?)
                          Text(
                            'Artist accepted ${_fullDate(context, date)}',
                            style: textTheme.epMeta,
                          ),
                      ],
                    ),
                  ),
                  if (offerMessage?.trim().isNotEmpty == true) ...[
                    const SectionBar(label: 'OFFER MESSAGE'),
                    EpCard(child: Text(offerMessage!, style: textTheme.epBody)),
                  ],
                  if (booking.counterpartyEmail case final email?) ...[
                    const SectionBar(label: 'CONTACT'),
                    EpCard(
                      child: Text(
                        email,
                        key: const Key('booking-counterparty-email'),
                      ),
                    ),
                  ],
                  if (booking.publicGigId case final gigId?) ...[
                    const SectionBar(label: 'EVENT PAGE'),
                    EpButton(
                      'EVENT PAGE',
                      key: const Key('booking-view-gig'),
                      onTap: () => context.read<AppState>().openGig(gigId),
                    ),
                  ],
                  if (booking.status == BookingStatus.completed ||
                      booking.status == BookingStatus.paid) ...[
                    const SectionBar(label: 'REVIEWS'),
                    _BookingReviewsSection(
                      bookingId: booking.id,
                      future: _reviews,
                    ),
                  ],
                  const SizedBox(height: 20),
                  InlineFormFeedback(
                    error: _error,
                    errorKey: const Key('booking-feedback'),
                  ),
                ],
              ),
            ),
            if (stickyBar != null)
              Positioned(left: 0, right: 0, bottom: 67, child: stickyBar),
          ],
        );
      },
    );
  }
}

class _FeeCard extends StatelessWidget {
  const _FeeCard({required this.fee, this.paidMinor = 0});

  final FeeBreakdown fee;
  final int paidMinor;

  @override
  Widget build(BuildContext context) {
    final percent = (fee.commissionBps / 100).toStringAsFixed(
      fee.commissionBps % 100 == 0 ? 0 : (fee.commissionBps % 10 == 0 ? 1 : 2),
    );
    return EpCard(
      key: const Key('booking-fee'),
      child: fee.grossMinor == 0
          ? const Text('No fee · confirms on acceptance')
          : Column(
              children: [
                LedgerRow(title: 'Guarantee', trailing: Text(fee.gross.label)),
                LedgerRow(
                  title: 'EarPlug commission ($percent%)',
                  trailing: Text(fee.commission.label),
                ),
                LedgerRow(
                  title: 'Artist receives',
                  trailing: Text(fee.artistNet.label),
                ),
                if (paidMinor > 0)
                  LedgerRow(
                    title:
                        'Paid ${Money(paidMinor, fee.currency).label} of ${fee.gross.label}',
                  ),
              ],
            ),
    );
  }
}

class _BookingLedgerSection extends StatelessWidget {
  const _BookingLedgerSection({
    super.key,
    required this.label,
    required this.children,
  });

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionBar(label: label),
      EpCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ],
  );
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    super.key,
    required this.payment,
    required this.showPay,
    required this.onPay,
  });

  final PaymentRecord payment;
  final bool showPay;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (payment.status) {
      PaymentRecordStatus.pending => ('Pending', EpStatusPillTone.neutral),
      PaymentRecordStatus.checkoutOpen => (
        'Checkout open',
        EpStatusPillTone.selected,
      ),
      PaymentRecordStatus.paid => (
        payment.paidAt == null
            ? 'Paid'
            : 'Paid ${_fullDate(context, payment.paidAt!)}',
        EpStatusPillTone.success,
      ),
      PaymentRecordStatus.failed => ('Failed', EpStatusPillTone.warning),
      PaymentRecordStatus.expired => ('Expired', EpStatusPillTone.warning),
      PaymentRecordStatus.refunded => ('Refunded', EpStatusPillTone.neutral),
      PaymentRecordStatus.partiallyRefunded => (
        'Partially refunded',
        EpStatusPillTone.neutral,
      ),
      PaymentRecordStatus.unknown => ('Unknown', EpStatusPillTone.neutral),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerRow(title: payment.label, trailing: Text(payment.amount.label)),
          Text(
            'Due ${_fullDate(context, payment.dueAt)}',
            style: Theme.of(context).textTheme.epMeta,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(label: label, tone: tone),
              if (showPay)
                TextButton(
                  key: Key('booking-pay-${payment.installmentIndex}'),
                  onPressed: onPay,
                  child: const Text('PAY'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({super.key, required this.payout});

  final Payout payout;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (payout.status) {
      PayoutStatus.scheduled => (
        'Scheduled ${_fullDate(context, payout.scheduledFor)}',
        EpStatusPillTone.neutral,
      ),
      PayoutStatus.held => (
        payout.holdReason == null ? 'Held' : 'Held: ${payout.holdReason}',
        EpStatusPillTone.warning,
      ),
      PayoutStatus.processing => ('Processing', EpStatusPillTone.selected),
      PayoutStatus.paid => (
        payout.paidAt == null
            ? 'Paid'
            : 'Paid ${_fullDate(context, payout.paidAt!)}',
        EpStatusPillTone.success,
      ),
      PayoutStatus.failed => ('Failed', EpStatusPillTone.warning),
      PayoutStatus.reversed => ('Reversed', EpStatusPillTone.warning),
      PayoutStatus.unknown => ('Unknown', EpStatusPillTone.neutral),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LedgerRow(
            title: switch (payout.kind) {
              PayoutKind.completion => 'Completion',
              PayoutKind.forfeit => 'Forfeit',
            },
            trailing: Text(payout.amount.label),
          ),
          StatusPill(label: label, tone: tone),
        ],
      ),
    );
  }
}

class _RefundRow extends StatelessWidget {
  const _RefundRow({required this.refund});

  final RefundRecord refund;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (refund.status) {
      RefundStatus.pending => ('Pending', EpStatusPillTone.neutral),
      RefundStatus.succeeded => ('Succeeded', EpStatusPillTone.success),
      RefundStatus.failed => ('Failed', EpStatusPillTone.warning),
      RefundStatus.unknown => ('Unknown', EpStatusPillTone.neutral),
    };
    final reason = switch (refund.reason) {
      RefundReason.organizerCancel => 'Organizer cancellation',
      RefundReason.artistCancel => 'Artist cancellation',
      RefundReason.forceMajeure => 'Force majeure',
      RefundReason.admin => 'Admin',
      RefundReason.dispute => 'Dispute',
      RefundReason.latePayment => 'Late payment',
      RefundReason.unknown => 'Unknown reason',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LedgerRow(title: reason, trailing: Text(refund.amount.label)),
          StatusPill(label: label, tone: tone),
        ],
      ),
    );
  }
}

class _BookingReviewsSection extends StatelessWidget {
  const _BookingReviewsSection({required this.bookingId, required this.future});

  final String bookingId;
  final Future<BookingReviews?> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BookingReviews?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final reviews = snapshot.data;
        if (reviews == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (reviews.mine case final mine?) ...[
              _ReviewCard(label: 'Your review', review: mine),
              const SizedBox(height: 12),
            ],
            if (reviews.theirs case final theirs?)
              _ReviewCard(label: 'Their review', review: theirs)
            else
              Text(
                reviews.mine != null
                    ? 'Waiting for the other side'
                    : 'Hidden until both sides review',
                style: Theme.of(context).textTheme.epMeta,
              ),
            if (reviews.canSubmit) ...[
              const SizedBox(height: 12),
              EpButton(
                'WRITE REVIEW',
                key: const Key('booking-review'),
                onTap: () =>
                    context.read<AppState>().openReviewCompose(bookingId),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.label, required this.review});

  final String label;
  final Review review;

  @override
  Widget build(BuildContext context) {
    return EpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$label · ${review.rating}/5',
            style: Theme.of(context).textTheme.epMeta,
          ),
          const SizedBox(height: 8),
          Text(review.text, style: Theme.of(context).textTheme.epBody),
        ],
      ),
    );
  }
}

class _CancelBookingSheet extends StatefulWidget {
  const _CancelBookingSheet({
    required this.app,
    required this.booking,
    required this.onCancelled,
  });

  final AppState app;
  final Booking booking;
  final VoidCallback onCancelled;

  @override
  State<_CancelBookingSheet> createState() => _CancelBookingSheetState();
}

class _CancelBookingSheetState extends State<_CancelBookingSheet> {
  final _reason = TextEditingController();
  late final Future<RefundPreview?> _preview;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _preview = widget.app.previewCancellation(widget.booking);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Cancellation reason is required');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.app.cancelBooking(widget.booking, reason: reason);
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = _errorMessage(error);
        });
      }
      return;
    }
    if (mounted) Navigator.pop(context);
    widget.onCancelled();
  }

  @override
  Widget build(BuildContext context) {
    return EpFormSheet(
      title: 'CANCEL BOOKING',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FutureBuilder<RefundPreview?>(
            future: _preview,
            builder: (context, snapshot) {
              final preview = snapshot.data;
              if (preview == null || preview.paidMinor == 0) {
                return const SizedBox.shrink();
              }
              final currency = widget.booking.fee.currency;
              final recipient = widget.booking.viewerSide == BookingSide.artist
                  ? 'You would receive'
                  : 'The artist receives';
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Refund: ${Money(preview.refundMinor, currency).label} · Forfeited: ${Money(preview.forfeitedMinor, currency).label}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$recipient ${Money(preview.artistPayoutMinor, currency).label}',
                    ),
                  ],
                ),
              );
            },
          ),
          EpLabeledField(
            label: 'REASON',
            hint: 'Explain why you need to cancel',
            controller: _reason,
            fieldKey: const Key('booking-cancel-reason'),
            required: true,
            minLines: 2,
            maxLines: 5,
            enabled: !_submitting,
          ),
          const SizedBox(height: 14),
          InlineFormFeedback(
            error: _error,
            errorKey: const Key('booking-feedback'),
          ),
          const SizedBox(height: 14),
          EpButton(
            'CONFIRM',
            key: const Key('booking-cancel-confirm'),
            onTap: _submitting ? null : _confirm,
          ),
        ],
      ),
    );
  }
}

List<TimelineStep> _timelineSteps(Booking booking) {
  if (const {
    BookingStatus.declined,
    BookingStatus.expired,
    BookingStatus.withdrawn,
    BookingStatus.cancelledByOrganizer,
    BookingStatus.cancelledByArtist,
    BookingStatus.forceMajeure,
    BookingStatus.refunded,
    BookingStatus.disputed,
  }.contains(booking.status)) {
    return [
      TimelineStep(
        label: booking.status.label,
        state: TimelineStepState.blocked,
      ),
    ];
  }
  return [
    TimelineStep(
      label: 'Offer sent',
      state: booking.status == BookingStatus.offerSent
          ? TimelineStepState.current
          : TimelineStepState.done,
    ),
    TimelineStep(
      label: 'Accepted',
      state: booking.artistAcceptedTermsAt != null
          ? TimelineStepState.done
          : booking.status == BookingStatus.artistAccepted
          ? TimelineStepState.current
          : TimelineStepState.pending,
    ),
    TimelineStep(
      label: 'Confirmed',
      state: booking.confirmedAt != null
          ? TimelineStepState.done
          : booking.status == BookingStatus.awaitingPayment
          ? TimelineStepState.current
          : TimelineStepState.pending,
    ),
    TimelineStep(
      label: 'Completed',
      state: booking.completedAt != null
          ? TimelineStepState.done
          : booking.status == BookingStatus.confirmed
          ? TimelineStepState.current
          : TimelineStepState.pending,
    ),
  ];
}

String _statusCaption(BuildContext context, Booking booking) {
  if (booking.status == BookingStatus.awaitingPayment &&
      booking.viewerSide == BookingSide.artist) {
    return "Accepted · awaiting the organizer's payment";
  }
  final (prefix, date) = switch (booking.status) {
    BookingStatus.offerSent => (
      'Offer expires',
      booking.expiresAt ?? booking.currentOffer?.expiresAt,
    ),
    BookingStatus.awaitingPayment => (
      'Awaiting payment · due',
      booking.paymentDueAt,
    ),
    BookingStatus.confirmed => ('Confirmed', booking.confirmedAt),
    BookingStatus.completed ||
    BookingStatus.paid => ('Completed', booking.completedAt),
    BookingStatus.cancelledByOrganizer ||
    BookingStatus.cancelledByArtist ||
    BookingStatus.forceMajeure ||
    BookingStatus.refunded ||
    BookingStatus.disputed => ('Cancelled', booking.cancelledAt),
    _ => ('', null),
  };
  if (booking.status == BookingStatus.offerSent) {
    return '$prefix ${_expiryLabel(date)}';
  }
  return date == null
      ? booking.status.label
      : '$prefix ${_fullDate(context, date)}';
}

String _expiryLabel(DateTime? date) {
  if (date == null) return 'soon';
  final now = DateTime.now();
  final local = date.toLocal();
  final remaining = local.difference(now);
  if (remaining.inHours < 1) return 'soon';
  if (DateUtils.isSameDay(local, now)) return 'today';
  if (remaining.inDays >= 1) {
    return 'in ${remaining.inDays} ${remaining.inDays == 1 ? 'day' : 'days'}';
  }
  return 'in ${remaining.inHours} ${remaining.inHours == 1 ? 'hour' : 'hours'}';
}

String _fullDate(BuildContext context, DateTime date) =>
    MaterialLocalizations.of(context).formatFullDate(date.toLocal());

String _errorMessage(Object error) =>
    error is StateError ? error.message : '$error';
