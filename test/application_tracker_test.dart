import 'dart:async';

import 'package:earplug/application_tracker.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

final _createdAt = DateTime(2026, 9, 1);
final _viewedAt = DateTime(2026, 9, 2);
final _shortlistedAt = DateTime(2026, 9, 3);
final _decidedAt = DateTime(2026, 9, 4);
final _hostNoteAt = DateTime(2026, 9, 5);

ArtistApplication _application({
  ArtistApplicationStatus status = ArtistApplicationStatus.submitted,
  DateTime? viewedAt,
  DateTime? shortlistedAt,
  DateTime? decidedAt,
}) => ArtistApplication(
  id: 'application',
  opportunityId: 'opportunity',
  slotId: 'slot',
  bandId: 'band',
  status: status,
  message: 'Ready to play.',
  viewedAt: viewedAt,
  shortlistedAt: shortlistedAt,
  decidedAt: decidedAt,
  createdAt: _createdAt,
  updatedAt: _createdAt,
);

void main() {
  group('ApplicationTracker', () {
    const applied = ApplicationTrackerStep.applied;
    const viewed = ApplicationTrackerStep.viewed;
    const shortlisted = ApplicationTrackerStep.shortlisted;
    const decision = ApplicationTrackerStep.decision;
    const expectations = {
      ArtistApplicationStatus.submitted: (
        reached: {applied},
        outcome: ApplicationOutcome.pending,
      ),
      ArtistApplicationStatus.underReview: (
        reached: {applied, viewed},
        outcome: ApplicationOutcome.pending,
      ),
      ArtistApplicationStatus.shortlisted: (
        reached: {applied, viewed, shortlisted},
        outcome: ApplicationOutcome.pending,
      ),
      ArtistApplicationStatus.offered: (
        reached: {applied, viewed, shortlisted, decision},
        outcome: ApplicationOutcome.offered,
      ),
      ArtistApplicationStatus.booked: (
        reached: {applied, viewed, shortlisted, decision},
        outcome: ApplicationOutcome.booked,
      ),
      ArtistApplicationStatus.declined: (
        reached: {applied, viewed, decision},
        outcome: ApplicationOutcome.declined,
      ),
      ArtistApplicationStatus.withdrawn: (
        reached: {applied, decision},
        outcome: ApplicationOutcome.withdrawn,
      ),
      ArtistApplicationStatus.expired: (
        reached: {applied, decision},
        outcome: ApplicationOutcome.expired,
      ),
    };

    for (final status in ArtistApplicationStatus.values) {
      for (final hasViewedAt in [false, true]) {
        for (final hasShortlistedAt in [false, true]) {
          for (final hasDecidedAt in [false, true]) {
            test('${status.name}: viewedAt=$hasViewedAt, '
                'shortlistedAt=$hasShortlistedAt, decidedAt=$hasDecidedAt', () {
              final application = _application(
                status: status,
                viewedAt: hasViewedAt ? _viewedAt : null,
                shortlistedAt: hasShortlistedAt ? _shortlistedAt : null,
                decidedAt: hasDecidedAt ? _decidedAt : null,
              );
              final expected = expectations[status]!;
              final tracker = ApplicationTracker.of(application);

              expect(tracker.reached, {
                ...expected.reached,
                if (hasViewedAt) viewed,
                if (hasShortlistedAt) shortlisted,
              });
              expect(tracker.outcome, expected.outcome);
              expect(tracker.stepTimes, {
                applied: _createdAt,
                viewed: hasViewedAt ? _viewedAt : null,
                shortlisted: hasShortlistedAt ? _shortlistedAt : null,
                decision: hasDecidedAt ? _decidedAt : null,
              });
            });
          }
        }
      }
    }

    test('declined without a shortlist timestamp skips shortlisted', () {
      final tracker = ApplicationTracker.of(
        _application(status: ArtistApplicationStatus.declined),
      );
      expect(tracker.reached, {applied, viewed, decision});
      expect(tracker.stepTimes[shortlisted], isNull);
    });

    test('declined keeps a recorded shortlist step', () {
      final tracker = ApplicationTracker.of(
        _application(
          status: ArtistApplicationStatus.declined,
          shortlistedAt: _shortlistedAt,
        ),
      );
      expect(tracker.reached, {applied, viewed, shortlisted, decision});
      expect(tracker.stepTimes[shortlisted], _shortlistedAt);
    });

    const decidedOutcomes = {
      ApplicationOutcome.pending: false,
      ApplicationOutcome.offered: false,
      ApplicationOutcome.booked: true,
      ApplicationOutcome.declined: true,
      ApplicationOutcome.withdrawn: true,
      ApplicationOutcome.expired: true,
    };
    for (final outcome in ApplicationOutcome.values) {
      test('isDecided for ${outcome.name}', () {
        final tracker = ApplicationTracker(
          reached: const {},
          outcome: outcome,
          stepTimes: const {},
        );
        expect(tracker.isDecided, decidedOutcomes[outcome]);
      });
    }
  });

  group('ApplicationDeclineReason', () {
    const labels = {
      ApplicationDeclineReason.slotFilled:
          'Slot filled — hosts can see your profile for future nights',
      ApplicationDeclineReason.notAFit: 'Not the fit for this night',
      ApplicationDeclineReason.lineupFull: 'Lineup already full',
      ApplicationDeclineReason.dateConflict: 'Date conflict on the host side',
      ApplicationDeclineReason.other: 'The host passed this time',
    };
    const wireValues = {
      'slot_filled': ApplicationDeclineReason.slotFilled,
      'not_a_fit': ApplicationDeclineReason.notAFit,
      'lineup_full': ApplicationDeclineReason.lineupFull,
      'date_conflict': ApplicationDeclineReason.dateConflict,
      'other': ApplicationDeclineReason.other,
    };

    test('labels use the expected copy', () {
      for (final reason in ApplicationDeclineReason.values) {
        expect(reason.label, labels[reason]);
      }
    });

    test('wire values decode and unknown reasons fall back to other', () {
      for (final entry in wireValues.entries) {
        expect(entry.value.wireValue, entry.key);
        expect(ApplicationDeclineReason.fromWire(entry.key), entry.value);
      }
      expect(
        ApplicationDeclineReason.fromWire('unrecognized'),
        ApplicationDeclineReason.other,
      );
    });
  });

  group('ArtistApplication', () {
    final json = <String, dynamic>{
      '_id': 'application',
      'opportunityId': 'opportunity',
      'slotId': 'slot',
      'bandId': 'band',
      'status': 'declined',
      'message': 'Ready to play.',
      'createdAt': _createdAt.millisecondsSinceEpoch,
      'updatedAt': _decidedAt.millisecondsSinceEpoch,
    };

    test('decodes all six populated tracker fields', () {
      final application = ArtistApplication.fromJson({
        ...json,
        'viewedAt': _viewedAt.millisecondsSinceEpoch,
        'shortlistedAt': _shortlistedAt.millisecondsSinceEpoch,
        'declineReason': 'slot_filled',
        'declineNote': 'We filled this slot.',
        'hostNote': 'Keep in touch.',
        'hostNoteAt': _hostNoteAt.millisecondsSinceEpoch,
      });

      expect(application.viewedAt, _viewedAt);
      expect(application.shortlistedAt, _shortlistedAt);
      expect(application.declineReason, ApplicationDeclineReason.slotFilled);
      expect(application.declineNote, 'We filled this slot.');
      expect(application.hostNote, 'Keep in touch.');
      expect(application.hostNoteAt, _hostNoteAt);
    });

    for (final explicitNulls in [false, true]) {
      test('decodes nullable tracker fields: explicitNulls=$explicitNulls', () {
        final application = ArtistApplication.fromJson({
          ...json,
          if (explicitNulls) ...{
            'viewedAt': null,
            'shortlistedAt': null,
            'declineReason': null,
            'declineNote': null,
            'hostNote': null,
            'hostNoteAt': null,
          },
        });

        expect(application.viewedAt, isNull);
        expect(application.shortlistedAt, isNull);
        expect(application.declineReason, isNull);
        expect(application.declineNote, isNull);
        expect(application.hostNote, isNull);
        expect(application.hostNoteAt, isNull);
      });
    }

    test('copyWith sets, preserves, and clears nullable tracker fields', () {
      final populated = _application().copyWith(
        viewedAt: _viewedAt,
        shortlistedAt: _shortlistedAt,
        decidedAt: _decidedAt,
        declineReason: ApplicationDeclineReason.notAFit,
        declineNote: 'Try another night.',
        hostNote: 'Keep in touch.',
        hostNoteAt: _hostNoteAt,
      );
      for (final application in [populated, populated.copyWith()]) {
        expect(application.viewedAt, _viewedAt);
        expect(application.shortlistedAt, _shortlistedAt);
        expect(application.decidedAt, _decidedAt);
        expect(application.declineReason, ApplicationDeclineReason.notAFit);
        expect(application.declineNote, 'Try another night.');
        expect(application.hostNote, 'Keep in touch.');
        expect(application.hostNoteAt, _hostNoteAt);
      }

      final cleared = populated.copyWith(
        viewedAt: null,
        shortlistedAt: null,
        decidedAt: null,
        declineReason: null,
        declineNote: null,
        hostNote: null,
        hostNoteAt: null,
      );
      expect(cleared.viewedAt, isNull);
      expect(cleared.shortlistedAt, isNull);
      expect(cleared.decidedAt, isNull);
      expect(cleared.declineReason, isNull);
      expect(cleared.declineNote, isNull);
      expect(cleared.hostNote, isNull);
      expect(cleared.hostNoteAt, isNull);
    });
  });

  group('DemoRepository application tracker', () {
    late DemoRepository repository;

    setUp(() async {
      final auth = FakeAuthService();
      repository = DemoRepository(auth: auth);
      await auth.signInDemo();
    });

    test(
      'watchMyApplications replays the band and emits when viewed',
      () async {
        final current = await repository.myApplications('b1');
        final first = Completer<List<BandApplication>>();
        final snapshots = repository
            .watchMyApplications('b1')
            .map((applications) {
              if (!first.isCompleted) first.complete(applications);
              return applications;
            })
            .take(2)
            .toList();

        final initial = await first.future;
        expect(initial.map((row) => row.application), [
          for (final row in current) same(row.application),
        ]);
        expect(initial.map((row) => row.application.id), ['app1']);
        expect(initial.single.application.viewedAt, isNull);

        // Let the replay attach to the broadcast stream before mutating it.
        final viewedAt = await Future<DateTime?>(
          () => repository.markApplicationViewed('app1'),
        );
        final emissions = await snapshots;
        expect(emissions, hasLength(2));
        expect(emissions.last.single.application.id, 'app1');
        expect(emissions.last.single.application.viewedAt, isNotNull);
        expect(emissions.last.single.application.viewedAt, viewedAt);
        expect(
          emissions.last.single.application.status,
          ArtistApplicationStatus.submitted,
        );
      },
    );

    test(
      'markApplicationViewed is idempotent and skips terminal states',
      () async {
        final viewedAt = await repository.markApplicationViewed('app1');
        expect(viewedAt, isNotNull);
        expect(await repository.markApplicationViewed('app1'), viewedAt);

        final app3 = (await repository.myApplications(
          'b2',
        )).singleWhere((row) => row.application.id == 'app3').application;
        expect(await repository.markApplicationViewed('app3'), app3.viewedAt);

        await repository.withdrawApplication('app1');
        expect(await repository.markApplicationViewed('app1'), viewedAt);
        final freshRepository = DemoRepository(auth: FakeAuthService());
        await freshRepository.withdrawApplication('app1');
        expect(await freshRepository.markApplicationViewed('app1'), isNull);
      },
    );

    test(
      'host notes are trimmed and can be cleared with their timestamps',
      () async {
        await repository.setApplicationHostNote(
          applicationId: 'app1',
          note: '  Sound check is at 6.  ',
        );
        final noted = (await repository.myApplications(
          'b1',
        )).single.application;
        expect(noted.hostNote, 'Sound check is at 6.');
        expect(noted.hostNoteAt, isNotNull);

        await repository.setApplicationHostNote(
          applicationId: 'app1',
          note: ' \n\t ',
        );
        final cleared = (await repository.myApplications(
          'b1',
        )).single.application;
        expect(cleared.hostNote, isNull);
        expect(cleared.hostNoteAt, isNull);
      },
    );
  });
}
