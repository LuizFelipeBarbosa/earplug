import 'models.dart';

/// What tapping a readiness step does. The state layer maps each value to a
/// navigation call; the model only names the intent.
enum ReadinessAction {
  editProfile,
  addMedia,
  manageShow,
  createShow,
  republish,
  preview,
  editLinks,
  inviteMembers,
}

/// One of the nine band readiness steps, with the copy the checklist shows
/// and the action that resolves it.
class ReadinessStep {
  final String id;
  final String label;
  final String reason;
  final String actionLabel;
  final ReadinessAction action;
  final bool done;

  const ReadinessStep({
    required this.id,
    required this.label,
    required this.reason,
    required this.actionLabel,
    required this.action,
    required this.done,
  });
}

/// The nine readiness steps in checklist order: six discovery criteria from
/// [BandDiscoveryReadiness] followed by three setup tasks from
/// [BandSetupStatus].
class ReadinessSnapshot {
  final List<ReadinessStep> steps;

  const ReadinessSnapshot._(this.steps);

  static const int total = 9;

  static const List<String> stepIds = [
    'band-discovery-profile',
    'band-discovery-image',
    'band-discovery-clip',
    'band-discovery-show',
    'band-discovery-listing',
    'band-discovery-revision',
    'band-setup-preview',
    'band-setup-social',
    'band-setup-members',
  ];

  /// Null until both sources have loaded; a partial checklist would report a
  /// misleading count.
  static ReadinessSnapshot? from({
    required BandDiscoveryReadiness? readiness,
    required BandSetupStatus? setup,
  }) {
    if (readiness == null || setup == null) return null;
    final hasShow = readiness.relevantShow != null;
    final showAction = hasShow
        ? ReadinessAction.manageShow
        : ReadinessAction.createShow;
    return ReadinessSnapshot._(
      List.unmodifiable([
        ReadinessStep(
          id: stepIds[0],
          label: 'Complete profile',
          reason: 'Hosts read this first.',
          actionLabel: 'Edit',
          action: ReadinessAction.editProfile,
          done: readiness.profileComplete,
        ),
        ReadinessStep(
          id: stepIds[1],
          label: 'Profile image',
          reason: 'Cards and lineups show it.',
          actionLabel: 'Add',
          action: ReadinessAction.addMedia,
          done: readiness.profileImageReady,
        ),
        ReadinessStep(
          id: stepIds[2],
          label: 'Video clip',
          reason: 'Hosts listen before booking.',
          actionLabel: 'Add',
          action: ReadinessAction.addMedia,
          done: readiness.clipReady,
        ),
        ReadinessStep(
          id: stepIds[3],
          label: 'Published lineup',
          reason: 'Nearby fans find you through shows.',
          actionLabel: hasShow ? 'Manage' : 'Create',
          action: showAction,
          done: readiness.publishedShowReady,
        ),
        ReadinessStep(
          id: stepIds[4],
          label: 'Venue and readable poster',
          reason: 'A venue and a readable poster make the listing.',
          actionLabel: hasShow ? 'Edit' : 'Create',
          action: showAction,
          done: readiness.venuePosterReady,
        ),
        ReadinessStep(
          id: stepIds[5],
          label: 'Latest revision published',
          reason: 'Fans see the published version.',
          actionLabel: hasShow ? 'Republish' : 'Create',
          action: hasShow
              ? ReadinessAction.republish
              : ReadinessAction.createShow,
          done: readiness.publishedRevisionCurrent,
        ),
        ReadinessStep(
          id: stepIds[6],
          label: 'Public profile previewed',
          reason: 'See what hosts and fans see.',
          actionLabel: 'Preview',
          action: ReadinessAction.preview,
          done: setup.publicProfilePreviewed,
        ),
        ReadinessStep(
          id: stepIds[7],
          label: 'Add social links',
          reason: 'Hosts check these before booking.',
          actionLabel: 'Edit',
          action: ReadinessAction.editLinks,
          done: setup.socialLinksAdded,
        ),
        ReadinessStep(
          id: stepIds[8],
          label: 'Invite band members',
          reason: 'Members can manage gigs with you.',
          actionLabel: 'Invite',
          action: ReadinessAction.inviteMembers,
          done: setup.membersInvited,
        ),
      ]),
    );
  }

  int get done => steps.where((step) => step.done).length;

  bool get complete => done == total;

  List<ReadinessStep> get todo => [
    for (final step in steps)
      if (!step.done) step,
  ];

  List<ReadinessStep> get finished => [
    for (final step in steps)
      if (step.done) step,
  ];

  /// Ids of the steps done now, in checklist order.
  Set<String> get doneIds => {
    for (final step in steps)
      if (step.done) step.id,
  };
}

/// Steps that were done at an earlier look and have since failed, with the
/// moment the first of them was noticed.
class ReadinessRegression {
  final List<String> stepIds;
  final DateTime since;

  const ReadinessRegression({required this.stepIds, required this.since});
}
