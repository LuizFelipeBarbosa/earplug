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
  test('null until both sources have loaded', () {
    expect(ReadinessSnapshot.from(readiness: null, setup: null), isNull);
    expect(
      ReadinessSnapshot.from(readiness: _readiness(), setup: null),
      isNull,
    );
    expect(ReadinessSnapshot.from(readiness: null, setup: _setup()), isNull);
    expect(
      ReadinessSnapshot.from(readiness: _readiness(), setup: _setup()),
      isNotNull,
    );
  });

  test('nine steps in checklist order with their copy', () {
    final snapshot = ReadinessSnapshot.from(
      readiness: _readiness(),
      setup: _setup(),
    )!;

    expect(ReadinessSnapshot.total, 9);
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
    expect(snapshot.steps.map((step) => step.id), ReadinessSnapshot.stepIds);
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
    final snapshot = ReadinessSnapshot.from(
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

  test('all nine done is complete', () {
    final snapshot = ReadinessSnapshot.from(
      readiness: _readiness(),
      setup: _setup(),
    )!;
    expect(snapshot.done, 9);
    expect(snapshot.complete, isTrue);
    expect(snapshot.todo, isEmpty);
    expect(snapshot.finished, hasLength(9));
  });

  test('show steps create a gig when the band has no relevant show', () {
    final snapshot = ReadinessSnapshot.from(
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
    final snapshot = ReadinessSnapshot.from(
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
    final snapshot = ReadinessSnapshot.from(
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
}
