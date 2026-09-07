import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AdminBookingsScreen extends StatefulWidget {
  const AdminBookingsScreen({super.key});

  @override
  State<AdminBookingsScreen> createState() => _AdminBookingsScreenState();
}

class _AdminBookingsScreenState extends State<AdminBookingsScreen> {
  static const _filters = [
    AdminBookingFilter.all,
    AdminBookingFilter.disputed,
    AdminBookingFilter.held,
    AdminBookingFilter.awaitingPayment,
  ];

  AdminBookingFilter _filter = AdminBookingFilter.all;
  AdminBookingsPage? _page;
  List<AdminBookingRow> _rows = const [];
  Object? _loadToken;
  bool _loadScheduled = false;
  bool _loading = false;
  bool _loadFailed = false;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;

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
    final requestedFilter = _filter;
    _loadToken = token;
    setState(() {
      _loading = true;
      _loadFailed = false;
      _loadingMore = false;
      _loadMoreFailed = false;
      _page = null;
      _rows = const [];
    });
    try {
      final page = await app.repository.adminBookings(filter: requestedFilter);
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _page = page;
        _rows = page.items;
        _loading = false;
      });
    } catch (error) {
      logError('adminBookings', error);
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadMore(AppState app) async {
    final currentPage = _page;
    if (_loading || _loadingMore || currentPage == null || currentPage.isDone) {
      return;
    }
    final token = _loadToken;
    final requestedFilter = _filter;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final page = await app.repository.adminBookings(
        filter: requestedFilter,
        cursor: currentPage.continueCursor,
      );
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _page = page;
        _rows = [..._rows, ...page.items];
        _loadingMore = false;
      });
    } catch (error) {
      logError('adminBookingsPage', error);
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
      app.say(genericErrorMessage);
    }
  }

  void _selectFilter(AppState app, AdminBookingFilter selected) {
    if (_filter == selected) return;
    setState(() => _filter = selected);
    _loadFirstPage(app);
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
                    'BOOKINGS',
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (
                          var index = 0;
                          index < _filters.length;
                          index++
                        ) ...[
                          EpChip(
                            key: Key(
                              'admin-bookings-filter-${_filters[index].name}',
                            ),
                            label: _filters[index].wireValue.replaceAll(
                              '_',
                              ' ',
                            ),
                            active: _filter == _filters[index],
                            onTap: () => _selectFilter(app, _filters[index]),
                          ),
                          if (index < _filters.length - 1)
                            const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_loadFailed) ...[
                    const Text("Couldn't load bookings."),
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
                        'No bookings match this filter.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.epCaption,
                      ),
                    )
                  else
                    for (final row in _rows) ...[
                      _BookingRow(
                        key: Key('admin-booking-${row.bookingId}'),
                        row: row,
                        onTap: () => app.openBooking(row.bookingId),
                      ),
                      const SizedBox(height: 12),
                    ],
                  if (!_loading && _page?.isDone == false)
                    EpButton(
                      _loadingMore
                          ? 'LOADING…'
                          : _loadMoreFailed
                          ? 'RETRY'
                          : 'LOAD MORE',
                      key: const Key('admin-bookings-more'),
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

class _BookingRow extends StatelessWidget {
  const _BookingRow({super.key, required this.row, required this.onTap});

  final AdminBookingRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return EpCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.title, style: Theme.of(context).textTheme.epSectionHeading),
          const SizedBox(height: 5),
          Text(
            '${row.organizationName} · ${row.bandName}',
            style: Theme.of(context).textTheme.epBody,
          ),
          const SizedBox(height: 8),
          Text(
            dateLabel(row.startsAt),
            style: Theme.of(context).textTheme.epCaption,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                label: row.status.label,
                tone: _statusTone(row.status),
              ),
              if (row.openDisputeId != null)
                StatusPill(
                  key: Key('admin-booking-${row.bookingId}-dispute'),
                  label: 'DISPUTE',
                  tone: EpStatusPillTone.warning,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                'Paid ${Money(row.paidMinor, 'usd').label}',
                style: Theme.of(context).textTheme.epCaption,
              ),
              if (row.refundedMinor > 0)
                Text(
                  'Refunded ${Money(row.refundedMinor, 'usd').label}',
                  style: Theme.of(context).textTheme.epCaption,
                ),
            ],
          ),
          if (row.payoutHoldReasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final reason in row.payoutHoldReasons)
                  EpChip(
                    label: reason.replaceAll('_', ' '),
                    active: false,
                    readOnly: true,
                    onTap: null,
                  ),
              ],
            ),
          ],
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
                'Only platform admins can view bookings.',
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

EpStatusPillTone _statusTone(BookingStatus status) => switch (status) {
  BookingStatus.confirmed ||
  BookingStatus.paid ||
  BookingStatus.completed => EpStatusPillTone.success,
  BookingStatus.disputed ||
  BookingStatus.awaitingPayment => EpStatusPillTone.warning,
  _ => EpStatusPillTone.neutral,
};
