import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../demo_data.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class GigCreateScreen extends StatelessWidget {
  const GigCreateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 10),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: Ep.whiteA(.09)))),
          child: Row(
            children: [
              CircleIconButton(onTap: app.back),
              const SizedBox(width: 10),
              Text('NEW GIG', style: epDisplay(size: 16)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 60),
            children: [
              GestureDetector(
                onTap: () => app.say('Flyer upload placeholder (demo)'),
                child: SizedBox(
                  height: 120,
                  child: DashedBox(
                    padding: EdgeInsets.zero,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('+ UPLOAD FLYER',
                              style: epText(
                                  size: 12,
                                  weight: FontWeight.w800,
                                  letterSpacing: .8,
                                  color: Ep.inkA(.5))),
                          const SizedBox(height: 4),
                          Text("We'll generate one from your title if you skip this",
                              style: epText(size: 10.5, letterSpacing: .3, color: Ep.inkA(.5))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const SectionLabel('GIG NAME'),
              const SizedBox(height: 6),
              TextFormField(
                initialValue: app.gfName,
                onChanged: app.setGfName,
                style: epText(size: 14),
                decoration: epInputDecoration('e.g. Riptide Tour Kickoff'),
              ),
              const SizedBox(height: 16),
              const SectionLabel('DATE & DOORS'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final d in const ['Fri Aug 14', 'Sat Aug 15', 'Fri Aug 21', 'Sat Aug 22'])
                    EpChip(
                        label: d,
                        active: app.gfDate == d,
                        onTap: () => app.setGfDate(app.gfDate == d ? null : d)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final t in const ['7PM', '8PM', '9PM'])
                    EpChip(
                        label: 'DOORS $t',
                        active: app.gfTime == t,
                        onTap: () => app.setGfTime(t)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SectionLabel('VENUE'),
                  GestureDetector(
                    onTap: () =>
                        app.say('New venue form placeholder — it becomes a shared record.'),
                    child: Text('+ NEW VENUE',
                        style: epText(
                            size: 11,
                            weight: FontWeight.w900,
                            letterSpacing: .6,
                            color: Ep.link)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  'Venues are shared records — pick one and the address stays consistent '
                  "across every band's listings.",
                  style: epText(size: 10.5, color: Ep.inkA(.4), height: 1.4)),
              const SizedBox(height: 8),
              for (final v in DemoData.venues.values) ...[
                _SelectCard(
                  selected: app.gfVenueId == v.id,
                  onTap: () => app.setGfVenue(v.id),
                  title: v.name.toUpperCase(),
                  subtitle: '${v.addr} · ${v.area}',
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              const SectionLabel('PRICE'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final p in const ['FREE', '\$5', '\$8', '\$10', '\$12', '\$15'])
                    EpChip(label: p, active: app.gfPrice == p, onTap: () => app.setGfPrice(p)),
                ],
              ),
              const SizedBox(height: 16),
              const SectionLabel('TICKETING'),
              const SizedBox(height: 8),
              _SelectCard(
                selected: app.gfTix == Ticketing.rsvp,
                onTap: () => app.setGfTix(Ticketing.rsvp),
                title: 'In-app RSVP',
                titleCase: true,
                subtitle: 'Free headcount, QR at the door, optional cap',
              ),
              if (app.gfTix == Ticketing.rsvp)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 8),
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final c in const ['No cap', '50', '100', '150'])
                        EpChip(label: c, active: app.gfCap == c, onTap: () => app.setGfCap(c)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              _SelectCard(
                selected: app.gfTix == Ticketing.external,
                onTap: () => app.setGfTix(Ticketing.external),
                title: 'External ticket link',
                titleCase: true,
                subtitle: 'DICE, Eventbrite, venue box office…',
              ),
              if (app.gfTix == Ticketing.external)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextFormField(
                    initialValue: app.gfExt,
                    onChanged: app.setGfExt,
                    style: epText(size: 12.5),
                    decoration: epInputDecoration('https://…'),
                  ),
                ),
              const SizedBox(height: 20),
              EpButton(
                'PUBLISH GIG',
                fontSize: 14,
                glow: app.canPublishGig,
                kind: app.canPublishGig ? EpButtonKind.filled : EpButtonKind.disabled,
                padding: const EdgeInsets.symmetric(vertical: 16),
                onTap: app.publishGig,
              ),
              if (!app.canPublishGig)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: GestureDetector(
                    onTap: app.publishGig,
                    child: Text('Name, date and venue required.',
                        textAlign: TextAlign.center,
                        style: epText(size: 11, color: Ep.inkA(.4))),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String subtitle;
  final bool titleCase;

  const _SelectCard({
    required this.selected,
    required this.onTap,
    required this.title,
    required this.subtitle,
    this.titleCase = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? Ep.blue.withValues(alpha: .16) : Ep.card,
          border: selected
              ? Border.all(color: Ep.blue, width: 1.5)
              : Border.all(color: Ep.whiteA(.14)),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: epText(
                    size: 12.5,
                    weight: FontWeight.w800,
                    letterSpacing: titleCase ? 0 : .3)),
            const SizedBox(height: 2),
            Text(subtitle, style: epText(size: 10.5, color: Ep.inkA(.5))),
          ],
        ),
      ),
    );
  }
}
