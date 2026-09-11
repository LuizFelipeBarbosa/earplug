import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../errors.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart' show EpFormSheet;

class AdminSafetyScreen extends StatefulWidget {
  const AdminSafetyScreen({super.key});

  @override
  State<AdminSafetyScreen> createState() => _AdminSafetyScreenState();
}

class _AdminSafetyScreenState extends State<AdminSafetyScreen> {
  SafetyReportsPage? _page;
  List<SafetyReportRow> _reports = const [];
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
    _loadToken = token;
    setState(() {
      _loading = true;
      _loadFailed = false;
      _loadingMore = false;
      _loadMoreFailed = false;
      _page = null;
      _reports = const [];
    });
    try {
      final page = await app.repository.openSafetyReports();
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _page = page;
        _reports = page.items;
        _loading = false;
      });
    } catch (error) {
      logError('adminSafety', error);
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
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final page = await app.repository.openSafetyReports(
        cursor: currentPage.continueCursor,
      );
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _page = page;
        _reports = [..._reports, ...page.items];
        _loadingMore = false;
      });
    } catch (error) {
      logError('adminSafetyPage', error);
      if (!mounted || !identical(_loadToken, token)) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
      app.say(genericErrorMessage);
    }
  }

  Future<void> _showResolve(AppState app, SafetyReportRow report) async {
    var confirmed = false;
    await showEpSheet(
      context,
      (_) => _ResolveSheet(
        onConfirm: (note) async {
          await app.repository.resolveSafetyReport(
            report.reportId,
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
                    'SAFETY REPORTS',
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
                  const SectionBar(label: 'OPEN REPORTS'),
                  if (_loadFailed) ...[
                    const Text("Couldn't load safety reports."),
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
                  else if (_reports.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Text(
                        'No open safety reports.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.epCaption,
                      ),
                    )
                  else
                    for (final report in _reports) ...[
                      _ReportRow(
                        key: Key('admin-safety-${report.reportId}'),
                        report: report,
                        onOpen: () => app.openBooking(report.bookingId),
                        onResolve: () => _showResolve(app, report),
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
                      key: const Key('admin-safety-more'),
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

class _ReportRow extends StatelessWidget {
  const _ReportRow({
    super.key,
    required this.report,
    required this.onOpen,
    required this.onResolve,
  });

  final SafetyReportRow report;
  final VoidCallback onOpen;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final side = switch (report.reporterSide) {
      BookingSide.artist => 'Artist',
      BookingSide.organizer => 'Host',
      null => null,
    };
    return EpCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _categoryLabel(report.category),
            style: Theme.of(context).textTheme.epMeta,
          ),
          const SizedBox(height: 6),
          Text(
            report.bookingTitle,
            style: Theme.of(context).textTheme.epSectionHeading,
          ),
          const SizedBox(height: 5),
          Text(report.bandName, style: Theme.of(context).textTheme.epBody),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (side != null)
                Text(side, style: Theme.of(context).textTheme.epCaption),
              Text(
                dateLabel(report.createdAt),
                style: Theme.of(context).textTheme.epCaption,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(report.text, style: Theme.of(context).textTheme.epBody),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              EpButton(
                'OPEN BOOKING',
                key: Key('admin-safety-open-${report.reportId}'),
                kind: EpButtonKind.outline,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                onTap: onOpen,
              ),
              EpButton(
                'RESOLVE',
                key: Key('admin-safety-resolve-${report.reportId}'),
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
  const _ResolveSheet({required this.onConfirm});

  final Future<void> Function(String? note) onConfirm;

  @override
  State<_ResolveSheet> createState() => _ResolveSheetState();
}

class _ResolveSheetState extends State<_ResolveSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final note = _controller.text.trim();
    try {
      await widget.onConfirm(note.isEmpty ? null : note);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      logError('adminSafetyResolve', error);
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
      title: 'Resolve report',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EpLabeledField(
            label: 'ADMIN NOTE',
            hint: 'Add a note (optional)',
            controller: _controller,
            fieldKey: const Key('admin-safety-note'),
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
            key: const Key('admin-safety-resolve-confirm'),
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
                'Only platform admins can view safety reports.',
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

String _categoryLabel(SafetyCategory category) => switch (category) {
  SafetyCategory.safety => 'Safety',
  SafetyCategory.harassment => 'Harassment',
  SafetyCategory.misrepresentation => 'Misrepresentation',
  SafetyCategory.other || SafetyCategory.unknown => 'Other',
};
