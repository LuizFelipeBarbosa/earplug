import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../date_names.dart';
import '../genres.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
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
    final sceneLabel = profile?.homeLocation == null
        ? 'SCENE UNDISCLOSED'
        : '${profile!.homeLocation!.label.toUpperCase()} SCENE';
    final upcoming = app.upcomingRsvpGigs;
    final nextShow = upcoming.firstOrNull;
    final savedGigs = [
      for (final id in app.saved)
        if (app.gig(id) case final Gig g) g,
    ];
    final followingNoun = app.follows.length == 1 ? 'band' : 'bands';
    final historyNoun = app.history.length == 1 ? 'event' : 'events';
    const sectionPadding = EdgeInsets.only(top: 16, bottom: 8);

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
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'PROFILE',
                  style: Theme.of(context).textTheme.epPageHeading,
                ),
              ),
            ),
            IconButton(
              key: const Key('edit-profile-action'),
              tooltip: 'Edit profile',
              onPressed: profile == null ? null : app.openEditProfile,
              style: const ButtonStyle(
                fixedSize: WidgetStatePropertyAll(Size.square(48)),
              ),
              icon: Icon(Icons.edit_outlined),
            ),
            IconButton(
              key: const Key('share-fan-profile'),
              tooltip: 'Share profile summary',
              onPressed: profile == null
                  ? null
                  : () => _shareFanProfile(
                      context,
                      displayName: profileName == null || profileName.isEmpty
                          ? 'EarPlug fan'
                          : profileName,
                      followingCount: app.follows.length,
                      historyCount: app.history.length,
                    ),
              style: const ButtonStyle(
                fixedSize: WidgetStatePropertyAll(Size.square(48)),
              ),
              icon: Icon(Icons.ios_share_outlined),
            ),
            IconButton(
              key: const Key('profile-settings-action'),
              tooltip: 'Privacy and account settings',
              onPressed: app.openSettings,
              style: const ButtonStyle(
                fixedSize: WidgetStatePropertyAll(Size.square(48)),
              ),
              icon: Icon(Icons.settings_outlined),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          key: const Key('fan-profile-header'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.epColors.surfaceRaised,
            border: Border.all(color: context.epColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    key: const Key('fan-profile-avatar-frame'),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: context.epColors.border,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: EpFanAvatar(
                      key: const Key('fan-profile-avatar'),
                      name: profileName,
                      imageUrl: profile?.avatarUrl,
                      size: 64,
                      radius: 17,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          key: const Key('fan-profile-name'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.epDisplay.copyWith(
                            color: context.epColors.contentPrimary,
                            fontSize: 22,
                          ),
                        ),
                        if (fanSince != null)
                          Text(
                            '$sceneLabel · FAN SINCE ${fanSince.toUpperCase()}',
                            key: const Key('fan-profile-scene'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.epBody.copyWith(
                              color: context.epColors.contentSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (profile?.bio case final String bio
                  when bio.trim().isNotEmpty) ...[
                const SizedBox(height: 11),
                Text(bio, style: Theme.of(context).textTheme.epBody),
              ],
              const SizedBox(height: 14),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _ProfileStat(
                        key: const Key('fan-following-stat'),
                        label: 'Following',
                        value: '${app.follows.length}',
                        semanticLabel:
                            'Following, ${app.follows.length} $followingNoun. Open followed bands.',
                        onTap: () => _showFollowingSheet(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ProfileStat(
                        key: const Key('fan-history-stat'),
                        label: 'RSVP History',
                        value: '${app.history.length}',
                        semanticLabel:
                            'RSVP History, ${app.history.length} past $historyNoun. Open RSVP history.',
                        onTap: () => _showHistorySheet(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (nextShow != null) ...[
          const SizedBox(height: 14),
          VoltStrip(
            key: ValueKey('next-show-${nextShow.id}'),
            kicker:
                'NEXT SHOW · ${nextShow.dateShort}${nextShow.lifecycle == GigLifecycle.cancelled ? ' · CANCELLED' : ''}',
            title: nextShow.title,
            meta: [
              app.venue(nextShow.venueId).name,
              nextShow.dateLine,
            ].join(' · '),
            actionLabel: nextShow.lifecycle == GigLifecycle.published
                ? 'QR PASS'
                : null,
            onAction: nextShow.lifecycle == GigLifecycle.published
                ? () => showQrDialog(
                    context,
                    nextShow,
                    app.venue(nextShow.venueId),
                  )
                : null,
          ),
        ],
        const SectionBar(label: 'UPCOMING RSVPS', padding: sectionPadding),
        if (upcoming.isEmpty)
          _EmptySection(
            message: 'No upcoming RSVPs. Pick a show you want to catch.',
            action: 'FIND A SHOW',
            onTap: () => app.resetTo(Screen.home),
          ),
        for (final g in upcoming) ...[
          FanEventCard(
            key: ValueKey('upcoming-rsvp-${g.id}'),
            gig: g,
            app: app,
            trailingAction:
                g.tix == Ticketing.rsvp && g.lifecycle == GigLifecycle.published
                ? _QrAction(gig: g, venue: app.venue(g.venueId))
                : null,
          ),
          const SizedBox(height: 8),
        ],
        const SectionBar(label: 'SAVED SHOWS', padding: sectionPadding),
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
        const SectionBar(
          label: 'UPCOMING SHOWS FROM FOLLOWED BANDS',
          padding: sectionPadding,
        ),
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
        if (app.profileTutorialVisible) ...[
          const SectionBar(label: 'PROFILE GUIDE', padding: sectionPadding),
          _ProfileTutorial(app: app),
        ],
        if (app.showFanOnboarding) ...[
          const SectionBar(label: 'PROFILE SETUP', padding: sectionPadding),
          _FanSetup(app: app),
        ],
        const SectionBar(label: 'SETTINGS', padding: sectionPadding),
        EpCard(
          key: const Key('settings-entry'),
          onTap: app.openSettings,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(
                Icons.settings_outlined,
                color: context.epColors.contentSecondary,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'PRIVACY & ACCOUNT',
                  style: Theme.of(context).textTheme.epLabel,
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: context.epColors.contentSecondary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({
    super.key,
    required this.label,
    required this.value,
    required this.semanticLabel,
    required this.onTap,
  });

  final String label;
  final String value;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: context.epColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.epColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.epDisplay.copyWith(
                      color: context.epColors.contentPrimary,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.epChipLabel
                              .copyWith(
                                color: context.epColors.contentSecondary,
                                letterSpacing: .7,
                              ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: context.epColors.contentSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showFollowingSheet(BuildContext context) {
  showEpSheet(
    context,
    (sheetContext) => Consumer<AppState>(
      builder: (context, app, _) => _FollowingSheet(
        app: app,
        onOpenBand: (bandId) {
          Navigator.pop(sheetContext);
          app.openBand(bandId);
        },
        onExplore: () {
          Navigator.pop(sheetContext);
          app.resetTo(Screen.explore);
        },
      ),
    ),
  );
}

void _showHistorySheet(BuildContext context) {
  showEpSheet(
    context,
    (sheetContext) => Consumer<AppState>(
      builder: (context, app, _) => _HistorySheet(
        app: app,
        onFindShow: () {
          Navigator.pop(sheetContext);
          app.resetTo(Screen.home);
        },
      ),
    ),
  );
}

Future<void> _shareFanProfile(
  BuildContext context, {
  required String displayName,
  required int followingCount,
  required int historyCount,
}) async {
  final bandLabel = followingCount == 1 ? 'band' : 'bands';
  final eventLabel = historyCount == 1 ? 'event' : 'events';
  final summary = [
    '$displayName on EarPlug',
    'Following: $followingCount $bandLabel',
    'RSVP History: $historyCount past $eventLabel',
    'RSVP history is not verified attendance.',
  ].join('\n');
  await copyForUser(
    context,
    summary,
    successMessage: 'Profile summary copied.',
  );
}

class _FollowingSheet extends StatefulWidget {
  const _FollowingSheet({
    required this.app,
    required this.onOpenBand,
    required this.onExplore,
  });

  final AppState app;
  final ValueChanged<String> onOpenBand;
  final VoidCallback onExplore;

  @override
  State<_FollowingSheet> createState() => _FollowingSheetState();
}

class _FollowingSheetState extends State<_FollowingSheet> {
  final _searchController = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  bool _matches(Band? band, String query) {
    if (band == null) return false;
    return [
      band.name,
      band.area,
      ...band.genres,
    ].any((value) => value.toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) {
    final bandIds = widget.app.follows.toList()
      ..sort((left, right) {
        final leftName = widget.app.band(left)?.name ?? left;
        final rightName = widget.app.band(right)?.name ?? right;
        return leftName.toLowerCase().compareTo(rightName.toLowerCase());
      });
    final normalizedQuery = _query.trim().toLowerCase();
    final visibleBandIds = normalizedQuery.isEmpty
        ? bandIds
        : [
            for (final bandId in bandIds)
              if (_matches(widget.app.band(bandId), normalizedQuery)) bandId,
          ];
    final subtitle = normalizedQuery.isEmpty
        ? '${bandIds.length} ${bandIds.length == 1 ? 'band' : 'bands'} in your list'
        : '${visibleBandIds.length} of ${bandIds.length} bands';

    return _ProfileDetailSheet(
      key: const Key('fan-following-sheet'),
      title: 'Following',
      subtitle: subtitle,
      child: bandIds.isEmpty
          ? ListView(
              padding: const EdgeInsets.only(top: 8),
              children: [
                _EmptySection(
                  message: 'Follow bands to keep their profiles close.',
                  action: 'EXPLORE BANDS',
                  onTap: widget.onExplore,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('following-search-field'),
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  autocorrect: false,
                  decoration:
                      epInputDecoration(
                        context,
                        'Search by name, genre, or home base',
                      ).copyWith(
                        labelText: 'Search followed bands',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        prefixIcon: Icon(Icons.search),
                        suffixIcon: normalizedQuery.isEmpty
                            ? null
                            : IconButton(
                                key: const Key('clear-following-search'),
                                tooltip: 'Clear Following search',
                                onPressed: _clearSearch,
                                icon: Icon(Icons.close),
                              ),
                      ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: visibleBandIds.isEmpty
                      ? ListView(
                          children: [
                            _EmptySection(
                              message:
                                  'No followed bands match “${_query.trim()}”.',
                              action: 'CLEAR SEARCH',
                              onTap: _clearSearch,
                            ),
                          ],
                        )
                      : ListView.separated(
                          itemCount: visibleBandIds.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final bandId = visibleBandIds[index];
                            return _FollowRow(
                              bandId: bandId,
                              app: widget.app,
                              onOpen: () => widget.onOpenBand(bandId),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({required this.app, required this.onFindShow});

  final AppState app;
  final VoidCallback onFindShow;

  @override
  Widget build(BuildContext context) {
    return _ProfileDetailSheet(
      key: const Key('fan-history-sheet'),
      title: 'RSVP History',
      subtitle:
          '${app.history.length} past ${app.history.length == 1 ? 'event' : 'events'}',
      notice: Text(
        'RSVP RECORD — ATTENDANCE NOT VERIFIED',
        key: const Key('history-qualification'),
        style: Theme.of(context).textTheme.epMeta.copyWith(
          color: context.epColors.contentSecondary,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: app.history.isEmpty
          ? ListView(
              padding: const EdgeInsets.only(top: 8),
              children: [
                _EmptySection(
                  message: 'Past RSVPs will build your private event history.',
                  action: 'FIND A SHOW',
                  onTap: onFindShow,
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.only(top: 8),
              itemCount: app.history.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _HistoryRow(item: app.history[index]),
            ),
    );
  }
}

class _ProfileDetailSheet extends StatelessWidget {
  const _ProfileDetailSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.notice,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.sizeOf(context).height * .84,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: context.epColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: context.epColors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.epColors.contentDisabled,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.toUpperCase(),
                        style: Theme.of(context).textTheme.epSectionHeading,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.epCaption,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close $title',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close),
                ),
              ],
            ),
            if (notice != null) ...[
              const SizedBox(height: 8),
              DefaultTextStyle.merge(
                style: Theme.of(context).textTheme.epMeta.copyWith(
                  color: context.epColors.contentSecondary,
                  fontWeight: FontWeight.w800,
                ),
                child: notice!,
              ),
            ],
            const SizedBox(height: 6),
            Expanded(child: child),
          ],
        ),
      ),
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
            style: Theme.of(context).textTheme.epBody.copyWith(
              color: context.epColors.contentSecondary,
            ),
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
                  ).textTheme.epLabel.copyWith(color: context.epColors.accent),
                ),
              ),
              IconButton(
                key: const Key('dismiss-profile-tutorial'),
                tooltip: 'Dismiss profile tutorial',
                onPressed: widget.app.completeProfileTutorial,
                icon: Icon(Icons.close),
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
      FanHistoryStatus.rsvped => 'RSVP RECORD',
    };
    final semanticLabel = [
      item.title,
      if (item.venueName.isNotEmpty) item.venueName,
      dateLabel,
      statusLabel,
    ].join(', ');

    return Semantics(
      key: ValueKey('history-${item.gigId}'),
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: EpCard(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            DateBlock(
              day: '${date.day}',
              month: monthNamesUpper[date.month - 1].substring(0, 3),
              semanticLabel: dateLabel,
              size: 44,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.epLabel,
                  ),
                  if (item.venueName.isNotEmpty)
                    Text(
                      item.venueName,
                      key: ValueKey('history-venue-${item.gigId}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.epCaption,
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '$dateLabel · $statusLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.epMeta.copyWith(
                      color: context.epColors.contentSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
            Icon(Icons.tune, color: context.epColors.accent),
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
            Icon(Icons.chevron_right, color: context.epColors.contentSecondary),
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
                    child: Text('FIND A SHOW'),
                  )
                : Text(
                    'A show is saved in your Profile.',
                    style: Theme.of(context).textTheme.epCaption.copyWith(
                      color: context.epColors.accent,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('fan-setup-not-now'),
              onPressed: () => app.setFanOnboardingCollapsed(true),
              child: Text('NOT NOW'),
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
            color: complete
                ? context.epColors.accent
                : context.epColors.surfaceSelected,
            border: Border.all(
              color: complete
                  ? context.epColors.accent
                  : context.epColors.border,
            ),
          ),
          child: complete
              ? Icon(Icons.check, size: 16, color: Colors.white)
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
        fixedSize: WidgetStatePropertyAll(Size.square(48)),
        foregroundColor: WidgetStatePropertyAll(context.epColors.accent),
      ),
      icon: Icon(Icons.qr_code_2, size: 20),
    );
  }
}

class _FollowRow extends StatelessWidget {
  final String bandId;
  final AppState app;
  final VoidCallback onOpen;

  const _FollowRow({
    required this.bandId,
    required this.app,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final band = app.band(bandId);
    if (band == null) {
      return EpCard(
        onTap: onOpen,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.music_note, color: context.epColors.contentSecondary),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FOLLOWED BAND',
                    style: Theme.of(context).textTheme.epLabel,
                  ),
                  Text(
                    'Profile details are loading',
                    style: Theme.of(context).textTheme.epCaption,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.epColors.contentSecondary),
          ],
        ),
      );
    }
    return EpCard(
      padding: const EdgeInsets.all(9),
      onTap: onOpen,
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
              minimumSize: WidgetStatePropertyAll(Size(48, 48)),
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10),
              ),
              textStyle: WidgetStatePropertyAll(
                Theme.of(
                  context,
                ).textTheme.epLabel.copyWith(fontSize: 11, letterSpacing: .4),
              ),
            ),
            child: Text('FOLLOWING ✓'),
          ),
        ],
      ),
    );
  }
}
