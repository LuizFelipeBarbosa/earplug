import 'dart:core';

import 'date_names.dart';
import 'genres.dart';
import 'models.dart';

class ExploreSignals {
  const ExploreSignals({
    required this.userGenres,
    required this.followedBandIds,
    required this.savedGigIds,
    required this.rsvpGigIds,
    required this.homeCity,
    required this.signedIn,
    required this.seed,
    required this.now,
    this.friendGigIds = const {},
    this.boostedGigIds = const {},
  });

  final Set<String> userGenres;
  final Set<String> followedBandIds;
  final Set<String> savedGigIds;
  final Set<String> rsvpGigIds;
  final FanCity? homeCity;
  final bool signedIn;
  final String seed;
  final DateTime now;
  final Set<String> friendGigIds;
  final Set<String> boostedGigIds;
}

enum ExploreCollectionKind {
  tonight,
  week,
  weekend,
  free,
  following,
  homeCity,
  genre,
  bigRooms,
  smallRooms,
  doorsSoon,
}

class ExploreCollection {
  ExploreCollection({
    required this.key,
    required this.kind,
    required this.title,
    this.eyebrow,
    required List<Gig> gigs,
    required this.score,
  }) : gigs = List.unmodifiable(gigs);

  final String key;
  final ExploreCollectionKind kind;
  final String title;
  final String? eyebrow;
  final List<Gig> gigs;
  final int score;
}

class VenueWithShows {
  VenueWithShows({required this.venue, required List<Gig> gigs})
      : gigs = List.unmodifiable(gigs);

  final Venue venue;
  final List<Gig> gigs;
  Gig get next => gigs.first;
}

class GenreChip {
  const GenreChip({required this.genre, required this.label, required this.feedCount});

  final String genre;
  final String label;
  final int feedCount;
}

class ExploreGenrePage {
  ExploreGenrePage({
    required this.genre,
    required this.label,
    required List<Gig> tonight,
    required List<Gig> week,
    required List<Gig> later,
    required List<String> bandIds,
  })  : tonight = List.unmodifiable(tonight),
        week = List.unmodifiable(week),
        later = List.unmodifiable(later),
        bandIds = List.unmodifiable(bandIds);

  final String genre;
  final String label;
  final List<Gig> tonight;
  final List<Gig> week;
  final List<Gig> later;
  final List<String> bandIds;
  int get gigCount => tonight.length + week.length + later.length;
}

/// Relevance of a gig to the fan; shared by the genre page, the featured
/// pair, and "just for you".
int gigRelevance({
  required Gig gig,
  required Map<String, Band> bands,
  required ExploreSignals signals,
  required double distanceMiles,
}) {
  var score = 0;
  if (gig.lineup.any(signals.followedBandIds.contains)) score += 4;
  if (signals.savedGigIds.contains(gig.id)) score += 3;
  if (signals.friendGigIds.contains(gig.id)) score += 3;
  if (signals.boostedGigIds.contains(gig.id)) score += 2;

  final userGenres = signals.userGenres.map(canonicalGenre).toSet();
  for (final genre in gig.genres) {
    if (_matchesAnyGenre(canonicalGenre(genre), userGenres)) score += 2;
  }
  for (final bandId in gig.lineup) {
    final band = bands[bandId];
    if (band == null) continue;
    for (final genre in band.genres) {
      if (_matchesAnyGenre(canonicalGenre(genre), userGenres)) score += 2;
    }
  }

  if (_within(gig.startsAt, signals.now, const Duration(days: 3))) {
    score += 2;
  } else if (_within(gig.startsAt, signals.now, const Duration(days: 7))) {
    score++;
  }
  if (gig.free) score++;
  final penalty = (distanceMiles < 0 ? 0 : distanceMiles / 10).floor().clamp(0, 3);
  return score - penalty;
}

({List<Gig> featured, List<Gig> forYou}) rankForYou({
  required List<Gig> gigs,
  required Map<String, Band> bands,
  required ExploreSignals signals,
  required double Function(Gig) distanceMiles,
  int featuredCount = 2,
}) {
  final scored = [
    for (final gig in gigs)
      _ScoredGig(gig, gigRelevance(
        gig: gig,
        bands: bands,
        signals: signals,
        distanceMiles: distanceMiles(gig),
      )),
  ];
  scored.sort((a, b) {
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    final starts = a.gig.startsAt.compareTo(b.gig.startsAt);
    return starts == 0 ? a.gig.title.compareTo(b.gig.title) : starts;
  });

  final count = featuredCount < 0 ? 0 : featuredCount;
  final featuredScored = <_ScoredGig>[];
  if (gigs.length < count) {
    featuredScored.addAll(scored);
  } else {
    final remaining = [...scored];
    while (featuredScored.length < count && remaining.isNotEmpty) {
      _ScoredGig? selected;
      for (final candidate in remaining) {
        final collides = featuredScored.any((picked) =>
            picked.gig.venueId == candidate.gig.venueId &&
            dayKey(picked.gig.startsAt) == dayKey(candidate.gig.startsAt));
        if (!collides) {
          selected = candidate;
          break;
        }
      }
      selected ??= remaining.first;
      featuredScored.add(selected);
      remaining.remove(selected);
    }
  }

  final featuredIds = {for (final item in featuredScored) item.gig.id};
  final featured = [for (final item in featuredScored) item.gig];
  if (featured.isEmpty) return (featured: const [], forYou: const []);
  final earliest = featured.map((gig) => gig.startsAt).reduce((a, b) => a.isBefore(b) ? a : b);
  final forYouScored = scored.where((item) =>
      !featuredIds.contains(item.gig.id) && !item.gig.startsAt.isBefore(earliest)).toList();
  forYouScored.sort((a, b) {
    final day = dayKey(a.gig.startsAt).compareTo(dayKey(b.gig.startsAt));
    if (day != 0) return day;
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    final starts = a.gig.startsAt.compareTo(b.gig.startsAt);
    return starts == 0 ? a.gig.title.compareTo(b.gig.title) : starts;
  });
  return (
    featured: List.unmodifiable(featured),
    forYou: List.unmodifiable([for (final item in forYouScored) item.gig]),
  );
}

enum DiscoverKind { venue, band }

class DiscoverEntry {
  const DiscoverEntry.venue(this.venue)
      : kind = DiscoverKind.venue, bandId = null;
  const DiscoverEntry.band(this.bandId)
      : kind = DiscoverKind.band, venue = null;

  final DiscoverKind kind;
  final VenueWithShows? venue;
  final String? bandId;
}

List<DiscoverEntry> discoverRail({
  required List<VenueWithShows> venues,
  required List<String> recommendedBandIds,
  int limit = 12,
}) {
  final result = <DiscoverEntry>[];
  final max = limit < 0 ? 0 : limit;
  var venueIndex = 0;
  var bandIndex = 0;
  var venueTurn = true;
  while (result.length < max && (venueIndex < venues.length || bandIndex < recommendedBandIds.length)) {
    if (venueTurn && venueIndex < venues.length || bandIndex >= recommendedBandIds.length) {
      result.add(DiscoverEntry.venue(venues[venueIndex++]));
    } else {
      result.add(DiscoverEntry.band(recommendedBandIds[bandIndex++]));
    }
    venueTurn = !venueTurn;
  }
  return List.unmodifiable(result);
}

List<String> rankRecommendedBands({
  required Map<String, Band> bands,
  required List<Gig> feed,
  required ExploreSignals signals,
  int limit = 12,
}) {
  final followedGenres = <String>{};
  for (final id in signals.followedBandIds) {
    final band = bands[id];
    if (band != null) followedGenres.addAll(band.genres.map(canonicalGenre));
  }
  final ranked = _rankBandIds(
    bands.keys.where((id) => !signals.followedBandIds.contains(id)),
    bands: bands,
    feed: feed,
    signals: signals,
    followedGenres: followedGenres,
  );
  return List.unmodifiable(ranked.take(limit < 0 ? 0 : limit));
}

List<String> _rankBandIds(
  Iterable<String> candidateIds, {
  required Map<String, Band> bands,
  required List<Gig> feed,
  required ExploreSignals signals,
  Set<String>? followedGenres,
}) {
  final sharedFollowedGenres = followedGenres ?? <String>{};
  if (followedGenres == null) {
    for (final id in signals.followedBandIds) {
      final band = bands[id];
      if (band != null) sharedFollowedGenres.addAll(band.genres.map(canonicalGenre));
    }
  }
  final candidates = <_ScoredBand>[];
  final gigById = <String, Gig>{};
  for (final gig in feed) {
    gigById.putIfAbsent(gig.id, () => gig);
  }
  for (final id in candidateIds) {
    final band = bands[id];
    if (band == null) continue;
    final hasSoon = band.upcoming.any((gigId) {
      final gig = gigById[gigId];
      return gig != null && _within(gig.startsAt, signals.now, const Duration(days: 7));
    });
    final hasLater = band.upcoming.any((gigId) {
      final gig = gigById[gigId];
      return gig != null && _within(gig.startsAt, signals.now, const Duration(days: 30));
    });
    candidates.add(_ScoredBand(
      id,
      _scoreBand(
        band,
        hasUpcomingSoon: hasSoon,
        hasUpcomingLater: hasLater,
        userGenres: signals.userGenres.map(canonicalGenre).toSet(),
        followedGenres: sharedFollowedGenres,
        homeCity: signals.homeCity,
      ),
    ));
  }
  candidates.sort((a, b) {
    final score = b.score.compareTo(a.score);
    if (score != 0) return score;
    final follower = bands[b.id]!.followers.compareTo(bands[a.id]!.followers);
    if (follower != 0) return follower;
    return bands[a.id]!.name.compareTo(bands[b.id]!.name);
  });
  final ordered = [for (final item in candidates) item.id];
  for (var i = 1; i < ordered.length; i++) {
    final previousGenre = _firstGenre(bands[ordered[i - 1]]!);
    if (_firstGenre(bands[ordered[i]]!) != previousGenre) continue;
    var alternative = -1;
    for (var j = i + 1; j < ordered.length; j++) {
      if (_firstGenre(bands[ordered[j]]!) != previousGenre) {
        alternative = j;
        break;
      }
    }
    if (alternative >= 0) {
      final id = ordered.removeAt(alternative);
      ordered.insert(i, id);
    }
  }
  return ordered;
}

int _scoreBand(
  Band band, {
  required bool hasUpcomingSoon,
  required bool hasUpcomingLater,
  required Set<String> userGenres,
  required Set<String> followedGenres,
  required FanCity? homeCity,
}) {
  var score = 0;
  for (final rawGenre in band.genres) {
    final genre = canonicalGenre(rawGenre);
    if (_matchesAnyGenre(genre, userGenres)) score += 3;
    if (_matchesAnyGenre(genre, followedGenres)) score += 2;
  }
  if (hasUpcomingSoon) {
    score += 4;
  } else if (hasUpcomingLater) {
    score += 2;
  }
  if (band.discoveryProfileReady) score += 2;
  if (band.avatarUrl != null) score++;
  if (homeCity != null && _mentionsCity(band.area, homeCity)) score++;
  return score;
}

List<ExploreCollection> buildCollections({
  required List<Gig> feed,
  required Venue Function(String id) venue,
  required Map<String, Band> bands,
  required ExploreSignals signals,
  int limit = 7,
}) {
  final candidates = <ExploreCollection>[];
  void add(String key, ExploreCollectionKind kind, String title, List<Gig> gigs,
      {int affinity = 0, String? eyebrow, int minimum = 2}) {
    if (gigs.length < minimum) return;
    candidates.add(ExploreCollection(
      key: key,
      kind: kind,
      title: title,
      eyebrow: eyebrow,
      gigs: gigs,
      score: gigs.length.clamp(0, 8) * 2 + affinity,
    ));
  }

  add('tonight', ExploreCollectionKind.tonight, 'Tonight',
      feed.where((gig) => gig.when == GigWhen.tonight).toList(), minimum: 1);
  final weekend = weekendWindow(signals.now);
  add('weekend', ExploreCollectionKind.weekend, 'This weekend', feed.where((gig) {
    return !gig.startsAt.isBefore(weekend.start) && gig.startsAt.isBefore(weekend.end);
  }).toList(), affinity: _weekendAffinity(signals.now));
  add('free', ExploreCollectionKind.free, 'Free tonight & this week',
      feed.where((gig) => gig.free && gig.when != GigWhen.later).toList(), affinity: 1);
  if (signals.signedIn) {
    add('following', ExploreCollectionKind.following, 'Bands you follow are playing', feed
        .where((gig) => gig.lineup.any(signals.followedBandIds.contains))
        .toList(), affinity: 6);
  }
  if (signals.homeCity != null) {
    final city = signals.homeCity!;
    add('city:${city.name}', ExploreCollectionKind.homeCity, 'In ${city.label}', feed.where((gig) {
      final resolved = venue(gig.venueId);
      return (resolved.city ?? '').toLowerCase() == city.label.toLowerCase() ||
          _mentionsCity(resolved.area, city);
    }).toList(), affinity: 3);
  }
  final userGenres = signals.userGenres.map(canonicalGenre).where((g) => g.isNotEmpty).toSet();
  if (userGenres.isNotEmpty) {
    for (final genre in userGenres) {
      add('genre:$genre', ExploreCollectionKind.genre, '${genreLabel(genre)} night',
          feed.where((gig) => gig.genres.any((g) => canonicalGenre(g) == genre)).toList(),
          affinity: 4);
    }
  } else {
    final counts = <String, int>{};
    for (final gig in feed) {
      for (final genre in gig.genres.map(canonicalGenre).where((g) => g.isNotEmpty)) {
        counts[genre] = (counts[genre] ?? 0) + 1;
      }
    }
    final trending = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!) == 0
          ? genreLabel(a).compareTo(genreLabel(b))
          : counts[b]!.compareTo(counts[a]!));
    for (final genre in trending.take(2)) {
      add('genre:$genre', ExploreCollectionKind.genre, 'Trending: ${genreLabel(genre)}',
          feed.where((gig) => gig.genres.any((g) => canonicalGenre(g) == genre)).toList(),
          affinity: 4);
    }
  }
  add('bigRooms', ExploreCollectionKind.bigRooms, 'Big rooms', feed.where((gig) {
    final v = venue(gig.venueId);
    return v.capacityPublic != null ? v.capacityPublic! >= 300 :
        (v.venueType == VenueType.hall || v.venueType == VenueType.club);
  }).toList());
  add('smallRooms', ExploreCollectionKind.smallRooms, 'Small rooms', feed.where((gig) {
    final v = venue(gig.venueId);
    return v.capacityPublic != null ? v.capacityPublic! < 150 :
        (v.venueType == VenueType.bar || v.venueType == VenueType.house);
  }).toList());
  final doorsEnd = signals.now.add(const Duration(hours: 4));
  add('doorsSoon', ExploreCollectionKind.doorsSoon, 'Doors open soon', feed.where((gig) {
    final doors = gig.doorsAt ?? gig.startsAt;
    return !doors.isBefore(signals.now) && !doors.isAfter(doorsEnd);
  }).toList(), affinity: 5, minimum: 1);

  candidates.sort((a, b) => b.score.compareTo(a.score) == 0
      ? a.key.compareTo(b.key)
      : b.score.compareTo(a.score));
  final fixedCount = candidates.length < 2 ? candidates.length : 2;
  final fixed = candidates.take(fixedCount).toList();
  final tail = candidates.skip(fixedCount).toList();
  if (tail.isNotEmpty) {
    final shift = fnv1a('${signals.seed}:${dayKey(signals.now)}') % tail.length;
    final rotated = [...tail.skip(shift), ...tail.take(shift)];
    fixed.addAll(rotated);
  }
  return List.unmodifiable(fixed.take(limit < 0 ? 0 : limit));
}

List<VenueWithShows> venuesWithShows({
  required List<Gig> feed,
  required Venue Function(String id) venue,
}) {
  final grouped = <String, List<Gig>>{};
  final resolved = <String, Venue>{};
  for (final gig in feed) {
    final v = venue(gig.venueId);
    if (v.id.isEmpty) continue;
    grouped.putIfAbsent(gig.venueId, () => []).add(gig);
    resolved[gig.venueId] = v;
  }
  final result = [
    for (final entry in grouped.entries)
      VenueWithShows(venue: resolved[entry.key]!, gigs: entry.value),
  ];
  result.sort((a, b) {
    final start = a.next.startsAt.compareTo(b.next.startsAt);
    return start == 0 ? b.gigs.length.compareTo(a.gigs.length) : start;
  });
  return List.unmodifiable(result);
}

List<GenreChip> rankGenres({
  required List<Gig> feed,
  required Iterable<List<String>> attendedGigGenres,
  required Iterable<Gig> interactionGigs,
  required Map<String, Band> bands,
  required ExploreSignals signals,
  int limit = 16,
}) {
  final attended = [for (final genres in attendedGigGenres) genres.map(canonicalGenre).toSet()];
  final interactions = interactionGigs.toList();
  final vocabulary = <String>{...kGenres.map(canonicalGenre), ...signals.userGenres.map(canonicalGenre)};
  for (final gig in feed) {
    vocabulary.addAll(gig.genres.map(canonicalGenre));
  }
  for (final genres in attended) {
    vocabulary.addAll(genres);
  }
  for (final band in bands.values) {
    if (signals.followedBandIds.contains(band.id)) {
      vocabulary.addAll(band.genres.map(canonicalGenre));
    }
  }
  final chips = <_ScoredGenre>[];
  for (final genre in vocabulary.where((g) => g.isNotEmpty)) {
    final feedCount = feed.where((gig) => gig.genres.any((g) => canonicalGenre(g) == genre)).length;
    var score = 0;
    if (signals.signedIn) {
      score += attended.where((set) => set.contains(genre)).length * 3;
      score += interactions.where((gig) => gig.genres.any((g) => canonicalGenre(g) == genre)).length * 2;
      score += bands.values.where((band) => signals.followedBandIds.contains(band.id) &&
          band.genres.any((g) => canonicalGenre(g) == genre)).length * 2;
      if (signals.userGenres.map(canonicalGenre).contains(genre)) score++;
    }
    chips.add(_ScoredGenre(GenreChip(genre: genre, label: genreLabel(genre), feedCount: feedCount), score));
  }
  chips.sort((a, b) {
    if (signals.signedIn) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
    }
    final count = b.chip.feedCount.compareTo(a.chip.feedCount);
    return count == 0 ? a.chip.label.compareTo(b.chip.label) : count;
  });
  return List.unmodifiable(chips.take(limit < 0 ? 0 : limit).map((item) => item.chip));
}

ExploreGenrePage buildGenrePage({
  required String genre,
  required List<Gig> feed,
  required Map<String, Band> bands,
  required Iterable<String> directoryBandIds,
  required ExploreSignals signals,
  required double Function(Gig gig) distanceMiles,
}) {
  final canonical = canonicalGenre(genre);
  final candidates = feed.where((gig) {
    return gig.genres.any((g) => canonicalGenre(g) == canonical) || gig.lineup.any((id) {
      return bands[id]?.genres.any((g) => canonicalGenre(g) == canonical) == true;
    });
  }).toList();
  final relevance = <String, int>{};
  final distances = <String, double>{};
  for (final gig in candidates) {
    final distance = distanceMiles(gig);
    distances[gig.id] = distance;
    relevance[gig.id] = gigRelevance(
      gig: gig,
      bands: bands,
      signals: signals,
      distanceMiles: distance,
    );
  }
  candidates.sort((a, b) {
    final day = dayKey(a.startsAt).compareTo(dayKey(b.startsAt));
    if (day != 0) return day;
    final score = relevance[b.id]!.compareTo(relevance[a.id]!);
    if (score != 0) return score;
    final distance = distances[a.id]!.compareTo(distances[b.id]!);
    return distance == 0 ? a.startsAt.compareTo(b.startsAt) : distance;
  });
  final tonight = candidates.where((gig) => gig.when == GigWhen.tonight).toList();
  final week = candidates.where((gig) => gig.when == GigWhen.week).toList();
  final later = candidates.where((gig) => gig.when == GigWhen.later).toList();
  final ids = <String>{
    for (final gig in feed)
      for (final id in gig.lineup)
        if (bands[id]?.genres.any((g) => canonicalGenre(g) == canonical) == true) id,
    ...directoryBandIds,
  };
  final rankedIds = _rankBandIds(ids, bands: bands, feed: feed, signals: signals);
  return ExploreGenrePage(
    genre: canonical,
    label: genreLabel(canonical),
    tonight: tonight,
    week: week,
    later: later,
    bandIds: rankedIds,
  );
}

String canonicalGenre(String raw) => raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String genreLabel(String canonical) {
  final value = canonicalGenre(canonical);
  return value.splitMapJoin(RegExp(r'([ -])'), onMatch: (m) => m.group(1)!,
      onNonMatch: (chunk) => chunk.isEmpty ? chunk : '${chunk[0].toUpperCase()}${chunk.substring(1)}');
}

String dayKey(DateTime t) => '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

int fnv1a(String s) {
  var hash = 0x811c9dc5;
  for (final rune in s.runes) {
    final bytes = rune <= 0x7f
        ? [rune]
        : rune <= 0x7ff
            ? [0xc0 | (rune >> 6), 0x80 | (rune & 0x3f)]
            : rune <= 0xffff
                ? [0xe0 | (rune >> 12), 0x80 | ((rune >> 6) & 0x3f), 0x80 | (rune & 0x3f)]
                : [0xf0 | (rune >> 18), 0x80 | ((rune >> 12) & 0x3f), 0x80 | ((rune >> 6) & 0x3f), 0x80 | (rune & 0x3f)];
    for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
  }
  return hash;
}

class _ScoredBand {
  const _ScoredBand(this.id, this.score);
  final String id;
  final int score;
}

class _ScoredGig {
  const _ScoredGig(this.gig, this.score);
  final Gig gig;
  final int score;
}

class _ScoredGenre {
  const _ScoredGenre(this.chip, this.score);
  final GenreChip chip;
  final int score;
}

bool _within(DateTime value, DateTime now, Duration duration) {
  return !value.isBefore(now) && value.difference(now) <= duration;
}

String _firstGenre(Band band) => band.genres.isEmpty ? '' : canonicalGenre(band.genres.first);

bool _matchesAnyGenre(String genre, Iterable<String> others) => others.any((other) {
  if (genre == other) return true;
  final left = genre.split(RegExp(r'[^a-z]+')).where((t) => t.isNotEmpty).toSet();
  final right = canonicalGenre(other).split(RegExp(r'[^a-z]+')).where((t) => t.isNotEmpty);
  return right.any(left.contains);
});

bool _mentionsCity(String text, FanCity city) {
  final lower = text.toLowerCase();
  if (lower.contains(city.label.toLowerCase())) return true;
  if (city == FanCity.sf) return RegExp(r'(^|[^a-z])sf([^a-z]|$)').hasMatch(lower);
  return false;
}

int _weekendAffinity(DateTime now) =>
    now.weekday >= DateTime.thursday ? 2 : 0;
