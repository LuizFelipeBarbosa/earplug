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
    dateLine:
        '${weekdayNamesUpper[gig.startsAt.weekday - 1]}, '
        '${monthNamesUpper[gig.startsAt.month - 1]} ${gig.startsAt.day} '
        'AT ${gig.doorsLabel}',
    title: gig.title,
    location: location,
    price: gig.priceLabel,
  );
}

enum FanEventCardPresentation { compact, featured }

/// The event summary used throughout the fan experience: a hairline gig row in
/// lists, a poster block where one show leads the page.
///
/// The card owns the standard event actions while callers can add one
/// surface-specific action, such as the QR button in Profile.
class FanEventCard extends StatelessWidget {
  const FanEventCard({
    super.key,
    required this.gig,
    required this.app,
    this.showDistance = false,
    this.trailingAction,
    this.presentation = FanEventCardPresentation.compact,
    this.friends = const <SocialUserCard>[],
    this.rowKey,
  });

  final Gig gig;
  final AppState app;
  final bool showDistance;
  final Widget? trailingAction;
  final FanEventCardPresentation presentation;
  final List<SocialUserCard> friends;
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
            key: ValueKey('fan-event-${gig.id}'),
            gig: gig,
            venueName: venue.name,
            lines: lines,
            actions: gigCardActions(context, gig, app, ring: false),
            onTap: () => app.openGig(gig.id),
            width: width,
            height: height,
          );
        },
      );
    }
    final actions = _EventActions(
      gig: gig,
      app: app,
      trailingAction: trailingAction,
    );
    final row = ExploreEventRow(
      key: rowKey ?? ValueKey('fan-event-${gig.id}'),
      gig: gig,
      venueName: venue.name,
      lines: lines,
      saveAction: trailingAction == null ? actions.saveAction : actions,
      onTap: () => app.openGig(gig.id),
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

List<Widget> gigCardActions(
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

// Retained for the Explore carousel and its tests until their call sites migrate.
String compactGigMeta(Gig gig, AppState app, {required bool showDistance}) {
  final info = compactGigInfo(gig, app, showDistance: showDistance);
  return [info.date, info.time, info.price, ?info.distance].join(' · ');
}

ExploreGigInfo compactGigInfo(
  Gig gig,
  AppState app, {
  required bool showDistance,
}) {
  final venue = app.venue(gig.venueId);
  final lines = gigCardLines(gig, app, showDistance: showDistance);
  return ExploreGigInfo(
    price: lines.price,
    date: _metaDateLabel(gig),
    time: gig.doorsLabel,
    distance: showDistance ? _distanceLabel(app.distanceOf(venue)) : null,
  );
}

String _metaDateLabel(Gig gig) =>
    '${gig.startsAt.day} ${monthNamesUpper[gig.startsAt.month - 1]}';

/// Reformats a distance such as "3.4 mi" as "3.4 MI" or "11 MI".
String _distanceLabel(String raw) {
  final miles = double.tryParse(raw.split(' ').first);
  if (miles == null) return raw.toUpperCase();
  final value = miles < 10
      ? miles.toStringAsFixed(1)
      : miles.round().toString();
  return '$value MI';
}

/// Compact save control and an optional caller-supplied action.
class _EventActions extends StatelessWidget {
  const _EventActions({
    required this.gig,
    required this.app,
    this.trailingAction,
    this.ring = true,
    this.color,
    this.iconShadows,
  });

  final Gig gig;
  final AppState app;
  final Widget? trailingAction;
  final bool ring;
  final Color? color;
  final List<Shadow>? iconShadows;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: ValueKey('event-actions-${gig.id}'),
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [saveAction, ?trailingAction],
    );
  }

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
