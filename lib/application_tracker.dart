import 'models.dart';

enum ApplicationTrackerStep { applied, viewed, shortlisted, decision }

enum ApplicationOutcome {
  pending,
  offered,
  booked,
  declined,
  withdrawn,
  expired,
}

class ApplicationTracker {
  const ApplicationTracker({
    required this.reached,
    required this.outcome,
    required this.stepTimes,
  });

  final Set<ApplicationTrackerStep> reached;
  final ApplicationOutcome outcome;
  final Map<ApplicationTrackerStep, DateTime?> stepTimes;

  bool get isDecided =>
      outcome != ApplicationOutcome.pending &&
      outcome != ApplicationOutcome.offered;

  static ApplicationTracker of(ArtistApplication a) {
    return ApplicationTracker(
      reached: {
        ApplicationTrackerStep.applied,
        if (a.viewedAt != null ||
            const {
              ArtistApplicationStatus.underReview,
              ArtistApplicationStatus.shortlisted,
              ArtistApplicationStatus.offered,
              ArtistApplicationStatus.booked,
              ArtistApplicationStatus.declined,
            }.contains(a.status))
          ApplicationTrackerStep.viewed,
        if (a.shortlistedAt != null ||
            const {
              ArtistApplicationStatus.shortlisted,
              ArtistApplicationStatus.offered,
              ArtistApplicationStatus.booked,
            }.contains(a.status))
          ApplicationTrackerStep.shortlisted,
        if (const {
          ArtistApplicationStatus.offered,
          ArtistApplicationStatus.booked,
          ArtistApplicationStatus.declined,
          ArtistApplicationStatus.withdrawn,
          ArtistApplicationStatus.expired,
        }.contains(a.status))
          ApplicationTrackerStep.decision,
      },
      outcome: switch (a.status) {
        ArtistApplicationStatus.offered => ApplicationOutcome.offered,
        ArtistApplicationStatus.booked => ApplicationOutcome.booked,
        ArtistApplicationStatus.declined => ApplicationOutcome.declined,
        ArtistApplicationStatus.withdrawn => ApplicationOutcome.withdrawn,
        ArtistApplicationStatus.expired => ApplicationOutcome.expired,
        _ => ApplicationOutcome.pending,
      },
      stepTimes: {
        ApplicationTrackerStep.applied: a.createdAt,
        ApplicationTrackerStep.viewed: a.viewedAt,
        ApplicationTrackerStep.shortlisted: a.shortlistedAt,
        ApplicationTrackerStep.decision: a.decidedAt,
      },
    );
  }
}
