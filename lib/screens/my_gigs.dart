import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../date_names.dart';
import '../genres.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/fan_event_card.dart';
import '../widgets/form_bits.dart';
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
    final upcoming = app.upcomingRsvpGigs;
    final nextShow = upcoming.cast<Gig?>().firstWhere(
      (gig) =>
          gig?.tix == Ticketing.rsvp &&
          gig?.lifecycle == GigLifecycle.published,
      orElse: () => null,
    );
    final remainingUpcoming = [
      for (final gig in upcoming)
        if (gig.id != nextShow?.id) gig,
    ];
    final savedGigs = [
      for (final id in app.saved)
        if (app.gig(id) case final Gig g) g,
    ];
    final followedBandIds = [
      for (final id in app.follows)
        if (app.band(id) != null) id,
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
            Expanded(
              child: Text(
                'PROFILE',
                style: Theme.of(context).textTheme.epPageHeading,
              ),
            ),
            IconButton(
              key: const Key('profile-settings-action'),
              tooltip: 'Privacy and account settings',
              onPressed: app.openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        const SectionBar(
          label: 'IDENTITY & EDIT PROFILE',
          padding: EdgeInsets.only(top: 14, bottom: 10),
        ),
        Row(
          children: [
            EpFanAvatar(
              key: const Key('fan-profile-avatar'),
              name: profileName,
              imageUrl: profile?.avatarUrl,
              size: 64,
              radius: 18,
            ),
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
                    '${fanSince == null ? '' : 'fan since $fanSince · '}'
                    '${app.history.length} past RSVPs',
                    style: Theme.of(context).textTheme.epCaption,
                  ),
                  const SizedBox(height: 3),
                  TextAction(
                    'EDIT PROFILE',
                    key: const Key('edit-profile-action'),
                    onTap: profile == null ? null : app.openEditProfile,
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (profile?.bio case final String bio when bio.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(bio, style: Theme.of(context).textTheme.epBody),
        ],
        if (nextShow != null) ...[
          const SizedBox(height: 18),
          VoltStrip(
            key: ValueKey('next-show-${nextShow.id}'),
            kicker: 'NEXT SHOW · ${nextShow.dateShort}',
            title: nextShow.title,
            meta: [
              app.venue(nextShow.venueId).name,
              nextShow.dateLine,
            ].join(' · '),
            actionLabel: 'QR PASS',
            onAction: () =>
                showQrDialog(context, nextShow, app.venue(nextShow.venueId)),
          ),
        ],
        const SectionBar(label: 'UPCOMING RSVPS'),
        if (remainingUpcoming.isEmpty)
          _EmptySection(
            message: nextShow == null
                ? 'No upcoming RSVPs. Pick a show you want to catch.'
                : 'Your next RSVP is ready above.',
            action: 'FIND A SHOW',
            onTap: () => app.resetTo(Screen.home),
          ),
        for (final g in remainingUpcoming) ...[
          FanEventCard(
            gig: g,
            app: app,
            trailingAction:
                g.tix == Ticketing.rsvp && g.lifecycle == GigLifecycle.published
                ? _QrAction(gig: g, venue: app.venue(g.venueId))
                : null,
          ),
          const SizedBox(height: 8),
        ],
        const SectionBar(label: 'SAVED SHOWS'),
        if (savedGigs.isEmpty)
          _EmptySection(
            message: 'Nothing saved. Bookmark a show to keep it handy.',
            action: 'FIND A SHOW',
            onTap: () => app.resetTo(Screen.home),
          ),
        for (final g in savedGigs) ...[
          FanEventCard(gig: g, app: app),
          const SizedBox(height: 8),
        ],
        const SectionBar(label: 'FOLLOWING'),
        if (app.follows.isEmpty)
          _EmptySection(
            message: 'Follow bands to keep their profiles close.',
            action: 'EXPLORE BANDS',
            onTap: () => app.resetTo(Screen.explore),
          ),
        if (app.follows.isNotEmpty && followedBandIds.isEmpty)
          _EmptySection(
            message: 'Followed band details are not available yet.',
            action: 'EXPLORE BANDS',
            onTap: () => app.resetTo(Screen.explore),
          ),
        for (final id in followedBandIds) ...[
          _FollowRow(bandId: id, app: app),
          const SizedBox(height: 8),
        ],
        const SectionBar(label: 'UPCOMING SHOWS FROM FOLLOWED BANDS'),
        if (app.followedBandShows.isEmpty)
          _EmptySection(
            message: profile?.followedBandUpdatesEnabled == false
                ? 'Followed-band updates are turned off.'
                : app.follows.isEmpty
                ? 'Follow a band to see its upcoming shows here.'
                : 'No followed bands have an upcoming show yet.',
            action: profile?.followedBandUpdatesEnabled == false
                ? 'EDIT PREFERENCES'
                : 'EXPLORE BANDS',
            onTap: profile?.followedBandUpdatesEnabled == false
                ? app.openEditProfile
                : () => app.resetTo(Screen.explore),
          ),
        for (final gig in app.followedBandShows) ...[
          FanEventCard(gig: gig, app: app),
          const SizedBox(height: 8),
        ],
        SectionBar(
          label: 'EVENT HISTORY',
          padding: EdgeInsets.only(
            top: 20,
            bottom: app.history.isEmpty ? 10 : 2,
          ),
        ),
        if (app.history.isEmpty)
          _EmptySection(
            message: 'Past RSVPs will build your private event history.',
            action: 'FIND A SHOW',
            onTap: () => app.resetTo(Screen.home),
          )
        else
          Text(
            'RSVP RECORD — ATTENDANCE NOT VERIFIED',
            key: const Key('history-qualification'),
            style: Theme.of(context).textTheme.epMeta.copyWith(
              color: Ep.contentSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        for (final item in app.history) ...[
          _HistoryRow(item: item),
          const SizedBox(height: 8),
        ],
        if (app.profileTutorialVisible) ...[
          const SectionBar(label: 'PROFILE GUIDE'),
          _ProfileTutorial(app: app),
        ],
        if (app.showFanOnboarding) ...[
          const SectionBar(label: 'PROFILE SETUP'),
          _FanSetup(app: app),
        ],
        const SectionBar(label: 'PLAY IN A BAND?'),
        _BandEntry(app: app),
        Align(
          alignment: Alignment.centerRight,
          child: TextAction(
            'CREATE A BAND',
            key: const Key('create-band-from-profile'),
            onTap: app.requestStartBand,
          ),
        ),
        const SectionBar(label: 'SETTINGS'),
        EpCard(
          key: const Key('settings-entry'),
          onTap: app.openSettings,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              const Icon(Icons.settings_outlined, color: Ep.contentSecondary),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'PRIVACY & ACCOUNT',
                  style: Theme.of(context).textTheme.epLabel,
                ),
              ),
              const Icon(Icons.chevron_right, color: Ep.contentSecondary),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({
    required this.message,
    required this.action,
    required this.onTap,
  });

  final String message;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DashedBox(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.epBody.copyWith(color: Ep.contentSecondary),
          ),
          TextAction(action, onTap: onTap),
        ],
      ),
    );
  }
}

class _ProfileTutorial extends StatefulWidget {
  const _ProfileTutorial({required this.app});

  final AppState app;

  @override
  State<_ProfileTutorial> createState() => _ProfileTutorialState();
}

class _ProfileTutorialState extends State<_ProfileTutorial> {
  var _step = 0;

  static const _titles = [
    'MAKE IT YOURS',
    'SAVE YOUR SCENE',
    'MANAGE YOUR BAND',
  ];
  static const _messages = [
    'Edit your name, photo, home scene, favorite genres, and privacy choices.',
    'RSVP to shows, save ones for later, and follow bands you want to hear from.',
    'Create a band from this profile, then open its dashboard anytime.',
  ];

  @override
  Widget build(BuildContext context) {
    final last = _step == _titles.length - 1;
    return EpCard(
      key: const Key('profile-tutorial'),
      variant: EpCardVariant.selected,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PROFILE TOUR · ${_step + 1} OF ${_titles.length}',
                  style: Theme.of(
                    context,
                  ).textTheme.epLabel.copyWith(color: Ep.accent),
                ),
              ),
              IconButton(
                key: const Key('dismiss-profile-tutorial'),
                tooltip: 'Dismiss profile tutorial',
                onPressed: widget.app.completeProfileTutorial,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(_titles[_step], style: epDisplay(size: 17)),
          const SizedBox(height: 5),
          Text(_messages[_step], style: Theme.of(context).textTheme.epBody),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('profile-tutorial-next'),
              onPressed: () {
                if (last) {
                  widget.app.completeProfileTutorial();
                } else {
                  setState(() => _step++);
                }
              },
              child: Text(last ? 'DONE' : 'NEXT'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item});

  final FanHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final date = item.startsAt.toLocal();
    final dateLabel =
        '${monthNamesUpper[date.month - 1]} ${date.day}, ${date.year}';
    final statusLabel = switch (item.status) {
      FanHistoryStatus.rsvped => "RSVP'D",
    };

    return LedgerRow(
      key: ValueKey('history-${item.gigId}'),
      title: item.title,
      details: [
        if (item.venueName.isNotEmpty) item.venueName,
        dateLabel,
        statusLabel,
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
                    'A show is saved in your Profile.',
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
    final membershipsLoading = app.authed && !app.membershipsLoaded;
    final count = app.membershipsLoaded ? app.myBands.length : 0;
    final label = membershipsLoading
        ? 'BANDS'
        : bandEntryLabel(count).toUpperCase();
    final detail = membershipsLoading
        ? 'Loading your bands'
        : count == 0
        ? 'Create a band profile'
        : count == 1
        ? (app.band(app.myBands.single)?.name ?? 'Your band')
        : app.myBandNames;

    return EpCard(
      key: const Key('band-entry'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: () {
        if (!app.authed) {
          app.requestStartBand();
        } else if (!app.membershipsLoaded) {
          return;
        } else if (count == 0) {
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
    return IconButton(
      key: ValueKey('show-qr-${gig.id}'),
      tooltip: 'Show QR code',
      onPressed: () => showQrDialog(context, gig, venue),
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size.square(48)),
        foregroundColor: const WidgetStatePropertyAll(Ep.accent),
      ),
      icon: const Icon(Icons.qr_code_2, size: 20),
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
                ).textTheme.epLabel.copyWith(fontSize: 11, letterSpacing: .4),
              ),
            ),
            child: const Text('FOLLOWING ✓'),
          ),
        ],
      ),
    );
  }
}
