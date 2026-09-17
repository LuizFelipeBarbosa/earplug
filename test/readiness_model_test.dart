import 'package:earplug/models.dart';
import 'package:earplug/readiness_model.dart';
import 'package:flutter_test/flutter_test.dart';

final _show = BandDiscoveryShow(
  gigId: 'g1',
  projectId: 'p1',
  title: 'Loud night',
  startsAt: DateTime(2026, 10, 1, 20),
);

BandDiscoveryReadiness _readiness({
  bool profileComplete = true,
  bool profileImageReady = true,
  bool clipReady = true,
  bool publishedShowReady = true,
  bool venuePosterReady = true,
  bool publishedRevisionCurrent = true,
  BandDiscoveryShow? relevantShow,
}) => BandDiscoveryReadiness(
  profileComplete: profileComplete,
  profileImageReady: profileImageReady,
  clipReady: clipReady,
  publishedShowReady: publishedShowReady,
  venuePosterReady: venuePosterReady,
  publishedRevisionCurrent: publishedRevisionCurrent,
  relevantShow: relevantShow,
);

BandSetupStatus _setup({
  bool publicProfilePreviewed = true,
  bool socialLinksAdded = true,
  bool membersInvited = true,
}) => BandSetupStatus(
  profileComplete: true,
  profileImageAdded: true,
  musicAdded: true,
  socialLinksAdded: socialLinksAdded,
  firstGigCreated: true,
  membersInvited: membersInvited,
  publicProfilePreviewed: publicProfilePreviewed,
);

void main() {
  test('band snapshot is null until both sources have loaded', () {
    expect(ReadinessSnapshot.band(readiness: null, setup: null), isNull);
    expect(
      ReadinessSnapshot.band(readiness: _readiness(), setup: null),
      isNull,
    );
    expect(ReadinessSnapshot.band(readiness: null, setup: _setup()), isNull);
    expect(
      ReadinessSnapshot.band(readiness: _readiness(), setup: _setup()),
      isNotNull,
    );
  });

  test('band snapshot has nine steps in checklist order with their copy', () {
    final snapshot = ReadinessSnapshot.band(
      readiness: _readiness(),
      setup: _setup(),
    )!;

    expect(snapshot.total, 9);
    expect(snapshot.steps, hasLength(9));
    expect(snapshot.steps.map((step) => step.id), [
      'band-discovery-profile',
      'band-discovery-image',
      'band-discovery-clip',
      'band-discovery-show',
      'band-discovery-listing',
      'band-discovery-revision',
      'band-setup-preview',
      'band-setup-social',
      'band-setup-members',
    ]);
    expect(snapshot.stepIds, ReadinessSnapshot.bandStepIds);
    expect(snapshot.steps.map((step) => step.label), [
      'Complete profile',
      'Profile image',
      'Video clip',
      'Published lineup',
      'Venue and readable poster',
      'Latest revision published',
      'Public profile previewed',
      'Add social links',
      'Invite band members',
    ]);
    expect(snapshot.steps.map((step) => step.reason), [
      'Hosts read this first.',
      'Cards and lineups show it.',
      'Hosts listen before booking.',
      'Nearby fans find you through shows.',
      'A venue and a readable poster make the listing.',
      'Fans see the published version.',
      'See what hosts and fans see.',
      'Hosts check these before booking.',
      'Members can manage gigs with you.',
    ]);
    expect(snapshot.steps.clear, throwsUnsupportedError);
  });

  test('done, todo and finished follow each source flag', () {
    final snapshot = ReadinessSnapshot.band(
      readiness: _readiness(clipReady: false, venuePosterReady: false),
      setup: _setup(membersInvited: false),
    )!;

    expect(snapshot.done, 6);
    expect(snapshot.complete, isFalse);
    expect(snapshot.todo.map((step) => step.id), [
      'band-discovery-clip',
      'band-discovery-listing',
      'band-setup-members',
    ]);
    expect(snapshot.finished.map((step) => step.id), [
      'band-discovery-profile',
      'band-discovery-image',
      'band-discovery-show',
      'band-discovery-revision',
      'band-setup-preview',
      'band-setup-social',
    ]);
    expect(snapshot.doneIds, {
      'band-discovery-profile',
      'band-discovery-image',
      'band-discovery-show',
      'band-discovery-revision',
      'band-setup-preview',
      'band-setup-social',
    });
  });

  test('all nine band steps done is complete', () {
    final snapshot = ReadinessSnapshot.band(
      readiness: _readiness(),
      setup: _setup(),
    )!;
    expect(snapshot.done, 9);
    expect(snapshot.complete, isTrue);
    expect(snapshot.todo, isEmpty);
    expect(snapshot.finished, hasLength(9));
  });

  test('show steps create a gig when the band has no relevant show', () {
    final snapshot = ReadinessSnapshot.band(
      readiness: _readiness(),
      setup: _setup(),
    )!;
    final byId = {for (final step in snapshot.steps) step.id: step};

    for (final id in [
      'band-discovery-show',
      'band-discovery-listing',
      'band-discovery-revision',
    ]) {
      expect(byId[id]!.action, ReadinessAction.createShow, reason: id);
      expect(byId[id]!.actionLabel, 'Create', reason: id);
    }
  });

  test('show steps manage or republish the relevant show when one exists', () {
    final snapshot = ReadinessSnapshot.band(
      readiness: _readiness(relevantShow: _show),
      setup: _setup(),
    )!;
    final byId = {for (final step in snapshot.steps) step.id: step};

    expect(byId['band-discovery-show']!.action, ReadinessAction.manageShow);
    expect(byId['band-discovery-show']!.actionLabel, 'Manage');
    expect(byId['band-discovery-listing']!.action, ReadinessAction.manageShow);
    expect(byId['band-discovery-listing']!.actionLabel, 'Edit');
    expect(byId['band-discovery-revision']!.action, ReadinessAction.republish);
    expect(byId['band-discovery-revision']!.actionLabel, 'Republish');
  });

  test('the other steps keep their fixed actions', () {
    final snapshot = ReadinessSnapshot.band(
      readiness: _readiness(),
      setup: _setup(),
    )!;
    final byId = {for (final step in snapshot.steps) step.id: step};

    expect(byId['band-discovery-profile']!.action, ReadinessAction.editProfile);
    expect(byId['band-discovery-profile']!.actionLabel, 'Edit');
    expect(byId['band-discovery-image']!.action, ReadinessAction.addMedia);
    expect(byId['band-discovery-image']!.actionLabel, 'Add');
    expect(byId['band-discovery-clip']!.action, ReadinessAction.addMedia);
    expect(byId['band-discovery-clip']!.actionLabel, 'Add');
    expect(byId['band-setup-preview']!.action, ReadinessAction.preview);
    expect(byId['band-setup-preview']!.actionLabel, 'Preview');
    expect(byId['band-setup-social']!.action, ReadinessAction.editLinks);
    expect(byId['band-setup-social']!.actionLabel, 'Edit');
    expect(byId['band-setup-members']!.action, ReadinessAction.inviteMembers);
    expect(byId['band-setup-members']!.actionLabel, 'Invite');
  });

  test('total is the number of steps the snapshot holds', () {
    const step = ReadinessStep(
      id: 'x',
      label: 'X',
      reason: 'Because.',
      actionLabel: 'Do',
      action: ReadinessAction.preview,
      done: true,
    );
    final snapshot = ReadinessSnapshot(const [step, step, step]);
    expect(snapshot.total, 3);
    expect(snapshot.done, 3);
    expect(snapshot.complete, isTrue);
    expect(snapshot.steps.clear, throwsUnsupportedError);
    expect(ReadinessSnapshot(const []).total, 0);
  });

  test('host snapshot has two steps with their copy and actions', () {
    final snapshot = ReadinessSnapshot.host(
      profileComplete: false,
      financeReady: false,
    );

    expect(snapshot.total, 2);
    expect(snapshot.steps, hasLength(2));
    expect(snapshot.stepIds, ['org-setup-profile', 'org-setup-finance']);
    expect(snapshot.stepIds, ReadinessSnapshot.hostStepIds);
    expect(snapshot.steps.map((step) => step.label), [
      'Complete profile',
      'Set up finance',
    ]);
    expect(snapshot.steps.map((step) => step.reason), [
      'Artists check this before applying.',
      'Deposits and payouts need it.',
    ]);
    expect(snapshot.steps.map((step) => step.actionLabel), ['Edit', 'Set up']);
    expect(snapshot.steps.map((step) => step.action), [
      ReadinessAction.editOrgProfile,
      ReadinessAction.setUpFinance,
    ]);
    expect(snapshot.done, 0);
    expect(snapshot.complete, isFalse);
    expect(snapshot.todo, hasLength(2));
    expect(snapshot.finished, isEmpty);
    expect(snapshot.steps.clear, throwsUnsupportedError);
  });

  test('host snapshot follows each flag and is complete at 2 of 2', () {
    final half = ReadinessSnapshot.host(
      profileComplete: true,
      financeReady: false,
    );
    expect(half.done, 1);
    expect(half.complete, isFalse);
    expect(half.todo.map((step) => step.id), ['org-setup-finance']);
    expect(half.doneIds, {'org-setup-profile'});

    final full = ReadinessSnapshot.host(
      profileComplete: true,
      financeReady: true,
    );
    expect(full.done, 2);
    expect(full.total, 2);
    expect('${full.done} of ${full.total}', '2 of 2');
    expect(full.complete, isTrue);
    expect(full.todo, isEmpty);
    expect(full.finished.map((step) => step.id), ReadinessSnapshot.hostStepIds);
  });
}
