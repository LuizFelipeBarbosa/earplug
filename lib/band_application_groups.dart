import 'models.dart';

class BandApplicationGroups {
  const BandApplicationGroups({
    required this.inProgress,
    required this.decided,
    required this.active,
    required this.shortlisted,
    required this.booked,
  });

  final List<BandApplication> inProgress;
  final List<BandApplication> decided;
  final int active;
  final int shortlisted;
  final int booked;

  static BandApplicationGroups from(List<BandApplication> all) {
    final inProgress = <BandApplication>[];
    final decided = <BandApplication>[];
    var shortlisted = 0;
    var booked = 0;
    for (final row in all) {
      switch (row.application.status) {
        case ArtistApplicationStatus.submitted:
        case ArtistApplicationStatus.underReview:
          inProgress.add(row);
        case ArtistApplicationStatus.shortlisted:
        case ArtistApplicationStatus.offered:
          inProgress.add(row);
          shortlisted++;
        case ArtistApplicationStatus.booked:
          booked++;
        case ArtistApplicationStatus.declined:
        case ArtistApplicationStatus.withdrawn:
        case ArtistApplicationStatus.expired:
          decided.add(row);
      }
    }
    inProgress.sort(
      (a, b) => b.application.createdAt.compareTo(a.application.createdAt),
    );
    decided.sort(
      (a, b) => (b.application.decidedAt ?? b.application.updatedAt).compareTo(
        a.application.decidedAt ?? a.application.updatedAt,
      ),
    );
    return BandApplicationGroups(
      inProgress: List.unmodifiable(inProgress),
      decided: List.unmodifiable(decided),
      active: inProgress.length,
      shortlisted: shortlisted,
      booked: booked,
    );
  }
}
