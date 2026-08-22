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
    return Container(
      padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 10),
      decoration: const BoxDecoration(
        color: Ep.background,
        border: Border(bottom: BorderSide(color: Ep.border)),
      ),
      child: Row(
        children: [
          CircleIconButton(onTap: onBack),
          const SizedBox(width: 10),
          Text(
            'VENUE',
            style: Theme.of(context).textTheme.epLabel.copyWith(
              letterSpacing: 1.4,
              color: Ep.contentSecondary,
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
              style: Theme.of(
                context,
              ).textTheme.epBody.copyWith(color: Ep.contentSecondary),
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

class _VenueContent extends StatelessWidget {
  const _VenueContent({required this.detail, required this.app});

  final VenueDetail detail;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final venue = detail.venue;
    final gigs = [...detail.gigs]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final performerIds = <String>[];
    final seen = <String>{};
    for (final gig in gigs) {
      for (final bandId in gig.lineup) {
        if (detail.bands.containsKey(bandId) && seen.add(bandId)) {
          performerIds.add(bandId);
        }
      }
    }

    return ListView(
      key: const Key('venue-detail-content'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text(
          venue.name.toUpperCase(),
          style: Theme.of(context).textTheme.epPageHeading,
        ),
        const SizedBox(height: 7),
        Text(venue.addr, style: Theme.of(context).textTheme.epBody),
        const SizedBox(height: 3),
        Text(
          '${venue.area} · ${app.distanceOf(venue)}',
          key: const Key('venue-detail-distance'),
          style: Theme.of(context).textTheme.epCaption,
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: VenueMiniMap(venue: venue),
        ),
        const SizedBox(height: 18),
        const SectionLabel('UPCOMING EVENTS', blue: true),
        const SizedBox(height: 8),
        if (gigs.isEmpty)
          DashedBox(
            child: Text(
              'Nothing on the calendar right now.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.epBody.copyWith(color: Ep.contentSecondary),
            ),
          ),
        for (final gig in gigs) ...[
          FanEventCard(gig: gig, app: app),
          const SizedBox(height: 9),
        ],
        if (detail.truncated) ...[
          Text(
            'Showing the next 200 events.',
            key: const Key('venue-detail-truncated'),
            style: Theme.of(context).textTheme.epCaption,
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 10),
        const SectionLabel('PERFORMING BANDS'),
        const SizedBox(height: 8),
        if (performerIds.isEmpty)
          Text(
            'No performers announced yet.',
            style: Theme.of(context).textTheme.epCaption,
          ),
        for (final bandId in performerIds) ...[
          _PerformerRow(band: detail.bands[bandId]!, app: app),
          const SizedBox(height: 7),
        ],
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
          const Icon(Icons.chevron_right, size: 18, color: Ep.contentSecondary),
        ],
      ),
    );
  }
}
