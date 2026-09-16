import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart' show EpAvatarTile, EpEntityRow;
import '../widgets/ep_sheet.dart' show showEpSheet;
import '../widgets/ep_text.dart';
import '../widgets/explore_tiles.dart';
import '../widgets/sheets.dart' show EpFormSheet;
import '../widgets/ticket_purchase_sheet.dart';
import '../widgets/venue_mini_map.dart';

const _sectionGap = 24.0;
const _titleToFactsGap = 12.0;
const _bottomBreathingRoom = 48.0;
const _headerBarContentHeight = 44 + EpLayout.gutter * 2;

class GigDetailScreen extends StatefulWidget {
  final String gigId;

  const GigDetailScreen({super.key, required this.gigId});

  @override
  State<GigDetailScreen> createState() => _GigDetailScreenState();
}

class _GigDetailScreenState extends State<GigDetailScreen> {
  bool _checkedPendingTicketPurchase = false;

  @override
  void initState() {
    super.initState();
    unawaited(context.read<AppState>().loadKnownAttendees(widget.gigId));
  }

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
class GigDetailPresentation extends StatefulWidget {
  const GigDetailPresentation({
    super.key,
    required this.gig,
    required this.app,
    required this.performers,
    this.previewLabel,
    this.onBack,
    this.flyerBytes,
    this.venueSet = true,
    this.previewCta,
  });

  final Gig gig;
  final AppState app;
  final List<GigPerformer> performers;
  final String? previewLabel;
  final VoidCallback? onBack;
  final Uint8List? flyerBytes;
  final bool venueSet;
  final Widget? previewCta;

  bool get isPreview => previewLabel != null;

  @override
  State<GigDetailPresentation> createState() => _GigDetailPresentationState();
}

class _GigDetailPresentationState extends State<GigDetailPresentation> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() => setState(() {});

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gig = widget.gig;
    final app = widget.app;
    final performers = widget.performers;
    final previewLabel = widget.previewLabel;
    final venueSet = widget.venueSet;
    final venue = app.venue(gig.venueId);
    final interactive = !widget.isPreview;
    final topInset = MediaQuery.paddingOf(context).top;
    final offset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final progress = (offset / 80).clamp(0.0, 1.0);

    return Stack(
      children: [
        ListView(
          controller: _scrollController,
          padding: EdgeInsets.only(
            bottom: actionBarClearance(context) + _bottomBreathingRoom,
          ),
          children: [
            _Hero(
              gig: gig,
              topInset: topInset,
              previewLabel: previewLabel,
              flyerBytes: widget.flyerBytes,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: _sectionGap),
                  _TitleBlock(
                    gig: gig,
                    app: app,
                    venue: venue,
                    venueSet: venueSet,
                    performers: performers,
                    interactive: interactive,
                  ),
                  const SizedBox(height: _titleToFactsGap),
                  _FactsSection(gig: gig),
                  const SizedBox(height: _sectionGap),
                  Column(
                    key: const ValueKey('gig-lineup'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionBar(
                        label: 'LINEUP',
                        count: performers.length,
                        padding: const EdgeInsets.only(bottom: 4),
                      ),
                      for (
                        var index = 0;
                        index < performers.length;
                        index++
                      ) ...[
                        if (index > 0) const EpHairline(),
                        _LineupRow(
                          performer: performers[index],
                          app: app,
                          interactive: interactive,
                        ),
                      ],
                    ],
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
                              const SizedBox(height: _sectionGap),
                              const SectionBar(
                                label: "WHO'S GOING",
                                padding: EdgeInsets.only(bottom: 4),
                              ),
                              _PeopleYouMayKnow(gig: gig, app: app),
                              _WhosGoing(gig: gig, app: app),
                              const EpHairline(),
                            ],
                          )
                        : SizedBox.shrink(
                            key: ValueKey('gig-attendance-hidden-${gig.id}'),
                          ),
                  ),
                  if (gig.desc.trim().isNotEmpty) ...[
                    const SizedBox(height: _sectionGap),
                    const SectionBar(
                      label: 'ABOUT',
                      padding: EdgeInsets.only(bottom: 4),
                    ),
                    Text(
                      gig.desc,
                      style: Theme.of(context).textTheme.epBody.copyWith(
                        color: context.epColors.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: _sectionGap),
                  if (venueSet)
                    _VenueCard(
                      venue: venue,
                      app: app,
                      interactive: interactive,
                    ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _GigDetailHeaderBar(
            gig: gig,
            app: app,
            topInset: topInset,
            progress: progress,
            previewLabel: previewLabel,
            onBack: widget.onBack ?? app.back,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: widget.isPreview && widget.previewCta != null
              ? widget.previewCta!
              : _GigCta(gig: gig, app: app, previewLabel: previewLabel),
        ),
      ],
    );
  }
}

class _CancelledBanner extends StatelessWidget {
  const _CancelledBanner();

  @override
  Widget build(BuildContext context) => Container(
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

/// The full-width flyer leads into compact lifecycle rows below the artwork.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.gig,
    required this.topInset,
    required this.previewLabel,
    required this.flyerBytes,
  });

  final Gig gig;
  final double topInset;
  final String? previewLabel;
  final Uint8List? flyerBytes;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('gig-detail-hero-content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Flyer(gig: gig, topInset: topInset, bytes: flyerBytes),
        if (previewLabel != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              EpLayout.gutter,
              12,
              EpLayout.gutter,
              0,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: IntrinsicWidth(
                child: _PreviewStatusBadge(label: previewLabel!),
              ),
            ),
          ),
        if (gig.lifecycle == GigLifecycle.cancelled)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              EpLayout.gutter,
              12,
              EpLayout.gutter,
              0,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: IntrinsicWidth(child: _CancelledBanner()),
            ),
          ),
      ],
    );
  }
}

class _Flyer extends StatelessWidget {
  const _Flyer({
    required this.gig,
    required this.topInset,
    required this.bytes,
  });

  final Gig gig;
  final double topInset;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final contentHeight = math.min(
        constraints.maxWidth * 1.25,
        MediaQuery.sizeOf(context).height * .6,
      );
      final custom =
          bytes != null || (gig.flyKey == 'custom' && gig.flyerUrl != null);
      return RepaintBoundary(
        key: const ValueKey('gig-detail-flyer'),
        child: SizedBox(
          width: constraints.maxWidth,
          height: topInset + contentHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: context.epColors.background),
              if (custom)
                Positioned.fill(
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: _image(context, BoxFit.cover),
                        ),
                        ColoredBox(
                          color: context.epColors.background.withValues(
                            alpha: .55,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Positioned.fill(
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: ColoredBox(color: context.epColors.panel),
                        ),
                        ColoredBox(
                          color: context.epColors.background.withValues(
                            alpha: .55,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                top: topInset,
                left: 0,
                right: 0,
                height: contentHeight,
                child: custom
                    ? _image(context, BoxFit.contain)
                    : Container(
                        key: const ValueKey('gig-detail-flyer-placeholder'),
                        color: context.epColors.panel,
                        child: Center(
                          child: Icon(
                            Icons.image_outlined,
                            size: 56,
                            color: context.epColors.muted,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _image(BuildContext context, BoxFit fit) {
    final localBytes = bytes;
    if (localBytes != null) return Image.memory(localBytes, fit: fit);
    return EpNetworkImage(
      url: gig.flyerUrl,
      fit: fit,
      fallback: ColoredBox(color: context.epColors.background),
    );
  }
}

class _GigDetailHeaderBar extends StatelessWidget {
  const _GigDetailHeaderBar({
    required this.gig,
    required this.app,
    required this.topInset,
    required this.progress,
    required this.previewLabel,
    required this.onBack,
  });

  final Gig gig;
  final AppState app;
  final double topInset;
  final double progress;
  final String? previewLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.epColors;
    final saved = app.saved.contains(gig.id);
    return Container(
      key: const ValueKey('gig-detail-header-bar'),
      height: _headerBarContentHeight + topInset,
      padding: EdgeInsets.only(top: topInset),
      decoration: BoxDecoration(
        color: Color.lerp(
          colors.background.withValues(alpha: 0),
          colors.background,
          progress,
        ),
      ),
      // Paint the hairline without subtracting from the centered row's height.
      foregroundDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Color.lerp(
              colors.line.withValues(alpha: 0),
              colors.line,
              progress,
            )!,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 44,
              child: Tooltip(
                message: 'Back',
                excludeFromSemantics: true,
                child: ExploreCardIconButton(
                  key: const ValueKey('gig-detail-back-control'),
                  circle: true,
                  icon: Icons.arrow_back,
                  semanticLabel: 'Back',
                  onPressed: onBack,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: progress,
                // Keep the hidden title out of traversal until it fades in.
                child: Offstage(
                  offstage: progress == 0,
                  child: EpDisplay(gig.title, size: 18, maxLines: 1),
                ),
              ),
            ),
            if (previewLabel == null) ...[
              const SizedBox(width: 12),
              SizedBox.square(
                dimension: 44,
                child: ExploreCardIconButton(
                  key: ValueKey('gig-detail-save-${gig.id}'),
                  circle: true,
                  icon: saved ? Icons.favorite : Icons.favorite_border,
                  semanticLabel: saved ? 'Remove saved event' : 'Save',
                  onPressed: () => app.requestSave(gig.id),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox.square(
                dimension: 44,
                child: ExploreCardIconButton(
                  key: ValueKey('gig-detail-share-${gig.id}'),
                  circle: true,
                  icon: Icons.ios_share,
                  semanticLabel: 'Share',
                  onPressed: () => copyForUser(
                    context,
                    publicWebUrl('g/${gig.publicRef}'),
                    successMessage:
                        'Link copied: ${publicWebDisplayUrl('g/${gig.publicRef}')}',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.gig,
    required this.app,
    required this.venue,
    required this.venueSet,
    required this.performers,
    required this.interactive,
  });

  final Gig gig;
  final AppState app;
  final Venue venue;
  final bool venueSet;
  final List<GigPerformer> performers;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final presenter = gig.createdByBand == null
        ? null
        : app.band(gig.createdByBand!);
    return Padding(
      key: const ValueKey('gig-detail-title-block'),
      padding: EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (presenter != null) ...[
                  EpEyebrow.accent('${presenter.name} presents'),
                  const SizedBox(height: 9),
                ],
                EpDisplay(gig.title, size: 32, maxLines: 3),
              ],
            ),
          ),
          if (interactive) _buildActions(context),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox.square(
        dimension: 44,
        child: Tooltip(
          message: 'Add to calendar',
          excludeFromSemantics: true,
          child: ExploreCardIconButton(
            key: const ValueKey('gig-add-to-calendar'),
            ring: true,
            icon: Icons.calendar_today_outlined,
            semanticLabel: 'Add to calendar',
            onPressed: () => openCalendar(
              context,
              gig,
              venueSet ? venue : null,
              presenterOrLineupLine: presenterOrLineupLine(
                gig,
                app,
                performers,
              ),
            ),
          ),
        ),
      ),
      if (venueSet && venue.exactAddress != null) ...[
        const SizedBox(width: 8),
        SizedBox.square(
          dimension: 44,
          child: Tooltip(
            message: 'Directions',
            excludeFromSemantics: true,
            child: ExploreCardIconButton(
              key: const ValueKey('gig-venue-directions'),
              ring: true,
              icon: Icons.directions_outlined,
              semanticLabel: 'Directions',
              onPressed: () => openDirections(context, venue),
            ),
          ),
        ),
      ],
    ],
  );
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

String? presenterOrLineupLine(
  Gig gig,
  AppState app,
  List<GigPerformer> performers,
) {
  final presenter = gig.createdByBand == null
      ? null
      : app.band(gig.createdByBand!);
  if (presenter != null) return 'Presented by ${presenter.name}';
  if (performers.isEmpty) return null;
  return 'Lineup: ${performers.map((performer) => performer.name).join(', ')}';
}

/// Date and admission read as open lines, divided by hairlines.
class _FactsSection extends StatelessWidget {
  const _FactsSection({required this.gig});

  final Gig gig;

  @override
  Widget build(BuildContext context) {
    final doors = gig.doorsLabel.trim();
    final start = _startLabel(gig.time);
    final line2 = [
      if (doors.isNotEmpty) 'Doors $doors',
      if (start.isNotEmpty) 'Start $start',
    ].join(' · ');
    return Column(
      key: const Key('gig-facts'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: const Key('gig-fact-date'),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EpDisplay(gig.dateShort, size: 20),
                    if (line2.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      EpMonoText(
                        line2,
                        key: const ValueKey('gig-fact-times'),
                        keepCase: true,
                        color: context.epColors.muted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const EpHairline(),
        Padding(
          key: const Key('gig-fact-meta'),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: _MonoLine(
            size: 15,
            tokens: [
              EpMonoText(
                gig.free ? 'FREE' : gig.priceLabel,
                size: 15,
                color: gig.free
                    ? context.epColors.accent
                    : context.epColors.ink,
              ),
              EpMonoText(
                gig.ageRequirement.label.toUpperCase(),
                size: 15,
                color: context.epColors.muted,
              ),
            ],
          ),
        ),
        const EpHairline(),
      ],
    );
  }
}

/// "8PM / 9PM" holds doors and start; a single time has no separate start.
String _startLabel(String time) {
  final separator = time.indexOf(' / ');
  return separator == -1 ? '' : time.substring(separator + 3).trim();
}

String _venueLocation(Venue venue) {
  final neighborhood = venue.neighborhood?.trim() ?? '';
  return neighborhood.isEmpty ? venue.area.trim() : neighborhood;
}

/// Keep tokens separate so price and neutral copy retain their
/// own styling and semantics, while the line can wrap on narrow screens.
class _MonoLine extends StatelessWidget {
  const _MonoLine({required this.tokens, this.size = 11});

  final List<Widget> tokens;
  final double size;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    runSpacing: 4,
    children: [
      for (var index = 0; index < tokens.length; index++) ...[
        if (index > 0)
          EpMonoText(' · ', size: size, color: context.epColors.muted),
        tokens[index],
      ],
    ],
  );
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
      subMaxLinesOne: true,
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

/// A venue link with its area, distance and available directions.
class _VenueCard extends StatelessWidget {
  const _VenueCard({
    required this.venue,
    required this.app,
    required this.interactive,
  });

  final Venue venue;
  final AppState app;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final area = _venueLocation(venue);
    final distance = app.distanceOf(venue);
    return Container(
      key: const Key('gig-venue-card'),
      decoration: BoxDecoration(
        color: context.epColors.panel,
        border: Border.all(color: context.epColors.line),
      ),
      child: InkWell(
        onTap: interactive ? () => app.openVenue(venue.id) : null,
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: VenueMapPreview(
                venue: venue,
                height: 96,
                showAttribution: false,
                approximate: venue.exactAddress == null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EpDisplay(venue.name, size: 18, maxLines: 2),
                  const SizedBox(height: 4),
                  _MonoLine(
                    tokens: [
                      if (area.isNotEmpty)
                        EpMonoText(area, color: context.epColors.muted),
                      if (distance.isNotEmpty)
                        EpMonoText(distance, color: context.epColors.muted),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (venue.exactAddress != null)
                    EpMonoText(
                      venue.exactAddress!,
                      color: context.epColors.muted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    EpMonoText(
                      'Area only · shared with ticket holders',
                      color: context.epColors.muted,
                    ),
                ],
              ),
            ),
            if (venue.exactAddress != null && interactive) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ExploreCardIconButton(
                  key: const ValueKey('gig-venue-card-directions'),
                  ring: true,
                  icon: Icons.directions_outlined,
                  semanticLabel: 'Directions',
                  onPressed: () => openDirections(context, venue),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _peopleYouMayKnowLine(int count) => count == 1
    ? '1 person you may know is going'
    : '$count people you may know are going';

Future<void> _openKnownPeopleSheet(
  BuildContext context,
  List<KnownAttendee> people,
) {
  return showEpSheet(
    context,
    (_) => EpFormSheet(
      key: const ValueKey('gig-people-sheet'),
      title: 'People you may know',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final person in people)
            EpEntityRow(
              key: ValueKey('known-person-${person.userId}'),
              leading: EpFanAvatar(
                name: person.name,
                imageUrl: person.avatarUrl,
                size: 32,
              ),
              title: person.name,
              sub: person.relation == KnownRelation.friend
                  ? 'Friend'
                  : 'Seen at ${person.sharedShows} show${person.sharedShows == 1 ? '' : 's'}',
            ),
        ],
      ),
    ),
  );
}

class _PeopleYouMayKnow extends StatelessWidget {
  const _PeopleYouMayKnow({required this.gig, required this.app});

  final Gig gig;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final known = app.knownAttendeesFor(gig.id);
    final people = known?.people ?? const <KnownAttendee>[];
    if (people.isEmpty) return const SizedBox.shrink();

    final shown = people.take(6).toList();
    final overflow = people.length - shown.length;

    return Column(
      key: const ValueKey('gig-people-you-know'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionBar(
          label: 'PEOPLE YOU MAY KNOW',
          count: people.length,
          padding: const EdgeInsets.only(bottom: 4),
        ),
        InkWell(
          onTap: () => _openKnownPeopleSheet(context, people),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final person in shown) ...[
                      ImageFiltered(
                        key: ValueKey('gig-people-blur-${person.userId}'),
                        imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                        child: EpFanAvatar(
                          name: person.name,
                          imageUrl: person.avatarUrl,
                          size: 40,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (overflow > 0)
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        color: context.epColors.panel,
                        child: EpMonoText(
                          '+$overflow',
                          color: context.epColors.muted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _peopleYouMayKnowLine(people.length),
                  style: Theme.of(
                    context,
                  ).textTheme.epCaption.copyWith(color: context.epColors.muted),
                ),
              ],
            ),
          ),
        ),
        const EpHairline(),
      ],
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

    return Padding(
      key: ValueKey('who-is-going-${gig.id}'),
      padding: const EdgeInsets.symmetric(vertical: 14),
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
                        color: context.epColors.ink,
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
        ? 'Free · RSVP for headcount'
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
