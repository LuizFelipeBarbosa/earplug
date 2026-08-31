import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'door_mode.dart';

class GigManagerScreen extends StatelessWidget {
  const GigManagerScreen({super.key});

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
            style: epText(color: Ep.contentSecondary),
          ),
        ),
      );
    }
    app.ensureManagedGigs();
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
                  'GIG MANAGER',
                  style: Theme.of(context).textTheme.epPageHeading,
                ),
              ),
              FilledButton(
                onPressed: app.startGigCreate,
                child: const Text('+ NEW GIG'),
              ),
            ],
          ),
          if (app.managedGigsLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 18),
          _ProjectSection(
            title: 'DRAFTS',
            projects: drafts,
            empty: 'No saved drafts.',
          ),
          const SizedBox(height: 18),
          _ProjectSection(
            title: 'PUBLISHED',
            projects: published,
            empty: 'No live gigs yet.',
            blue: true,
          ),
          const SizedBox(height: 18),
          _ProjectSection(
            title: 'CANCELLED',
            projects: cancelled,
            empty: 'No cancelled gigs.',
          ),
          const SizedBox(height: 18),
          const SectionLabel('PAST'),
          const SizedBox(height: 7),
          if ((app.myBand?.past ?? const []).isEmpty)
            Text(
              'Played gigs will collect here after your first show.',
              style: epText(size: 11.5, color: Ep.contentDisabled),
            )
          else
            for (final show in app.myBand!.past)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(show.title),
                trailing: Text(show.meta),
              ),
        ],
      ),
    );
  }
}

class _ProjectSection extends StatelessWidget {
  final String title;
  final List<GigProject> projects;
  final String empty;
  final bool blue;

  const _ProjectSection({
    required this.title,
    required this.projects,
    required this.empty,
    this.blue = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionLabel(title, blue: blue),
      const SizedBox(height: 8),
      if (projects.isEmpty)
        DashedBox(
          padding: const EdgeInsets.all(18),
          child: Text(
            empty,
            textAlign: TextAlign.center,
            style: epText(color: Ep.contentDisabled),
          ),
        )
      else
        for (final project in projects) ...[
          _ProjectRow(project: project),
          const SizedBox(height: 8),
        ],
    ],
  );
}

enum _ProjectAction {
  edit,
  preview,
  duplicate,
  doorMode,
  unpublish,
  cancel,
  delete,
}

class _ProjectRow extends StatelessWidget {
  final GigProject project;

  const _ProjectRow({required this.project});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final venue = project.venueId == null ? null : app.venue(project.venueId!);
    return EpCard(
      padding: const EdgeInsets.all(12),
      onTap: () => app.editGigProject(project.id),
      child: Row(
        children: [
          FlyerBox(
            style: app.flyer(project.flyKey),
            width: 46,
            height: 60,
            radius: 5,
            shadow: false,
            child: const Icon(Icons.music_note, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (project.title ?? 'Untitled gig').toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: epText(size: 13, weight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (project.startsAt != null)
                      Gig.dateShortFor(
                        project.startsAt!.millisecondsSinceEpoch,
                      ),
                    if (venue != null) venue.name,
                  ].join(' · ').ifEmpty('Details incomplete'),
                  style: epText(size: 11, color: Ep.contentSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  project.hasUnpublishedChanges
                      ? 'UNPUBLISHED CHANGES'
                      : project.status.name.toUpperCase(),
                  style: epText(
                    size: 9.5,
                    weight: FontWeight.w900,
                    letterSpacing: .8,
                    color: project.hasUnpublishedChanges
                        ? Ep.warning
                        : Ep.accent,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<_ProjectAction>(
            onSelected: (action) => _runAction(context, app, action),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _ProjectAction.edit,
                child: Text('Edit'),
              ),
              const PopupMenuItem(
                value: _ProjectAction.preview,
                child: Text('Preview as fan'),
              ),
              const PopupMenuItem(
                value: _ProjectAction.duplicate,
                child: Text('Duplicate'),
              ),
              if (project.status == GigProjectStatus.published &&
                  project.ticketing == Ticketing.rsvp)
                const PopupMenuItem(
                  value: _ProjectAction.doorMode,
                  child: Text('Door Mode'),
                ),
              if (project.status == GigProjectStatus.published)
                const PopupMenuItem(
                  value: _ProjectAction.unpublish,
                  child: Text('Unpublish'),
                ),
              if (project.status == GigProjectStatus.published)
                const PopupMenuItem(
                  value: _ProjectAction.cancel,
                  child: Text('Cancel gig'),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _ProjectAction.delete,
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runAction(
    BuildContext context,
    AppState app,
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
      case _ProjectAction.doorMode:
        await showDoorMode(context, project.id);
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
            child: const Text('KEEP'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    ) ??
    false;

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
