import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final unlocked = (app.myBand?.followers ?? 0) >= 25;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: [
        Text('FAN ANALYTICS', style: epDisplay(size: 18)),
        const SizedBox(height: 14),
        if (unlocked) ..._open(app) else _Locked(app: app),
      ],
    );
  }

  List<Widget> _open(AppState app) {
    final band = app.myBand;
    final gigs = app.myBandGigs;
    final rsvps = gigs.fold(0, (sum, gig) => sum + app.rsvpCount(gig));

    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: Ep.blue.withValues(alpha: .14),
          border: Border.all(color: Ep.blue.withValues(alpha: .5)),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          'Aggregates only. Shown because ${band?.name} passed the 25-follower '
          'privacy threshold — no individual fan is ever identifiable.',
          style: epText(size: 11, color: Ep.linkSoft, height: 1.45),
        ),
      ),
      const SizedBox(height: 14),
      EpCard(
        padding: const EdgeInsets.all(14),
        radius: 13,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('THE NUMBERS SO FAR'),
            const SizedBox(height: 10),
            _StatRow(label: 'Followers', value: band?.followersLabel ?? '0'),
            _StatRow(label: 'Upcoming gigs listed', value: '${gigs.length}'),
            _StatRow(label: 'RSVPs across them', value: '$rsvps'),
          ],
        ),
      ),
      const SizedBox(height: 8),
      DashedBox(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Text(
          'Fan geography, new-vs-returning and turnout charts are on the way — '
          'they build up from RSVPs as your gigs happen.',
          textAlign: TextAlign.center,
          style: epText(size: 12, color: Ep.inkA(.5), height: 1.5),
        ),
      ),
    ];
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Ep.whiteA(.06))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: epText(
              size: 12,
              weight: FontWeight.w700,
              color: Ep.inkA(.78),
            ),
          ),
          Text(
            value,
            style: epText(size: 12, weight: FontWeight.w800, color: Ep.link),
          ),
        ],
      ),
    );
  }
}

class _Locked extends StatelessWidget {
  final AppState app;

  const _Locked({required this.app});

  @override
  Widget build(BuildContext context) {
    final followers = app.myBand?.followers ?? 0;
    final pct = math.min(1.0, followers / 25);
    return DashedBox(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 34),
      child: Column(
        children: [
          const Text('🔒', style: TextStyle(fontSize: 26)),
          const SizedBox(height: 10),
          Text(
            'LOCKED UNTIL 25 FOLLOWERS',
            textAlign: TextAlign.center,
            style: epDisplay(size: 15),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              '$followers of 25 followers so far. Insights only ever show aggregates — '
              'the threshold makes sure no individual fan is identifiable.',
              textAlign: TextAlign.center,
              style: epText(size: 12, color: Ep.inkA(.55), height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 200,
            height: 7,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Stack(
                children: [
                  Container(color: Ep.whiteA(.1)),
                  FractionallySizedBox(
                    widthFactor: pct,
                    child: Container(color: Ep.blue),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
