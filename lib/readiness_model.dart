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
  editOrgProfile,
  setUpFinance,
}

/// One readiness step, with the copy the checklist shows and the action that
/// resolves it.
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

/// A readiness checklist in order. [ReadinessSnapshot.band] builds the nine
/// band steps and [ReadinessSnapshot.host] the two host steps; the module and
/// sheet read [total] from the snapshot so they serve either.
class ReadinessSnapshot {
  final List<ReadinessStep> steps;

  ReadinessSnapshot(List<ReadinessStep> steps)
    : steps = List.unmodifiable(steps);

  /// The nine band step ids in checklist order: six discovery criteria from
  /// [BandDiscoveryReadiness] followed by three setup tasks from
  /// [BandSetupStatus].
  static const List<String> bandStepIds = [
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

  static const List<String> hostStepIds = [
    'org-setup-profile',
    'org-setup-finance',
  ];

  /// The band checklist. Null until both sources have loaded; a partial
  /// checklist would report a misleading count.
  static ReadinessSnapshot? band({
    required BandDiscoveryReadiness? readiness,
    required BandSetupStatus? setup,
  }) {
    if (readiness == null || setup == null) return null;
    final hasShow = readiness.relevantShow != null;
    final showAction = hasShow
        ? ReadinessAction.manageShow
        : ReadinessAction.createShow;
    return ReadinessSnapshot([
      ReadinessStep(
        id: bandStepIds[0],
        label: 'Complete profile',
        reason: 'Hosts read this first.',
        actionLabel: 'Edit',
        action: ReadinessAction.editProfile,
        done: readiness.profileComplete,
      ),
      ReadinessStep(
        id: bandStepIds[1],
        label: 'Profile image',
        reason: 'Cards and lineups show it.',
        actionLabel: 'Add',
        action: ReadinessAction.addMedia,
        done: readiness.profileImageReady,
      ),
      ReadinessStep(
        id: bandStepIds[2],
        label: 'Video clip',
        reason: 'Hosts listen before booking.',
        actionLabel: 'Add',
        action: ReadinessAction.addMedia,
        done: readiness.clipReady,
      ),
      ReadinessStep(
        id: bandStepIds[3],
        label: 'Published lineup',
        reason: 'Nearby fans find you through shows.',
        actionLabel: hasShow ? 'Manage' : 'Create',
        action: showAction,
        done: readiness.publishedShowReady,
      ),
      ReadinessStep(
        id: bandStepIds[4],
        label: 'Venue and readable poster',
        reason: 'A venue and a readable poster make the listing.',
        actionLabel: hasShow ? 'Edit' : 'Create',
        action: showAction,
        done: readiness.venuePosterReady,
      ),
      ReadinessStep(
        id: bandStepIds[5],
        label: 'Latest revision published',
        reason: 'Fans see the published version.',
        actionLabel: hasShow ? 'Republish' : 'Create',
        action: hasShow
            ? ReadinessAction.republish
            : ReadinessAction.createShow,
        done: readiness.publishedRevisionCurrent,
      ),
      ReadinessStep(
        id: bandStepIds[6],
        label: 'Public profile previewed',
        reason: 'See what hosts and fans see.',
        actionLabel: 'Preview',
        action: ReadinessAction.preview,
        done: setup.publicProfilePreviewed,
      ),
      ReadinessStep(
        id: bandStepIds[7],
        label: 'Add social links',
        reason: 'Hosts check these before booking.',
        actionLabel: 'Edit',
        action: ReadinessAction.editLinks,
        done: setup.socialLinksAdded,
      ),
      ReadinessStep(
        id: bandStepIds[8],
        label: 'Invite band members',
        reason: 'Members can manage gigs with you.',
        actionLabel: 'Invite',
        action: ReadinessAction.inviteMembers,
        done: setup.membersInvited,
      ),
    ]);
  }

  /// The host checklist: a complete organization profile and a finance setup
  /// that can take deposits and pay out.
  factory ReadinessSnapshot.host({
    required bool profileComplete,
    required bool financeReady,
  }) => ReadinessSnapshot([
    ReadinessStep(
      id: hostStepIds[0],
      label: 'Complete profile',
      reason: 'Artists check this before applying.',
      actionLabel: 'Edit',
      action: ReadinessAction.editOrgProfile,
      done: profileComplete,
    ),
    ReadinessStep(
      id: hostStepIds[1],
      label: 'Set up finance',
      reason: 'Deposits and payouts need it.',
      actionLabel: 'Set up',
      action: ReadinessAction.setUpFinance,
      done: financeReady,
    ),
  ]);

  int get total => steps.length;

  /// Ids of every step, in checklist order.
  List<String> get stepIds => [for (final step in steps) step.id];

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
