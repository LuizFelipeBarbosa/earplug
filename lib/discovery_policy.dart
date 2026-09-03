/// The discovery boost policy: which gigs get a boost and how the feed is
/// ordered around them.
library;

import 'models.dart';

const discoveryBoostLead = Duration(days: 7);
const discoveryBoostGrace = Duration(hours: 6);
const discoveryDistanceBucketMiles = 5.0;

Set<String> discoveryBoostedGigIds({
  required Iterable<Gig> gigs,
  required Map<String, Band> bands,
  required DateTime now,
}) {
  final earliestByBand = <String, Gig>{};
  for (final gig in gigs) {
    final creatorId = gig.createdByBand;
    if (creatorId == null ||
        gig.lifecycle != GigLifecycle.published ||
        !gig.discoveryListingReady ||
        bands[creatorId]?.discoveryProfileReady != true ||
        now.isBefore(gig.startsAt.subtract(discoveryBoostLead)) ||
        now.isAfter(gig.startsAt.add(discoveryBoostGrace))) {
      continue;
    }
    final current = earliestByBand[creatorId];
    if (current == null || gig.startsAt.isBefore(current.startsAt)) {
      earliestByBand[creatorId] = gig;
    }
  }
  return {for (final gig in earliestByBand.values) gig.id};
}

List<Gig> orderDiscoveryGigs({
  required Iterable<Gig> gigs,
  required double Function(Gig gig) distanceMiles,
  required Set<String> boostedGigIds,
}) {
  final ordered = gigs.toList();
  final originalIndex = {
    for (final (index, gig) in ordered.indexed) gig.id: index,
  };
  ordered.sort((left, right) {
    final distance = distanceMiles(left).compareTo(distanceMiles(right));
    if (distance != 0) return distance;
    final start = left.startsAt.compareTo(right.startsAt);
    if (start != 0) return start;
    return originalIndex[left.id]!.compareTo(originalIndex[right.id]!);
  });

  final positionsByPeerGroup = <String, List<int>>{};
  for (var index = 0; index < ordered.length; index++) {
    final gig = ordered[index];
    final bucket = (distanceMiles(gig) / discoveryDistanceBucketMiles).floor();
    final key = '${_losAngelesDayKey(gig.startsAt)}:$bucket';
    positionsByPeerGroup.putIfAbsent(key, () => []).add(index);
  }
  for (final positions in positionsByPeerGroup.values) {
    if (positions.length < 2) continue;
    final peers = [for (final position in positions) ordered[position]];
    peers.sort((left, right) {
      final boost = (boostedGigIds.contains(right.id) ? 1 : 0).compareTo(
        boostedGigIds.contains(left.id) ? 1 : 0,
      );
      if (boost != 0) return boost;
      final distance = distanceMiles(left).compareTo(distanceMiles(right));
      if (distance != 0) return distance;
      final start = left.startsAt.compareTo(right.startsAt);
      if (start != 0) return start;
      return originalIndex[left.id]!.compareTo(originalIndex[right.id]!);
    });
    for (var index = 0; index < positions.length; index++) {
      ordered[positions[index]] = peers[index];
    }
  }
  return ordered;
}

String _losAngelesDayKey(DateTime value) {
  final utc = value.toUtc();
  final year = utc.year;
  final marchFirst = DateTime.utc(year, 3, 1);
  final firstMarchSunday = 1 + ((7 - marchFirst.weekday) % 7);
  final daylightStarts = DateTime.utc(year, 3, firstMarchSunday + 7, 10);
  final novemberFirst = DateTime.utc(year, 11, 1);
  final firstNovemberSunday = 1 + ((7 - novemberFirst.weekday) % 7);
  final daylightEnds = DateTime.utc(year, 11, firstNovemberSunday, 9);
  final offsetHours =
      !utc.isBefore(daylightStarts) && utc.isBefore(daylightEnds) ? -7 : -8;
  final local = utc.add(Duration(hours: offsetHours));
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
