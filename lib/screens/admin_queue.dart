import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

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
          ScreenHeader(
            child: EpPageHeading(
              title: 'EARPLUG ADMIN',
              action: TextButton(
                key: const Key('admin-queue-exit'),
                onPressed: app.toFanView,
                child: const Text('BACK TO FAN VIEW'),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadFirstPage(app),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_overview case final overview?) ...[
                    _OverviewCards(overview: overview),
                    const SizedBox(height: 22),
                  ],
                  EpButton(
                    'SAFETY REPORTS',
                    key: const Key('admin-safety-entry'),
                    kind: EpButtonKind.outline,
                    onTap: () => app.go(Screen.adminSafety),
                  ),
                  const SizedBox(height: 16),
                  EpButton(
                    'DISPUTES',
                    key: const Key('admin-disputes-entry'),
                    kind: EpButtonKind.outline,
                    onTap: () => app.go(Screen.adminDisputes),
                  ),
                  const SizedBox(height: 16),
                  EpButton(
                    'BOOKINGS',
                    key: const Key('admin-bookings-entry'),
                    kind: EpButtonKind.outline,
                    onTap: () => app.go(Screen.adminBookings),
                  ),
                  const SizedBox(height: 16),
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
                              'admin-queue-filter-${_filters[index].name}',
                            ),
                            label: _statusLabel(_filters[index]).toUpperCase(),
                            active: _filter == _filters[index],
                            onTap: () => _selectFilter(app, _filters[index]),
                          ),
                          if (index < _filters.length - 1)
                            const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SectionBar(label: 'KIND'),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        EpChip(
                          key: const Key('admin-queue-kind-all'),
                          label: 'ALL',
                          active: _kind == null,
                          onTap: () => _selectKind(app, null),
                        ),
                        const SizedBox(width: 8),
                        EpChip(
                          key: const Key('admin-queue-kind-organization'),
                          label: 'ORGANIZATIONS',
                          active: _kind == ApplicationKind.organization,
                          onTap: () =>
                              _selectKind(app, ApplicationKind.organization),
                        ),
                        const SizedBox(width: 8),
                        EpChip(
                          key: const Key('admin-queue-kind-host'),
                          label: 'HOSTS',
                          active: _kind == ApplicationKind.host,
                          onTap: () => _selectKind(app, ApplicationKind.host),
                        ),
                      ],
                    ),
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
                        style: Theme.of(context).textTheme.epCaption,
                      ),
                    )
                  else
                    for (var index = 0; index < _rows.length; index++) ...[
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
                      if (index < _rows.length - 1) const SizedBox(height: 10),
                    ],
                  if (!_loading && _page?.isDone == false) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      key: const Key('admin-queue-load-more'),
                      onPressed: _loadingMore ? null : () => _loadMore(app),
                      child: Text(
                        _loadingMore
                            ? 'LOADING…'
                            : _loadMoreFailed
                            ? 'RETRY'
                            : 'LOAD MORE',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewCards extends StatelessWidget {
  const _OverviewCards({required this.overview});

  final AdminOverview overview;

  @override
  Widget build(BuildContext context) {
    final caption = overview.capped ? '100+' : null;
    final hosts = overview.hostApplications;
    return Column(
      children: [
        Row(
          children: [
            EpStatCard(
              label: 'SUBMITTED',
              value: '${overview.submitted}',
              caption: caption,
            ),
            const SizedBox(width: 8),
            EpStatCard(
              label: 'UNDER REVIEW',
              value: '${overview.underReview}',
              caption: caption,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            EpStatCard(
              label: 'NEEDS INFO',
              value: '${overview.needsInfo}',
              caption: caption,
            ),
            const SizedBox(width: 8),
            EpStatCard(
              label: 'VERIFIED ORGS',
              value: '${overview.verifiedOrganizations}',
              caption: caption,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            EpStatCard(
              label: 'HOSTS',
              value: '${hosts.submitted + hosts.underReview + hosts.needsInfo}',
              caption: caption,
            ),
          ],
        ),
      ],
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
    return EpCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  heading,
                  style: Theme.of(context).textTheme.epSectionHeading,
                ),
              ),
              if (isHost) ...[
                const SizedBox(width: 8),
                StatusPill(
                  key: Key('admin-row-${application.id}-host'),
                  label: 'HOST',
                  tone: EpStatusPillTone.neutral,
                ),
              ],
              const SizedBox(width: 10),
              StatusPill(
                label: _statusLabel(application.status),
                tone: _statusTone(application.status),
              ),
            ],
          ),
          if (!isHost) ...[
            const SizedBox(height: 5),
            StatusPill(
              key: Key('admin-row-${application.id}-type'),
              label: organizationTypeLabel(application.orgType).toUpperCase(),
              tone: EpStatusPillTone.neutral,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '${row.applicantName} · ${dateLabel(application.createdAt)}',
            style: Theme.of(context).textTheme.epCaption.copyWith(
              color: context.epColors.contentSecondary,
            ),
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
                'Only platform admins can review organizer applications.',
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

String _statusLabel(OrganizationApplicationStatus status) => status.wireValue
    .replaceAll('_', ' ')
    .split(' ')
    .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
    .join(' ');

EpStatusPillTone _statusTone(OrganizationApplicationStatus status) =>
    switch (status) {
      OrganizationApplicationStatus.approved => EpStatusPillTone.success,
      OrganizationApplicationStatus.submitted => EpStatusPillTone.selected,
      OrganizationApplicationStatus.underReview ||
      OrganizationApplicationStatus.needsInfo => EpStatusPillTone.warning,
      OrganizationApplicationStatus.draft ||
      OrganizationApplicationStatus.rejected ||
      OrganizationApplicationStatus.withdrawn => EpStatusPillTone.neutral,
    };
