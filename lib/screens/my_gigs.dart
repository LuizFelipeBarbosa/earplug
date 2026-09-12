import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../date_names.dart';
import '../genres.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/ep_text.dart';
import '../widgets/fan_event_card.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';

class MyGigsScreen extends StatefulWidget {
  const MyGigsScreen({super.key});

  @override
  State<MyGigsScreen> createState() => _MyGigsScreenState();
}

enum _ProfileList { going, tickets, saved, followed, past }

class _MyGigsScreenState extends State<MyGigsScreen> {
  _ProfileList? _selected;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.myTicketsLoaded) unawaited(app.loadMyTickets());
    final now = DateTime.now();
    final tickets =
        app.myTickets
            .where(
              (ticket) =>
                  (ticket.status == TicketStatus.valid ||
                      ticket.status == TicketStatus.used) &&
                  ticket.gig.startsAt.isAfter(now),
            )
            .toList()
          ..sort(
            (left, right) => left.gig.startsAt.compareTo(right.gig.startsAt),
          );
    final upcoming = app.upcomingRsvpGigs;
    final savedGigs = [
      for (final id in app.saved)
        if (app.gig(id) case final Gig gig) gig,
    ];
    final selected =
        _selected ??
        (app.current.screen == Screen.myTickets
            ? _ProfileList.tickets
            : _ProfileList.going);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: EpLayout.workspaceWidth),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            EpLayout.gutter,
            headerTopPad(context),
            EpLayout.gutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProfileHeader(app: app),
              if (upcoming.isNotEmpty || tickets.isNotEmpty) ...[
                const SizedBox(height: 24),
                _NextShow(app: app, upcoming: upcoming, tickets: tickets),
              ],
              const SizedBox(height: 24),
              EpStatGrid(
                topLine: false,
                stats: [
                  EpStat('${app.follows.length}', 'Following'),
                  EpStat('${app.history.length}', 'Past RSVPs'),
                  EpStat('${app.saved.length}', 'Saved'),
                ],
              ),
              const SizedBox(height: 20),
              EpSegmentTabs(
                labels: [
                  'Going · ${upcoming.length}',
                  'Tickets · ${tickets.length}',
                  'Saved · ${savedGigs.length}',
                  'Followed',
                  'Past',
                ],
                selected: selected.index,
                scrollable: true,
                onSelect: (index) =>
                    setState(() => _selected = _ProfileList.values[index]),
              ),
              ...switch (selected) {
                _ProfileList.going => [
                  if (upcoming.isEmpty)
                    _ListNote(
                      message:
                          'No upcoming RSVPs. Pick a show you want to catch.',
                      actionLabel: 'Find a show',
                      onAction: () => app.resetTo(Screen.home),
                    ),
                  for (final gig in upcoming)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      // Keep the shared RSVP, save, share, and ticket actions.
                      child: FanEventCard(
                        key: ValueKey('upcoming-rsvp-${gig.id}'),
                        gig: gig,
                        app: app,
                        trailingAction:
                            gig.tix == Ticketing.rsvp &&
                                gig.lifecycle == GigLifecycle.published
                            ? _QrAction(gig: gig, venue: app.venue(gig.venueId))
                            : null,
                      ),
                    ),
                  if (upcoming.isNotEmpty)
                    _ListNote(
                      message: 'Pick another show you want to catch.',
                      actionLabel: 'Find a show',
                      onAction: () => app.resetTo(Screen.home),
                    ),
                ],
                _ProfileList.tickets => [
                  if (tickets.isEmpty)
                    const _ListNote(
                      message: 'No tickets yet · paid shows list them here',
                    ),
                  for (final ticket in tickets)
                    _TicketRow(
                      ticket: ticket,
                      onTap: () => app.openTicket(ticket.id),
                    ),
                ],
                _ProfileList.saved => [
                  if (savedGigs.isEmpty)
                    _ListNote(
                      message:
                          'Nothing saved. Bookmark a show to keep it handy.',
                      actionLabel: 'Find a show',
                      onAction: () => app.resetTo(Screen.home),
                    ),
                  for (final gig in savedGigs)
                    _GigActionsRow(gig: gig, app: app),
                ],
                _ProfileList.followed => [
                  if (app.follows.isEmpty)
                    _ListNote(
                      message: 'Follow bands to keep their profiles close.',
                      actionLabel: 'Explore bands',
                      onAction: () => app.resetTo(Screen.explore),
                    ),
                  for (final bandId in app.follows)
                    _FollowRow(
                      bandId: bandId,
                      app: app,
                      onOpen: () => app.openBand(bandId),
                    ),
                  const EpSectionHeader(
                    label: 'Upcoming shows from followed bands',
                  ),
                  if (app.followedBandShows.isEmpty)
                    _ListNote(
                      message: app.profile?.followedBandUpdatesEnabled == false
                          ? 'Followed-band updates are turned off.'
                          : app.follows.isEmpty
                          ? 'Follow a band to see its upcoming shows here.'
                          : 'No followed bands have an upcoming show yet.',
                      actionLabel:
                          app.profile?.followedBandUpdatesEnabled == false
                          ? 'Edit preferences'
                          : 'Explore bands',
                      onAction: app.profile?.followedBandUpdatesEnabled == false
                          ? app.openEditProfile
                          : () => app.resetTo(Screen.explore),
                    ),
                  for (final gig in app.followedBandShows)
                    _GigActionsRow(gig: gig, app: app),
                ],
                _ProfileList.past => [
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: EpEyebrow(
                      'RSVP record — attendance not verified',
                      key: Key('history-qualification'),
                    ),
                  ),
                  if (app.history.isEmpty)
                    _ListNote(
                      message:
                          'Past RSVPs will build your private event history.',
                      actionLabel: 'Find a show',
                      onAction: () => app.resetTo(Screen.home),
                    ),
                  for (final item in app.history) _HistoryRow(item: item),
                ],
              },
              _ProfileDetails(app: app),
              if (app.profileTutorialVisible) ...[
                const EpSectionHeader(label: 'Profile guide'),
                _ProfileTutorial(app: app),
              ],
              if (app.showFanOnboarding) ...[
                const EpSectionHeader(label: 'Profile setup'),
                _FanSetup(app: app),
              ],
              const SizedBox(height: 24),
              EpMenuRow(
                key: const Key('settings-entry'),
                icon: Icons.settings_outlined,
                label: 'Privacy & account',
                onTap: app.openSettings,
              ),
              const SizedBox(height: tabBarClearance),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final profile = app.profile;
    final name = profile?.name.trim();
    final displayName = name == null || name.isEmpty ? 'Your profile' : name;
    final scene = [
      if (profile?.homeLocation case final location?) '${location.label} scene',
      if (profile != null) 'since ${monthLabel(profile.createdAt)}',
    ].join(' · ');
    return Column(
      key: const Key('fan-profile-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              key: const Key('fan-profile-avatar-frame'),
              image: true,
              label: name == null || name.isEmpty
                  ? 'Profile avatar'
                  : '$name avatar',
              excludeSemantics: true,
              child: EpAvatarTile(
                key: const Key('fan-profile-avatar'),
                initials: _initials(name),
                image: profile?.avatarUrl == null
                    ? null
                    : NetworkImage(profile!.avatarUrl!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EpDisplay(
                    displayName,
                    key: const Key('fan-profile-name'),
                    size: 20,
                    keepCase: true,
                  ),
                  if (scene.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    EpEyebrow(scene, key: const Key('fan-profile-scene')),
                  ],
                ],
              ),
            ),
            EpIconPill(
              key: const Key('edit-profile-action'),
              icon: Icons.edit_outlined,
              semanticLabel: 'Edit profile',
              onPressed: profile == null ? null : app.openEditProfile,
            ),
            EpIconPill(
              key: const Key('profile-settings-action'),
              icon: Icons.settings_outlined,
              semanticLabel: 'Privacy and account settings',
              onPressed: app.openSettings,
            ),
          ],
        ),
        if (!app.authed) ...[
          const SizedBox(height: 20),
          const EpDisplay('Your scene starts here.', size: 36),
          const SizedBox(height: 16),
          EpPill(
            label: 'Sign in',
            variant: EpPillVariant.primary,
            onPressed: app.openMyGigsTab,
          ),
        ],
      ],
    );
  }
}

String _initials(String? name) {
  final parts = name?.trim().split(RegExp(r'\s+')) ?? const <String>[];
  if (parts.isEmpty || parts.first.isEmpty) return 'EF';
  return parts.take(2).map((part) => part.characters.first).join();
}

class _NextShow extends StatelessWidget {
  const _NextShow({
    required this.app,
    required this.upcoming,
    required this.tickets,
  });

  final AppState app;
  final List<Gig> upcoming;
  final List<TicketSummary> tickets;

  @override
  Widget build(BuildContext context) {
    final rsvp = upcoming.firstOrNull;
    final ticket = tickets.firstOrNull;
    if (ticket != null &&
        (rsvp == null || ticket.gig.startsAt.isBefore(rsvp.startsAt))) {
      final gig = app.gig(ticket.gigId);
      final published = ticket.gig.lifecycle == GigLifecycle.published;
      return VoltStrip(
        key: ValueKey('next-show-${ticket.gigId}'),
        kicker:
            'Next show · ${gig?.dateLine ?? dateLabel(ticket.gig.startsAt)}${published ? '' : ' · Cancelled'}',
        title: ticket.gig.title,
        meta: ticket.gig.venueName,
        actionLabel: published ? 'Show QR pass' : null,
        onAction: published ? () => app.openTicket(ticket.id) : null,
      );
    }
    final gig = rsvp!;
    final venue = app.venue(gig.venueId);
    final canShowQr =
        gig.lifecycle == GigLifecycle.published && gig.tix == Ticketing.rsvp;
    return VoltStrip(
      key: ValueKey('next-show-${gig.id}'),
      kicker:
          'Next show · ${gig.dateLine}${gig.lifecycle == GigLifecycle.cancelled ? ' · Cancelled' : ''}',
      title: gig.title,
      meta: [
        venue.name,
        if (venue.area.trim().isNotEmpty) venue.area,
      ].join(' · '),
      actionLabel: canShowQr ? 'Show QR pass' : null,
      onAction: canShowQr ? () => showQrDialog(context, gig, venue) : null,
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.ticket, required this.onTap});

  final TicketSummary ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => EpGigRow(
    key: ValueKey('ticket-${ticket.id}'),
    date: ticket.gig.startsAt,
    title: ticket.gig.title,
    meta: ticket.gig.venueName,
    sub: ticket.status == TicketStatus.used ? 'CHECKED IN' : 'VALID',
    trailing: SizedBox(
      width: 64,
      child: EpMonoText('Ticket', color: context.epColors.accent),
    ),
    onTap: onTap,
  );
}

/// Secondary event controls use the shared card so save, share, RSVP, and
/// external ticket behavior stay consistent with Going and the gig screens.
class _GigActionsRow extends StatelessWidget {
  const _GigActionsRow({required this.gig, required this.app});

  final Gig gig;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final venue = app.venue(gig.venueId);
    return EpGigRow(
      key: ValueKey('fan-event-${gig.id}'),
      date: gig.startsAt,
      title: gig.title,
      sub: [
        venue.name,
        'Doors ${gig.doorsLabel}',
        gig.priceLabel,
        if (gig.lifecycle == GigLifecycle.cancelled) 'Cancelled',
      ].join(' · '),
      onTap: () => app.openGig(gig.id),
      trailing: EpIconPill(
        key: ValueKey('gig-actions-${gig.id}'),
        icon: Icons.more_horiz,
        semanticLabel: 'Actions for ${gig.title}',
        onPressed: () => showEpSheet(
          context,
          (sheetContext) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(EpLayout.gutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: EpIconPill(
                      icon: Icons.close,
                      semanticLabel: 'Close event actions',
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ),
                  Consumer<AppState>(
                    builder: (context, app, _) =>
                        FanEventCard(gig: gig, app: app),
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

class _ListNote extends StatelessWidget {
  const _ListNote({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.epBody.copyWith(color: context.epColors.muted),
        ),
        if (actionLabel != null)
          EpPill(
            label: actionLabel!,
            variant: EpPillVariant.ghost,
            onPressed: onAction,
          ),
      ],
    ),
  );
}

class _ProfileDetails extends StatelessWidget {
  const _ProfileDetails({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final profile = app.profile;
    final incomplete =
        profile != null &&
        (profile.name.trim().isEmpty ||
            profile.avatarUrl == null ||
            (profile.bio?.trim().isEmpty ?? true) ||
            profile.genres.isEmpty);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (profile?.bio case final String bio
              when bio.trim().isNotEmpty) ...[
            Text(bio, style: Theme.of(context).textTheme.epBody),
            const SizedBox(height: 12),
          ],
          if (profile != null && profile.genres.isNotEmpty)
            Wrap(
              key: const Key('fan-profile-genres'),
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final genre in profile.genres)
                  EpChip(
                    key: ValueKey('fan-profile-genre-$genre'),
                    label: genre,
                    active: true,
                    neutralSelected: true,
                    semanticLabel: '$genre. Edit favorite genres.',
                    onTap: app.openEditProfile,
                  ),
              ],
            ),
          if (incomplete) ...[
            const SizedBox(height: 12),
            Text(
              'Add a photo, bio, and genres so bands and fans recognize you.',
              key: const Key('fan-profile-incomplete-hint'),
              style: Theme.of(context).textTheme.epCaption,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              EpIconPill(
                key: const Key('share-fan-profile'),
                icon: Icons.ios_share_outlined,
                semanticLabel: 'Share profile summary',
                onPressed: profile == null
                    ? null
                    : () => _shareFanProfile(
                        context,
                        displayName: profile.name.trim().isEmpty
                            ? 'EarPlug fan'
                            : profile.name.trim(),
                        followingCount: app.follows.length,
                        historyCount: app.history.length,
                      ),
              ),
              EpPill(
                key: const Key('fan-following-stat'),
                label: 'Browse following',
                variant: EpPillVariant.ghost,
                semanticLabel:
                    'Following, ${app.follows.length} ${app.follows.length == 1 ? 'band' : 'bands'}. Open followed bands.',
                onPressed: () => _showFollowingSheet(context),
              ),
              EpPill(
                key: const Key('fan-history-stat'),
                label: 'RSVP history',
                variant: EpPillVariant.ghost,
                semanticLabel:
                    'RSVP History, ${app.history.length} past ${app.history.length == 1 ? 'event' : 'events'}. Open RSVP history.',
                onPressed: () => _showHistorySheet(context),
              ),
            ],
          ),
        ],
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
                EmptyNote(
                  message: 'Follow bands to keep their profiles close.',
                  actionLabel: 'EXPLORE BANDS',
                  onAction: widget.onExplore,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EpLabeledField(
                  fieldKey: const Key('following-search-field'),
                  controller: _searchController,
                  label: 'Search followed bands',
                  hint: 'Search by name, genre, or home base',
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  autocorrect: false,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: normalizedQuery.isEmpty
                      ? null
                      : EpIconPill(
                          key: const Key('clear-following-search'),
                          semanticLabel: 'Clear Following search',
                          onPressed: _clearSearch,
                          icon: Icons.close,
                        ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: visibleBandIds.isEmpty
                      ? ListView(
                          children: [
                            EmptyNote(
                              message:
                                  'No followed bands match “${_query.trim()}”.',
                              actionLabel: 'CLEAR SEARCH',
                              onAction: _clearSearch,
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
      notice: const EpEyebrow(
        'RSVP record — attendance not verified',
        key: Key('history-qualification'),
      ),
      child: app.history.isEmpty
          ? ListView(
              padding: const EdgeInsets.only(top: 8),
              children: [
                EmptyNote(
                  message: 'Past RSVPs will build your private event history.',
                  actionLabel: 'FIND A SHOW',
                  onAction: onFindShow,
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
    return EpSheetShell(
      heightFactor: .84,
      padding: const EdgeInsets.fromLTRB(
        EpLayout.gutter,
        12,
        EpLayout.gutter,
        16,
      ),
      handleBottomSpacing: 8,
      header: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EpDisplay(title, size: 20),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.epCaption),
              ],
            ),
          ),
          EpIconPill(
            semanticLabel: 'Close $title',
            onPressed: () => Navigator.pop(context),
            icon: Icons.close,
          ),
        ],
      ),
      children: [
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
                child: EpEyebrow(
                  'Profile tour · ${_step + 1} of ${_titles.length}',
                ),
              ),
              EpIconPill(
                key: const Key('dismiss-profile-tutorial'),
                semanticLabel: 'Dismiss profile tutorial',
                onPressed: widget.app.completeProfileTutorial,
                icon: Icons.close,
              ),
            ],
          ),
          EpDisplay(_titles[_step], size: 20),
          const SizedBox(height: 5),
          Text(_messages[_step], style: Theme.of(context).textTheme.epBody),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: EpPill(
              key: const Key('profile-tutorial-next'),
              onPressed: () {
                if (last) {
                  widget.app.completeProfileTutorial();
                } else {
                  setState(() => _step++);
                }
              },
              label: last ? 'Done' : 'Next',
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
    final dateText =
        '${monthNamesUpper[date.month - 1]} ${date.day}, ${date.year}';
    const statusLabel = 'RSVP RECORD';
    return Semantics(
      key: ValueKey('history-${item.gigId}'),
      container: true,
      label: [
        item.title,
        if (item.venueName.isNotEmpty) item.venueName,
        dateText,
        statusLabel,
      ].join(', '),
      excludeSemantics: true,
      child: EpGigRow(
        key: ValueKey('history-venue-${item.gigId}'),
        date: date,
        title: item.title,
        meta: item.venueName.isEmpty ? null : item.venueName,
        sub: '$dateText · $statusLabel',
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
      return EpMenuRow(
        key: const Key('fan-setup-collapsed'),
        icon: Icons.tune,
        label: 'Finish setup',
        sub: 'Pick your city and sound, then save a show.',
        onTap: () => app.setFanOnboardingCollapsed(false),
      );
    }

    return EpCard(
      key: const Key('fan-setup-expanded'),
      variant: EpCardVariant.raised,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EpDisplay('Make EarPlug yours', size: 20),
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
                ? EpPill(
                    key: const Key('fan-setup-find-show'),
                    variant: EpPillVariant.ghost,
                    onPressed: () => app.resetTo(Screen.home),
                    label: 'Find a show',
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
            child: EpPill(
              key: const Key('fan-setup-not-now'),
              variant: EpPillVariant.ghost,
              onPressed: () => app.setFanOnboardingCollapsed(true),
              label: 'Not now',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EpChecklistRow(done: complete, label: '$number · $title'),
        const SizedBox(height: 8),
        child,
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
    return EpIconPill(
      key: ValueKey('show-qr-${gig.id}'),
      semanticLabel: 'Show QR code',
      onPressed: () => showQrDialog(context, gig, venue),
      icon: Icons.qr_code_2,
    );
  }
}

class _FollowRow extends StatelessWidget {
  const _FollowRow({
    required this.bandId,
    required this.app,
    required this.onOpen,
  });

  final String bandId;
  final AppState app;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final band = app.band(bandId);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackAction =
            constraints.maxWidth < 340 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final follow = band == null
            ? null
            : EpPill(
                label: 'Following ✓',
                onPressed: () => app.toggleFollow(bandId),
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            EpEntityRow(
              leading: EpAvatarTile(
                initials: band?.initials ?? '?',
                image: band?.avatarUrl == null
                    ? null
                    : NetworkImage(band!.avatarUrl!),
              ),
              title: band?.name ?? 'Followed band',
              sub: band?.genreLine ?? 'Profile details are loading',
              trailing: stackAction ? null : follow,
              onTap: onOpen,
            ),
            if (stackAction && follow != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: follow,
              ),
          ],
        );
      },
    );
  }
}
