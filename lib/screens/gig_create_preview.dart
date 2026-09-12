import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import 'door_mode.dart';
import 'gig_detail.dart';

// ============================ fan preview ============================

/// The fan-facing preview of the draft being edited.
class GigDraftPreview extends StatelessWidget {
  const GigDraftPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ColoredBox(
      color: context.epColors.background,
      child: GigDetailPresentation(
        key: const ValueKey('redesigned-gig-draft-preview'),
        gig: _draftGigFrom(app),
        app: app,
        performers: app.gfPerformers,
        previewLabel: app.gigPreviewLabel,
        onBack: app.closeGigPreview,
        flyerBytes: app.gfFlyerArt?.bytes,
        venueSet: app.gfVenueId != null,
      ),
    );
  }
}

/// A [Gig] built from the editor's current fields, for previewing.
Gig _draftGigFrom(AppState app) {
  final draftDate = app.gfDate;
  final date = draftDate ?? DateTime.now();
  final doorsAt = DateTime(
    date.year,
    date.month,
    date.day,
    app.gfDoors.hour,
    app.gfDoors.minute,
  );
  var startsAt = DateTime(
    date.year,
    date.month,
    date.day,
    app.gfStart.hour,
    app.gfStart.minute,
  );
  if (startsAt.isBefore(doorsAt)) {
    startsAt = startsAt.add(const Duration(days: 1));
  }
  final price =
      int.tryParse(app.gfPrice.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  final lineup = [
    for (final performer in app.gfPerformers)
      if (performer.bandId != null) performer.bandId!,
  ];
  final genres = <String>{
    for (final bandId in lineup) ...?app.band(bandId)?.genres,
  }.toList();

  return Gig(
    id: 'draft-preview',
    title: app.gfName.trim().isEmpty ? 'Untitled gig' : app.gfName.trim(),
    venueId: app.gfVenueId ?? '',
    price: price,
    startsAt: startsAt,
    doorsAt: doorsAt,
    dateShort: draftDate == null
        ? 'DATE NOT SET'
        : Gig.dateShortFor(doorsAt.millisecondsSinceEpoch),
    dateLine: draftDate == null
        ? 'DATE NOT SET · DOORS ${app.gfDoorsLabel}'
        : Gig.dateLineFor(
            startsAt.millisecondsSinceEpoch,
            '${app.gfDoorsLabel} / ${app.gfStartLabel}',
          ),
    time: '${app.gfDoorsLabel} / ${app.gfStartLabel}',
    when: Gig.whenFor(startsAt.millisecondsSinceEpoch),
    flyKey: app.gfFly,
    lineup: lineup,
    performers: List.of(app.gfPerformers),
    going: 0,
    genres: genres,
    desc: app.gfDesc,
    tix: app.gfTix,
    externalUrl: app.gfExt.trim().isEmpty ? null : app.gfExt.trim(),
    flyerUrl: app.gfFlyerUrl,
    cap: app.gfCap,
    ageRequirement: app.gfAgeRequirement,
    lifecycle: GigLifecycle.unpublished,
    createdByBand: app.bandId.isEmpty ? null : app.bandId,
  );
}

// ============================ published ============================

/// The celebration shown once the gig is live, with its share actions.
class GigPublishedView extends StatelessWidget {
  const GigPublishedView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final gig = _draftGigFrom(app);
    final venue = app.gfVenueId == null ? null : app.venue(app.gfVenueId!);
    final publicGigId = app.gfProject?.publicGigId;
    return ColoredBox(
      color: context.epColors.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: EpLayout.gutter,
            vertical: 32,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const EpEyebrow.accent('Published'),
                const SizedBox(height: 12),
                const EpDisplay("It's live.", size: 36),
                const SizedBox(height: 20),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: .9, end: 1),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutBack,
                  builder: (_, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: EpGigRow(
                    date: gig.startsAt,
                    title: gig.title,
                    meta: venue == null
                        ? gig.dateLine
                        : '${gig.dateLine} · ${venue.name}',
                    sub: app.gigUrl,
                  ),
                ),
                const SizedBox(height: 24),
                if (publicGigId != null) ...[
                  EpPill(
                    label: 'Open public gig',
                    variant: EpPillVariant.primary,
                    size: EpPillSize.large,
                    expand: true,
                    onPressed: () => app.openGig(publicGigId),
                  ),
                  const SizedBox(height: 16),
                ],
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton(
                      onPressed: () => copyForUser(
                        context,
                        'https://${app.gigUrl}',
                        successMessage: 'Link copied: ${app.gigUrl}',
                      ),
                      child: const EpMonoText('Share link'),
                    ),
                    if (app.gfProject?.ticketing == Ticketing.rsvp)
                      TextButton(
                        onPressed: () => showDoorMode(
                          context,
                          DoorModeLaunch(
                            projectId: app.gfProject!.id,
                            gigTitle: app.gfName.trim().isEmpty
                                ? 'Untitled gig'
                                : app.gfName,
                            venueName: venue?.name ?? 'Venue TBD',
                            doorsTime: app.gfDoorsLabel,
                          ),
                        ),
                        child: const EpMonoText('Door mode'),
                      ),
                    TextButton(
                      onPressed: app.editPublishedGig,
                      child: const EpMonoText('Keep editing'),
                    ),
                    TextButton(
                      onPressed: app.makeAnotherGig,
                      child: const EpMonoText('Make another'),
                    ),
                    TextButton(
                      onPressed: app.closeGigCreate,
                      child: const EpMonoText('Back to gigs'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
