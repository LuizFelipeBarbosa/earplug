import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../date_names.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/gig_project_actions.dart';
import 'door_mode.dart';

class HostedGigScreen extends StatefulWidget {
  const HostedGigScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<HostedGigScreen> createState() => _HostedGigScreenState();
}

class _HostedGigScreenState extends State<HostedGigScreen> {
  String? _requestedSalesGigId;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().ensureManagedGigs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _requestSales();
  }

  @override
  void didUpdateWidget(covariant HostedGigScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _requestSales();
  }

  void _requestSales() {
    final app = context.read<AppState>();
    final project = app.managedGigProjects
        .where((project) => project.id == widget.projectId)
        .firstOrNull;
    final gigId = project?.publicGigId;
    if (project?.ticketing != Ticketing.paid || gigId == null) return;
    if (_requestedSalesGigId == gigId || app.salesFor(gigId) != null) return;
    _requestedSalesGigId = gigId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.projectId != project!.id) return;
      unawaited(app.loadTicketSales(gigId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final project = app.managedGigProjects
        .where((project) => project.id == widget.projectId)
        .firstOrNull;
    final padding = EdgeInsets.fromLTRB(
      EpLayout.gutter,
      headerTopPad(context),
      EpLayout.gutter,
      tabBarClearance,
    );
    if (project == null) {
      return ListView(
        padding: padding,
        children: [
          EpDisplay(
            app.managedGigsLoading ? 'Loading gig…' : 'Gig unavailable',
            size: 24,
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: EpPill(
              key: const Key('hosted-gig-unavailable-back'),
              label: 'Back',
              onPressed: app.back,
            ),
          ),
        ],
      );
    }

    final cancelled = project.status == GigProjectStatus.cancelled;
    final canWrite = !cancelled && app.isAdminOf(project.bandId);
    final title = project.title?.trim();
    final venue = project.venueId == null ? null : app.venue(project.venueId!);
    final startsAt = project.startsAt?.toLocal();
    final meta = [
      if (venue != null && venue.name.isNotEmpty) venue.name,
      if (startsAt != null)
        '${weekdayNames[startsAt.weekday - 1]}, '
            '${monthNames[startsAt.month - 1]} ${startsAt.day}',
      if (startsAt != null) _time(context, startsAt),
    ];
    final cachedGig = project.publicGigId == null
        ? null
        : app.allGigs.where((gig) => gig.id == project.publicGigId).firstOrNull;
    final sales = project.ticketing == Ticketing.paid
        ? app.salesFor(project.publicGigId ?? '')
        : null;
    final doorLaunch = canWrite ? doorLaunchFor(app, project) : null;
    final statusLabel = project.hasUnpublishedChanges
        ? 'UNPUBLISHED CHANGES'
        : project.status.name.toUpperCase();
    final statusTone = project.hasUnpublishedChanges
        ? EpStatusPillTone.warning
        : project.status == GigProjectStatus.published
        ? EpStatusPillTone.success
        : EpStatusPillTone.neutral;
    final access = switch (project.ticketing) {
      Ticketing.rsvp => 'Free · RSVP',
      Ticketing.external => 'External tickets',
      Ticketing.paid =>
        'Paid ${Money(project.ticketPriceMinor ?? project.price * 100).label}',
    };

    return ListView(
      padding: padding,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            EpIconPill(
              key: const Key('hosted-gig-back-control'),
              icon: Icons.arrow_back,
              semanticLabel: 'Back',
              onPressed: app.back,
            ),
            if (canWrite)
              EpIconPill(
                key: const Key('hosted-gig-actions'),
                icon: Icons.more_horiz,
                semanticLabel: 'More actions',
                onPressed: () => showGigProjectActions(context, app, project),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (startsAt != null) ...[
              EpDateBlock(date: startsAt),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: EpDisplay(
                title == null || title.isEmpty ? 'Untitled gig' : title,
                size: 28,
                maxLines: 3,
              ),
            ),
          ],
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 12),
          EpEyebrow(meta.join(' · ')),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: StatusPill(
            key: const Key('hosted-gig-status'),
            label: statusLabel,
            tone: statusTone,
          ),
        ),
        const SizedBox(height: 24),
        const EpHairline(),
        EpFactGrid(
          bottomLine: false,
          cells: [
            EpFactCell(label: 'DOORS', value: _time(context, project.doorsAt)),
            EpFactCell(label: 'START', value: _time(context, startsAt)),
            EpFactCell(
              label: 'VENUE',
              value: venue?.name ?? 'Venue TBD',
              sub: venue == null || venue.area.isEmpty ? null : venue.area,
              display: false,
            ),
            EpFactCell(label: 'ACCESS', value: access, display: false),
          ],
        ),
        if (cachedGig != null) ...[
          EpMonoText('GOING · ${app.rsvpCount(cachedGig)}'),
          const SizedBox(height: 12),
        ],
        if (sales != null) ...[
          EpMonoText(
            'SALES · ${sales.sold}/${sales.capacity}',
            key: const Key('hosted-gig-sales'),
          ),
          const SizedBox(height: 12),
        ],
        const EpHairline(),
        if (!cancelled) ...[
          const EpSectionHeader(label: 'TOOLS'),
          if (doorLaunch != null)
            EpMenuRow(
              key: const Key('hosted-gig-door'),
              icon: Icons.qr_code_scanner,
              label: 'DOOR',
              onTap: () => showDoorMode(context, doorLaunch),
            ),
          EpMenuRow(
            key: const Key('hosted-gig-preview'),
            icon: Icons.visibility,
            label: 'PREVIEW',
            onTap: () async {
              await app.editGigProject(project.id);
              app.previewGigDraft();
            },
          ),
          if (canWrite)
            EpMenuRow(
              key: const Key('hosted-gig-edit'),
              icon: Icons.edit,
              label: 'EDIT',
              onTap: () => app.editGigProject(project.id),
            ),
        ],
      ],
    );
  }
}

String _time(BuildContext context, DateTime? date) => date == null
    ? 'TBD'
    : TimeOfDay.fromDateTime(date.toLocal()).format(context);
