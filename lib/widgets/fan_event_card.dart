import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// The full event summary used throughout the fan experience.
///
/// The card owns the standard event actions while callers can add one
/// surface-specific action, such as the QR button in My Gigs.
class FanEventCard extends StatelessWidget {
  const FanEventCard({
    super.key,
    required this.gig,
    required this.app,
    this.showDistance = false,
    this.trailingAction,
  });

  final Gig gig;
  final AppState app;
  final bool showDistance;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final venue = app.venue(gig.venueId);
    final lineup = [
      for (final bandId in gig.lineup)
        if (app.band(bandId) case final Band band) band.name,
    ];

    return EpCard(
      key: ValueKey('fan-event-${gig.id}'),
      padding: const EdgeInsets.all(11),
      radius: 14,
      onTap: () => app.openGig(gig.id),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GigFlyer(
            gig,
            app.flyer(gig.flyKey),
            width: 72,
            height: 96,
            rotationDeg: -1.4,
            radius: 6,
            shadow: false,
            padding: const EdgeInsets.all(7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  gig.title.toUpperCase(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: epDisplay(
                    size: 9,
                    height: 1.08,
                    color: app.flyer(gig.flyKey).fg,
                  ),
                ),
                Text(
                  gig.dateShort,
                  style: epText(
                    size: 7,
                    weight: FontWeight.w900,
                    color: app.flyer(gig.flyKey).fg.withValues(alpha: .8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        gig.title.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: epDisplay(size: 14, height: 1.12),
                      ),
                    ),
                    const SizedBox(width: 6),
                    PriceBadge(gig),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${gig.dateShort} · DOORS ${_doorsTime(gig.time)}',
                  style: epText(
                    size: 11.5,
                    weight: FontWeight.w800,
                    color: Ep.link,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${venue.name}${showDistance ? ' · ${app.distanceOf(venue)}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: epText(size: 11.5, color: Ep.inkA(.62)),
                ),
                if (lineup.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    lineup.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: epText(size: 10.5, color: Ep.inkA(.48)),
                  ),
                ],
                const SizedBox(height: 7),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AgeBadge(gig.ageRequirement.label),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 5,
                        runSpacing: 5,
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
                            onTap: () => _share(app, gig),
                          ),
                          _TicketAction(gig: gig, app: app),
                          ?trailingAction,
                        ],
                      ),
                    ),
                  ],
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

void _share(AppState app, Gig gig) {
  final url = 'https://earplug.app/g/${gig.id}';
  Clipboard.setData(ClipboardData(text: url));
  app.say('Link copied — earplug.app/g/${gig.id}');
}

Future<void> _openTickets(AppState app, Gig gig) async {
  final url = gig.externalUrl;
  if (url == null || url.isEmpty) {
    app.say('No ticket link listed for this gig.');
    return;
  }
  final opened = await launchUrl(
    Uri.parse(url),
    mode: LaunchMode.externalApplication,
  );
  if (!opened) app.say("Couldn't open that link.");
}

class _AgeBadge extends StatelessWidget {
  const _AgeBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: Ep.whiteA(.22)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label.toUpperCase(),
        style: epText(
          size: 9,
          weight: FontWeight.w900,
          letterSpacing: .5,
          color: Ep.inkA(.68),
        ),
      ),
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
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 17, color: active ? Ep.link : Ep.inkA(.62)),
        ),
      ),
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
    final label = external ? 'GET TICKETS ↗' : (going ? 'GOING ✓' : 'RSVP');
    return GestureDetector(
      key: ValueKey('ticket-action-${gig.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: external
          ? () => _openTickets(app, gig)
          : () => going ? app.toggleRsvp(gig.id) : app.requestRsvp(gig.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: !external && !going ? Ep.blue : null,
          border: Border.all(
            color: !external && !going ? Ep.blue : Ep.whiteA(.24),
          ),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: epText(
            size: external ? 8.5 : 9.5,
            weight: FontWeight.w900,
            letterSpacing: .4,
            color: !external && !going ? Colors.white : Ep.inkA(.75),
          ),
        ),
      ),
    );
  }
}
