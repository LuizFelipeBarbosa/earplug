import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';
import 'door_mode.dart';

class GigManagerScreen extends StatefulWidget {
  const GigManagerScreen({super.key});

  @override
  State<GigManagerScreen> createState() => _GigManagerScreenState();
}

class _GigManagerScreenState extends State<GigManagerScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (app.isAdminOf(app.bandId)) app.ensureManagedGigs();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.isAdminOf(app.bandId)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Only band admins can create and manage gigs.',
            textAlign: TextAlign.center,
            style: epText(color: context.epColors.contentSecondary),
          ),
        ),
      );
    }
    final projects = app.managedGigProjects;
    final drafts = projects
        .where((project) => project.status == GigProjectStatus.draft)
        .toList();
    final published = projects
        .where((project) => project.status == GigProjectStatus.published)
        .toList();
    final cancelled = projects
        .where((project) => project.status == GigProjectStatus.cancelled)
        .toList();

    return RefreshIndicator(
      onRefresh: app.refreshManagedGigs,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          headerTopPad(context),
          16,
          tabBarClearance,
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Gigs',
                  style: Theme.of(context).textTheme.epPageHeading,
                ),
              ),
              FilledButton(
                onPressed: app.startGigCreate,
                child: Text('+ NEW GIG'),
              ),
            ],
          ),
          if (app.managedGigsLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 20),
          _DraftSection(projects: drafts),
          const SizedBox(height: 20),
          _ProjectSection(
            title: 'PUBLISHED',
            projects: published,
            empty: 'No live gigs yet.',
          ),
          const SizedBox(height: 20),
          _ProjectSection(
            title: 'CANCELLED',
            projects: cancelled,
            empty: 'No cancelled gigs.',
          ),
          const SizedBox(height: 20),
          _PastSection(app: app),
        ],
      ),
    );
  }
}

class _ProjectSection extends StatelessWidget {
  const _ProjectSection({
    required this.title,
    required this.projects,
    required this.empty,
  });

  final String title;
  final List<GigProject> projects;
  final String empty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionBar(
          label: title,
          count: projects.isEmpty ? null : projects.length,
        ),
        const SizedBox(height: 10),
        if (projects.isEmpty)
          EmptyNote(
            message: empty,
            padding: const EdgeInsets.all(18),
            style: Theme.of(context).textTheme.epCaption,
          )
        else
          for (var index = 0; index < projects.length; index++) ...[
            _ProjectCard(project: projects[index]),
            if (index < projects.length - 1) const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _DraftSection extends StatelessWidget {
  const _DraftSection({required this.projects});

  final List<GigProject> projects;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionBar(
          label: 'DRAFTS',
          count: projects.isEmpty ? null : projects.length,
        ),
        const SizedBox(height: 10),
        if (projects.isEmpty)
          DashedBox(
            padding: const EdgeInsets.all(18),
            child: Text(
              'No saved drafts.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.epCaption,
            ),
          )
        else
          for (var index = 0; index < projects.length; index++) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: GhostDraftRow(
                        title: _projectTitle(projects[index]),
                        missing: _draftMissing(projects[index]),
                        onResume: () => app.editGigProject(projects[index].id),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('gig-actions-${projects[index].id}'),
                      tooltip:
                          'More actions for ${_projectTitle(projects[index])}',
                      onPressed: () =>
                          _showProjectActions(context, app, projects[index]),
                      icon: Icon(Icons.more_horiz),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _FeatureAction(
                        key: ValueKey('gig-preview-${projects[index].id}'),
                        icon: Icons.visibility,
                        label: 'PREVIEW',
                        onTap: () => _runProjectAction(
                          context,
                          app,
                          projects[index],
                          _ProjectAction.preview,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _FeatureAction(
                        key: ValueKey('gig-edit-${projects[index].id}'),
                        icon: Icons.edit,
                        label: 'EDIT',
                        onTap: () => _runProjectAction(
                          context,
                          app,
                          projects[index],
                          _ProjectAction.edit,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (index < projects.length - 1) const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _PastSection extends StatelessWidget {
  const _PastSection({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final past = app.myBand?.past ?? const <PastGig>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionBar(label: 'PAST', count: past.isEmpty ? null : past.length),
        const SizedBox(height: 8),
        if (past.isEmpty)
          Text(
            'Played gigs will collect here after your first show.',
            style: Theme.of(context).textTheme.epCaption,
          )
        else
          for (final show in past)
            LedgerRow(title: show.title, details: [show.meta]),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});

  final GigProject project;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final venue = project.venueId == null ? null : app.venue(project.venueId!);
    final cachedGig = project.publicGigId == null
        ? null
        : app.allGigs.where((gig) => gig.id == project.publicGigId).firstOrNull;
    final date = _projectDate(context, project);
    final doorLaunch = _doorLaunch(context, app, project);
    final statusLabel = project.hasUnpublishedChanges
        ? 'UNPUBLISHED CHANGES'
        : project.status.name.toUpperCase();
    final statusTone = project.hasUnpublishedChanges
        ? EpStatusPillTone.warning
        : project.status == GigProjectStatus.published
        ? EpStatusPillTone.success
        : EpStatusPillTone.neutral;
    final meta = [
      venue?.name ?? 'Venue TBD',
      if (cachedGig != null) '${app.rsvpCount(cachedGig)} going',
    ];

    return EpCard(
      key: ValueKey('gig-project-${project.id}'),
      padding: EdgeInsets.zero,
      onTap: () => app.editGigProject(project.id),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 10),
            child: Row(
              children: [
                DateBlock(
                  day: date.day,
                  month: date.month,
                  semanticLabel: date.semanticLabel,
                  size: 54,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _projectTitle(project),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.epSectionHeading,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        meta.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.epMeta,
                      ),
                      const SizedBox(height: 7),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: StatusPill(label: statusLabel, tone: statusTone),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('gig-actions-${project.id}'),
                  tooltip: 'More actions for ${_projectTitle(project)}',
                  onPressed: () => _showProjectActions(context, app, project),
                  icon: Icon(Icons.more_horiz),
                ),
              ],
            ),
          ),
          Divider(height: 1),
          Row(
            children: [
              if (doorLaunch != null)
                Expanded(
                  child: _FeatureAction(
                    key: ValueKey('gig-door-${project.id}'),
                    icon: Icons.qr_code_scanner,
                    label: 'DOOR',
                    onTap: () => showDoorMode(context, doorLaunch),
                  ),
                ),
              Expanded(
                child: _FeatureAction(
                  key: ValueKey('gig-preview-${project.id}'),
                  icon: Icons.visibility,
                  label: 'PREVIEW',
                  onTap: () => _runProjectAction(
                    context,
                    app,
                    project,
                    _ProjectAction.preview,
                  ),
                ),
              ),
              Expanded(
                child: _FeatureAction(
                  key: ValueKey('gig-edit-${project.id}'),
                  icon: Icons.edit,
                  label: 'EDIT',
                  onTap: () => _runProjectAction(
                    context,
                    app,
                    project,
                    _ProjectAction.edit,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureAction extends StatelessWidget {
  const _FeatureAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: context.epColors.accent),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.epChipLabel),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ProjectAction { edit, preview, duplicate, unpublish, cancel, delete }

void _showProjectActions(
  BuildContext context,
  AppState app,
  GigProject project,
) {
  final items = <EpActionSheetItem>[
    EpActionSheetItem(
      label: 'Duplicate',
      icon: Icons.copy,
      onPressed: () => unawaited(
        _runProjectAction(context, app, project, _ProjectAction.duplicate),
      ),
    ),
    if (project.status == GigProjectStatus.published)
      EpActionSheetItem(
        label: 'Unpublish…',
        icon: Icons.visibility_off,
        onPressed: () => unawaited(
          _runProjectAction(context, app, project, _ProjectAction.unpublish),
        ),
      ),
    if (project.status == GigProjectStatus.published)
      EpActionSheetItem(
        label: 'Cancel gig…',
        icon: Icons.block,
        onPressed: () => unawaited(
          _runProjectAction(context, app, project, _ProjectAction.cancel),
        ),
      ),
    EpActionSheetItem(
      label: 'Delete',
      icon: Icons.delete_outline,
      destructive: true,
      onPressed: () => unawaited(
        _runProjectAction(context, app, project, _ProjectAction.delete),
      ),
    ),
  ];
  unawaited(
    showEpActionSheet(context, header: _projectTitle(project), items: items),
  );
}

Future<void> _runProjectAction(
  BuildContext context,
  AppState app,
  GigProject project,
  _ProjectAction action,
) async {
  switch (action) {
    case _ProjectAction.edit:
      await app.editGigProject(project.id);
    case _ProjectAction.preview:
      await app.editGigProject(project.id);
      app.previewGigDraft();
    case _ProjectAction.duplicate:
      await app.duplicateGigProject(project.id);
    case _ProjectAction.unpublish:
      if (await _confirm(
        context,
        'Unpublish gig?',
        'Fans will no longer see it. The listing returns to Drafts.',
      )) {
        await app.unpublishGigProject(project.id);
      }
    case _ProjectAction.cancel:
      if (await _confirm(
        context,
        'Cancel gig?',
        'The gig leaves discovery but its public page stays available as cancelled.',
      )) {
        await app.cancelGigProject(project.id);
      }
    case _ProjectAction.delete:
      if (await _confirm(
        context,
        'Delete gig permanently?',
        'The listing, RSVPs, saves, and invite links will be removed.',
      )) {
        await app.deleteGigProject(project.id);
      }
  }
}

DoorModeLaunch? _doorLaunch(
  BuildContext context,
  AppState app,
  GigProject project,
) {
  if (project.status != GigProjectStatus.published ||
      project.ticketing != Ticketing.rsvp) {
    return null;
  }
  final venueName = project.venueId == null
      ? 'Venue TBD'
      : app.venue(project.venueId!).name;
  final doorsTime = project.doorsAt == null
      ? 'TBD'
      : TimeOfDay.fromDateTime(project.doorsAt!.toLocal()).format(context);
  return DoorModeLaunch(
    projectId: project.id,
    gigTitle: _projectTitle(project),
    venueName: venueName,
    doorsTime: doorsTime,
  );
}

({String day, String month, String semanticLabel}) _projectDate(
  BuildContext context,
  GigProject project,
) {
  final date = project.startsAt;
  if (date == null) {
    return (day: '—', month: 'TBD', semanticLabel: 'Date to be determined');
  }
  final parts = Gig.dateShortFor(date.millisecondsSinceEpoch).split(' ');
  return (
    day: parts.last,
    month: parts.length > 1 ? parts[parts.length - 2] : '',
    semanticLabel: MaterialLocalizations.of(
      context,
    ).formatFullDate(date.toLocal()),
  );
}

String _projectTitle(GigProject project) {
  final title = project.title?.trim();
  return title == null || title.isEmpty ? 'Untitled gig' : title;
}

String _draftMissing(GigProject project) {
  final missing = <String>[
    if (project.title?.trim().isNotEmpty != true) 'name',
    if (project.startsAt == null || project.doorsAt == null) 'date and times',
    if (project.venueId == null) 'venue',
    if (project.performers.isEmpty) 'lineup',
  ];
  return missing.isEmpty
      ? 'review before publishing'
      : 'finish ${missing.join(', ')}';
}

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('KEEP'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('CONFIRM'),
          ),
        ],
      ),
    ) ??
    false;
