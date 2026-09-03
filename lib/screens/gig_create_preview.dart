import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';
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
        gig: draftGigFrom(app),
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
Gig draftGigFrom(AppState app) {
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
  const GigPublishedView({super.key, required this.poster});

  /// The gig's poster, scaled in as the view appears.
  final Widget poster;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ColoredBox(
      color: context.epColors.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'PUBLISHED',
                style: epText(
                  size: 11,
                  weight: FontWeight.w900,
                  letterSpacing: 2,
                  color: context.epColors.accent,
                ),
              ),
              const SizedBox(height: 16),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: .9, end: 1),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: poster,
              ),
              const SizedBox(height: 16),
              Text("IT'S LIVE.", style: epDisplay(size: 20)),
              const SizedBox(height: 4),
              Text(
                app.gigUrl,
                style: epText(
                  size: 12,
                  color: context.epColors.contentSecondary,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 300,
                child: Row(
                  children: [
                    Expanded(
                      child: EpButton(
                        'SHARE LINK',
                        fontSize: 11.5,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        onTap: () => copyForUser(
                          context,
                          'https://${app.gigUrl}',
                          successMessage: 'Link copied: ${app.gigUrl}',
                        ),
                      ),
                    ),
                    if (app.gfProject?.ticketing == Ticketing.rsvp) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: EpButton(
                          'DOOR MODE',
                          kind: EpButtonKind.ghost,
                          fontSize: 11.5,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          onTap: () => showDoorMode(
                            context,
                            DoorModeLaunch(
                              projectId: app.gfProject!.id,
                              gigTitle: app.gfName.trim().isEmpty
                                  ? 'Untitled gig'
                                  : app.gfName,
                              venueName: app.gfVenueId == null
                                  ? 'Venue TBD'
                                  : app.venue(app.gfVenueId!).name,
                              doorsTime: app.gfDoorsLabel,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextAction(
                    'KEEP EDITING',
                    onTap: app.editPublishedGig,
                    color: context.epColors.contentSecondary,
                    size: 11,
                    letterSpacing: .6,
                  ),
                  TextAction(
                    'MAKE ANOTHER',
                    onTap: app.makeAnotherGig,
                    size: 11,
                    letterSpacing: .6,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextAction(
                'BACK TO GIGS',
                onTap: app.closeGigCreate,
                color: context.epColors.contentDisabled,
                size: 11,
                letterSpacing: .6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
