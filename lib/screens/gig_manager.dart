import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../genres.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/form_bits.dart';
import '../widgets/opportunity_labels.dart';
import '../widgets/sheets.dart';
import 'door_mode.dart';

class GigManagerScreen extends StatefulWidget {
  const GigManagerScreen({super.key});

  @override
  State<GigManagerScreen> createState() => _GigManagerScreenState();
}

class _GigManagerScreenState extends State<GigManagerScreen> {
  _GigSegment _segment = _GigSegment.open;
  bool _requestedDiscovery = false;
  List<GigProject>? _partitionedProjects;
  List<GigProject> _drafts = const [];
  List<GigProject> _published = const [];
  List<GigProject> _cancelled = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (app.isAdminOf(app.bandId)) app.ensureManagedGigs();
    if (!_requestedDiscovery) {
      _requestedDiscovery = true;
      scheduleMicrotask(() {
        if (!mounted) return;
        unawaited(app.refreshBrowse());
        unawaited(app.refreshMyApplications());
        unawaited(app.refreshBandBookings());
      });
    }
  }

  /// Splits the projects by status once per list instance; unrelated
  /// AppState notifications rebuild this screen with the same list.
  void _partition(List<GigProject> projects) {
    if (identical(projects, _partitionedProjects)) return;
    _drafts = [
      for (final project in projects)
        if (project.status == GigProjectStatus.draft) project,
    ];
    _published = [
      for (final project in projects)
        if (project.status == GigProjectStatus.published) project,
    ];
    _cancelled = [
      for (final project in projects)
        if (project.status == GigProjectStatus.cancelled) project,
    ];
    _partitionedProjects = projects;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    _partition(app.managedGigProjects);
    if (app.isAdminOf(app.bandId)) app.ensureManagedGigs();
    final now = DateTime.now();
    final confirmedBookings = app.bandBookings
        .where(
          (booking) => booking.status.isLive && booking.startsAt.isAfter(now),
        )
        .toList();
    final pastBookings = app.bandBookings.where(
      (booking) =>
          booking.status == BookingStatus.completed ||
          booking.status == BookingStatus.paid ||
          (booking.status.isLive && booking.startsAt.isBefore(now)),
    );

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          app.refreshBrowse(),
          app.refreshMyApplications(),
          app.refreshBandBookings(),
          app.refreshManagedGigs(),
          app.refreshGigWritePolicy(),
        ]);
      },
      child: ListView(
        key: ValueKey(_segment),
        physics: const AlwaysScrollableScrollPhysics(),
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
                  'GIGS',
                  style: Theme.of(context).textTheme.epPageHeading,
                ),
              ),
              if (app.gigWritePolicy && app.isAdminOf(app.bandId))
                FilledButton(
                  onPressed: app.startGigCreate,
                  child: Text('+ NEW GIG'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final segment in _GigSegment.values)
                EpChip(
                  key: ValueKey('band-gigs-seg-${segment.name}'),
                  label: segment.name.toUpperCase(),
                  active: _segment == segment,
                  onTap: () => setState(() => _segment = segment),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (_segment == _GigSegment.open) _OpenSection(app: app),
          if (_segment == _GigSegment.applied) _AppliedSection(app: app),
          if (_segment == _GigSegment.booked) ...[
            if (app.bandBookingsStatus == DataStatus.connecting)
              const LinearProgressIndicator(),
            if (app.bandBookingsStatus == DataStatus.error) ...[
              const EmptyNote(message: 'Could not load bookings.'),
              TextButton(
                onPressed: app.refreshBandBookings,
                child: const Text('RETRY'),
              ),
            ],
            for (final booking in confirmedBookings) ...[
              _BookingCard(
                key: ValueKey('band-booking-${booking.id}'),
                booking: booking,
                onTap: () => app.openBooking(booking.id),
              ),
              const SizedBox(height: 12),
            ],
            if (confirmedBookings.isEmpty && _published.isEmpty)
              const EmptyNote(message: 'No confirmed bookings yet.'),
            if (app.managedGigsLoading) const LinearProgressIndicator(),
            _ProjectSection(
              title: 'PUBLISHED',
              projects: _published,
              empty: 'No live gigs yet.',
            ),
            if (_drafts.isNotEmpty) ...[
              const SizedBox(height: 20),
              _DraftSection(projects: _drafts),
            ],
          ],
          if (_segment == _GigSegment.past) ...[
            for (final booking in pastBookings) ...[
              _BookingCard(
                key: ValueKey('band-booking-${booking.id}'),
                booking: booking,
                onTap: () => app.openBooking(booking.id),
              ),
              const SizedBox(height: 12),
            ],
            _PastSection(app: app),
            const SizedBox(height: 20),
            _ProjectSection(
              title: 'CANCELLED',
              projects: _cancelled,
              empty: 'No cancelled gigs.',
              readOnly: true,
            ),
          ],
        ],
      ),
    );
  }
}

enum _GigSegment { open, applied, booked, past }

class _BookingCard extends StatelessWidget {
  const _BookingCard({super.key, required this.booking, required this.onTap});

  final Booking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final approxLabel = booking.venue.approxLabel;
    return EpCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DateBlock.forDate(booking.startsAt),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.opportunityTitle,
                  style: textTheme.epSectionHeading,
                ),
                const SizedBox(height: 4),
                Text(
                  approxLabel == null || approxLabel.isEmpty
                      ? booking.venue.name
                      : '${booking.venue.name} · $approxLabel',
                  style: textTheme.epMeta,
                ),
                Text(slotRoleLabel(booking.slotRole), style: textTheme.epMeta),
                const SizedBox(height: 8),
                Text(
                  booking.fee.grossMinor > 0
                      ? 'Artist receives ${booking.fee.artistNet.label}'
                      : 'No fee',
                  style: textTheme.epCaption,
                ),
                const SizedBox(height: 8),
                StatusPill(label: booking.status.label),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenSection extends StatelessWidget {
  const _OpenSection({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final browse = app.browse;
    final opportunities = <String, BrowseItem>{};
    for (final item in [...browse.invited, ...browse.items]) {
      opportunities.putIfAbsent(item.opportunity.id, () => item);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            key: const Key('band-gigs-filters'),
            onPressed: () =>
                showEpSheet(context, (_) => _OpportunityFiltersSheet(app: app)),
            child: const Text('FILTERS'),
          ),
        ),
        const SizedBox(height: 12),
        if (browse.status == DataStatus.connecting)
          const LinearProgressIndicator(),
        if (browse.status == DataStatus.error) ...[
          EmptyNote(message: browse.error ?? 'Could not load opportunities.'),
          TextButton(onPressed: app.refreshBrowse, child: const Text('RETRY')),
        ],
        for (final item in opportunities.values) ...[
          _OpportunityCard(
            key: ValueKey('opp-card-${item.opportunity.id}'),
            item: item,
          ),
          const SizedBox(height: 12),
        ],
        if (browse.status == DataStatus.ready &&
            browse.invited.isEmpty &&
            browse.items.isEmpty)
          const EmptyNote(message: 'Nothing open right now.'),
        if (!browse.isDone)
          OutlinedButton(
            key: const Key('band-gigs-load-more'),
            onPressed: app.loadMoreOpportunities,
            child: const Text('LOAD MORE'),
          ),
      ],
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({super.key, required this.item});

  final BrowseItem item;

  @override
  Widget build(BuildContext context) {
    final opportunity = item.opportunity;
    final venue = opportunity.venue;
    return EpCard(
      onTap: () => context.read<AppState>().openOpportunity(opportunity.slug),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DateBlock.forDate(opportunity.startsAt),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      opportunity.title,
                      style: Theme.of(context).textTheme.epSectionHeading,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      venue == null
                          ? opportunity.area
                          : '${venue.name} · ${venue.area}',
                      style: Theme.of(context).textTheme.epMeta,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final slot in opportunity.slots)
            Text(
              '${slot.role.name.toUpperCase()} · ${Money(slot.guaranteeMinor, opportunity.currency).label}',
              style: Theme.of(context).textTheme.epMeta,
            ),
          const SizedBox(height: 8),
          Text(
            'Apply by ${_opportunityDate(opportunity.applicationsCloseAt)}',
            style: Theme.of(context).textTheme.epCaption,
          ),
          if (item.invited || item.myApplicationStatus != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if (item.invited)
                  const StatusPill(
                    label: 'INVITED',
                    tone: EpStatusPillTone.selected,
                  ),
                if (item.myApplicationStatus case final status?)
                  StatusPill(label: applicationStatusLabel(status)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AppliedSection extends StatefulWidget {
  const _AppliedSection({required this.app});

  final AppState app;

  @override
  State<_AppliedSection> createState() => _AppliedSectionState();
}

class _AppliedSectionState extends State<_AppliedSection> {
  final Set<String> _withdrawing = {};

  Future<void> _withdraw(ArtistApplication application) async {
    if (!_withdrawing.add(application.id)) return;
    setState(() {});
    final app = widget.app;
    try {
      if (!await _confirm(
        context,
        'Withdraw application?',
        'Your band will no longer be considered for this opportunity.',
      )) {
        return;
      }
      await app.repository.withdrawApplication(application.id);
      await app.refreshMyApplications();
      await app.refreshBrowse();
    } catch (error) {
      app.say(error is StateError ? error.message : '$error');
    } finally {
      if (mounted) setState(() => _withdrawing.remove(application.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final applications = app.myApplications;
    if (applications.isEmpty) {
      return const EmptyNote(message: 'Your applications will appear here.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in applications) ...[
          EpCard(
            key: ValueKey('band-app-${row.application.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DateBlock.forDate(row.opportunity.startsAt),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.opportunity.title,
                            style: Theme.of(context).textTheme.epSectionHeading,
                          ),
                          Text(
                            _opportunityDate(row.opportunity.startsAt),
                            style: Theme.of(context).textTheme.epMeta,
                          ),
                          Text(
                            row.opportunity.slots
                                    .where(
                                      (slot) =>
                                          slot.id == row.application.slotId,
                                    )
                                    .firstOrNull
                                    ?.role
                                    .name
                                    .toUpperCase() ??
                                'Slot unavailable',
                            style: Theme.of(context).textTheme.epMeta,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(
                      label:
                          row.application.status ==
                              ArtistApplicationStatus.offered
                          ? 'Offer received'
                          : applicationStatusLabel(row.application.status),
                    ),
                    if (row.application.status ==
                            ArtistApplicationStatus.offered ||
                        row.application.status ==
                            ArtistApplicationStatus.booked)
                      if (app.bandBookings
                              .where(
                                (booking) =>
                                    booking.applicationId == row.application.id,
                              )
                              .firstOrNull
                          case final booking?)
                        TextButton(
                          key: ValueKey(
                            'band-app-${row.application.id}-'
                            '${row.application.status == ArtistApplicationStatus.offered ? 'respond' : 'booking'}',
                          ),
                          onPressed: () => app.openBooking(booking.id),
                          child: Text(
                            row.application.status ==
                                    ArtistApplicationStatus.offered
                                ? 'RESPOND'
                                : 'VIEW BOOKING',
                          ),
                        ),
                    if (row.application.status.isActive &&
                        row.application.status !=
                            ArtistApplicationStatus.offered)
                      TextButton(
                        key: ValueKey(
                          'band-app-${row.application.id}-withdraw',
                        ),
                        onPressed: _withdrawing.contains(row.application.id)
                            ? null
                            : () => _withdraw(row.application),
                        child: const Text('WITHDRAW'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

String _opportunityDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  return '${months[local.month - 1]} ${local.day}';
}

class _OpportunityFiltersSheet extends StatefulWidget {
  const _OpportunityFiltersSheet({required this.app});

  final AppState app;

  @override
  State<_OpportunityFiltersSheet> createState() =>
      _OpportunityFiltersSheetState();
}

class _OpportunityFiltersSheetState extends State<_OpportunityFiltersSheet> {
  late final _area = TextEditingController(text: widget.app.browseFilters.area);
  late final _minimum = TextEditingController(
    text: widget.app.browseFilters.minGuaranteeMinor == null
        ? ''
        : (widget.app.browseFilters.minGuaranteeMinor! / 100).toStringAsFixed(
            2,
          ),
  );
  late String? _genre = widget.app.browseFilters.genre;
  late VenueType? _venueType = widget.app.browseFilters.venueType;
  String? _error;

  @override
  void dispose() {
    _area.dispose();
    _minimum.dispose();
    super.dispose();
  }

  void _apply() {
    final amount = double.tryParse(_minimum.text.trim());
    if (_minimum.text.trim().isNotEmpty &&
        (amount == null || !amount.isFinite || amount < 0)) {
      setState(() => _error = 'Enter a valid minimum guarantee.');
      return;
    }
    widget.app.setBrowseFilters(
      OpportunityFilters(
        area: _area.text.trim().isEmpty ? null : _area.text.trim(),
        genre: _genre,
        venueType: _venueType,
        minGuaranteeMinor: amount == null ? null : (amount * 100).round(),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: EpSheetShell(
        heightFactor: .88,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        header: Row(
          children: [
            Expanded(
              child: Text(
                'FILTERS',
                style: Theme.of(context).textTheme.epSectionHeading,
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        children: [
          Expanded(
            child: ListView(
              children: [
                EpLabeledField(
                  label: 'AREA',
                  hint: 'Any area',
                  controller: _area,
                  fieldKey: const Key('band-gigs-filter-area'),
                ),
                const SizedBox(height: 18),
                const SectionBar(label: 'GENRE'),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final genre in kGenres)
                      EpChip(
                        label: genre,
                        active: _genre == genre,
                        onTap: () => setState(
                          () => _genre = _genre == genre ? null : genre,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const SectionBar(label: 'VENUE TYPE'),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final type in VenueType.values)
                      EpChip(
                        label: type.name.toUpperCase(),
                        active: _venueType == type,
                        onTap: () => setState(
                          () => _venueType = _venueType == type ? null : type,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                EpLabeledField(
                  label: 'MINIMUM GUARANTEE (DOLLARS)',
                  hint: 'Any guarantee',
                  controller: _minimum,
                  fieldKey: const Key('band-gigs-filter-minimum'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) InlineFormFeedback(error: _error),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('band-gigs-filter-apply'),
            onPressed: _apply,
            child: const Text('APPLY'),
          ),
        ],
      ),
    );
  }
}

class _ProjectSection extends StatelessWidget {
  const _ProjectSection({
    required this.title,
    required this.projects,
    required this.empty,
    this.readOnly = false,
  });

  final String title;
  final List<GigProject> projects;
  final String empty;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionBar(
          label: title,
          count: projects.isEmpty ? null : projects.length,
        ),
        const SizedBox(height: 10),
        if (projects.isEmpty)
          EmptyNote(
            message: empty,
            padding: const EdgeInsets.all(18),
            style: Theme.of(context).textTheme.epCaption,
          )
        else
          for (var index = 0; index < projects.length; index++) ...[
            _ProjectCard(project: projects[index], readOnly: readOnly),
            if (index < projects.length - 1) const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _DraftSection extends StatelessWidget {
  const _DraftSection({required this.projects});

  final List<GigProject> projects;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final canWrite = app.gigWritePolicy && app.isAdminOf(app.bandId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionBar(
          label: 'LEGACY DRAFTS',
          count: projects.isEmpty ? null : projects.length,
        ),
        const SizedBox(height: 10),
        if (!app.gigWritePolicy)
          const EmptyNote(message: 'Drafts are read-only now'),
        if (projects.isEmpty)
          DashedBox(
            padding: const EdgeInsets.all(18),
            child: Text(
              'No saved drafts.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.epCaption,
            ),
          )
        else
          for (var index = 0; index < projects.length; index++) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: GhostDraftRow(
                        title: _projectTitle(projects[index]),
                        missing: _draftMissing(projects[index]),
                        onResume: canWrite
                            ? () => app.editGigProject(projects[index].id)
                            : null,
                        actionLabel: canWrite ? 'RESUME →' : '',
                      ),
                    ),
                    if (canWrite)
                      IconButton(
                        key: ValueKey('gig-actions-${projects[index].id}'),
                        tooltip:
                            'More actions for ${_projectTitle(projects[index])}',
                        onPressed: () =>
                            _showProjectActions(context, app, projects[index]),
                        icon: Icon(Icons.more_horiz),
                      ),
                  ],
                ),
                if (app.isAdminOf(app.bandId) && !app.gigWritePolicy)
                  _FeatureAction(
                    key: ValueKey('gig-delete-${projects[index].id}'),
                    icon: Icons.delete_outline,
                    label: 'DELETE',
                    onTap: () => _runProjectAction(
                      context,
                      app,
                      projects[index],
                      _ProjectAction.delete,
                    ),
                  )
                else if (canWrite)
                  Row(
                    children: [
                      Expanded(
                        child: _FeatureAction(
                          key: ValueKey('gig-preview-${projects[index].id}'),
                          icon: Icons.visibility,
                          label: 'PREVIEW',
                          onTap: () => _runProjectAction(
                            context,
                            app,
                            projects[index],
                            _ProjectAction.preview,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _FeatureAction(
                          key: ValueKey('gig-edit-${projects[index].id}'),
                          icon: Icons.edit,
                          label: 'EDIT',
                          onTap: () => _runProjectAction(
                            context,
                            app,
                            projects[index],
                            _ProjectAction.edit,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (index < projects.length - 1) const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _PastSection extends StatelessWidget {
  const _PastSection({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final past = app.myBand?.past ?? const <PastGig>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionBar(label: 'PAST', count: past.isEmpty ? null : past.length),
        const SizedBox(height: 8),
        if (past.isEmpty)
          Text(
            'Played gigs will collect here after your first show.',
            style: Theme.of(context).textTheme.epCaption,
          )
        else
          for (final show in past)
            LedgerRow(title: show.title, details: [show.meta]),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, this.readOnly = false});

  final GigProject project;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final canManage = !readOnly && app.isAdminOf(app.bandId);
    final canWrite = canManage && app.gigWritePolicy;
    final venue = project.venueId == null ? null : app.venue(project.venueId!);
    final cachedGig = project.publicGigId == null
        ? null
        : app.allGigs.where((gig) => gig.id == project.publicGigId).firstOrNull;
    final date = _projectDate(context, project);
    final doorLaunch = _doorLaunch(context, app, project);
    final statusLabel = project.hasUnpublishedChanges
        ? 'UNPUBLISHED CHANGES'
        : project.status.name.toUpperCase();
    final statusTone = project.hasUnpublishedChanges
        ? EpStatusPillTone.warning
        : project.status == GigProjectStatus.published
        ? EpStatusPillTone.success
        : EpStatusPillTone.neutral;
    final meta = [
      venue?.name ?? 'Venue TBD',
      if (cachedGig != null) '${app.rsvpCount(cachedGig)} going',
    ];

    return EpCard(
      key: ValueKey('gig-project-${project.id}'),
      padding: EdgeInsets.zero,
      onTap: canWrite ? () => app.editGigProject(project.id) : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 10),
            child: Row(
              children: [
                DateBlock(
                  day: date.day,
                  month: date.month,
                  semanticLabel: date.semanticLabel,
                  size: 54,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _projectTitle(project),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.epSectionHeading,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        meta.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.epMeta,
                      ),
                      const SizedBox(height: 7),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: StatusPill(label: statusLabel, tone: statusTone),
                      ),
                    ],
                  ),
                ),
                if (canManage)
                  IconButton(
                    key: ValueKey('gig-actions-${project.id}'),
                    tooltip: 'More actions for ${_projectTitle(project)}',
                    onPressed: () => _showProjectActions(context, app, project),
                    icon: Icon(Icons.more_horiz),
                  ),
              ],
            ),
          ),
          Divider(height: 1),
          Row(
            children: [
              if (doorLaunch != null)
                Expanded(
                  child: _FeatureAction(
                    key: ValueKey('gig-door-${project.id}'),
                    icon: Icons.qr_code_scanner,
                    label: 'DOOR',
                    onTap: () => showDoorMode(context, doorLaunch),
                  ),
                ),
              Expanded(
                child: _FeatureAction(
                  key: ValueKey('gig-preview-${project.id}'),
                  icon: Icons.visibility,
                  label: 'PREVIEW',
                  onTap: () => _runProjectAction(
                    context,
                    app,
                    project,
                    _ProjectAction.preview,
                  ),
                ),
              ),
              if (canWrite)
                Expanded(
                  child: _FeatureAction(
                    key: ValueKey('gig-edit-${project.id}'),
                    icon: Icons.edit,
                    label: 'EDIT',
                    onTap: () => _runProjectAction(
                      context,
                      app,
                      project,
                      _ProjectAction.edit,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureAction extends StatelessWidget {
  const _FeatureAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: context.epColors.accent),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.epChipLabel),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ProjectAction { edit, preview, duplicate, unpublish, cancel, delete }

void _showProjectActions(
  BuildContext context,
  AppState app,
  GigProject project,
) {
  if (!app.isAdminOf(app.bandId) ||
      project.status == GigProjectStatus.cancelled) {
    return;
  }
  final items = <EpActionSheetItem>[
    if (app.gigWritePolicy)
      EpActionSheetItem(
        label: 'Duplicate',
        icon: Icons.copy,
        onPressed: () => unawaited(
          _runProjectAction(context, app, project, _ProjectAction.duplicate),
        ),
      ),
    if (project.status == GigProjectStatus.published)
      EpActionSheetItem(
        label: 'Unpublish…',
        icon: Icons.visibility_off,
        onPressed: () => unawaited(
          _runProjectAction(context, app, project, _ProjectAction.unpublish),
        ),
      ),
    if (project.status == GigProjectStatus.published)
      EpActionSheetItem(
        label: 'Cancel gig…',
        icon: Icons.block,
        onPressed: () => unawaited(
          _runProjectAction(context, app, project, _ProjectAction.cancel),
        ),
      ),
    EpActionSheetItem(
      label: 'Delete',
      icon: Icons.delete_outline,
      destructive: true,
      onPressed: () => unawaited(
        _runProjectAction(context, app, project, _ProjectAction.delete),
      ),
    ),
  ];
  unawaited(
    showEpActionSheet(context, header: _projectTitle(project), items: items),
  );
}

Future<void> _runProjectAction(
  BuildContext context,
  AppState app,
  GigProject project,
  _ProjectAction action,
) async {
  if (action != _ProjectAction.preview &&
      (project.status == GigProjectStatus.cancelled ||
          !app.isAdminOf(app.bandId) ||
          (!app.gigWritePolicy &&
              (action == _ProjectAction.edit ||
                  action == _ProjectAction.duplicate)))) {
    return;
  }
  switch (action) {
    case _ProjectAction.edit:
      await app.editGigProject(project.id);
    case _ProjectAction.preview:
      await app.editGigProject(project.id);
      app.previewGigDraft();
    case _ProjectAction.duplicate:
      await app.duplicateGigProject(project.id);
    case _ProjectAction.unpublish:
      if (await _confirm(
        context,
        'Unpublish gig?',
        'Fans will no longer see it. The listing returns to Drafts.',
      )) {
        await app.unpublishGigProject(project.id);
      }
    case _ProjectAction.cancel:
      if (await _confirm(
        context,
        'Cancel gig?',
        'The gig leaves discovery but its public page stays available as cancelled.',
      )) {
        await app.cancelGigProject(project.id);
      }
    case _ProjectAction.delete:
      if (await _confirm(
        context,
        'Delete gig permanently?',
        'The listing, RSVPs, saves, and invite links will be removed.',
      )) {
        await app.deleteGigProject(project.id);
      }
  }
}

DoorModeLaunch? _doorLaunch(
  BuildContext context,
  AppState app,
  GigProject project,
) {
  if (project.status != GigProjectStatus.published ||
      project.ticketing != Ticketing.rsvp) {
    return null;
  }
  final venueName = project.venueId == null
      ? 'Venue TBD'
      : app.venue(project.venueId!).name;
  final doorsTime = project.doorsAt == null
      ? 'TBD'
      : TimeOfDay.fromDateTime(project.doorsAt!.toLocal()).format(context);
  return DoorModeLaunch(
    projectId: project.id,
    gigTitle: _projectTitle(project),
    venueName: venueName,
    doorsTime: doorsTime,
  );
}

({String day, String month, String semanticLabel}) _projectDate(
  BuildContext context,
  GigProject project,
) {
  final date = project.startsAt;
  if (date == null) {
    return (day: '—', month: 'TBD', semanticLabel: 'Date to be determined');
  }
  final parts = Gig.dateShortFor(date.millisecondsSinceEpoch).split(' ');
  return (
    day: parts.last,
    month: parts.length > 1 ? parts[parts.length - 2] : '',
    semanticLabel: MaterialLocalizations.of(
      context,
    ).formatFullDate(date.toLocal()),
  );
}

String _projectTitle(GigProject project) {
  final title = project.title?.trim();
  return title == null || title.isEmpty ? 'Untitled gig' : title;
}

String _draftMissing(GigProject project) {
  final missing = <String>[
    if (project.title?.trim().isNotEmpty != true) 'name',
    if (project.startsAt == null || project.doorsAt == null) 'date and times',
    if (project.venueId == null) 'venue',
    if (project.performers.isEmpty) 'lineup',
  ];
  return missing.isEmpty
      ? 'review before publishing'
      : 'finish ${missing.join(', ')}';
}

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('KEEP'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('CONFIRM'),
          ),
        ],
      ),
    ) ??
    false;
