import 'package:flutter/material.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../date_names.dart';
import '../models.dart';
import '../services/user_actions.dart';
import 'ep_text.dart';
import 'explore_tiles.dart';

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
    if (presentation == FanEventCardPresentation.featured) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = (width * 0.6).roundToDouble();
          return ExploreFeaturedCard(
            key: ValueKey('fan-event-${gig.id}'),
            gig: gig,
            venueName: venue.name,
            info: compactGigInfo(gig, app, showDistance: showDistance),
            lineup: exploreLineupFor(gig, app),
            actions: gigCardActions(context, gig, app, ring: false),
            friends: friends,
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
      info: ExploreGigInfo(
        dateTime: '${_metaDateLabel(gig)} · ${gig.doorsLabel}',
        distance: showDistance ? _distanceLabel(app.distanceOf(venue)) : null,
        price: gig.priceLabel,
      ),
      lineup: exploreLineupFor(gig, app),
      actions: actions.posterActions(context),
      friends: friends,
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
}) => _EventActions(
  gig: gig,
  app: app,
  trailingAction: null,
  ring: ring,
).posterActions(context);

String compactGigMeta(Gig gig, AppState app, {required bool showDistance}) {
  final venue = app.venue(gig.venueId);
  return [
    _metaDateLabel(gig),
    gig.doorsLabel,
    gig.priceLabel,
    if (showDistance) _distanceLabel(app.distanceOf(venue)),
  ].join(' · ');
}

ExploreGigInfo compactGigInfo(
  Gig gig,
  AppState app, {
  required bool showDistance,
}) {
  final venue = app.venue(gig.venueId);
  return ExploreGigInfo(
    dateTime: '${_metaDateLabel(gig)} · ${gig.doorsLabel}',
    distance: showDistance ? _distanceLabel(app.distanceOf(venue)) : null,
    price: gig.priceLabel,
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

/// Save, share, and one caller-supplied action.
class _EventActions extends StatelessWidget {
  const _EventActions({
    required this.gig,
    required this.app,
    required this.trailingAction,
    this.ring = true,
  });

  final Gig gig;
  final AppState app;
  final Widget? trailingAction;
  final bool ring;

  List<Widget> posterActions(BuildContext context) => [
    _saveAction,
    _shareAction(context),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: ValueKey('event-actions-${gig.id}'),
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [...posterActions(context), ?trailingAction],
    );
  }

  Widget get _saveAction {
    final saved = app.saved.contains(gig.id);
    return ExploreCardIconButton(
      key: ValueKey('save-${gig.id}'),
      icon: Icons.bookmark_border,
      fillIcon: Icons.bookmark,
      semanticLabel: saved ? 'Remove saved event' : 'Save event',
      active: saved,
      onPressed: () => app.requestSave(gig.id),
      ring: ring,
    );
  }

  Widget _shareAction(BuildContext context) => ExploreCardIconButton(
    key: ValueKey('share-${gig.id}'),
    icon: Icons.ios_share,
    semanticLabel: 'Share event',
    onPressed: () => _share(context, gig),
    ring: ring,
  );
}

Future<void> _share(BuildContext context, Gig gig) => copyForUser(
  context,
  publicWebUrl('g/${gig.publicRef}'),
  successMessage: 'Link copied: ${publicWebDisplayUrl('g/${gig.publicRef}')}',
);
