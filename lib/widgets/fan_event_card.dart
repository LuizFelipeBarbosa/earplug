import 'package:flutter/material.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../date_names.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import 'common.dart';
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
  });

  final Gig gig;
  final AppState app;
  final bool showDistance;
  final Widget? trailingAction;
  final FanEventCardPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final venue = app.venue(gig.venueId);
    final place = [
      venue.name,
      if (venue.area.trim().isNotEmpty) venue.area,
      if (showDistance) app.distanceOf(venue),
    ].join(' · ');
    final actions = _EventActions(
      gig: gig,
      app: app,
      trailingAction: trailingAction,
      prominent: presentation == FanEventCardPresentation.featured,
    );

    if (presentation == FanEventCardPresentation.featured) {
      return _FeaturedPoster(
        gig: gig,
        app: app,
        place: place,
        lineup: exploreLineupFor(gig, app),
        showDistance: showDistance,
        actions: actions,
      );
    }
    final meta = compactGigMeta(gig, app, showDistance: showDistance);
    final row = ExploreEventRow(
      key: ValueKey('fan-event-${gig.id}'),
      gig: gig,
      venueName: venue.name,
      meta: meta,
      lineup: exploreLineupFor(gig, app),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 104),
        child: actions,
      ),
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

String compactGigMeta(Gig gig, AppState app, {required bool showDistance}) {
  final venue = app.venue(gig.venueId);
  return [
    _metaDateLabel(gig),
    gig.doorsLabel,
    gig.priceLabel,
    if (showDistance) _distanceLabel(app.distanceOf(venue)),
  ].join(' · ');
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

/// The lead show: flyer art with the title over it, then a facts row.
class _FeaturedPoster extends StatelessWidget {
  const _FeaturedPoster({
    required this.gig,
    required this.app,
    required this.place,
    required this.lineup,
    required this.showDistance,
    required this.actions,
  });

  final Gig gig;
  final AppState app;
  final String place;
  final List<ExploreLineupBand> lineup;
  final bool showDistance;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final desktop = EpLayout.isDesktop(context);
    final flyer = app.flyer(gig.flyKey);
    final presenter = gig.createdByBand == null
        ? null
        : app.band(gig.createdByBand!);

    return Column(
      key: ValueKey('fan-event-${gig.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: gig.title,
          child: InkWell(
            onTap: () => app.openGig(gig.id),
            child: GigFlyer(
              gig,
              flyer,
              height: desktop ? 380 : 220,
              scrim: true,
              padding: EdgeInsets.all(desktop ? 24 : 18),
              child: MediaQuery.withNoTextScaling(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EpEyebrow(place, color: flyer.fg.withValues(alpha: .75)),
                    if (presenter != null)
                      EpMonoText(
                        '${presenter.name} presents',
                        color: flyer.fg.withValues(alpha: .75),
                      ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: EpDisplay(
                          gig.title,
                          size: desktop ? 64 : 40,
                          color: flyer.fg,
                          maxLines: 3,
                        ),
                      ),
                    ),
                    if (lineup.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ExploreLineupWrap(
                        bands: lineup,
                        textColor: flyer.fg.withValues(alpha: .85),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        _FactsRow(
          gig: gig,
          app: app,
          showDistance: showDistance,
          actions: actions,
        ),
        const EpHairline(),
      ],
    );
  }
}

/// Doors / price / age on the left, the event actions on the right; they stack
/// when the row cannot hold both.
class _FactsRow extends StatelessWidget {
  const _FactsRow({
    required this.gig,
    required this.app,
    required this.showDistance,
    required this.actions,
  });

  final Gig gig;
  final AppState app;
  final bool showDistance;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final facts = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EpMonoText(compactGigMeta(gig, app, showDistance: showDistance)),
        const SizedBox(height: 4),
        Text(
          gig.lifecycle == GigLifecycle.cancelled
              ? 'This show was cancelled.'
              : '${app.rsvpCount(gig)} going',
          style: Theme.of(
            context,
          ).textTheme.epBody.copyWith(color: context.epColors.muted),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: EpLayout.stackActions(context)
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [facts, const SizedBox(height: 12), actions],
            )
          : Row(
              children: [
                Expanded(child: facts),
                const SizedBox(width: 12),
                actions,
              ],
            ),
    );
  }
}

/// Save, share, the RSVP/ticket control and one caller-supplied action.
class _EventActions extends StatelessWidget {
  const _EventActions({
    required this.gig,
    required this.app,
    required this.trailingAction,
    required this.prominent,
  });

  final Gig gig;
  final AppState app;
  final Widget? trailingAction;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final saved = app.saved.contains(gig.id);
    return Wrap(
      key: ValueKey('event-actions-${gig.id}'),
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        EpIconPill(
          key: ValueKey('save-${gig.id}'),
          icon: saved ? Icons.bookmark : Icons.bookmark_border,
          semanticLabel: saved ? 'Remove saved event' : 'Save event',
          filled: saved,
          onPressed: () => app.requestSave(gig.id),
        ),
        EpIconPill(
          key: ValueKey('share-${gig.id}'),
          icon: Icons.ios_share,
          semanticLabel: 'Share event',
          onPressed: () => _share(context, gig),
        ),
        if (gig.lifecycle == GigLifecycle.cancelled)
          const EpBadge(label: 'Cancelled')
        else ...[
          _TicketAction(gig: gig, app: app, prominent: prominent),
          ?trailingAction,
        ],
      ],
    );
  }
}

class _TicketAction extends StatelessWidget {
  const _TicketAction({
    required this.gig,
    required this.app,
    required this.prominent,
  });

  final Gig gig;
  final AppState app;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final external = gig.tix == Ticketing.external;
    final going = app.rsvps.contains(gig.id);
    return EpPill(
      key: ValueKey('ticket-action-${gig.id}'),
      label: external ? 'Tickets ↗' : (going ? 'Going ✓' : 'RSVP'),
      variant: going ? EpPillVariant.outline : EpPillVariant.primary,
      size: prominent ? EpPillSize.regular : EpPillSize.chip,
      onPressed: external
          ? () => _openTickets(context, app, gig)
          : () => going ? app.toggleRsvp(gig.id) : app.requestRsvp(gig.id),
    );
  }
}

Future<void> _share(BuildContext context, Gig gig) => copyForUser(
  context,
  publicWebUrl('g/${gig.publicRef}'),
  successMessage: 'Link copied: ${publicWebDisplayUrl('g/${gig.publicRef}')}',
);

Future<void> _openTickets(BuildContext context, AppState app, Gig gig) async {
  final url = gig.externalUrl;
  if (url == null || url.isEmpty) {
    app.say('No ticket link listed for this gig.');
    return;
  }
  await openExternalForUser(context, url);
}
