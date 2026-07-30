import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../band_media_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';

class BandDashScreen extends StatelessWidget {
  const BandDashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final band = app.myBand;
    if (band == null) return const SizedBox.shrink();

    final mine = app.myBandGigs;
    final next = mine.isEmpty ? null : mine.first;
    final clips = context.watch<BandMediaController>().videosFor(band.id);

    final tips = [
      if (mine.isEmpty) 'List your first gig — RSVPs count live.',
      if (clips.isEmpty) 'Post a "this is what we sound like" clip.',
      if (band.followers < 25)
        'Analytics unlock at 25 followers — ${25 - band.followers} to go.',
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, tabBarClearance),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () => showSwitcherSheet(context),
              child: Row(
                children: [
                  BandAvatar(band, size: 38, radius: 9, fontSize: 13),
                  const SizedBox(width: 9),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${band.name.toUpperCase()} ▾',
                          style: epDisplay(size: 16, height: 1)),
                      const SizedBox(height: 3),
                      Text('BAND VIEW · ${app.roleFor(band.id).toUpperCase()}',
                          style: epText(
                              size: 10,
                              weight: FontWeight.w800,
                              letterSpacing: 1,
                              color: Ep.link)),
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: app.toFanView,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: Ep.whiteA(.2)),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text('FAN VIEW',
                    style: epText(
                        size: 10,
                        weight: FontWeight.w800,
                        letterSpacing: .8,
                        color: Ep.inkA(.7))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _StatCard(
                label: 'FOLLOWERS',
                value: band.followersLabel,
                sub: band.followers == 0
                    ? 'just the band so far'
                    : 'and counting'),
            const SizedBox(width: 8),
            _StatCard(
                label: 'NEXT GIG RSVPS',
                value: next != null ? '${app.rsvpCount(next)}' : '—',
                sub: next != null
                    ? (next.title.length > 16 ? next.title.substring(0, 16) : next.title)
                    : 'no gig listed'),
            const SizedBox(width: 8),
            _StatCard(
                label: 'CLIPS',
                value: '${clips.length}',
                sub: clips.isEmpty ? 'post your first clip' : 'on your profile'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _ActionButton(
                label: '▶ POST MEDIA',
                onTap: app.openBandMedia),
            const SizedBox(width: 8),
            _ActionButton(
                label: '+ CREATE GIG', filled: true, onTap: app.startGigCreate),
            const SizedBox(width: 8),
            _ActionButton(
                label: '▦ ANALYTICS', onTap: () => app.resetTo(Screen.analytics)),
          ],
        ),
        if (next != null) ...[
          const SizedBox(height: 14),
          const SectionLabel('NEXT UP', blue: true),
          const SizedBox(height: 8),
          _NextUpCard(gig: next, app: app),
        ],
        if (tips.isNotEmpty) ...[
          const SizedBox(height: 14),
          const SectionLabel('GET ROLLING'),
          const SizedBox(height: 6),
          for (final tip in tips)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
              decoration:
                  BoxDecoration(border: Border(bottom: BorderSide(color: Ep.whiteA(.07)))),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: Ep.blue, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(tip, style: epText(size: 12.5, color: Ep.inkA(.75))),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;

  const _StatCard({required this.label, required this.value, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: EpCard(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
        radius: 13,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: epText(
                    size: 9.5, weight: FontWeight.w800, letterSpacing: 1, color: Ep.inkA(.45))),
            const SizedBox(height: 4),
            Text(value, style: epDisplay(size: 22)),
            const SizedBox(height: 2),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: epText(size: 10, weight: FontWeight.w800, color: Ep.link)),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _ActionButton({required this.label, this.filled = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? Ep.blue : Ep.card,
            border: filled ? null : Border.all(color: Ep.whiteA(.14)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              maxLines: 1,
              style: epText(
                  size: 11,
                  weight: filled ? FontWeight.w900 : FontWeight.w800,
                  letterSpacing: .6,
                  color: filled ? Colors.white : Ep.ink)),
        ),
      ),
    );
  }
}

class _NextUpCard extends StatelessWidget {
  final Gig gig;
  final AppState app;

  const _NextUpCard({required this.gig, required this.app});

  @override
  Widget build(BuildContext context) {
    return EpCard(
      padding: const EdgeInsets.all(12),
      radius: 13,
      borderColor: Ep.whiteA(.12),
      onTap: () => app.openGig(gig.id),
      child: Row(
        children: [
          FlyerBox(
              style: app.flyer(gig.flyKey),
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
                    style: epText(size: 13.5, weight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('${gig.dateShort} · ${app.venue(gig.venueId).name}',
                    style: epText(size: 11.5, color: Ep.inkA(.55))),
                const SizedBox(height: 3),
                Text('${app.rsvpCount(gig)} RSVPs · counting live',
                    style: epText(size: 11, weight: FontWeight.w800, color: Ep.link)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: Ep.inkA(.4)),
        ],
      ),
    );
  }
}
