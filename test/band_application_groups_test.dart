import 'package:earplug/band_application_groups.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('booked applications appear in neither list', () {
    final groups = BandApplicationGroups.from([
      _row('booked', ArtistApplicationStatus.booked),
    ]);

    expect(groups.inProgress, isEmpty);
    expect(groups.decided, isEmpty);
    expect(groups.booked, 1);
    expect(groups.active, 0);
    expect(groups.shortlisted, 0);
  });

  test('in progress sorts by newest creation without changing the input', () {
    final oldest = _row(
      'oldest',
      ArtistApplicationStatus.offered,
      createdDay: 1,
    );
    final newest = _row(
      'newest',
      ArtistApplicationStatus.submitted,
      createdDay: 9,
    );
    final middle = _row(
      'middle',
      ArtistApplicationStatus.underReview,
      createdDay: 4,
    );
    final input = [oldest, newest, middle];

    final groups = BandApplicationGroups.from(input);

    expect(groups.inProgress, [newest, middle, oldest]);
    expect(input, [oldest, newest, middle]);
  });

  test('decided sorts by decision date with updated date as the fallback', () {
    final oldDecision = _row(
      'old-decision',
      ArtistApplicationStatus.declined,
      decidedDay: 2,
      updatedDay: 20,
    );
    final latestUpdate = _row(
      'latest-update',
      ArtistApplicationStatus.withdrawn,
      updatedDay: 10,
    );
    final middleDecision = _row(
      'middle-decision',
      ArtistApplicationStatus.expired,
      decidedDay: 6,
      updatedDay: 1,
    );
    final input = [oldDecision, latestUpdate, middleDecision];

    final groups = BandApplicationGroups.from(input);

    expect(groups.decided, [latestUpdate, middleDecision, oldDecision]);
    expect(input, [oldDecision, latestUpdate, middleDecision]);
  });

  test('counts and groups a mixed list containing all eight statuses', () {
    final groups = BandApplicationGroups.from([
      for (final status in ArtistApplicationStatus.values)
        _row(status.name, status),
    ]);

    expect(groups.active, 4);
    expect(groups.active, groups.inProgress.length);
    expect(groups.shortlisted, 2);
    expect(groups.booked, 1);
    expect(
      groups.inProgress.map((row) => row.application.status),
      unorderedEquals([
        ArtistApplicationStatus.submitted,
        ArtistApplicationStatus.underReview,
        ArtistApplicationStatus.shortlisted,
        ArtistApplicationStatus.offered,
      ]),
    );
    expect(
      groups.decided.map((row) => row.application.status),
      unorderedEquals([
        ArtistApplicationStatus.declined,
        ArtistApplicationStatus.withdrawn,
        ArtistApplicationStatus.expired,
      ]),
    );
  });

  test('an empty list has empty groups and zero counts', () {
    final groups = BandApplicationGroups.from([]);

    expect(groups.inProgress, isEmpty);
    expect(groups.decided, isEmpty);
    expect([groups.active, groups.shortlisted, groups.booked], [0, 0, 0]);
  });
}

BandApplication _row(
  String id,
  ArtistApplicationStatus status, {
  int createdDay = 1,
  int updatedDay = 1,
  int? decidedDay,
}) => BandApplication(
  application: ArtistApplication(
    id: id,
    opportunityId: 'opp1',
    slotId: 'opp1-support',
    bandId: 'b1',
    status: status,
    message: 'Ready to play.',
    createdAt: DateTime.utc(2026, 9, createdDay),
    updatedAt: DateTime.utc(2026, 9, updatedDay),
    decidedAt: decidedDay == null ? null : DateTime.utc(2026, 9, decidedDay),
  ),
  opportunity: DemoData.opportunities['opp1']!,
);
