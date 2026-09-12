import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/map_view.dart';
import '../widgets/ticket_purchase_sheet.dart';

class GigDetailScreen extends StatefulWidget {
  final String gigId;

  const GigDetailScreen({super.key, required this.gigId});

  @override
  State<GigDetailScreen> createState() => _GigDetailScreenState();
}

class _GigDetailScreenState extends State<GigDetailScreen> {
  bool _checkedPendingTicketPurchase = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkedPendingTicketPurchase) return;
    _checkedPendingTicketPurchase = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<AppState>().consumePendingTicketPurchase(widget.gigId)) {
        final gig = context.read<AppState>().gig(widget.gigId);
        if (gig != null) unawaited(showTicketPurchaseSheet(context, gig));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final gig = app.gig(widget.gigId);
    if (gig == null) {
      if (app.publicGigError(widget.gigId) != null) {
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
                EpButton(
                  'TRY AGAIN',
                  onTap: () => app.retryPublicGig(widget.gigId),
                ),
              ],
            ),
          ),
        );
      }
      if (app.publicGigMissing(widget.gigId)) {
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
    final interactive = !isPreview;
    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.only(bottom: actionBarClearance(context)),
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
              const _CancelledBanner(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FactsSection(
                    gig: gig,
                    app: app,
                    venue: venue,
                    venueSet: venueSet,
                    interactive: interactive,
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
                        interactive &&
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
                  for (final performer in performers)
                    _LineupRow(
                      performer: performer,
                      app: app,
                      interactive: interactive,
                    ),
                  if (gig.desc.trim().isNotEmpty) ...[
                    const SectionBar(label: 'ABOUT'),
                    Text(
                      gig.desc,
                      style: Theme.of(context).textTheme.epBody.copyWith(
                        color: context.epColors.muted,
                      ),
                    ),
                  ],
                  if (venueSet)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: _VenueMapSection(
                        venue: venue,
                        app: app,
                        interactive: interactive,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _GigCta(gig: gig, app: app, previewLabel: previewLabel),
        ),
      ],
    );
  }
}

class _CancelledBanner extends StatelessWidget {
  const _CancelledBanner();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(EpLayout.gutter, 16, EpLayout.gutter, 0),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.epColors.warning.withValues(alpha: .12),
      border: Border.all(color: context.epColors.warning),
    ),
    child: Center(
      child: EpMonoText(
        'This gig has been cancelled',
        color: context.epColors.warning,
      ),
    ),
  );
}

/// The full-bleed flyer: artwork, the presenter eyebrow, the title and the
/// lineup line, with the back / save / share pills floating over it.
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

  static const double _height = 360;

  @override
  Widget build(BuildContext context) {
    final fly = app.flyer(gig.flyKey);
    final presenter = gig.createdByBand == null
        ? null
        : app.band(gig.createdByBand!);
    final lineupLine = performers
        .map((performer) => performer.name)
        .join(' · ');

    final content = Padding(
      padding: EdgeInsets.fromLTRB(22, headerTopPad(context) + 8, 22, 20),
      child: Stack(
        key: const ValueKey('gig-detail-hero-content'),
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (presenter != null) ...[
                        EpEyebrow.accent('${presenter.name} presents'),
                        const SizedBox(height: 9),
                      ],
                      Flexible(
                        child: EpDisplay(
                          gig.title,
                          size: 48,
                          color: fly.fg,
                          maxLines: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (lineupLine.isNotEmpty)
                EpMonoText(lineupLine, color: fly.fg.withValues(alpha: .85)),
            ],
          ),
          Positioned(
            left: -8,
            top: -2,
            child: EpIconPill(
              icon: Icons.arrow_back,
              semanticLabel: 'Back',
              onPressed: onBack,
              color: fly.fg,
            ),
          ),
          Positioned(
            right: -8,
            top: -2,
            child: previewLabel == null
                ? _HeroActions(gig: gig, app: app, color: fly.fg)
                : _PreviewStatusBadge(label: previewLabel!),
          ),
        ],
      ),
    );

    final bytes = flyerBytes;
    if (bytes != null) {
      return RepaintBoundary(
        child: SizedBox(
          height: _height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                bytes,
                fit: BoxFit.cover,
                cacheHeight: (_height * MediaQuery.devicePixelRatioOf(context))
                    .round(),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black54,
                      Colors.transparent,
                      Colors.black87,
                    ],
                    stops: [0, .42, 1],
                  ),
                ),
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
        height: _height,
        radius: 0,
        shadow: false,
        scrim: gig.flyKey == 'custom',
        child: content,
      ),
    );
  }
}

class _HeroActions extends StatelessWidget {
  const _HeroActions({
    required this.gig,
    required this.app,
    required this.color,
  });

  final Gig gig;
  final AppState app;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final saved = app.saved.contains(gig.id);
    return Row(
      children: [
        EpIconPill(
          key: ValueKey('gig-detail-save-${gig.id}'),
          icon: saved ? Icons.favorite : Icons.favorite_border,
          semanticLabel: saved ? 'Remove saved event' : 'Save',
          onPressed: () => app.requestSave(gig.id),
          color: color,
        ),
        const SizedBox(width: 6),
        EpIconPill(
          key: ValueKey('gig-detail-share-${gig.id}'),
          icon: Icons.ios_share,
          semanticLabel: 'Share',
          color: color,
          onPressed: () => copyForUser(
            context,
            publicWebUrl('g/${gig.publicRef}'),
            successMessage:
                'Link copied: ${publicWebDisplayUrl('g/${gig.publicRef}')}',
          ),
        ),
      ],
    );
  }
}

/// The editor preview's lifecycle chip. Its 32px height is part of the
/// preview contract, so it stays a plain container rather than a pill
/// primitive.
class _PreviewStatusBadge extends StatelessWidget {
  const _PreviewStatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('gig-draft-preview-status'),
    constraints: const BoxConstraints(minHeight: 32),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .72),
      border: Border.all(color: Ep.whiteA(.35)),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: epText(
        size: 10.5,
        weight: FontWeight.w900,
        letterSpacing: .7,
        color: Ep.whiteA(1),
      ),
    ),
  );
}

/// When / where on one hairline row, then cover / age / going on the next.
class _FactsSection extends StatelessWidget {
  const _FactsSection({
    required this.gig,
    required this.app,
    required this.venue,
    required this.venueSet,
    required this.interactive,
  });

  final Gig gig;
  final AppState app;
  final Venue venue;
  final bool venueSet;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final area = venue.area.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EpFactGrid(
          columns: 2,
          cells: [
            EpFactCell(
              label: 'When',
              value: gig.dateShort,
              sub: 'Doors ${gig.doorsLabel} · Start ${_startLabel(gig.time)}',
            ),
            InkWell(
              onTap: interactive && venueSet
                  ? () => app.openVenue(venue.id)
                  : null,
              child: EpFactCell(
                label: 'Where',
                value: venueSet ? venue.name : 'Venue not set',
                sub: venueSet && area.isNotEmpty ? area : null,
              ),
            ),
          ],
        ),
        EpFactGrid(
          columns: 3,
          cells: [
            EpFactCell(label: 'Cover', value: gig.priceLabel),
            EpFactCell(
              label: 'Age',
              value: gig.ageRequirement == AgeRequirement.allAges
                  ? 'All'
                  : gig.ageRequirement.label,
            ),
            if (gig.tix == Ticketing.rsvp)
              EpFactCell(label: 'Going', value: '${app.rsvpCount(gig)}'),
          ],
        ),
      ],
    );
  }
}

/// "8PM / 9PM" holds doors and start; [Gig.doorsLabel] owns the first half.
String _startLabel(String time) {
  final separator = time.indexOf(' / ');
  return separator == -1 ? time : time.substring(separator + 3);
}

String _initialsFor(String name) {
  final words = name.trim().split(RegExp(r'\s+'))
    ..removeWhere((word) => word.isEmpty);
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, 1);
  return '${words.first.substring(0, 1)}${words.last.substring(0, 1)}';
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
    final role = switch (performer.role) {
      GigPerformerRole.headliner => 'Headliner',
      GigPerformerRole.support => 'Support',
      GigPerformerRole.opener => 'Opener',
    };
    final genreLine = band?.genreLine ?? '';
    return EpEntityRow(
      leading: band == null
          ? EpAvatarTile(initials: _initialsFor(performer.name))
          : BandAvatar(band),
      title: performer.name,
      sub: genreLine.isEmpty ? role : '$role · $genreLine',
      onTap: interactive && band != null ? () => app.openBand(band.id) : null,
      trailing: !interactive || band == null
          ? null
          : EpPill(
              key: ValueKey('gig-lineup-follow-${band.id}'),
              label: app.follows.contains(band.id) ? 'Following ✓' : 'Follow',
              onPressed: () => app.requestFollow(band.id),
            ),
    );
  }
}

/// The venue map, its verification badge and the address line under it.
class _VenueMapSection extends StatelessWidget {
  const _VenueMapSection({
    required this.venue,
    required this.app,
    required this.interactive,
  });

  final Venue venue;
  final AppState app;
  final bool interactive;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: interactive ? () => app.openVenue(venue.id) : null,
          child: EpPanel(
            child: VenueMiniMap(
              venue: venue,
              approximate: venue.exactPoint == null,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (venue.verified) ...[
              const EpBadge(key: Key('gig-venue-verified'), label: 'Verified'),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                venue.exactAddress ?? '${venue.area} · Approx. area',
                style: Theme.of(
                  context,
                ).textTheme.epBody.copyWith(color: context.epColors.muted),
              ),
            ),
            if (interactive && venue.exactPoint != null) ...[
              const SizedBox(width: 8),
              EpPill(
                key: const Key('gig-venue-directions'),
                label: 'Directions ↗',
                onPressed: () => openExternalForUser(
                  context,
                  'https://www.google.com/maps/search/?api=1&query='
                  '${venue.point.latitude},${venue.point.longitude}',
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
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
          EpDisplay('$going+ GOING', size: 22),
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
                        color: context.epColors.muted,
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
                        backgroundColor: context.epColors.line,
                        color: context.epColors.accent,
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

/// The one docked action: RSVP, tickets or the read-only preview stand-in.
class _GigCta extends StatelessWidget {
  const _GigCta({
    required this.gig,
    required this.app,
    required this.previewLabel,
  });

  final Gig gig;
  final AppState app;
  final String? previewLabel;

  @override
  Widget build(BuildContext context) {
    if (previewLabel != null) return _preview();
    if (gig.lifecycle == GigLifecycle.cancelled) {
      return const EpBottomCta(child: _CtaPill(label: 'Gig cancelled'));
    }
    if (gig.sellsTickets) return _tickets(context);
    return _rsvp(context);
  }

  Widget _preview() {
    final (hint, label) = gig.tix == Ticketing.external
        ? ('External ticketing · preview only', 'Tickets ↗')
        : gig.free
        ? ('Free RSVP · preview only', 'RSVP')
        : (
            'Pay at the door · preview only',
            'RSVP — ${gig.priceLabel} AT DOOR',
          );
    return EpBottomCta(
      hint: hint,
      child: _CtaPill(label: label),
    );
  }

  Widget _tickets(BuildContext context) => EpBottomCta(
    hint: gig.ticketSeller?.kind == TicketSellerKind.band
        ? 'Tickets are sold by ${gig.ticketSeller!.name} · EarPlug fee added at checkout'
        : 'Tickets are sold by the organizer · EarPlug fee added at checkout',
    child: _CtaPill(
      key: const Key('gig-buy-tickets'),
      label: 'Buy tickets · ${gig.priceLabel}',
      variant: EpPillVariant.primary,
      onPressed: app.authed
          ? () => showTicketPurchaseSheet(context, gig)
          : () => app.requestTickets(gig.id),
    ),
  );

  Widget _rsvp(BuildContext context) {
    final external = gig.tix == Ticketing.external;
    final hint = external
        ? 'External ticketing'
        : gig.free
        ? 'Free. RSVP for headcount'
        : 'Pay at the door · RSVP holds nothing';

    final Widget pill;
    if (external) {
      pill = _CtaPill(
        label: 'Tickets ↗',
        onPressed: () {
          final url = gig.externalUrl;
          if (url == null) {
            app.say('No ticket link listed for this gig.');
          } else {
            openExternalForUser(context, url);
          }
        },
      );
    } else if (app.rsvps.contains(gig.id)) {
      pill = _CtaPill(
        label: 'Going ✓',
        selected: true,
        onPressed: () => app.toggleRsvp(gig.id),
      );
    } else {
      pill = _CtaPill(
        label: gig.free ? 'RSVP' : 'RSVP — ${gig.priceLabel} AT DOOR',
        variant: EpPillVariant.primary,
        onPressed: () => app.requestRsvp(gig.id),
      );
    }
    return EpBottomCta(hint: hint, child: pill);
  }
}

class _CtaPill extends StatelessWidget {
  const _CtaPill({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = EpPillVariant.outline,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final EpPillVariant variant;
  final bool selected;

  @override
  Widget build(BuildContext context) => EpPill(
    label: label,
    onPressed: onPressed,
    variant: variant,
    selected: selected,
    size: EpPillSize.large,
    expand: true,
  );
}
