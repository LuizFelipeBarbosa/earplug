import 'models.dart';

enum SearchTimeTerm { tonight, today, tomorrow, thisWeek }

class ParsedSearch {
  const ParsedSearch({
    required this.raw,
    this.time = const {},
    this.free = false,
    this.nearMe = false,
    this.terms = const [],
  });

  final String raw;
  final Set<SearchTimeTerm> time;
  final bool free;
  final bool nearMe;
  final List<String> terms;

  bool get isEmpty => time.isEmpty && !free && !nearMe && terms.isEmpty;

  List<String> get labels => [
    if (time.contains(SearchTimeTerm.tonight)) 'TONIGHT',
    if (time.contains(SearchTimeTerm.today)) 'TODAY',
    if (time.contains(SearchTimeTerm.tomorrow)) 'TOMORROW',
    if (time.contains(SearchTimeTerm.thisWeek)) 'THIS WEEK',
    if (free) 'FREE',
    if (nearMe) 'NEAR ME',
    for (final term in terms) term.toUpperCase(),
  ];
}

final _phrases = RegExp(r'\b(this(?:\s+|-)week|near\s+me)\b');
final _words = RegExp(r'[\p{L}\p{N}]+', unicode: true);
const _stopWords = {
  'events',
  'event',
  'shows',
  'show',
  'gigs',
  'gig',
  'in',
  'at',
  'the',
  'a',
  'near',
  'me',
};

ParsedSearch parseSearchQuery(String raw) {
  final time = <SearchTimeTerm>{};
  var nearMe = false;
  final remaining = raw.toLowerCase().replaceAllMapped(_phrases, (match) {
    if (match[0]!.startsWith('this')) {
      time.add(SearchTimeTerm.thisWeek);
    } else {
      nearMe = true;
    }
    return ' ';
  });

  var free = false;
  final terms = <String>[];
  for (final match in _words.allMatches(remaining)) {
    final token = match[0]!;
    switch (token) {
      case 'tonight':
        time.add(SearchTimeTerm.tonight);
      case 'today':
        time.add(SearchTimeTerm.today);
      case 'tomorrow':
        time.add(SearchTimeTerm.tomorrow);
      case 'week':
        time.add(SearchTimeTerm.thisWeek);
      case 'free':
        free = true;
      case 'near' || 'nearby':
        nearMe = true;
      default:
        if (!_stopWords.contains(token)) terms.add(token);
    }
  }

  return ParsedSearch(
    raw: raw,
    time: Set.unmodifiable(time),
    free: free,
    nearMe: nearMe,
    terms: List.unmodifiable(terms),
  );
}

class SearchHit {
  const SearchHit({
    required this.gig,
    required this.score,
    required this.matched,
  });

  final Gig gig;
  final double score;
  final List<String> matched;
}

const _fieldWeights = {
  'title': 6.0,
  'band': 5.0,
  'venue': 4.0,
  'location': 3.0,
  'genre': 2.0,
};

bool _fieldMatches(String field, String term) {
  final normalized = field.toLowerCase();
  return normalized.contains(term) ||
      _words.allMatches(normalized).any((word) => word[0]!.startsWith(term));
}

List<SearchHit> rankSearchResults({
  required ParsedSearch parsed,
  required Iterable<Gig> gigs,
  required Band? Function(String id) band,
  required Venue? Function(String id) venue,
  required DateTime now,
  double? Function(Gig gig)? distanceMiles,
  Set<String> friendGigIds = const {},
  Set<String> savedGigIds = const {},
}) {
  if (parsed.isEmpty) return [];

  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final afterTomorrow = DateTime(now.year, now.month, now.day + 2);
  final nextMonday = DateTime(
    now.year,
    now.month,
    now.day + DateTime.sunday - now.weekday + 1,
  );
  final pastCutoff = now.subtract(const Duration(hours: 4));
  final selectsToday =
      parsed.time.contains(SearchTimeTerm.today) ||
      parsed.time.contains(SearchTimeTerm.tonight);
  final hits = <SearchHit>[];

  for (final gig in gigs) {
    final startsAt = gig.startsAt;
    final isToday = !startsAt.isBefore(today) && startsAt.isBefore(tomorrow);
    if (startsAt.isBefore(pastCutoff) && !(selectsToday && isToday)) {
      continue;
    }
    if (parsed.time.isNotEmpty &&
        !parsed.time.any(
          (term) => switch (term) {
            SearchTimeTerm.tonight => isToday && !startsAt.isBefore(now),
            SearchTimeTerm.today => isToday,
            SearchTimeTerm.tomorrow =>
              !startsAt.isBefore(tomorrow) && startsAt.isBefore(afterTomorrow),
            SearchTimeTerm.thisWeek =>
              !startsAt.isBefore(now) && startsAt.isBefore(nextMonday),
          },
        )) {
      continue;
    }
    if (parsed.free && !gig.free) continue;

    var score = 0.0;
    final matchedCategories = <String>{};
    if (parsed.terms.isNotEmpty) {
      final gigVenue = venue(gig.venueId);
      final lineup = [
        for (final id in gig.lineup)
          if (band(id) case final Band performer) performer,
      ];
      final fields = <String, List<String>>{
        'title': [gig.title],
        'band': [for (final performer in lineup) performer.name],
        'venue': [if (gigVenue != null) gigVenue.name],
        'location': [
          if (gigVenue != null) gigVenue.area,
          if (gigVenue?.neighborhood case final String value) value,
          if (gigVenue?.city case final String value) value,
        ],
        'genre': [
          ...gig.genres,
          for (final performer in lineup) ...performer.genres,
        ],
      };

      var allTermsMatch = true;
      for (final term in parsed.terms) {
        var termMatches = false;
        var exactWordMatch = false;
        for (final category in fields.entries) {
          for (final field in category.value) {
            if (!_fieldMatches(field, term)) continue;
            termMatches = true;
            matchedCategories.add(category.key);
            if (!exactWordMatch) {
              exactWordMatch = _words
                  .allMatches(field.toLowerCase())
                  .any((word) => word[0] == term);
            }
          }
        }
        if (!termMatches) {
          allTermsMatch = false;
          break;
        }
        if (exactWordMatch) score += 1;
      }
      if (!allTermsMatch) continue;

      for (final category in matchedCategories) {
        score += _fieldWeights[category]!;
      }
    }

    if (friendGigIds.contains(gig.id)) score += 1.5;
    if (savedGigIds.contains(gig.id)) score += 1;
    hits.add(
      SearchHit(
        gig: gig,
        score: score,
        matched: [
          // Genre contributes to the score, but isn't a displayed match label.
          for (final category in _fieldWeights.keys)
            if (category != 'genre' && matchedCategories.contains(category))
              category,
        ],
      ),
    );
  }

  final distances = <Gig, double>{};
  hits.sort((a, b) {
    if ((a.score - b.score).abs() > 0.001) {
      return b.score.compareTo(a.score);
    }
    if (parsed.nearMe) {
      final aDistance = distances.putIfAbsent(
        a.gig,
        () => distanceMiles?.call(a.gig) ?? double.infinity,
      );
      final bDistance = distances.putIfAbsent(
        b.gig,
        () => distanceMiles?.call(b.gig) ?? double.infinity,
      );
      final byDistance = aDistance.compareTo(bDistance);
      if (byDistance != 0) return byDistance;
    }
    final byStart = a.gig.startsAt.compareTo(b.gig.startsAt);
    if (byStart != 0) return byStart;
    return a.gig.title.toLowerCase().compareTo(b.gig.title.toLowerCase());
  });
  return hits;
}

String searchMetaLine(ParsedSearch parsed, int count) {
  final countLabel = '$count RESULT${count == 1 ? '' : 'S'}';
  final labels = parsed.labels;
  return labels.isEmpty ? countLabel : '$countLabel · ${labels.join(' · ')}';
}
