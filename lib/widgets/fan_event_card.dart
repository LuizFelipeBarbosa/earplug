import 'package:flutter/material.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../date_names.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import 'common.dart';

enum FanEventCardPresentation { compact, featured }

/// The full event summary used throughout the fan experience.
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
    final lineup = [
      for (final bandId in gig.lineup)
        if (app.band(bandId) case final Band band) band.name,
    ];
    final presenter = gig.createdByBand == null
        ? null
        : app.band(gig.createdByBand!);

    if (presentation == FanEventCardPresentation.featured) {
      return _buildFeatured(context, venue, lineup, presenter);
    }
    return _buildCompact(context, venue, lineup);
  }

  Widget _buildCompact(BuildContext context, Venue venue, List<String> lineup) {
    return EpCard(
      key: ValueKey('fan-event-${gig.id}'),
      padding: const EdgeInsets.all(11),
      radius: 14,
      onTap: () => app.openGig(gig.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DateBlock(
                day: gig.startsAt.day.toString().padLeft(2, '0'),
                month: monthNamesUpper[gig.startsAt.month - 1],
                semanticLabel: gig.dateShort,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (app.isDiscoveryBoosted(gig)) ...[
                      Text(
                        'DISCOVERY BOOST · COMPLETE LISTING',
                        key: ValueKey('discovery-boost-${gig.id}'),
                        style: Theme.of(context).textTheme.epMeta.copyWith(
                          color: context.epColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .45,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      gig.title.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.epPosterTitle.copyWith(
                        fontSize: 17,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${gig.dateShort} · DOORS ${_doorsTime(gig.time)}',
                      style: Theme.of(context).textTheme.epMeta.copyWith(
                        color: context.epColors.accent,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        venue.name,
                        if (venue.area.trim().isNotEmpty) venue.area,
                        if (showDistance) app.distanceOf(venue),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.epMeta,
                    ),
                    if (lineup.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        lineup.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.epCaption,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: [
              PriceBadge(gig),
              _AgeBadge(gig.ageRequirement.label),
              if (gig.lifecycle == GigLifecycle.cancelled)
                const StatusPill(
                  label: 'Cancelled',
                  tone: EpStatusPillTone.warning,
                )
              else
                StatusPill(
                  label: '${app.rsvpCount(gig)} GOING',
                  tone: EpStatusPillTone.selected,
                ),
            ],
          ),
          _EventActions(gig: gig, app: app, trailingAction: trailingAction),
        ],
      ),
    );
  }

  Widget _buildFeatured(
    BuildContext context,
    Venue venue,
    List<String> lineup,
    Band? presenter,
  ) {
    final flyer = app.flyer(gig.flyKey);
    return EpCard(
      key: ValueKey('fan-event-${gig.id}'),
      padding: EdgeInsets.zero,
      radius: 14,
      onTap: () => app.openGig(gig.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GigFlyer(
            gig,
            flyer,
            height: 220,
            radius: 0,
            shadow: false,
            padding: const EdgeInsets.all(18),
            child: MediaQuery.withNoTextScaling(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (presenter != null)
                    Text(
                      '${presenter.name.toUpperCase()} PRESENTS',
                      style: epText(
                        size: 11,
                        weight: FontWeight.w900,
                        color: flyer.fg,
                        letterSpacing: 1.8,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    gig.title.toUpperCase(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: epDisplay(size: 34, color: flyer.fg, height: 1.03),
                  ),
                  if (lineup.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      lineup.join(' + ').toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: epText(
                        size: 11,
                        weight: FontWeight.w900,
                        color: flyer.fg,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            color: context.epColors.selected,
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${gig.dateShort} · DOORS ${_doorsTime(gig.time)}',
                  style: Theme.of(
                    context,
                  ).textTheme.epLabel.copyWith(color: context.epColors.volt),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    venue.name,
                    if (venue.area.trim().isNotEmpty) venue.area,
                    if (showDistance) app.distanceOf(venue),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.epMeta.copyWith(color: context.epColors.ink),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    PriceBadge(gig),
                    _AgeBadge(gig.ageRequirement.label),
                    if (gig.lifecycle == GigLifecycle.cancelled)
                      const StatusPill(
                        label: 'Cancelled',
                        tone: EpStatusPillTone.warning,
                      )
                    else
                      StatusPill(
                        label: '${app.rsvpCount(gig)} GOING',
                        tone: EpStatusPillTone.selected,
                      ),
                  ],
                ),
                _EventActions(
                  gig: gig,
                  app: app,
                  trailingAction: trailingAction,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _doorsTime(String value) {
  final separator = value.indexOf(' / ');
  return separator == -1 ? value : value.substring(0, separator);
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

class _AgeBadge extends StatelessWidget {
  const _AgeBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: context.epColors.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.epChipLabel.copyWith(
          fontSize: 11,
          color: context.epColors.contentSecondary,
        ),
      ),
    );
  }
}

class _EventActions extends StatelessWidget {
  const _EventActions({
    required this.gig,
    required this.app,
    required this.trailingAction,
  });

  final Gig gig;
  final AppState app;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final cancelled = gig.lifecycle == GigLifecycle.cancelled;
    return Row(
      key: ValueKey('event-actions-${gig.id}'),
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _IconAction(
          key: ValueKey('save-${gig.id}'),
          tooltip: app.saved.contains(gig.id)
              ? 'Remove saved event'
              : 'Save event',
          icon: app.saved.contains(gig.id)
              ? Icons.bookmark
              : Icons.bookmark_border,
          active: app.saved.contains(gig.id),
          onTap: () => app.requestSave(gig.id),
        ),
        _IconAction(
          key: ValueKey('share-${gig.id}'),
          tooltip: 'Share event',
          icon: Icons.ios_share,
          onTap: () => _share(context, gig),
        ),
        if (!cancelled) ...[_TicketAction(gig: gig, app: app), ?trailingAction],
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: ButtonStyle(
        fixedSize: WidgetStatePropertyAll(Size.square(48)),
        foregroundColor: WidgetStatePropertyAll(
          active ? context.epColors.accent : context.epColors.contentSecondary,
        ),
      ),
      icon: Icon(icon, size: 19),
    );
  }
}

class _TicketAction extends StatelessWidget {
  const _TicketAction({required this.gig, required this.app});

  final Gig gig;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final external = gig.tix == Ticketing.external;
    final going = app.rsvps.contains(gig.id);
    final label = external ? 'TICKETS ↗' : (going ? 'GOING ✓' : 'RSVP');
    final onPressed = external
        ? () => _openTickets(context, app, gig)
        : () => going ? app.toggleRsvp(gig.id) : app.requestRsvp(gig.id);
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(48, 48)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 11)),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.epChipLabel.copyWith(fontSize: 11),
      ),
    );
    if (going) {
      return OutlinedButton(
        key: ValueKey('ticket-action-${gig.id}'),
        onPressed: onPressed,
        style: style,
        child: Text(label),
      );
    }
    return FilledButton(
      key: ValueKey('ticket-action-${gig.id}'),
      onPressed: onPressed,
      style: style,
      child: Text(label),
    );
  }
}
