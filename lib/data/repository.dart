import '../models.dart';

class FeedSnapshot {
  final List<Gig> gigs;
  final Map<String, Venue> venues;
  final Map<String, Band> bands;

  const FeedSnapshot({
    required this.gigs,
    required this.venues,
    required this.bands,
  });
}

class Interactions {
  final Set<String> rsvpGigIds;
  final Set<String> followBandIds;
  final Set<String> savedGigIds;
  final int attendedCount;

  const Interactions({
    required this.rsvpGigIds,
    required this.followBandIds,
    required this.savedGigIds,
    required this.attendedCount,
  });

  static const empty = Interactions(
    rsvpGigIds: {},
    followBandIds: {},
    savedGigIds: {},
    attendedCount: 0,
  );
}

class BandMembership {
  final Band band;
  final String role;

  const BandMembership({required this.band, required this.role});
}

abstract class EarplugRepository {
  Stream<FeedSnapshot> feed();
  Stream<Interactions> myInteractions();
  Stream<List<BandMembership>> myBands();
  Future<List<VideoClip>> videosFor(String bandId);
  Future<Band?> band(String bandId);
  Future<List<Band>> searchBands(String q);
  Future<void> toggleRsvp(String gigId);
  Future<void> toggleFollow(String bandId);
  Future<void> toggleSave(String gigId);
  Future<void> setGenres(List<String> genres);
  Future<void> ensureUser({String? name});
  Future<String> createBand({
    required String name,
    required List<String> genres,
    required String bio,
    required List<String> inviteHandles,
  });
  Future<void> updateBandProfile({
    required String bandId,
    String? bio,
    String? linkIg,
    String? linkBc,
  });
  Future<String> publishGig({
    required String bandId,
    required String title,
    required int startsAt,
    required String doorsTime,
    required String venueId,
    required int price,
    required Ticketing ticketing,
    String? externalUrl,
    required String cap,
  });
  Future<void> pinVideo(String videoId);
  Future<void> moveVideo(String videoId, String direction);
}
