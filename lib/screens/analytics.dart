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
    return ListView(
      padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, tabBarClearance),
      children: [
        Text('FAN ANALYTICS', style: epDisplay(size: 18)),
        const SizedBox(height: 14),
        if (app.bandIsNew) _Locked(app: app) else ..._open(app),
      ],
    );
  }

  List<Widget> _open(AppState app) {
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: Ep.blue.withValues(alpha: .14),
          border: Border.all(color: Ep.blue.withValues(alpha: .5)),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
            'Aggregates only. Shown because ${app.myBand?.name} passed the 25-follower '
            'privacy threshold — no individual fan is ever identifiable.',
            style: epText(size: 11, color: Ep.linkSoft, height: 1.45)),
      ),
      const SizedBox(height: 14),
      EpCard(
        padding: const EdgeInsets.all(14),
        radius: 13,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('WHERE YOUR FANS COME FROM'),
            const SizedBox(height: 10),
            for (final (name, pct, w) in const [
              ('Mission, SF', '34%', 1.0),
              ('Bernal Heights', '18%', .53),
              ('Temescal, Oak', '14%', .41),
              ('Dogpatch', '9%', .26),
              ('Outer Sunset', '8%', .24),
              ('Everywhere else', '17%', .5),
            ]) ...[
              _HoodBar(name: name, pct: pct, fraction: w),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      const SizedBox(height: 8),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: EpCard(
                padding: const EdgeInsets.all(14),
                radius: 13,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NEW VS RETURNING',
                        style: epText(
                            size: 10.5,
                            weight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Ep.inkA(.5))),
                    const SizedBox(height: 10),
                    const Center(child: _Donut(newPct: .38)),
                    const SizedBox(height: 10),
                    Center(
                      child: Text('62% came back for more',
                          style:
                              epText(size: 10, weight: FontWeight.w700, color: Ep.inkA(.55))),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EpCard(
                padding: const EdgeInsets.all(14),
                radius: 13,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GENRE OVERLAP',
                        style: epText(
                            size: 10.5,
                            weight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Ep.inkA(.5))),
                    const SizedBox(height: 8),
                    for (final (name, pct) in const [
                      ('garage', '71%'),
                      ('surf', '54%'),
                      ('post-punk', '47%'),
                      ('noise', '29%'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(name,
                                style: epText(
                                    size: 11, weight: FontWeight.w700, color: Ep.inkA(.75))),
                            Text(pct,
                                style: epText(
                                    size: 11, weight: FontWeight.w800, color: Ep.link)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      EpCard(
        padding: const EdgeInsets.all(14),
        radius: 13,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('YOUR FANS ALSO ATTEND'),
            const SizedBox(height: 9),
            for (final (name, pct) in const [
              ('Pigeon Court shows', '41%'),
              ('Noise Night series', '26%'),
              ('Trash Panda Riot shows', '19%'),
            ])
              Container(
                padding: const EdgeInsets.only(bottom: 8),
                margin: const EdgeInsets.only(bottom: 9),
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Ep.whiteA(.06)))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(name,
                        style: epText(size: 12, weight: FontWeight.w700, color: Ep.inkA(.78))),
                    Text('$pct of your fans',
                        style: epText(size: 11, weight: FontWeight.w800, color: Ep.inkA(.55))),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      EpCard(
        padding: const EdgeInsets.all(14),
        radius: 13,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('RSVP → TURNOUT BY GIG'),
            const SizedBox(height: 10),
            SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (label, rh, th) in const [
                    ('PERALTA JUN 6', .88, .61),
                    ('IN-STORE JUN 27', .47, .44),
                    ('WARMUP JUL 12', .79, .63),
                    ('RIPTIDE (LIVE)', 1.0, .12),
                  ])
                    Expanded(child: _TrendColumn(label: label, rsvp: rh, turnout: th)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _LegendSwatch(color: Ep.whiteA(.22), label: 'RSVP'),
                const SizedBox(width: 14),
                const _LegendSwatch(color: Ep.blue, label: 'SHOWED UP'),
              ],
            ),
          ],
        ),
      ),
    ];
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
          Text('LOCKED UNTIL 25 FOLLOWERS',
              textAlign: TextAlign.center, style: epDisplay(size: 15)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
                '$followers of 25 followers so far. Insights only ever show aggregates — '
                'the threshold makes sure no individual fan is identifiable.',
                textAlign: TextAlign.center,
                style: epText(size: 12, color: Ep.inkA(.55), height: 1.5)),
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

class _HoodBar extends StatelessWidget {
  final String name;
  final String pct;
  final double fraction;

  const _HoodBar({required this.name, required this.pct, required this.fraction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 104,
          child: Text(name,
              style: epText(size: 11.5, weight: FontWeight.w700, color: Ep.inkA(.75))),
        ),
        Expanded(
          child: SizedBox(
            height: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(color: Ep.whiteA(.07)),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(color: Ep.blue),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(pct,
              textAlign: TextAlign.right,
              style: epText(size: 11, weight: FontWeight.w800, color: Ep.inkA(.6))),
        ),
      ],
    );
  }
}

class _Donut extends StatelessWidget {
  final double newPct;

  const _Donut({required this.newPct});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          transform: const GradientRotation(-math.pi / 2),
          stops: [0, newPct, newPct, 1],
          colors: [Ep.blue, Ep.blue, Ep.whiteA(.16), Ep.whiteA(.16)],
        ),
      ),
      child: Container(
        width: 60,
        height: 60,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: Ep.card, shape: BoxShape.circle),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${(newPct * 100).round()}%', style: epDisplay(size: 16)),
            Text('NEW',
                style: epText(
                    size: 7.5,
                    weight: FontWeight.w800,
                    letterSpacing: .8,
                    color: Ep.inkA(.5))),
          ],
        ),
      ),
    );
  }
}

class _TrendColumn extends StatelessWidget {
  final String label;
  final double rsvp;
  final double turnout;

  const _TrendColumn({required this.label, required this.rsvp, required this.turnout});

  @override
  Widget build(BuildContext context) {
    Widget bar(double fraction, Color color) {
      return FractionallySizedBox(
        heightFactor: fraction,
        child: Container(
          width: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              bar(rsvp, Ep.whiteA(.22)),
              const SizedBox(width: 3),
              bar(turnout, Ep.blue),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Text(label,
            textAlign: TextAlign.center,
            style: epText(
                size: 8.5,
                weight: FontWeight.w800,
                letterSpacing: .3,
                color: Ep.inkA(.5),
                height: 1.2)),
      ],
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendSwatch({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: epText(size: 9.5, weight: FontWeight.w800, color: Ep.inkA(.5))),
      ],
    );
  }
}
