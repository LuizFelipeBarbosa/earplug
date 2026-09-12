import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';

String organizationTypeLabel(OrganizationType type) => switch (type) {
  OrganizationType.venueOperator => 'Venue operator',
  OrganizationType.promoter => 'Promoter',
  OrganizationType.studentOrg => 'Student org',
  OrganizationType.privateHost => 'Private host',
  OrganizationType.other => 'Other',
};

class AdminQueueScreen extends StatefulWidget {
  const AdminQueueScreen({super.key});

  @override
  State<AdminQueueScreen> createState() => _AdminQueueScreenState();
}

class _AdminQueueScreenState extends State<AdminQueueScreen> {
  static const _filters = [
    OrganizationApplicationStatus.submitted,
    OrganizationApplicationStatus.underReview,
    OrganizationApplicationStatus.needsInfo,
    OrganizationApplicationStatus.approved,
    OrganizationApplicationStatus.rejected,
  ];

  OrganizationApplicationStatus _filter =
      OrganizationApplicationStatus.submitted;
  ApplicationKind? _kind;
  AdminOverview? _overview;
  AdminApplicationPage? _page;
  List<AdminApplicationRow> _rows = const [];
  Object? _loadToken;
  bool _loadScheduled = false;
  bool _loading = false;
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
      _loadingMore = false;
      _loadMoreFailed = false;
      _page = null;
      _rows = const [];
    });

    try {
      final overviewFuture = app.repository.adminOverview();
      final pageFuture = app.repository.applicationsForReview(
        status: requestedFilter,
        kind: _kind,
      );
      final overview = await overviewFuture;
      final page = await pageFuture;
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _overview = overview;
        _page = page;
        _rows = page.items;
        _loading = false;
      });
    } catch (error) {
      logError('adminQueue', error);
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() => _loading = false);
      app.say(genericErrorMessage);
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
      final nextPage = await app.repository.applicationsForReview(
        status: requestedFilter,
        kind: _kind,
        cursor: currentPage.continueCursor,
      );
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _page = nextPage;
        _rows = [..._rows, ...nextPage.items];
        _loadingMore = false;
      });
    } catch (error) {
      logError('adminQueuePage', error);
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
      app.say(genericErrorMessage);
    }
  }

  void _selectFilter(AppState app, OrganizationApplicationStatus selected) {
    if (_filter == selected || _loading) return;
    setState(() => _filter = selected);
    _loadFirstPage(app);
  }

  void _selectKind(AppState app, ApplicationKind? selected) {
    if (_kind == selected || _loading) return;
    setState(() => _kind = selected);
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
          Padding(
            padding: EdgeInsets.fromLTRB(
              EpLayout.gutter,
              headerTopPad(context),
              EpLayout.gutter,
              24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: EpEyebrow.accent('Admin')),
                    EpPill(
                      key: const Key('admin-queue-exit'),
                      label: 'Fan view',
                      variant: EpPillVariant.outline,
                      onPressed: app.toFanView,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const EpDisplay('Applications', size: 36),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadFirstPage(app),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: EpLayout.gutter,
                ),
                children: [
                  if (_overview case final overview?) ...[
                    EpStatGrid(
                      valueSize: 28,
                      stats: [
                        EpStat(
                          '${overview.submitted}${overview.capped ? '+' : ''}',
                          'Submitted',
                        ),
                        EpStat(
                          '${overview.underReview}${overview.capped ? '+' : ''}',
                          'Review',
                        ),
                        EpStat(
                          '${overview.needsInfo}${overview.capped ? '+' : ''}',
                          'Needs info',
                        ),
                        EpStat(
                          '${overview.verifiedOrganizations}${overview.capped ? '+' : ''}',
                          'Verified',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                  EpSegmentTabs(
                    labels: [
                      for (final filter in _filters) _statusLabel(filter),
                    ],
                    selected: _filters.indexOf(_filter),
                    onSelect: (index) => _selectFilter(app, _filters[index]),
                    scrollable: true,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      EpChip(
                        key: const Key('admin-queue-kind-all'),
                        label: 'ALL',
                        active: _kind == null,
                        onTap: () => _selectKind(app, null),
                      ),
                      EpChip(
                        key: const Key('admin-queue-kind-organization'),
                        label: 'ORGANIZATIONS',
                        active: _kind == ApplicationKind.organization,
                        onTap: () =>
                            _selectKind(app, ApplicationKind.organization),
                      ),
                      EpChip(
                        key: const Key('admin-queue-kind-host'),
                        label: 'HOSTS',
                        active: _kind == ApplicationKind.host,
                        onTap: () => _selectKind(app, ApplicationKind.host),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Text(
                        'No ${_statusLabel(_filter).toLowerCase()} applications.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.epBody.copyWith(
                          color: context.epColors.muted,
                        ),
                      ),
                    )
                  else
                    for (var index = 0; index < _rows.length; index++)
                      _ApplicationRow(
                        key: Key(
                          'admin-queue-row-${_rows[index].application.id}',
                        ),
                        row: _rows[index],
                        onTap: () => app.go(
                          Screen.adminApplication,
                          _rows[index].application.id,
                        ),
                      ),
                  if (!_loading && _page?.isDone == false) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: EpPill(
                        key: const Key('admin-queue-load-more'),
                        variant: EpPillVariant.ghost,
                        size: EpPillSize.chip,
                        onPressed: _loadingMore ? null : () => _loadMore(app),
                        label: _loadingMore
                            ? 'Loading…'
                            : _loadMoreFailed
                            ? 'Retry'
                            : 'Load more',
                      ),
                    ),
                  ],
                  const Padding(
                    padding: EdgeInsets.only(top: 32, bottom: 8),
                    child: EpEyebrow('Other queues'),
                  ),
                  _OtherQueueRow(
                    key: const Key('admin-safety-entry'),
                    label: 'Safety reports',
                    onTap: () => app.go(Screen.adminSafety),
                  ),
                  _OtherQueueRow(
                    key: const Key('admin-disputes-entry'),
                    label: 'Disputes',
                    onTap: () => app.go(Screen.adminDisputes),
                  ),
                  _OtherQueueRow(
                    key: const Key('admin-bookings-entry'),
                    label: 'Bookings',
                    onTap: () => app.go(Screen.adminBookings),
                  ),
                  const EpHairline(),
                  const SizedBox(height: tabBarClearance),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicationRow extends StatelessWidget {
  const _ApplicationRow({super.key, required this.row, required this.onTap});

  final AdminApplicationRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final application = row.application;
    final isHost = application.kind == ApplicationKind.host;
    final hostDisplayName = application.hostDisplayName?.trim();
    final heading =
        isHost && hostDisplayName != null && hostDisplayName.isNotEmpty
        ? hostDisplayName
        : application.orgName;
    final venue = application.venue;
    final hostArea = application.hostArea?.trim();
    final details = [
      application.contactName,
      if (venue != null) ...[
        venue.addr,
        if (venue.capacity != null) 'cap ${venue.capacity}',
      ] else if (isHost && hostArea != null && hostArea.isNotEmpty)
        hostArea,
    ].join(' · ');

    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            EpDisplay(heading, size: 24),
                            EpBadge(
                              key: Key(
                                'admin-row-${application.id}-${isHost ? 'host' : 'type'}',
                              ),
                              label: isHost
                                  ? 'Host'
                                  : organizationTypeLabel(application.orgType),
                              variant: EpBadgeVariant.secondary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          details,
                          style: Theme.of(context).textTheme.epBody.copyWith(
                            color: context.epColors.muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        EpMonoText(
                          'Submitted ${dateLabel(application.createdAt)}',
                          color: context.epColors.muted,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: context.epColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const EpHairline(),
          ],
        ),
      ),
    );
  }
}

class _OtherQueueRow extends StatelessWidget {
  const _OtherQueueRow({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      child: Column(
        children: [
          const EpHairline(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [Expanded(child: EpDisplay(label, size: 20))]),
          ),
        ],
      ),
    ),
  );
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
                'Only platform admins can review organizer applications.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.epBody,
              ),
              const SizedBox(height: 16),
              EpPill(
                label: 'Back to fan view',
                variant: EpPillVariant.outline,
                onPressed: onBack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _statusLabel(OrganizationApplicationStatus status) => status.wireValue
    .replaceAll('_', ' ')
    .split(' ')
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');
