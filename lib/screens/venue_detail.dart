import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/map_view.dart';

class VenueDetailScreen extends StatefulWidget {
  const VenueDetailScreen({super.key, required this.venueId});

  final String venueId;

  @override
  State<VenueDetailScreen> createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends State<VenueDetailScreen> {
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().venueDetail(widget.venueId);
      setState(() => _requested = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final detail = _requested ? app.venueDetail(widget.venueId) : null;

    return Column(
      children: [
        _TopBar(onBack: app.back),
        Expanded(
          child: detail != null
              ? _VenueContent(detail: detail, app: app)
              : _VenueState(venueId: widget.venueId, app: app),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        EpLayout.gutter,
        headerTopPad(context),
        EpLayout.gutter,
        0,
      ),
      child: Row(
        children: [
          EpIconPill(
            icon: Icons.arrow_back,
            semanticLabel: 'Back',
            onPressed: onBack,
          ),
        ],
      ),
    );
  }
}

class _VenueState extends StatelessWidget {
  const _VenueState({required this.venueId, required this.app});

  final String venueId;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final error = app.venueDetailError(venueId);
    if (error != null) {
      return _CenteredState(
        title: "Couldn't load this venue",
        message: 'The venue details are unavailable right now.',
        action: EpPill(
          key: const Key('venue-detail-retry'),
          label: 'Retry',
          size: EpPillSize.regular,
          onPressed: () => app.retryVenueDetail(venueId),
        ),
      );
    }
    if (app.venueDetailMissing(venueId)) {
      return const _CenteredState(
        title: 'Venue not found',
        message: 'This venue may have been removed.',
      );
    }
    return const _CenteredState(
      title: 'Loading venue…',
      message: 'Finding the next shows.',
      progress: true,
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.title,
    required this.message,
    this.action,
    this.progress = false,
  });

  final String title;
  final String message;
  final Widget? action;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (progress) ...[
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 16),
            ],
            EpDisplay(title, size: 24, maxLines: 3, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.epBody.copyWith(color: context.epColors.muted),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class _VenueContent extends StatefulWidget {
  const _VenueContent({required this.detail, required this.app});

  final VenueDetail detail;
  final AppState app;

  @override
  State<_VenueContent> createState() => _VenueContentState();
}

class _VenueContentState extends State<_VenueContent> {
  late List<Gig> _gigs;
  late List<String> _performerIds;

  @override
  void initState() {
    super.initState();
    _cacheRelationships();
  }

  @override
  void didUpdateWidget(covariant _VenueContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.detail, widget.detail)) {
      _cacheRelationships();
    }
  }

  void _cacheRelationships() {
    final gigs = [...widget.detail.gigs]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final performerIds = <String>[];
    final seen = <String>{};
    for (final gig in gigs) {
      for (final bandId in gig.lineup) {
        if (widget.detail.bands.containsKey(bandId) && seen.add(bandId)) {
          performerIds.add(bandId);
        }
      }
    }
    _gigs = List.unmodifiable(gigs);
    _performerIds = List.unmodifiable(performerIds);
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final app = widget.app;
    final venue = detail.venue;

    return ListView(
      key: const Key('venue-detail-content'),
      padding: const EdgeInsets.fromLTRB(
        EpLayout.gutter,
        28,
        EpLayout.gutter,
        40,
      ),
      children: [
        _VenueHeader(venue: venue),
        const SizedBox(height: 20),
        EpPanel(
          height: 160,
          child: VenueMiniMap(
            key: const Key('venue-detail-map'),
            venue: venue,
            approximate: venue.exactAddress == null,
          ),
        ),
        _VenueFacts(venue: venue, distance: app.distanceOf(venue)),
        EpSectionHeader(label: 'Upcoming · ${_gigs.length}'),
        if (_gigs.isEmpty)
          const _QuietNote('Nothing on the calendar right now.')
        else
          for (final gig in _gigs)
            EpGigRow(
              key: ValueKey('fan-event-${gig.id}'),
              date: gig.startsAt,
              title: gig.title,
              sub: _gigSubtitle(gig, detail.bands),
              onTap: () => app.openGig(gig.id),
            ),
        if (detail.truncated)
          const _QuietNote(
            'Showing the next 200 events.',
            key: Key('venue-detail-truncated'),
          ),
        EpSectionHeader(label: 'Performing bands · ${_performerIds.length}'),
        if (_performerIds.isEmpty)
          const _QuietNote('No performers announced yet.')
        else
          for (final bandId in _performerIds)
            _PerformerRow(band: detail.bands[bandId]!, app: app),
      ],
    );
  }
}

/// "Doors 8PM · $10 · Foghorn Diet · Pigeon Court" for one upcoming show.
String _gigSubtitle(Gig gig, Map<String, Band> bands) {
  final doors = gig.doorsLabel.trim();
  return [
    if (doors.isNotEmpty) 'Doors $doors',
    gig.free ? 'Free' : gig.priceLabel,
    for (final bandId in gig.lineup)
      if (bands[bandId] case final band?) band.name,
  ].join(' · ');
}

String _venueTypeLabel(VenueType type) => switch (type) {
  VenueType.bar => 'Bar',
  VenueType.club => 'Club',
  VenueType.hall => 'Hall',
  VenueType.house => 'House',
  VenueType.outdoor => 'Outdoor',
  VenueType.private => 'Private',
  VenueType.other => 'Other',
};

class _VenueHeader extends StatelessWidget {
  const _VenueHeader({required this.venue});

  final Venue venue;

  @override
  Widget build(BuildContext context) {
    final area = venue.area.trim();
    final traits = [
      if (venue.venueType case final type?) _venueTypeLabel(type),
      if (venue.capacityPublic case final capacity?) 'Capacity $capacity',
    ].join(' · ');
    final description = [
      ?venue.description?.trim(),
      if (traits.isNotEmpty) '$traits.',
    ].where((part) => part.isNotEmpty).join(' ');

    return Column(
      key: const Key('venue-detail-hero'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            EpEyebrow.accent(area.isEmpty ? 'Venue' : 'Venue · $area'),
            if (venue.verified)
              const EpBadge(
                key: Key('venue-detail-verified'),
                label: 'Verified',
              ),
          ],
        ),
        const SizedBox(height: 12),
        EpDisplay(venue.name, size: 48, maxLines: 4),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.epBody.copyWith(color: context.epColors.muted),
          ),
        ],
      ],
    );
  }
}

/// Address and distance. Approximate venues never render the exact address.
class _VenueFacts extends StatelessWidget {
  const _VenueFacts({required this.venue, required this.distance});

  final Venue venue;
  final String distance;

  @override
  Widget build(BuildContext context) {
    final approximate = venue.exactAddress == null;
    return EpFactGrid(
      cells: [
        EpFactCell(
          key: approximate ? const Key('venue-detail-approx-note') : null,
          label: 'Address',
          value: approximate ? venue.approx.label : venue.exactAddress!,
          sub: approximate ? 'Shared with ticket holders' : null,
          display: false,
        ),
        EpFactCell(
          key: const Key('venue-detail-distance'),
          label: 'From you',
          value: approximate ? '~$distance' : distance,
        ),
      ],
    );
  }
}

class _PerformerRow extends StatelessWidget {
  const _PerformerRow({required this.band, required this.app});

  final Band band;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return EpEntityRow(
      key: ValueKey('venue-band-${band.id}'),
      leading: BandAvatar(band),
      title: band.name,
      sub: band.genreLine,
      trailing: Icon(
        Icons.chevron_right,
        size: 16,
        color: context.epColors.muted,
      ),
      onTap: () => app.openBand(band.id),
    );
  }
}

/// Muted aside used by the empty and truncated states.
class _QuietNote extends StatelessWidget {
  const _QuietNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.epBody.copyWith(color: context.epColors.muted),
      ),
    );
  }
}
