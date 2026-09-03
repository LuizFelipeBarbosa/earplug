import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/map_view.dart';

class GigDetailScreen extends StatelessWidget {
  final String gigId;

  const GigDetailScreen({super.key, required this.gigId});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final gig = app.gig(gigId);
    if (gig == null) {
      if (app.publicGigError(gigId) != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "THIS GIG ISN'T AVAILABLE RIGHT NOW",
                  textAlign: TextAlign.center,
                  style: epText(color: context.epColors.contentSecondary),
                ),
                const SizedBox(height: 16),
                EpButton('TRY AGAIN', onTap: () => app.retryPublicGig(gigId)),
              ],
            ),
          ),
        );
      }
      if (app.publicGigMissing(gigId)) {
        return Center(
          child: Text(
            'THIS GIG IS NO LONGER AVAILABLE',
            style: epText(color: context.epColors.contentSecondary),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final performers = gig.performers.isNotEmpty
        ? gig.performers
        : [
            for (var index = 0; index < gig.lineup.length; index++)
              if (app.band(gig.lineup[index]) case final band?)
                GigPerformer(
                  id: '',
                  kind: GigPerformerKind.band,
                  name: band.name,
                  role: index == 0
                      ? GigPerformerRole.headliner
                      : GigPerformerRole.support,
                  bandId: band.id,
                ),
          ];

    return GigDetailPresentation(gig: gig, app: app, performers: performers);
  }
}

/// The redesigned public gig composition, also used by the editor's read-only
/// draft preview so current form values are shown in the same hierarchy.
class GigDetailPresentation extends StatelessWidget {
  const GigDetailPresentation({
    super.key,
    required this.gig,
    required this.app,
    required this.performers,
    this.previewLabel,
    this.onBack,
    this.flyerBytes,
    this.venueSet = true,
  });

  final Gig gig;
  final AppState app;
  final List<GigPerformer> performers;
  final String? previewLabel;
  final VoidCallback? onBack;
  final Uint8List? flyerBytes;
  final bool venueSet;

  bool get isPreview => previewLabel != null;

  @override
  Widget build(BuildContext context) {
    final venue = app.venue(gig.venueId);
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            _Hero(
              gig: gig,
              app: app,
              performers: performers,
              onBack: onBack ?? app.back,
              previewLabel: previewLabel,
              flyerBytes: flyerBytes,
            ),
            if (gig.lifecycle == GigLifecycle.cancelled)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.epColors.warning.withValues(alpha: .12),
                  border: Border.all(color: context.epColors.warning),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'THIS GIG HAS BEEN CANCELLED',
                  textAlign: TextAlign.center,
                  style: epText(
                    size: 12,
                    weight: FontWeight.w900,
                    letterSpacing: .8,
                    color: context.epColors.warning,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoCards(
                    gig: gig,
                    venue: venue,
                    previewLabel: previewLabel,
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => SizeTransition(
                      sizeFactor: animation,
                      alignment: Alignment.topCenter,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child:
                        !isPreview &&
                            gig.tix == Ticketing.rsvp &&
                            gig.lifecycle == GigLifecycle.published &&
                            app.hasConfirmedRsvp(gig.id)
                        ? Column(
                            key: ValueKey('gig-attendance-${gig.id}'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SectionBar(label: "WHO'S GOING"),
                              _WhosGoing(gig: gig, app: app),
                            ],
                          )
                        : SizedBox.shrink(
                            key: ValueKey('gig-attendance-hidden-${gig.id}'),
                          ),
                  ),
                  const SizedBox(height: 16),
                  SectionBar(label: 'LINEUP', count: performers.length),
                  for (final performer in performers) ...[
                    _LineupRow(
                      performer: performer,
                      app: app,
                      interactive: !isPreview,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (gig.desc.trim().isNotEmpty) ...[
                    const SectionBar(label: 'ABOUT'),
                    Text(
                      gig.desc,
                      style: epText(
                        size: 13.5,
                        color: context.epColors.contentSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SectionBar(label: 'VENUE'),
                  if (venueSet)
                    _VenueCard(venue: venue, app: app, interactive: !isPreview)
                  else
                    const _MissingVenueCard(),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: isPreview
              ? _PreviewCtaBar(gig: gig)
              : _GigCtaBar(gig: gig, app: app),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  final Gig gig;
  final AppState app;
  final List<GigPerformer> performers;
  final VoidCallback onBack;
  final String? previewLabel;
  final Uint8List? flyerBytes;

  const _Hero({
    required this.gig,
    required this.app,
    required this.performers,
    required this.onBack,
    required this.previewLabel,
    required this.flyerBytes,
  });

  @override
  Widget build(BuildContext context) {
    final fly = app.flyer(gig.flyKey);
    final venue = app.venue(gig.venueId);
    final presenter = gig.createdByBand == null
        ? null
        : app.band(gig.createdByBand!);
    final lineupLine = performers
        .map((performer) => performer.name)
        .join(' · ')
        .toUpperCase();
    final topPad = headerTopPad(context);

    final content = Stack(
      fit: StackFit.expand,
      children: [
        if (gig.flyKey == 'custom')
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent, Colors.black87],
                stops: [0, .42, 1],
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(22, topPad + 8, 22, 20),
          child: Stack(
            key: const ValueKey('gig-detail-hero-content'),
            clipBehavior: Clip.none,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (presenter != null) ...[
                          Text(
                            '${presenter.name.toUpperCase()} PRESENTS',
                            style: epText(
                              size: 11,
                              weight: FontWeight.w900,
                              color: fly.fg,
                              letterSpacing: 1.8,
                            ),
                          ),
                          const SizedBox(height: 9),
                        ],
                        Text(
                          gig.title.toUpperCase(),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: epDisplay(
                            size: 34,
                            color: fly.fg,
                            letterSpacing: -.5,
                            height: .98,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${gig.dateShort} · ${venue.name.toUpperCase()}',
                        style: epDisplay(size: 15, color: fly.fg),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lineupLine,
                        style: epText(
                          size: 11,
                          weight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: fly.fg.withValues(alpha: .75),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Positioned(
                left: -8,
                top: -2,
                child: CircleIconButton(
                  tooltip: 'Back',
                  onTap: onBack,
                  background: Colors.black.withValues(alpha: .55),
                  bordered: false,
                ),
              ),
              Positioned(
                right: -8,
                top: -2,
                child: previewLabel == null
                    ? Row(
                        children: [
                          _HeroAction(
                            key: ValueKey('gig-detail-save-${gig.id}'),
                            tooltip: app.saved.contains(gig.id)
                                ? 'Remove saved event'
                                : 'Save event',
                            onTap: () => app.requestSave(gig.id),
                            child: Icon(
                              app.saved.contains(gig.id)
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _HeroAction(
                            key: ValueKey('gig-detail-share-${gig.id}'),
                            tooltip: 'Share event',
                            onTap: () => copyForUser(
                              context,
                              publicWebUrl('g/${gig.publicRef}'),
                              successMessage:
                                  'Link copied: ${publicWebDisplayUrl('g/${gig.publicRef}')}',
                            ),
                            child: Text(
                              'SHARE ↗',
                              style: epText(
                                size: 11,
                                weight: FontWeight.w800,
                                letterSpacing: 1,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Container(
                        key: const ValueKey('gig-draft-preview-status'),
                        constraints: const BoxConstraints(minHeight: 32),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .72),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .35),
                          ),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          previewLabel!,
                          style: epText(
                            size: 10.5,
                            weight: FontWeight.w900,
                            letterSpacing: .7,
                            color: Colors.white,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );

    final bytes = flyerBytes;
    if (bytes != null) {
      return RepaintBoundary(
        child: SizedBox(
          height: 330,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                bytes,
                fit: BoxFit.cover,
                cacheHeight: (330 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
              ),
              content,
            ],
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: GigFlyer(
        gig,
        fly,
        height: 330,
        radius: 0,
        shadow: false,
        child: content,
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({
    super.key,
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(99),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 48,
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _InfoCards extends StatelessWidget {
  final Gig gig;
  final Venue venue;
  final String? previewLabel;

  const _InfoCards({
    required this.gig,
    required this.venue,
    required this.previewLabel,
  });

  @override
  Widget build(BuildContext context) {
    Widget fact(IconData icon, String text) {
      return Row(
        children: [
          Icon(icon, size: 18, color: context.epColors.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.epLabel,
            ),
          ),
        ],
      );
    }

    Widget pill(String label, String value, {Color? valueColor}) {
      return Container(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 72),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: context.epColors.surface,
          border: Border.all(color: context.epColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.epCaption.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: Theme.of(context).textTheme.epLabel.copyWith(
                color: valueColor ?? context.epColors.contentPrimary,
              ),
            ),
          ],
        ),
      );
    }

    return EpCard(
      variant: EpCardVariant.raised,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fact(Icons.calendar_month, '${gig.dateShort} · DOORS ${gig.time}'),
          const SizedBox(height: 11),
          fact(
            Icons.location_on,
            [
              venue.name,
              if (venue.area.trim().isNotEmpty) venue.area,
            ].join(' · '),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              pill(
                'PRICE',
                gig.priceLabel,
                valueColor: gig.free
                    ? context.epColors.accent
                    : context.epColors.contentPrimary,
              ),
              pill('AGE', gig.ageRequirement.label),
              if (previewLabel != null)
                StatusPill(
                  label: previewLabel!,
                  tone: EpStatusPillTone.warning,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineupRow extends StatelessWidget {
  final GigPerformer performer;
  final AppState app;
  final bool interactive;

  const _LineupRow({
    required this.performer,
    required this.app,
    required this.interactive,
  });

  @override
  Widget build(BuildContext context) {
    final band = performer.bandId == null ? null : app.band(performer.bandId!);
    return EpCard(
      padding: const EdgeInsets.all(10),
      onTap: !interactive || band == null ? null : () => app.openBand(band.id),
      child: Row(
        children: [
          if (band != null)
            BandAvatar(band)
          else
            const CircleAvatar(child: Icon(Icons.music_note, size: 18)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  performer.name.toUpperCase(),
                  style: epText(
                    size: 13.5,
                    weight: FontWeight.w800,
                    letterSpacing: .3,
                  ),
                ),
                Text(
                  band?.genreLine ?? performer.role.name.toUpperCase(),
                  style: epText(
                    size: 11.5,
                    color: context.epColors.contentSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (interactive && band != null) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              key: ValueKey('gig-lineup-follow-${band.id}'),
              onPressed: () => app.requestFollow(band.id),
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(48, 48)),
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
              child: Text(
                app.follows.contains(band.id) ? 'FOLLOWING ✓' : 'FOLLOW',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VenueCard extends StatelessWidget {
  final Venue venue;
  final AppState app;
  final bool interactive;

  const _VenueCard({
    required this.venue,
    required this.app,
    required this.interactive,
  });

  @override
  Widget build(BuildContext context) {
    return EpCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: interactive ? () => app.openVenue(venue.id) : null,
              child: VenueMiniMap(venue: venue),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: interactive ? () => app.openVenue(venue.id) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              venue.name.toUpperCase(),
                              style: epText(
                                size: 13.5,
                                weight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${venue.addr} · ${venue.area}',
                              style: epText(
                                size: 11.5,
                                color: context.epColors.contentSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (interactive) ...[
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => openExternalForUser(
                      context,
                      'https://www.google.com/maps/search/?api=1&query='
                      '${venue.point.latitude},${venue.point.longitude}',
                    ),
                    child: Text('DIRECTIONS ↗'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingVenueCard extends StatelessWidget {
  const _MissingVenueCard();

  @override
  Widget build(BuildContext context) {
    return EpCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            Icons.location_off_outlined,
            color: context.epColors.contentDisabled,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'VENUE NOT SET',
              style: Theme.of(context).textTheme.epLabel.copyWith(
                color: context.epColors.contentSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhosGoing extends StatelessWidget {
  final Gig gig;
  final AppState app;

  const _WhosGoing({required this.gig, required this.app});

  @override
  Widget build(BuildContext context) {
    final going = app.rsvpCount(gig);
    final capacity = gig.numericCapacity;
    final progress = capacity == null ? null : (going / capacity).clamp(0, 1);
    final spotsLabel = capacity == 1 ? 'spot' : 'spots';

    return EpCard(
      key: ValueKey('who-is-going-${gig.id}'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$going+ GOING', style: epDisplay(size: 22)),
          if (capacity != null && progress != null) ...[
            const SizedBox(height: 12),
            Semantics(
              key: ValueKey('attendance-capacity-progress-${gig.id}'),
              container: true,
              label: '$going of $capacity $spotsLabel filled',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '$going of $capacity $spotsLabel filled',
                      style: Theme.of(context).textTheme.epCaption.copyWith(
                        color: context.epColors.contentSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      tween: Tween<double>(begin: 0, end: progress.toDouble()),
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(99),
                        backgroundColor: context.epColors.border,
                        color: context.epColors.volt,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewCtaBar extends StatelessWidget {
  const _PreviewCtaBar({required this.gig});

  final Gig gig;

  @override
  Widget build(BuildContext context) {
    final external = gig.tix == Ticketing.external;
    final note = external
        ? 'External ticketing · preview only'
        : gig.free
        ? 'Free RSVP · preview only'
        : 'Pay at the door · preview only';
    final label = external
        ? 'GET TICKETS ↗'
        : gig.free
        ? 'RSVP — FREE'
        : 'RSVP — ${gig.priceLabel} AT DOOR';

    return _CtaBar(
      note: note,
      child: EpButton(label, kind: EpButtonKind.disabled, onTap: null),
    );
  }
}

class _GigCtaBar extends StatelessWidget {
  final Gig gig;
  final AppState app;

  const _GigCtaBar({required this.gig, required this.app});

  @override
  Widget build(BuildContext context) {
    if (gig.lifecycle == GigLifecycle.cancelled) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
        color: context.epColors.background,
        child: EpButton(
          'GIG CANCELLED',
          kind: EpButtonKind.disabled,
          onTap: null,
        ),
      );
    }
    final isRsvpd = app.rsvps.contains(gig.id);
    final external = gig.tix == Ticketing.external;
    final tixNote = external
        ? 'External ticketing'
        : gig.free
        ? 'Free. RSVP for headcount'
        : 'Pay at the door · RSVP holds nothing';

    final Widget button;
    if (external) {
      button = EpButton(
        'GET TICKETS ↗',
        kind: EpButtonKind.light,
        fontSize: 14,
        padding: const EdgeInsets.symmetric(vertical: 16),
        onTap: () {
          final url = gig.externalUrl;
          if (url == null) {
            app.say('No ticket link listed for this gig.');
          } else {
            openExternalForUser(context, url);
          }
        },
      );
    } else if (isRsvpd) {
      button = EpButton(
        'GOING ✓',
        kind: EpButtonKind.outline,
        fontSize: 14,
        onTap: () => app.toggleRsvp(gig.id),
      );
    } else {
      button = EpButton(
        gig.free ? 'RSVP — FREE' : 'RSVP — ${gig.priceLabel} AT DOOR',
        fontSize: 14,
        padding: const EdgeInsets.symmetric(vertical: 16),
        onTap: () => app.requestRsvp(gig.id),
      );
    }

    return _CtaBar(note: tixNote, child: button);
  }
}

/// The footer that fades up over the page and holds a ticketing note above
/// the call to action.
class _CtaBar extends StatelessWidget {
  const _CtaBar({required this.note, required this.child});

  final String note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: [0, .75, 1],
          colors: [
            context.epColors.background,
            context.epColors.background,
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            note,
            textAlign: TextAlign.center,
            style: epText(
              size: 11,
              weight: FontWeight.w700,
              letterSpacing: .5,
              color: context.epColors.contentSecondary,
            ),
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }
}
