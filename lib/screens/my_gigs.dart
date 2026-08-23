import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../genres.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/fan_event_card.dart';
import '../widgets/sheets.dart';

class MyGigsScreen extends StatelessWidget {
  const MyGigsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final profile = app.profile;
    final profileName = profile?.name.trim();
    final displayName = profileName == null || profileName.isEmpty
        ? 'YOUR PROFILE'
        : profileName.toUpperCase();
    final fanSince = profile == null ? null : monthLabel(profile.createdAt);
    final upcoming = [
      for (final id in app.rsvps)
        if (app.gig(id) case final Gig g) g,
    ];
    final savedGigs = [
      for (final id in app.saved)
        if (app.gig(id) case final Gig g) g,
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: [
        Row(
          children: [
            EpProfileAvatar(name: profileName, size: 56, radius: 16),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.epSectionHeading,
                  ),
                  Text(
                    '${app.gigsAttended} gigs attended'
                    '${fanSince == null ? '' : ' · fan since $fanSince'}',
                    style: Theme.of(context).textTheme.epCaption,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (app.showFanOnboarding) ...[
          _FanSetup(app: app),
          const SizedBox(height: 16),
        ],
        _BandEntry(app: app),
        const SizedBox(height: 16),
        const SectionLabel("UPCOMING: YOU'RE GOING", blue: true),
        const SizedBox(height: 8),
        if (upcoming.isEmpty)
          DashedBox(
            child: Text(
              'No RSVPs yet. Go find a show.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.epBody.copyWith(color: Ep.contentSecondary),
            ),
          ),
        for (final g in upcoming) ...[
          FanEventCard(
            gig: g,
            app: app,
            trailingAction: _QrAction(gig: g, venue: app.venue(g.venueId)),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        const SectionLabel('SAVED'),
        const SizedBox(height: 8),
        if (savedGigs.isEmpty)
          Text(
            'Nothing saved. Tap the bookmark on a gig to stash it here.',
            style: Theme.of(context).textTheme.epCaption,
          ),
        for (final g in savedGigs) ...[
          FanEventCard(gig: g, app: app),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        const SectionLabel('FOLLOWING'),
        const SizedBox(height: 8),
        if (app.follows.isEmpty)
          Text(
            'Not following any bands yet.',
            style: Theme.of(context).textTheme.epCaption,
          ),
        for (final id in app.follows.toList())
          if (app.band(id) != null) ...[
            _FollowRow(bandId: id, app: app),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 8),
        const SectionLabel('HISTORY'),
        const SizedBox(height: 6),
        if (app.history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No gigs on record yet. RSVP and show up, and this fills itself in.',
              style: Theme.of(context).textTheme.epCaption,
            ),
          ),
        for (final p in app.history)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Ep.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    p.title,
                    style: Theme.of(context).textTheme.epBody,
                  ),
                ),
                const SizedBox(width: 8),
                Text(p.meta, style: Theme.of(context).textTheme.epCaption),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Your history powers new-vs-returning fan stats for bands. It is always aggregated, never named.',
          style: Theme.of(context).textTheme.epCaption,
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: app.signOut,
          child: Text(
            'SIGN OUT',
            style: Theme.of(context).textTheme.epLabel.copyWith(
              letterSpacing: 1,
              color: Ep.contentSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _FanSetup extends StatelessWidget {
  const _FanSetup({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final onboarding = app.fanOnboarding;
    if (onboarding == null) return const SizedBox.shrink();
    if (onboarding.collapsed) {
      return EpCard(
        key: const Key('fan-setup-collapsed'),
        padding: const EdgeInsets.all(14),
        onTap: () => app.setFanOnboardingCollapsed(false),
        child: Row(
          children: [
            const Icon(Icons.tune, color: Ep.accent),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FINISH SETUP',
                    style: Theme.of(context).textTheme.epLabel,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Pick your city and sound, then save a show.',
                    style: Theme.of(context).textTheme.epCaption,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Ep.contentSecondary),
          ],
        ),
      );
    }

    return EpCard(
      key: const Key('fan-setup-expanded'),
      variant: EpCardVariant.raised,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MAKE EARPLUG YOURS', style: epDisplay(size: 19)),
          const SizedBox(height: 4),
          Text(
            'Three quick steps to tune what you see.',
            style: Theme.of(context).textTheme.epCaption,
          ),
          const SizedBox(height: 16),
          _SetupStep(
            number: 1,
            complete: onboarding.preferredCity != null,
            title: 'Choose where you browse',
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                EpChip(
                  key: const Key('fan-city-sf'),
                  label: 'SAN FRANCISCO',
                  active: onboarding.preferredCity == FanCity.sf,
                  onTap: () => app.selectFanCity(FanCity.sf),
                ),
                EpChip(
                  key: const Key('fan-city-oak'),
                  label: 'OAKLAND',
                  active: onboarding.preferredCity == FanCity.oak,
                  onTap: () => app.selectFanCity(FanCity.oak),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          _SetupStep(
            number: 2,
            complete: onboarding.genreChoice != FanGenreChoice.pending,
            title: 'Choose genres, or stay open',
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final genre in kGenres)
                  EpChip(
                    key: ValueKey('fan-genre-$genre'),
                    label: genre,
                    active:
                        onboarding.genreChoice == FanGenreChoice.selected &&
                        app.userGenres.contains(genre),
                    onTap: () => app.toggleFanGenre(genre),
                  ),
                EpChip(
                  key: const Key('fan-genres-open'),
                  label: "I'M OPEN",
                  active: onboarding.genreChoice == FanGenreChoice.open,
                  onTap: app.chooseOpenGenres,
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          _SetupStep(
            number: 3,
            complete: app.saved.isNotEmpty,
            title: 'Find and save a show',
            child: app.saved.isEmpty
                ? TextButton(
                    key: const Key('fan-setup-find-show'),
                    onPressed: () => app.resetTo(Screen.home),
                    child: const Text('FIND A SHOW'),
                  )
                : Text(
                    'A show is saved in My Gigs.',
                    style: Theme.of(
                      context,
                    ).textTheme.epCaption.copyWith(color: Ep.accent),
                  ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('fan-setup-not-now'),
              onPressed: () => app.setFanOnboardingCollapsed(true),
              child: const Text('NOT NOW'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.number,
    required this.complete,
    required this.title,
    required this.child,
  });

  final int number;
  final bool complete;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: complete ? Ep.accent : Ep.surfaceSelected,
            border: Border.all(color: complete ? Ep.accent : Ep.border),
          ),
          child: complete
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text('$number', style: Theme.of(context).textTheme.epLabel),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.epLabel,
              ),
              const SizedBox(height: 7),
              child,
            ],
          ),
        ),
      ],
    );
  }
}

class _BandEntry extends StatelessWidget {
  const _BandEntry({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final count = app.myBands.length;
    final label = bandEntryLabel(count).toUpperCase();
    final detail = count == 0
        ? 'Create a band profile'
        : count == 1
        ? (app.band(app.myBands.single)?.name ?? 'Your band')
        : app.myBandNames;

    return EpCard(
      key: const Key('band-entry'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: () {
        if (count == 0) {
          app.requestStartBand();
        } else if (count == 1) {
          app.switchToBand(app.myBands.single);
        } else {
          showSwitcherSheet(context);
        }
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.epLabel.copyWith(letterSpacing: .8),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$detail ›',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: Theme.of(
                context,
              ).textTheme.epLabel.copyWith(color: Ep.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrAction extends StatelessWidget {
  const _QrAction({required this.gig, required this.venue});

  final Gig gig;
  final Venue venue;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      key: ValueKey('show-qr-${gig.id}'),
      onPressed: () => showQrDialog(context, gig, venue),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 9),
        ),
        textStyle: WidgetStatePropertyAll(
          Theme.of(
            context,
          ).textTheme.epLabel.copyWith(fontSize: 9, letterSpacing: .4),
        ),
      ),
      child: const Text('SHOW QR'),
    );
  }
}

class _FollowRow extends StatelessWidget {
  final String bandId;
  final AppState app;

  const _FollowRow({required this.bandId, required this.app});

  @override
  Widget build(BuildContext context) {
    final band = app.band(bandId);
    if (band == null) return const SizedBox.shrink();
    return EpCard(
      padding: const EdgeInsets.all(9),
      onTap: () => app.openBand(bandId),
      child: Row(
        children: [
          BandAvatar(band, size: 36, radius: 8, fontSize: 12),
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
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => app.toggleFollow(bandId),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10),
              ),
              textStyle: WidgetStatePropertyAll(
                Theme.of(
                  context,
                ).textTheme.epLabel.copyWith(fontSize: 10, letterSpacing: .4),
              ),
            ),
            child: const Text('FOLLOWING ✓'),
          ),
        ],
      ),
    );
  }
}
