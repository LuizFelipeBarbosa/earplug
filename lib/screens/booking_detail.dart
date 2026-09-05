import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
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
    _future = app.loadBooking(widget.bookingId, refresh: refresh);
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

  Widget? _stickyBar(Booking booking) {
    final isOffer = booking.status == BookingStatus.offerSent;
    if (!isOffer && booking.status != BookingStatus.confirmed) return null;
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
        final stickyBar = _stickyBar(booking);
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
                  _FeeCard(fee: booking.fee),
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
  const _FeeCard({required this.fee});

  final FeeBreakdown fee;

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
  bool _submitting = false;
  String? _error;

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
  final (prefix, date) = switch (booking.status) {
    BookingStatus.offerSent => (
      'Offer expires',
      booking.expiresAt ?? booking.currentOffer?.expiresAt,
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
