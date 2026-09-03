import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';
import '../widgets/status_timeline.dart';

Future<bool> _confirmWithdraw(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('WITHDRAW APPLICATION?'),
        content: const Text(
          'Withdrawing ends this application. You will need to reapply.',
        ),
        actions: [
          TextButton(
            key: const Key('org-status-withdraw-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('KEEP'),
          ),
          FilledButton(
            key: const Key('org-status-withdraw-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    ) ??
    false;

class OrgApplicationStatusScreen extends StatefulWidget {
  const OrgApplicationStatusScreen({super.key});

  @override
  State<OrgApplicationStatusScreen> createState() =>
      _OrgApplicationStatusScreenState();
}

class _OrgApplicationStatusScreenState
    extends State<OrgApplicationStatusScreen> {
  bool _withdrawing = false;

  @override
  void initState() {
    super.initState();
    unawaited(context.read<AppState>().refreshOrganizationApplication());
  }

  Future<void> _withdraw(OrganizationApplication application) async {
    if (!await _confirmWithdraw(context) || !mounted) return;
    setState(() => _withdrawing = true);
    final app = context.read<AppState>();
    try {
      await app.repository.withdrawOrganizationApplication(application.id);
      await app.refreshOrganizationApplication();
      if (!mounted) return;
      app.toFanView();
    } catch (_) {
      if (!mounted) return;
      setState(() => _withdrawing = false);
      app.say('Could not withdraw the application. Please try again.');
      await app.refreshOrganizationApplication();
    }
  }

  List<TimelineStep> _steps(OrganizationApplication application) {
    final status = application.status;
    final decisionCaption = switch (status) {
      OrganizationApplicationStatus.needsInfo =>
        'Needs more info${_noteSuffix(application.reviewNote)}',
      OrganizationApplicationStatus.rejected =>
        'Rejected${_noteSuffix(application.reviewNote)}',
      OrganizationApplicationStatus.withdrawn => 'Withdrawn',
      OrganizationApplicationStatus.approved => 'Approved',
      _ => null,
    };
    final (submitted, review, decision) = switch (status) {
      OrganizationApplicationStatus.draft => (
        TimelineStepState.pending,
        TimelineStepState.pending,
        TimelineStepState.pending,
      ),
      OrganizationApplicationStatus.submitted ||
      OrganizationApplicationStatus.underReview => (
        TimelineStepState.done,
        TimelineStepState.current,
        TimelineStepState.pending,
      ),
      OrganizationApplicationStatus.needsInfo ||
      OrganizationApplicationStatus.rejected ||
      OrganizationApplicationStatus.withdrawn => (
        TimelineStepState.done,
        TimelineStepState.done,
        TimelineStepState.blocked,
      ),
      OrganizationApplicationStatus.approved => (
        TimelineStepState.done,
        TimelineStepState.done,
        TimelineStepState.done,
      ),
    };
    return [
      TimelineStep(label: 'Submitted', state: submitted),
      TimelineStep(label: 'Under review', state: review),
      TimelineStep(
        label: 'Decision',
        caption: decisionCaption,
        state: decision,
      ),
    ];
  }

  String _noteSuffix(String? note) {
    final trimmed = note?.trim() ?? '';
    return trimmed.isEmpty ? '' : ': $trimmed';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final application = app.myOrganizationApplication;
    return Material(
      color: context.epColors.background,
      child: Column(
        children: [
          ScreenHeader(
            child: Row(
              children: [
                CircleIconButton(onTap: () => context.read<AppState>().back()),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ORGANIZER APPLICATION',
                    style: epDisplay(size: 16),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: application == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No organizer application found.',
                        textAlign: TextAlign.center,
                        style: epText(color: context.epColors.contentSecondary),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                    children: [
                      StatusTimeline(
                        key: const Key('org-status-timeline'),
                        steps: _steps(application),
                      ),
                      if (application.status ==
                          OrganizationApplicationStatus.needsInfo) ...[
                        EpButton(
                          'EDIT APPLICATION',
                          key: const Key('org-status-edit'),
                          onTap: () =>
                              context.read<AppState>().go(Screen.orgApply),
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (application.status ==
                          OrganizationApplicationStatus.approved) ...[
                        Text(
                          "You're verified",
                          style: Theme.of(context).textTheme.epPageHeading,
                        ),
                        const SizedBox(height: 12),
                        EpButton(
                          'SWITCH TO ORGANIZER',
                          key: const Key('org-status-switch'),
                          onTap: () =>
                              context.read<AppState>().switchToOrganization(
                                application.resultingOrganizationId!,
                              ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (application.status ==
                          OrganizationApplicationStatus.rejected) ...[
                        Text(
                          'You can apply again later.',
                          style: Theme.of(context).textTheme.epBody,
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (application.status ==
                          OrganizationApplicationStatus.withdrawn) ...[
                        Text(
                          'Withdrawn. You can start a new application later.',
                          style: Theme.of(context).textTheme.epBody,
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (application.status ==
                              OrganizationApplicationStatus.submitted ||
                          application.status ==
                              OrganizationApplicationStatus.underReview ||
                          application.status ==
                              OrganizationApplicationStatus.needsInfo)
                        DangerZone(
                          key: const Key('org-status-withdraw'),
                          label: _withdrawing
                              ? 'WITHDRAWING…'
                              : 'WITHDRAW APPLICATION',
                          consequence:
                              'You will need to reapply if you withdraw.',
                          onPressed: _withdrawing
                              ? null
                              : () => _withdraw(application),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
