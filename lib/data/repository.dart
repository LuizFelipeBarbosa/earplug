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

/// A band's past gigs, newest first, with the venues they were played at.
///
/// Separate from [FeedSnapshot] because history carries no band map: the caller
/// already knows whose profile it is looking at.
class BandHistory {
  final List<Gig> gigs;
  final Map<String, Venue> venues;

  const BandHistory({required this.gigs, required this.venues});

  static const empty = BandHistory(gigs: [], venues: {});
}

abstract class EarplugRepository {
  Stream<FeedSnapshot> feed();
  Stream<Interactions> myInteractions();
  Stream<List<BandMembership>> myBands();
  Future<List<BandMedia>> mediaFor(String bandId);
  Future<String> generateMediaUploadUrl(String bandId);
  Future<String> addBandMedia({
    required String bandId,
    required MediaKind kind,
    required String storageId,
    required String title,
    String? caption,
    int? lengthSec,
  });
  Future<void> deleteBandMedia(String mediaId);
  Future<void> pinBandMedia(String mediaId);
  Future<void> moveBandMedia(String mediaId, String direction);
  Future<void> setBandPhoto({required String bandId, required String mediaId});
  Future<void> clearBandPhoto(String bandId);
  Future<List<PastGig>> history();
  Future<BandHistory> bandHistory(String bandId);
  Future<List<Venue>> venues();
  Future<Band?> band(String bandId);
  Future<List<Band>> searchBands(String q);
  Future<void> toggleRsvp(String gigId);
  Future<void> toggleFollow(String bandId);
  Future<void> toggleSave(String gigId);
  Future<void> setGenres(List<String> genres);
  Future<void> ensureUser({String? name});

  /// Returns the new band's id and its server-issued unique profile slug.
  Future<({String bandId, String slug})> createBand({
    required String name,
    required List<String> genres,
    required String bio,
    required List<String> inviteHandles,
    String? area,
    String? linkIg,
    String? linkBc,
    String? linkYt,
  });
  Future<void> updateBandProfile({
    required String bandId,
    String? name,
    List<String>? genres,
    String? area,
    String? bio,
    List<String>? inviteHandles,
    String? linkIg,
    String? linkBc,
    String? linkYt,
  });
  Future<String> publishGig({
    required String bandId,
    required String title,
    required int startsAt,
    required String doorsTime,
    required String venueId,
    required int price,
    required String flyKey,
    String? flyStorageId,
    required Ticketing ticketing,
    String? externalUrl,
    required String cap,
  });
}
