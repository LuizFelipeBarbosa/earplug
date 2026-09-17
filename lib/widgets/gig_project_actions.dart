import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../screens/door_mode.dart';
import 'band_ticket_sales_sheet.dart';
import 'ep_sheet.dart';
import 'opportunity_labels.dart';
import 'sheets.dart';

enum _ProjectAction { duplicate, unpublish, cancel, delete }

Future<void> showGigProjectActions(
  BuildContext context,
  AppState app,
  GigProject project,
) async {
  if (!app.isAdminOf(project.bandId) ||
      project.status == GigProjectStatus.cancelled) {
    return;
  }
  final hasSoldTickets =
      project.ticketing == Ticketing.paid &&
      (app.salesFor(project.publicGigId ?? '')?.sold ?? 0) > 0;
  final items = <EpActionSheetItem>[
    if (project.ticketing == Ticketing.paid && project.publicGigId != null)
      EpActionSheetItem(
        label: 'Sales',
        icon: Icons.confirmation_number_outlined,
        onPressed: () => unawaited(
          showBandTicketSalesSheet(
            context,
            gigId: project.publicGigId!,
            title: projectTitle(project),
          ),
        ),
      ),
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
    if (!hasSoldTickets)
      EpActionSheetItem(
        label: 'Delete',
        icon: Icons.delete_outline,
        destructive: true,
        onPressed: () => unawaited(
          _runProjectAction(context, app, project, _ProjectAction.delete),
        ),
      ),
  ];
  await showEpActionSheet(context, header: projectTitle(project), items: items);
}

Future<void> _runProjectAction(
  BuildContext context,
  AppState app,
  GigProject project,
  _ProjectAction action,
) async {
  if (project.status == GigProjectStatus.cancelled ||
      !app.isAdminOf(project.bandId)) {
    return;
  }
  switch (action) {
    case _ProjectAction.duplicate:
      await app.duplicateGigProject(project.id);
    case _ProjectAction.unpublish:
      if (await epConfirm(
        context,
        title: 'Unpublish gig?',
        body: 'Fans will no longer see it. The listing returns to Drafts.',
      )) {
        await app.unpublishGigProject(project.id);
      }
    case _ProjectAction.cancel:
      final body =
          project.ticketing == Ticketing.paid &&
              project.publicGigId != null &&
              (app.salesFor(project.publicGigId!)?.sold ?? 0) > 0
          ? 'Sold tickets are refunded in full and buyers are emailed. The gig leaves discovery but its public page stays available as cancelled.'
          : 'The gig leaves discovery but its public page stays available as cancelled.';
      if (await epConfirm(context, title: 'Cancel gig?', body: body)) {
        await app.cancelGigProject(project.id);
      }
    case _ProjectAction.delete:
      if (await epConfirm(
        context,
        title: 'Delete gig permanently?',
        body: 'The listing, RSVPs, saves, and invite links will be removed.',
      )) {
        await app.deleteGigProject(project.id);
      }
  }
}

DoorModeLaunch? doorLaunchFor(AppState app, GigProject project) {
  if (project.status != GigProjectStatus.published) {
    return null;
  }
  final venueName = project.venueId == null
      ? 'Venue TBD'
      : app.venue(project.venueId!).name;
  final doorsTime = project.doorsAt == null
      ? 'TBD'
      : const DefaultMaterialLocalizations().formatTimeOfDay(
          TimeOfDay.fromDateTime(project.doorsAt!.toLocal()),
          alwaysUse24HourFormat:
              WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat,
        );
  if (project.publicGigId != null) {
    return DoorModeLaunch.organizer(
      gigId: project.publicGigId!,
      gigTitle: projectTitle(project),
      venueName: venueName,
      doorsTime: doorsTime,
    );
  }
  return DoorModeLaunch(
    projectId: project.id,
    gigTitle: projectTitle(project),
    venueName: venueName,
    doorsTime: doorsTime,
  );
}
