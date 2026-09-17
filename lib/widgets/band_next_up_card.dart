import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../screens/door_mode.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_text.dart';

/// The band's hero: its next published gig with the live RSVP count and the
/// door-mode / public-gig actions, or a prompt to publish one.
class BandNextUpCard extends StatelessWidget {
  const BandNextUpCard({super.key, required this.bandId});

  final String bandId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isAdmin = app.isAdminOf(bandId);
    // The feed is date-ordered, so the first gig on the lineup is the next one.
    final gig = app.allGigs
        .where((gig) => gig.lineup.contains(bandId))
        .firstOrNull;

    if (gig == null) {
      return EpCard(
        key: const Key('band-next-up-empty'),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EpEyebrow('Nothing scheduled'),
            const SizedBox(height: 12),
            const EpDisplay(
              'No gig coming up — publish one',
              size: 24,
              maxLines: 3,
            ),
            if (isAdmin) ...[
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: EpPill(
                  key: const Key('band-next-up-publish'),
                  label: 'Publish a gig',
                  variant: EpPillVariant.primary,
                  size: EpPillSize.chip,
                  onPressed: app.startGigCreate,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return EpCard(
      key: const Key('band-next-up'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: EpEyebrow.accent('Up next')),
              const SizedBox(width: 12),
              Flexible(
                child: EpMonoText(
                  '${gig.dateShort} · Doors ${_doorsLabel(context, gig)}',
                  key: const Key('band-next-up-when'),
                  color: context.epColors.contentSecondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          EpDisplay(gig.title, size: 32, maxLines: 3),
          const SizedBox(height: 12),
          EpMonoText(
            '${app.venue(gig.venueId).name} · ${app.rsvpCount(gig)} RSVPs · '
            'counting live',
            color: context.epColors.contentSecondary,
          ),
          const SizedBox(height: 20),
          // A wrap rather than a row so large text never clips an action.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (isAdmin)
                EpPill(
                  key: const Key('band-next-door-mode'),
                  label: 'Door mode',
                  variant: EpPillVariant.primary,
                  size: EpPillSize.chip,
                  onPressed: () =>
                      showDoorMode(context, _doorLaunchFor(context, app, gig)),
                ),
              EpPill(
                key: const Key('band-next-public-gig'),
                label: 'Public gig ↗',
                variant: EpPillVariant.outline,
                size: EpPillSize.chip,
                keepCase: true,
                onPressed: () => app.openGig(gig.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _doorsLabel(BuildContext context, Gig gig) => gig.doorsAt == null
    ? gig.time.split('/').first.trim()
    : TimeOfDay.fromDateTime(gig.doorsAt!.toLocal()).format(context);

DoorModeLaunch _doorLaunchFor(BuildContext context, AppState app, Gig next) =>
    DoorModeLaunch.organizer(
      gigId: next.id,
      gigTitle: next.title,
      venueName: app.venue(next.venueId).name,
      doorsTime: _doorsLabel(context, next),
    );
