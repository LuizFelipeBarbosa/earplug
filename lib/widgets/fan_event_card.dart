import 'package:flutter/material.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../date_names.dart';
import '../models.dart';
import '../services/user_actions.dart';
import 'ep_text.dart';
import 'explore_tiles.dart';

class GigCardLines {
  const GigCardLines({
    required this.dateLine,
    required this.title,
    required this.location,
    required this.price,
  });

  final String dateLine;
  final String title;
  final String location;
  final String price;
}

/// The event's start date paired with its already-formatted doors time.
String eventDateLine(DateTime startsAt, {required String doorsLabel}) =>
    '${weekdayNamesUpper[startsAt.weekday - 1]}, '
    '${monthNamesUpper[startsAt.month - 1]} ${startsAt.day} AT $doorsLabel';

GigCardLines gigCardLines(Gig gig, AppState app, {required bool showDistance}) {
  final venue = app.venue(gig.venueId);
  final area =
      venue.neighborhood ??
      (venue.area.isNotEmpty ? venue.area : venue.city) ??
      '';
  final distance = showDistance ? app.distanceOf(venue) : null;
  final location = (distance == null || distance.isEmpty)
      ? area
      : (area.isEmpty ? distance : '$area · $distance');
  return GigCardLines(
    dateLine: eventDateLine(gig.startsAt, doorsLabel: gig.doorsLabel),
    title: gig.title,
    location: location,
    price: gig.priceLabel,
  );
}

enum FanEventCardPresentation { compact, featured }

/// The event summary used throughout the fan experience: a hairline gig row in
/// lists, a poster block where one show leads the page.
///
/// Compact cards show a save action by default. Callers can replace it with a
/// surface-specific action, such as the QR button in Profile.
class FanEventCard extends StatelessWidget {
  const FanEventCard({
    super.key,
    required this.gig,
    required this.app,
    this.showDistance = false,
    this.trailingAction,
    this.showSaveAction = true,
    this.showHairline = true,
    this.presentation = FanEventCardPresentation.compact,
    this.rowKey,
  });

  final Gig gig;
  final AppState app;
  final bool showDistance;
  final Widget? trailingAction;

  /// Whether compact cards fall back to save when [trailingAction] is absent.
  final bool showSaveAction;

  /// Whether compact cards include a divider below the row.
  final bool showHairline;

  final FanEventCardPresentation presentation;
  final Key? rowKey;

  @override
  Widget build(BuildContext context) {
    final venue = app.venue(gig.venueId);
    final lines = gigCardLines(gig, app, showDistance: showDistance);
    if (presentation == FanEventCardPresentation.featured) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = (width * 0.6).roundToDouble();
          return ExploreFeaturedCard(
            key: rowKey ?? ValueKey('fan-event-${gig.id}'),
            gig: gig,
            venueName: venue.name,
            lines: lines,
            actions: _gigCardActions(context, gig, app, ring: false),
            onTap: () => app.openGig(gig.id),
            width: width,
            height: height,
          );
        },
      );
    }
    final actions = _EventActions(gig: gig, app: app);
    final row = ExploreEventRow(
      key: rowKey ?? ValueKey('fan-event-${gig.id}'),
      gig: gig,
      venueName: venue.name,
      lines: lines,
      saveAction:
          trailingAction ?? (showSaveAction ? actions.saveAction : null),
      onTap: () => app.openGig(gig.id),
      showHairline: showHairline,
    );
    if (!app.isDiscoveryBoosted(gig)) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: EpEyebrow.accent(
            'Discovery boost · complete listing',
            key: ValueKey('discovery-boost-${gig.id}'),
          ),
        ),
        row,
      ],
    );
  }
}

/// An event card for ticket or history snapshots that need no full [Gig].
class FanEventSnapshotCard extends StatelessWidget {
  const FanEventSnapshotCard({
    super.key,
    required this.id,
    required this.lines,
    this.flyerUrl,
    this.flyKey,
    this.onTap,
    this.rowKey,
  });

  final String id;
  final GigCardLines lines;
  final String? flyerUrl;
  final String? flyKey;
  final VoidCallback? onTap;
  final Key? rowKey;

  @override
  Widget build(BuildContext context) => ExploreEventSnapshotRow(
    key: rowKey ?? ValueKey('fan-event-snapshot-$id'),
    id: id,
    lines: lines,
    flyerUrl: flyerUrl,
    flyKey: flyKey,
    onTap: onTap,
  );
}

List<Widget> _gigCardActions(
  BuildContext context,
  Gig gig,
  AppState app, {
  bool ring = true,
  Color? color,
  List<Shadow>? iconShadows,
}) {
  // A non-ring action belongs to a featured poster and uses an opaque circle.
  final actions = _EventActions(
    gig: gig,
    app: app,
    ring: ring,
    color: color,
    iconShadows: iconShadows,
  );
  return [actions.shareAction(context), actions.saveAction];
}

/// Standard save and share controls for compact and featured cards.
class _EventActions {
  const _EventActions({
    required this.gig,
    required this.app,
    this.ring = true,
    this.color,
    this.iconShadows,
  });

  final Gig gig;
  final AppState app;
  final bool ring;
  final Color? color;
  final List<Shadow>? iconShadows;

  Widget get saveAction {
    final saved = app.saved.contains(gig.id);
    return ExploreCardIconButton(
      key: ValueKey('save-${gig.id}'),
      icon: Icons.bookmark_border,
      fillIcon: Icons.bookmark,
      semanticLabel: saved ? 'Remove saved event' : 'Save event',
      active: saved,
      onPressed: () => app.requestSave(gig.id),
      ring: ring,
      circle: !ring,
      color: color,
      iconShadows: iconShadows,
    );
  }

  Widget shareAction(BuildContext context) => ExploreCardIconButton(
    key: ValueKey('share-${gig.id}'),
    icon: Icons.ios_share,
    semanticLabel: 'Share event',
    onPressed: () => _share(context, gig),
    ring: ring,
    circle: !ring,
    color: color,
    iconShadows: iconShadows,
  );
}

Future<void> _share(BuildContext context, Gig gig) => copyForUser(
  context,
  publicWebUrl('g/${gig.publicRef}'),
  successMessage: 'Link copied: ${publicWebDisplayUrl('g/${gig.publicRef}')}',
);
