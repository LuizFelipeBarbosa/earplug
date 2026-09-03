import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/fan_event_card.dart';
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
        _Header(onBack: app.back),
        Expanded(
          child: detail != null
              ? _VenueContent(detail: detail, app: app)
              : _VenueState(venueId: widget.venueId, app: app),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ScreenHeader(
      child: Row(
        children: [
          CircleIconButton(onTap: onBack),
          const SizedBox(width: 10),
          Text(
            'VENUE',
            style: Theme.of(context).textTheme.epLabel.copyWith(
              letterSpacing: 1.4,
              color: context.epColors.contentSecondary,
            ),
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
        title: "COULDN'T LOAD THIS VENUE",
        message: 'The venue details are unavailable right now.',
        action: EpButton(
          'RETRY',
          key: const Key('venue-detail-retry'),
          kind: EpButtonKind.outline,
          onTap: () => app.retryVenueDetail(venueId),
        ),
      );
    }
    if (app.venueDetailMissing(venueId)) {
      return const _CenteredState(
        title: 'VENUE NOT FOUND',
        message: 'This venue may have been removed.',
      );
    }
    return const _CenteredState(
      title: 'LOADING VENUE…',
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
              const SizedBox(height: 14),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.epSectionHeading,
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.epBody.copyWith(
                color: context.epColors.contentSecondary,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              SizedBox(width: 140, child: action),
            ],
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
    final rows = <_VenueContentRow>[
      const _VenueHeroRow(),
      const _VenueMapRow(),
      _VenueSectionRow('UPCOMING EVENTS', _gigs.length),
      if (_gigs.isEmpty)
        const _VenueEmptyEventsRow()
      else
        for (final gig in _gigs) _VenueGigRow(gig),
      if (widget.detail.truncated) const _VenueTruncatedRow(),
      _VenueSectionRow('PERFORMING BANDS', _performerIds.length),
      if (_performerIds.isEmpty)
        const _VenueEmptyPerformersRow()
      else
        for (final bandId in _performerIds) _VenuePerformerRow(bandId),
    ];

    return ListView.builder(
      key: const Key('venue-detail-content'),
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: rows.length,
      itemBuilder: (context, index) => _buildRow(context, rows[index]),
    );
  }

  Widget _buildRow(BuildContext context, _VenueContentRow row) {
    final detail = widget.detail;
    final app = widget.app;
    return switch (row) {
      _VenueHeroRow() => _VenueHero(
        venue: detail.venue,
        distance: app.distanceOf(detail.venue),
      ),
      _VenueMapRow() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: VenueMiniMap(venue: detail.venue),
        ),
      ),
      _VenueSectionRow(:final label, :final count) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SectionBar(
          label: label,
          trailing: Text(
            '$count',
            style: Theme.of(context).textTheme.epCaption,
          ),
        ),
      ),
      _VenueEmptyEventsRow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DashedBox(
          child: Text(
            'Nothing on the calendar right now.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.epBody.copyWith(
              color: context.epColors.contentSecondary,
            ),
          ),
        ),
      ),
      _VenueGigRow(:final gig) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 9),
        child: FanEventCard(gig: gig, app: app),
      ),
      _VenueTruncatedRow() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          'Showing the next 200 events.',
          key: const Key('venue-detail-truncated'),
          style: Theme.of(context).textTheme.epCaption,
        ),
      ),
      _VenueEmptyPerformersRow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'No performers announced yet.',
          style: Theme.of(context).textTheme.epCaption,
        ),
      ),
      _VenuePerformerRow(:final bandId) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
        child: _PerformerRow(band: detail.bands[bandId]!, app: app),
      ),
    };
  }
}

sealed class _VenueContentRow {
  const _VenueContentRow();
}

class _VenueHeroRow extends _VenueContentRow {
  const _VenueHeroRow();
}

class _VenueMapRow extends _VenueContentRow {
  const _VenueMapRow();
}

class _VenueSectionRow extends _VenueContentRow {
  const _VenueSectionRow(this.label, this.count);

  final String label;
  final int count;
}

class _VenueEmptyEventsRow extends _VenueContentRow {
  const _VenueEmptyEventsRow();
}

class _VenueGigRow extends _VenueContentRow {
  const _VenueGigRow(this.gig);

  final Gig gig;
}

class _VenueTruncatedRow extends _VenueContentRow {
  const _VenueTruncatedRow();
}

class _VenueEmptyPerformersRow extends _VenueContentRow {
  const _VenueEmptyPerformersRow();
}

class _VenuePerformerRow extends _VenueContentRow {
  const _VenuePerformerRow(this.bandId);

  final String bandId;
}

class _VenueHero extends StatelessWidget {
  const _VenueHero({required this.venue, required this.distance});

  final Venue venue;
  final String distance;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const Key('venue-detail-hero'),
          constraints: const BoxConstraints(minHeight: 150),
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 28),
          decoration: BoxDecoration(
            color: Ep.brand,
            border: Border(
              bottom: BorderSide(color: context.epColors.accent, width: 2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                [
                  'VENUE',
                  if (venue.area.trim().isNotEmpty) venue.area.toUpperCase(),
                ].join(' · '),
                style: Theme.of(
                  context,
                ).textTheme.epSection.copyWith(color: Ep.ink),
              ),
              const SizedBox(height: 8),
              Text(
                venue.name.toUpperCase(),
                style: Theme.of(
                  context,
                ).textTheme.epPosterTitle.copyWith(color: Ep.ink),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Transform.translate(
            offset: const Offset(0, -12),
            child: EpCard(
              variant: EpCardVariant.raised,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(venue.addr, style: Theme.of(context).textTheme.epBody),
                  const SizedBox(height: 5),
                  Text(
                    [
                      if (venue.area.trim().isNotEmpty) venue.area,
                      distance,
                    ].join(' · '),
                    key: const Key('venue-detail-distance'),
                    style: Theme.of(context).textTheme.epCaption,
                  ),
                ],
              ),
            ),
          ),
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
    return EpCard(
      key: ValueKey('venue-band-${band.id}'),
      padding: const EdgeInsets.all(9),
      onTap: () => app.openBand(band.id),
      child: Row(
        children: [
          BandAvatar(band, size: 38, radius: 8, fontSize: 12),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  band.name.toUpperCase(),
                  style: Theme.of(context).textTheme.epLabel,
                ),
                Text(
                  band.genreLine,
                  style: Theme.of(context).textTheme.epCaption,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: context.epColors.contentSecondary,
          ),
        ],
      ),
    );
  }
}
