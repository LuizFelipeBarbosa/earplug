import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class GigManagerScreen extends StatelessWidget {
  const GigManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final upcoming = app.myBandGigs;
    final past = app.myBand?.past ?? const [];

    return ListView(
      padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, tabBarClearance),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('GIG MANAGER', style: epDisplay(size: 18)),
            GestureDetector(
              onTap: app.startGigCreate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: Ep.blue,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('+ NEW GIG',
                    style: epText(
                        size: 10.5,
                        weight: FontWeight.w900,
                        letterSpacing: .8,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const SectionLabel('UPCOMING · LIVE RSVP COUNTS', blue: true),
        const SizedBox(height: 8),
        if (upcoming.isEmpty)
          DashedBox(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
            child: Text.rich(
              TextSpan(
                style: epText(size: 12.5, color: Ep.inkA(.45), height: 1.5),
                children: [
                  const TextSpan(text: 'No gigs yet.\n'),
                  TextSpan(
                      text: 'Book the room, then list it here.',
                      style: epText(size: 12.5, weight: FontWeight.w800)),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        for (final g in upcoming) ...[
          _ManagerRow(gig: g, app: app),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        const SectionLabel('PAST'),
        const SizedBox(height: 6),
        if (past.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Played gigs will collect here after your first show.',
              style: epText(size: 11.5, color: Ep.inkA(.4)),
            ),
          ),
        for (final p in past)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
            decoration:
                BoxDecoration(border: Border(bottom: BorderSide(color: Ep.whiteA(.07)))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(p.title,
                      style: epText(size: 12.5, weight: FontWeight.w700, color: Ep.inkA(.75))),
                ),
                Text(p.meta, style: epText(size: 10.5, color: Ep.inkA(.4))),
              ],
            ),
          ),
      ],
    );
  }
}

class _ManagerRow extends StatelessWidget {
  final Gig gig;
  final AppState app;

  const _ManagerRow({required this.gig, required this.app});

  @override
  Widget build(BuildContext context) {
    final tixTag = gig.tix == Ticketing.external
        ? 'EXTERNAL TICKETS ↗'
        : gig.cap != 'No cap'
            ? 'IN-APP RSVP · CAP ${gig.cap.toUpperCase()}'
            : 'IN-APP RSVP · NO CAP';
    return EpCard(
      padding: const EdgeInsets.all(12),
      radius: 13,
      borderColor: Ep.whiteA(.12),
      onTap: () => app.openGig(gig.id),
      child: Row(
        children: [
          GigFlyer(
              gig,
              app.flyer(gig.flyKey),
              width: 46,
              height: 60,
              rotationDeg: -2,
              radius: 5,
              shadow: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gig.title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: epText(size: 13, weight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('${gig.dateShort} · ${app.venue(gig.venueId).name}',
                    style: epText(size: 11, color: Ep.inkA(.55))),
                const SizedBox(height: 3),
                Text(tixTag,
                    style: epText(
                        size: 10,
                        weight: FontWeight.w700,
                        letterSpacing: .4,
                        color: Ep.inkA(.4))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${app.rsvpCount(gig)}', style: epDisplay(size: 20, color: Ep.link)),
              Text('RSVPS',
                  style: epText(
                      size: 9, weight: FontWeight.w800, letterSpacing: .8, color: Ep.inkA(.45))),
            ],
          ),
        ],
      ),
    );
  }
}
