import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart' show EpFormSheet;

class AdminDisputesScreen extends StatefulWidget {
  const AdminDisputesScreen({super.key});

  @override
  State<AdminDisputesScreen> createState() => _AdminDisputesScreenState();
}

class _AdminDisputesScreenState extends State<AdminDisputesScreen> {
  DisputesPage? _page;
  AdminBookingsPage? _reviewPage;
  List<DisputeRow> _rows = const [];
  final _startingReview = <String>{};
  Object? _loadToken;
  bool _loadScheduled = false;
  bool _loading = false;
  bool _loadFailed = false;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;

  bool get _hasMore => _page?.isDone == false || _reviewPage?.isDone == false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.watch<AppState>();
    if (!app.isPlatformAdmin || _loadScheduled) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentApp = context.read<AppState>();
      if (currentApp.isPlatformAdmin) {
        _loadFirstPage(currentApp);
      } else {
        _loadScheduled = false;
      }
    });
  }

  Future<void> _loadFirstPage(AppState app) async {
    final token = Object();
    _loadToken = token;
    setState(() {
      _loading = true;
      _loadFailed = false;
      _loadingMore = false;
      _loadMoreFailed = false;
      _page = null;
      _reviewPage = null;
      _rows = const [];
    });
    try {
      final page = await app.repository.openDisputes();
      final review = await _loadReviewPage(app);
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _page = page;
        _reviewPage = review.page;
        _rows = _mergeRows([...page.items, ...review.rows]);
        _loading = false;
      });
    } catch (error) {
      logError('adminDisputes', error);
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadMore(AppState app) async {
    final currentPage = _page;
    final currentReviewPage = _reviewPage;
    if (_loading ||
        _loadingMore ||
        currentPage == null ||
        currentReviewPage == null ||
        !_hasMore) {
      return;
    }
    final token = _loadToken;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final page = currentPage.isDone
          ? null
          : await app.repository.openDisputes(
              cursor: currentPage.continueCursor,
            );
      final review = currentReviewPage.isDone
          ? null
          : await _loadReviewPage(
              app,
              cursor: currentReviewPage.continueCursor,
            );
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _page = page ?? currentPage;
        _reviewPage = review?.page ?? currentReviewPage;
        _rows = _mergeRows([..._rows, ...?page?.items, ...?review?.rows]);
        _loadingMore = false;
      });
    } catch (error) {
      logError('adminDisputesPage', error);
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
      app.say(genericErrorMessage);
    }
  }

  // openDisputes only returns status=open. Read the other unresolved cases
  // through disputed bookings so reviewing a case does not hide it on reload.
  Future<({AdminBookingsPage page, List<DisputeRow> rows})> _loadReviewPage(
    AppState app, {
    String? cursor,
  }) async {
    final page = await app.repository.adminBookings(
      filter: AdminBookingFilter.disputed,
      cursor: cursor,
    );
    final rowsByBooking = await Future.wait([
      for (final booking in page.items)
        app.repository
            .disputesForBooking(booking.bookingId)
            .then(
              (disputes) => [
                for (final dispute in disputes)
                  if (dispute.status == DisputeStatus.underReview)
                    DisputeRow(
                      disputeId: dispute.disputeId,
                      bookingId: dispute.bookingId,
                      side: dispute.side,
                      category: dispute.category,
                      text: dispute.text,
                      requestedRefundMinor: dispute.requestedRefundMinor,
                      status: dispute.status,
                      createdAt: dispute.createdAt,
                      bookingTitle: booking.title,
                      organizationName: booking.organizationName,
                      bandName: booking.bandName,
                      paidMinor: booking.paidMinor,
                      bookingStatus: booking.status,
                    ),
              ],
            ),
    ]);
    return (page: page, rows: rowsByBooking.expand((rows) => rows).toList());
  }

  Future<void> _startReview(AppState app, DisputeRow row) async {
    if (_startingReview.contains(row.disputeId)) return;
    setState(() => _startingReview.add(row.disputeId));
    try {
      await app.startDisputeReview(row.disputeId);
      if (!mounted || !app.isPlatformAdmin) return;
      await _loadFirstPage(app);
    } catch (error) {
      logError('adminDisputeReview', error);
      if (mounted) app.say(genericErrorMessage);
    } finally {
      if (mounted) setState(() => _startingReview.remove(row.disputeId));
    }
  }

  Future<void> _showResolve(AppState app, DisputeRow row) async {
    var confirmed = false;
    await showEpSheet(
      context,
      (_) => _ResolveSheet(
        paidMinor: row.paidMinor,
        onConfirm: (resolution, refundMinor, note) async {
          await app.resolveDispute(
            row.disputeId,
            resolution: resolution,
            refundMinor: refundMinor,
            adminNote: note,
          );
          confirmed = true;
        },
      ),
    );
    if (!confirmed || !mounted || !app.isPlatformAdmin) return;
    await _loadFirstPage(app);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.isPlatformAdmin) {
      return _NotAuthorized(onBack: app.toFanView);
    }

    return Material(
      color: context.epColors.background,
      child: Column(
        children: [
          ScreenHeader(
            child: Row(
              children: [
                CircleIconButton(onTap: app.back),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'DISPUTES',
                    style: Theme.of(context).textTheme.epPageHeading,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadFirstPage(app),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  const SectionBar(label: 'OPEN DISPUTES'),
                  if (_loadFailed) ...[
                    const Text("Couldn't load disputes."),
                    const SizedBox(height: 12),
                    EpButton(
                      'RETRY',
                      kind: EpButtonKind.outline,
                      onTap: () => _loadFirstPage(app),
                    ),
                  ] else if (_loading || _page == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Text(
                        'No open disputes.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.epCaption,
                      ),
                    )
                  else
                    for (final row in _rows) ...[
                      _DisputeRow(
                        key: Key('admin-dispute-${row.disputeId}'),
                        row: row,
                        onOpen: () => app.openBooking(row.bookingId),
                        onReview: _startingReview.contains(row.disputeId)
                            ? null
                            : () => _startReview(app, row),
                        onResolve: _startingReview.contains(row.disputeId)
                            ? null
                            : () => _showResolve(app, row),
                      ),
                      const SizedBox(height: 12),
                    ],
                  if (!_loading && _hasMore)
                    EpButton(
                      _loadingMore
                          ? 'LOADING…'
                          : _loadMoreFailed
                          ? 'RETRY'
                          : 'LOAD MORE',
                      key: const Key('admin-disputes-more'),
                      kind: EpButtonKind.outline,
                      onTap: _loadingMore ? null : () => _loadMore(app),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<DisputeRow> _mergeRows(List<DisputeRow> rows) =>
    {for (final row in rows) row.disputeId: row}.values.toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));

class _DisputeRow extends StatelessWidget {
  const _DisputeRow({
    super.key,
    required this.row,
    required this.onOpen,
    required this.onReview,
    required this.onResolve,
  });

  final DisputeRow row;
  final VoidCallback onOpen;
  final VoidCallback? onReview;
  final VoidCallback? onResolve;

  @override
  Widget build(BuildContext context) {
    final paid = Money(row.paidMinor, 'usd').label;
    final requested = row.requestedRefundMinor;
    return EpCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            row.side == DisputeSide.organizer ? 'Refund request' : 'Dispute',
            style: Theme.of(context).textTheme.epMeta,
          ),
          const SizedBox(height: 6),
          Text(
            row.category.label,
            style: Theme.of(context).textTheme.epCaption,
          ),
          const SizedBox(height: 6),
          Text(
            row.bookingTitle,
            style: Theme.of(context).textTheme.epSectionHeading,
          ),
          const SizedBox(height: 5),
          Text(
            '${row.organizationName} · ${row.bandName}',
            style: Theme.of(context).textTheme.epBody,
          ),
          const SizedBox(height: 8),
          Text(
            requested == null
                ? 'Paid $paid'
                : 'Requested ${Money(requested, 'usd').label} of $paid',
            style: Theme.of(context).textTheme.epCaption,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                dateLabel(row.createdAt),
                style: Theme.of(context).textTheme.epCaption,
              ),
              StatusPill(
                label: row.status.wireValue.replaceAll('_', ' '),
                tone: EpStatusPillTone.warning,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(row.text, style: Theme.of(context).textTheme.epBody),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              EpButton(
                'OPEN BOOKING',
                key: Key('admin-dispute-open-${row.disputeId}'),
                kind: EpButtonKind.outline,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                onTap: onOpen,
              ),
              if (row.status == DisputeStatus.open)
                EpButton(
                  'START REVIEW',
                  key: Key('admin-dispute-review-${row.disputeId}'),
                  kind: EpButtonKind.outline,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  onTap: onReview,
                ),
              EpButton(
                'RESOLVE',
                key: Key('admin-dispute-resolve-${row.disputeId}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                onTap: onResolve,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResolveSheet extends StatefulWidget {
  const _ResolveSheet({required this.paidMinor, required this.onConfirm});

  final int paidMinor;
  final Future<void> Function(
    DisputeResolution resolution,
    int? refundMinor,
    String? note,
  )
  onConfirm;

  @override
  State<_ResolveSheet> createState() => _ResolveSheetState();
}

class _ResolveSheetState extends State<_ResolveSheet> {
  static const _resolutions = [
    (DisputeResolution.released, 'RELEASE TO ARTIST'),
    (DisputeResolution.refundedFull, 'REFUND IN FULL'),
    (DisputeResolution.refundedPartial, 'PARTIAL REFUND'),
    (DisputeResolution.dismissed, 'DISMISS'),
  ];

  final _amount = TextEditingController();
  final _note = TextEditingController();
  DisputeResolution _resolution = DisputeResolution.released;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    int? refundMinor;
    if (_resolution == DisputeResolution.refundedPartial) {
      final dollars = double.tryParse(_amount.text.trim());
      final cents = dollars == null ? null : dollars * 100;
      if (cents != null && cents.isFinite) refundMinor = cents.round();
      if (refundMinor == null ||
          refundMinor <= 0 ||
          refundMinor >= widget.paidMinor) {
        setState(() {
          _error =
              'Enter an amount greater than ${Money(0, 'usd').label} '
              'and less than ${Money(widget.paidMinor, 'usd').label}.';
        });
        return;
      }
    }
    // Resolve the sheet's navigator while its context is known to be active.
    final navigator = Navigator.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    final note = _note.text.trim();
    try {
      await widget.onConfirm(
        _resolution,
        refundMinor,
        note.isEmpty ? null : note,
      );
      if (mounted) navigator.pop();
    } catch (error) {
      logError('adminDisputeResolve', error);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = genericErrorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return EpFormSheet(
      title: 'Resolve dispute',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (resolution, label) in _resolutions)
                EpChip(
                  key: Key('admin-dispute-resolution-${resolution.wireValue}'),
                  label: label,
                  active: _resolution == resolution,
                  onTap: _submitting
                      ? null
                      : () => setState(() {
                          _resolution = resolution;
                          _error = null;
                        }),
                ),
            ],
          ),
          if (_resolution == DisputeResolution.refundedPartial) ...[
            const SizedBox(height: 16),
            EpLabeledField(
              label: 'AMOUNT (\$)',
              hint: '0.00',
              controller: _amount,
              fieldKey: const Key('admin-dispute-amount'),
              keyboardType: TextInputType.number,
              enabled: !_submitting,
            ),
          ],
          const SizedBox(height: 16),
          EpLabeledField(
            label: 'ADMIN NOTE',
            hint: 'Add a note (optional)',
            controller: _note,
            fieldKey: const Key('admin-dispute-note'),
            enabled: !_submitting,
            minLines: 3,
            maxLines: 5,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            InlineFormFeedback(error: _error),
          ],
          const SizedBox(height: 14),
          EpButton(
            'CONFIRM',
            key: const Key('admin-dispute-confirm'),
            onTap: _submitting ? null : _confirm,
          ),
        ],
      ),
    );
  }
}

class _NotAuthorized extends StatelessWidget {
  const _NotAuthorized({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('admin-not-authorized'),
      child: Material(
        color: context.epColors.background,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Only platform admins can view disputes.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.epBody,
              ),
              const SizedBox(height: 16),
              EpButton(
                'BACK TO FAN VIEW',
                kind: EpButtonKind.outline,
                onTap: onBack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
