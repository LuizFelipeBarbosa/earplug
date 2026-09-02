import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'app_links.dart';
import 'date_names.dart';

class Venue {
  final String id;
  final String name;
  final String area;
  final String addr;
  final String distSF;
  final String distOak;
  final LatLng point;

  const Venue({
    required this.id,
    required this.name,
    required this.area,
    required this.addr,
    required this.distSF,
    required this.distOak,
    required this.point,
  });

  factory Venue.fromJson(Map<String, dynamic> json) => Venue(
    id: json['_id'] as String,
    name: json['name'] as String,
    area: json['area'] as String,
    addr: json['addr'] as String,
    distSF: json['distSF'] as String,
    distOak: json['distOak'] as String,
    point: LatLng(
      (json['lat'] as num).toDouble(),
      (json['lng'] as num).toDouble(),
    ),
  );
}

class VenueCreationResult {
  const VenueCreationResult({required this.venue, required this.created});

  final Venue venue;
  final bool created;
}

class RsvpTicket {
  const RsvpTicket({required this.payload, this.checkedInAt});

  final String payload;
  final DateTime? checkedInAt;

  factory RsvpTicket.fromJson(Map<String, dynamic> json) => RsvpTicket(
    payload: json['payload'] as String,
    checkedInAt: _optionalDate(json['checkedInAt']),
  );
}

class DoorRoster {
  const DoorRoster({
    required this.total,
    required this.checkedIn,
    required this.truncated,
  });

  final int total;
  final int checkedIn;
  final bool truncated;

  factory DoorRoster.fromJson(Map<String, dynamic> json) => DoorRoster(
    total: (json['total'] as num).toInt(),
    checkedIn: (json['checkedIn'] as num).toInt(),
    truncated: json['truncated'] as bool,
  );
}

enum DoorCheckInStatus { invalid, wrongGig, checkedIn, alreadyCheckedIn }

class DoorCheckInResult {
  const DoorCheckInResult({
    required this.status,
    this.fanName,
    this.checkedInAt,
  });

  final DoorCheckInStatus status;
  final String? fanName;
  final DateTime? checkedInAt;

  factory DoorCheckInResult.fromJson(Map<String, dynamic> json) =>
      DoorCheckInResult(
        status: DoorCheckInStatus.values.byName(json['status'] as String),
        fanName: json['fanName'] as String?,
        checkedInAt: _optionalDate(json['checkedInAt']),
      );
}

enum FanCity {
  sf,
  oak,
  berkeley,
  alameda,
  emeryville,
  richmond,
  dalyCity,
  sanMateo,
  paloAlto,
  sanJose,
  hayward,
  fremont,
  walnutCreek,
  sanRafael,
}

extension FanCityDetails on FanCity {
  String get label => switch (this) {
    FanCity.sf => 'San Francisco',
    FanCity.oak => 'Oakland',
    FanCity.berkeley => 'Berkeley',
    FanCity.alameda => 'Alameda',
    FanCity.emeryville => 'Emeryville',
    FanCity.richmond => 'Richmond',
    FanCity.dalyCity => 'Daly City',
    FanCity.sanMateo => 'San Mateo',
    FanCity.paloAlto => 'Palo Alto',
    FanCity.sanJose => 'San Jose',
    FanCity.hayward => 'Hayward',
    FanCity.fremont => 'Fremont',
    FanCity.walnutCreek => 'Walnut Creek',
    FanCity.sanRafael => 'San Rafael',
  };

  LatLng get center => switch (this) {
    FanCity.sf => const LatLng(37.7749, -122.4194),
    FanCity.oak => const LatLng(37.8044, -122.2712),
    FanCity.berkeley => const LatLng(37.8715, -122.2730),
    FanCity.alameda => const LatLng(37.7652, -122.2416),
    FanCity.emeryville => const LatLng(37.8313, -122.2852),
    FanCity.richmond => const LatLng(37.9358, -122.3477),
    FanCity.dalyCity => const LatLng(37.6879, -122.4702),
    FanCity.sanMateo => const LatLng(37.5630, -122.3255),
    FanCity.paloAlto => const LatLng(37.4419, -122.1430),
    FanCity.sanJose => const LatLng(37.3382, -121.8863),
    FanCity.hayward => const LatLng(37.6688, -122.0808),
    FanCity.fremont => const LatLng(37.5485, -121.9886),
    FanCity.walnutCreek => const LatLng(37.9101, -122.0652),
    FanCity.sanRafael => const LatLng(37.9735, -122.5311),
  };

  String get autocompleteLabel => '$label, CA';

  Iterable<String> get _locationSearchValues => [
    label,
    '$label, CA',
    '$label, California',
    ...switch (this) {
      FanCity.sf => const ['SF', 'San Fran'],
      FanCity.sanJose => const ['SJ'],
      _ => const <String>[],
    },
  ];

  bool matchesLocationQuery(String query) {
    final normalizedQuery = _normalizeLocationInput(query);
    if (normalizedQuery.isEmpty) return false;
    final queryTerms = normalizedQuery.split(' ');
    return _locationSearchValues.any((value) {
      final normalizedValue = _normalizeLocationInput(value);
      return queryTerms.every(normalizedValue.contains);
    });
  }

  bool matchesExactLocation(String input) {
    final normalizedInput = _normalizeLocationInput(input);
    return normalizedInput.isNotEmpty &&
        _locationSearchValues.any(
          (value) => _normalizeLocationInput(value) == normalizedInput,
        );
  }
}

String _normalizeLocationInput(String input) => input
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

FanCity? fanCityFromLocationInput(String input) {
  for (final city in FanCity.values) {
    if (city.matchesExactLocation(input)) return city;
  }
  return null;
}

Iterable<FanCity> fanCitySuggestions(String query) sync* {
  if (query.trim().isEmpty) return;
  for (final city in FanCity.values) {
    if (city.matchesLocationQuery(query)) yield city;
  }
}

FanCity? _fanCityFromWire(Object? value) {
  if (value is! String) return null;
  for (final city in FanCity.values) {
    if (city.name == value) return city;
  }
  return null;
}

enum FanGenreChoice { pending, selected, open }

class FanOnboarding {
  final FanCity? preferredCity;
  final FanGenreChoice genreChoice;
  final bool collapsed;

  const FanOnboarding({
    this.preferredCity,
    required this.genreChoice,
    required this.collapsed,
  });

  factory FanOnboarding.fromJson(Map<String, dynamic> json) => FanOnboarding(
    preferredCity: _fanCityFromWire(json['preferredCity']),
    genreChoice: FanGenreChoice.values.byName(json['genreChoice'] as String),
    collapsed: json['collapsed'] as bool,
  );
}

class UserProfile {
  final String name;
  final String email;
  final List<String> genres;
  final int attendedCount;
  final DateTime createdAt;
  final String? avatarUrl;
  final String? bio;
  final FanCity? homeLocation;
  final bool locationPersonalizationEnabled;
  final bool followedBandUpdatesEnabled;
  final bool profileTutorialAvailable;
  final bool profileTutorialCompleted;
  final FanOnboarding? fanOnboarding;

  const UserProfile({
    required this.name,
    required this.email,
    required this.genres,
    required this.attendedCount,
    required this.createdAt,
    this.avatarUrl,
    this.bio,
    this.homeLocation,
    this.locationPersonalizationEnabled = false,
    this.followedBandUpdatesEnabled = true,
    this.profileTutorialAvailable = true,
    this.profileTutorialCompleted = false,
    this.fanOnboarding,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: json['name'] as String,
    email: json['email'] as String,
    genres: List<String>.from(json['genres'] as List),
    attendedCount: (json['attendedCount'] as num).toInt(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (json['createdAt'] as num).toInt(),
    ),
    avatarUrl: json['avatarUrl'] is String ? json['avatarUrl'] as String : null,
    bio: json['bio'] is String ? json['bio'] as String : null,
    homeLocation: _fanCityFromWire(json['homeLocation']),
    locationPersonalizationEnabled:
        json['locationPersonalizationEnabled'] is bool
        ? json['locationPersonalizationEnabled'] as bool
        : false,
    followedBandUpdatesEnabled: json['followedBandUpdatesEnabled'] is bool
        ? json['followedBandUpdatesEnabled'] as bool
        : true,
    // Presence is a compatibility capability. Backends released before the
    // tutorial mutation omit this key; showing its controls against those
    // deployments guarantees a function-not-found error on completion.
    profileTutorialAvailable: json['profileTutorialCompleted'] is bool,
    profileTutorialCompleted: json['profileTutorialCompleted'] is bool
        ? json['profileTutorialCompleted'] as bool
        : false,
    fanOnboarding: switch (json['fanOnboarding']) {
      final Map<Object?, Object?> value => FanOnboarding.fromJson(
        Map<String, dynamic>.from(value),
      ),
      _ => null,
    },
  );

  static const _unchanged = Object();

  UserProfile copyWith({
    String? name,
    String? email,
    List<String>? genres,
    int? attendedCount,
    DateTime? createdAt,
    Object? avatarUrl = _unchanged,
    Object? bio = _unchanged,
    Object? homeLocation = _unchanged,
    bool? locationPersonalizationEnabled,
    bool? followedBandUpdatesEnabled,
    bool? profileTutorialAvailable,
    bool? profileTutorialCompleted,
    Object? fanOnboarding = _unchanged,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      genres: genres ?? this.genres,
      attendedCount: attendedCount ?? this.attendedCount,
      createdAt: createdAt ?? this.createdAt,
      avatarUrl: identical(avatarUrl, _unchanged)
          ? this.avatarUrl
          : avatarUrl as String?,
      bio: identical(bio, _unchanged) ? this.bio : bio as String?,
      homeLocation: identical(homeLocation, _unchanged)
          ? this.homeLocation
          : homeLocation as FanCity?,
      locationPersonalizationEnabled:
          locationPersonalizationEnabled ?? this.locationPersonalizationEnabled,
      followedBandUpdatesEnabled:
          followedBandUpdatesEnabled ?? this.followedBandUpdatesEnabled,
      profileTutorialAvailable:
          profileTutorialAvailable ?? this.profileTutorialAvailable,
      profileTutorialCompleted:
          profileTutorialCompleted ?? this.profileTutorialCompleted,
      fanOnboarding: identical(fanOnboarding, _unchanged)
          ? this.fanOnboarding
          : fanOnboarding as FanOnboarding?,
    );
  }
}

/// Print texture laid over a flyer's base color.
enum FlyerPattern {
  /// Photocopier scan lines: 2px bars every [FlyerStyle.pitch].
  scan,

  /// Riso dot grid: one dot per [FlyerStyle.pitch] square.
  dots,

  /// Blueprint hatching: 45° bars, half of [FlyerStyle.pitch] wide.
  hatch,

  /// Sunburst rays: alternating wedges [FlyerStyle.pitch] degrees apart.
  rays,
}

/// Xeroxed-flyer treatment: base color, a print texture over it, and the ink
/// colour text on the flyer is set in.
class FlyerStyle {
  final Color base;
  final Color patternColor;
  final Color fg;
  final FlyerPattern pattern;

  /// Texture spacing — pixels for [FlyerPattern.scan], [FlyerPattern.dots] and
  /// [FlyerPattern.hatch], degrees per wedge pair for [FlyerPattern.rays].
  final double pitch;

  const FlyerStyle({
    required this.base,
    required this.patternColor,
    required this.fg,
    this.pattern = FlyerPattern.scan,
    this.pitch = 5,
  });
}

enum GigWhen { tonight, week, later }

enum Ticketing { rsvp, external }

enum GigLifecycle { published, cancelled, unpublished, deleted }

enum GigProjectStatus { draft, published, cancelled, deleted }

enum GigPerformerKind { band, invited, text }

enum GigPerformerRole { headliner, support, opener }

class GigPerformer {
  final String id;
  final GigPerformerKind kind;
  final String name;
  final GigPerformerRole role;
  final String? bandId;
  final String? inviteUrl;

  const GigPerformer({
    required this.id,
    required this.kind,
    required this.name,
    required this.role,
    this.bandId,
    this.inviteUrl,
  });

  factory GigPerformer.fromJson(Map<String, dynamic> json) => GigPerformer(
    id: json['_id'] as String,
    kind: GigPerformerKind.values.byName(json['kind'] as String),
    name: json['name'] as String,
    role: GigPerformerRole.values.byName(json['role'] as String),
    bandId: json['bandId'] as String?,
    inviteUrl: json['inviteUrl'] as String?,
  );
}

class GigProject {
  final String id;
  final String bandId;
  final String? publicGigId;
  final String? publicSlug;
  final GigProjectStatus status;
  final int revision;
  final int? publishedRevision;
  final String? title;
  final DateTime? doorsAt;
  final DateTime? startsAt;
  final String? venueId;
  final int price;
  final String flyKey;
  final String? flyStorageId;
  final String? flyerUrl;
  final bool overlay;
  final String desc;
  final Ticketing ticketing;
  final AgeRequirement ageRequirement;
  final String? externalUrl;
  final String cap;
  final DateTime updatedAt;
  final List<GigPerformer> performers;

  const GigProject({
    required this.id,
    required this.bandId,
    required this.status,
    required this.revision,
    required this.price,
    required this.flyKey,
    required this.overlay,
    required this.desc,
    required this.ticketing,
    required this.ageRequirement,
    required this.cap,
    required this.updatedAt,
    required this.performers,
    this.publicGigId,
    this.publicSlug,
    this.publishedRevision,
    this.title,
    this.doorsAt,
    this.startsAt,
    this.venueId,
    this.flyStorageId,
    this.flyerUrl,
    this.externalUrl,
  });

  factory GigProject.fromJson(Map<String, dynamic> json) => GigProject(
    id: json['_id'] as String,
    bandId: json['bandId'] as String,
    publicGigId: json['publicGigId'] as String?,
    publicSlug: json['publicSlug'] as String?,
    status: GigProjectStatus.values.byName(json['status'] as String),
    revision: (json['revision'] as num).toInt(),
    publishedRevision: (json['publishedRevision'] as num?)?.toInt(),
    title: json['title'] as String?,
    doorsAt: _optionalDate(json['doorsAt']),
    startsAt: _optionalDate(json['startsAt']),
    venueId: json['venueId'] as String?,
    price: (json['price'] as num).toInt(),
    flyKey: json['flyKey'] as String,
    flyStorageId: json['flyStorageId'] as String?,
    flyerUrl: json['flyerUrl'] as String?,
    overlay: json['overlay'] as bool,
    desc: json['desc'] as String,
    ticketing: Ticketing.values.byName(json['ticketing'] as String),
    ageRequirement: AgeRequirement.fromJson(json['ageRequirement']),
    externalUrl: json['externalUrl'] as String?,
    cap: json['cap'] as String,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      (json['updatedAt'] as num).toInt(),
    ),
    performers: [
      for (final item in json['performers'] as List)
        GigPerformer.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
  );

  bool get hasUnpublishedChanges =>
      status == GigProjectStatus.published && publishedRevision != revision;
}

DateTime? _optionalDate(Object? milliseconds) => milliseconds == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch((milliseconds as num).toInt());

enum AgeRequirement {
  allAges('allAges', 'All ages'),
  eighteenPlus('18Plus', '18+'),
  twentyOnePlus('21Plus', '21+');

  const AgeRequirement(this.wireValue, this.label);

  final String wireValue;
  final String label;

  /// Legacy gigs did not store an age requirement. They remain visible as
  /// all-ages shows until the backend data is optionally backfilled.
  static AgeRequirement fromJson(Object? value) => switch (value) {
    '18Plus' => AgeRequirement.eighteenPlus,
    '21Plus' => AgeRequirement.twentyOnePlus,
    _ => AgeRequirement.allAges,
  };
}

class Gig {
  final String id;
  final String slug;
  final String title;
  final String venueId;
  final int price; // dollars; 0 == free
  final DateTime startsAt;
  final DateTime? doorsAt;
  final String dateShort; // "TUE JUL 28"
  final String dateLine; // "TONIGHT · DOORS 8PM"
  final String time; // "8PM / 9PM"
  final GigWhen when;
  final String flyKey;
  final List<String> lineup; // band ids
  final List<GigPerformer> performers;
  final int going;
  final List<String> genres;
  final String desc;
  final Ticketing tix;
  final String? externalUrl;
  final String? flyerUrl;
  final String cap;
  final AgeRequirement ageRequirement;
  final GigLifecycle lifecycle;
  final String? createdByBand;
  final bool discoveryListingReady;

  const Gig({
    required this.id,
    this.slug = '',
    required this.title,
    required this.venueId,
    required this.price,
    required this.startsAt,
    this.doorsAt,
    required this.dateShort,
    required this.dateLine,
    required this.time,
    required this.when,
    required this.flyKey,
    required this.lineup,
    this.performers = const [],
    required this.going,
    required this.genres,
    required this.desc,
    required this.tix,
    this.externalUrl,
    this.flyerUrl,
    this.cap = 'No cap',
    this.ageRequirement = AgeRequirement.allAges,
    this.lifecycle = GigLifecycle.published,
    this.createdByBand,
    this.discoveryListingReady = false,
  });

  /// The stable public slug when one is available, otherwise the legacy ID.
  /// Keeping the fallback here prevents older/demo records from producing an
  /// empty `/g/` link during the slug rollout.
  String get publicRef => slug.isEmpty ? id : slug;

  factory Gig.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    now ??= DateTime.now();
    final startsAtMs = (json['startsAt'] as num).toInt();
    final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMs);
    final doorsAtMs = json['doorsAt'] as num?;
    final doorsTime = json['doorsTime'] as String;

    return Gig(
      id: json['_id'] as String,
      slug: (json['slug'] as String?) ?? json['_id'] as String,
      title: json['title'] as String,
      venueId: json['venueId'] as String,
      price: (json['price'] as num).toInt(),
      startsAt: startsAt,
      doorsAt: doorsAtMs == null
          ? startsAt
          : DateTime.fromMillisecondsSinceEpoch(doorsAtMs.toInt()),
      dateShort: _dateShortForDate(startsAt),
      dateLine: _dateLineForDate(startsAt, doorsTime, now),
      time: doorsTime,
      when: _whenForDate(startsAt, now),
      flyKey: json['flyKey'] as String,
      lineup: List<String>.from(json['lineup'] as List),
      performers: [
        for (final item in (json['performers'] as List?) ?? const [])
          GigPerformer(
            id: '',
            kind: (item as Map)['bandId'] == null
                ? GigPerformerKind.text
                : GigPerformerKind.band,
            name: item['name'] as String,
            role: GigPerformerRole.values.byName(item['role'] as String),
            bandId: item['bandId'] as String?,
          ),
      ],
      going: (json['goingCount'] as num?)?.toInt() ?? 0,
      genres: List<String>.from(json['genres'] as List),
      desc: json['desc'] as String,
      tix: Ticketing.values.byName(json['ticketing'] as String),
      externalUrl: json['externalUrl'] as String?,
      flyerUrl: json['flyerUrl'] as String?,
      cap: json['cap'] as String,
      ageRequirement: AgeRequirement.fromJson(json['ageRequirement']),
      lifecycle: GigLifecycle.values.byName(
        (json['lifecycle'] as String?) ?? 'published',
      ),
      createdByBand: json['createdByBand'] as String?,
      discoveryListingReady: json['discoveryListingReady'] == true,
    );
  }

  static GigWhen whenFor(int startsAtMs, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMs);
    return _whenForDate(startsAt, current);
  }

  static GigWhen _whenForDate(DateTime startsAt, DateTime now) {
    final isTonight =
        startsAt.year == now.year &&
        startsAt.month == now.month &&
        startsAt.day == now.day;
    if (isTonight) return GigWhen.tonight;
    if (startsAt.difference(now) < const Duration(days: 7)) {
      return GigWhen.week;
    }
    return GigWhen.later;
  }

  static String dateShortFor(int startsAtMs) {
    final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMs);
    return _dateShortForDate(startsAt);
  }

  static String _dateShortForDate(DateTime startsAt) {
    return '${weekdayNamesUpper[startsAt.weekday - 1]} '
        '${monthNamesUpper[startsAt.month - 1]} ${startsAt.day}';
  }

  static String dateLineFor(int startsAtMs, String doorsTime, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMs);
    return _dateLineForDate(startsAt, doorsTime, current);
  }

  static String _dateLineForDate(
    DateTime startsAt,
    String doorsTime,
    DateTime now,
  ) {
    final separator = doorsTime.indexOf(' / ');
    final doors = separator == -1
        ? doorsTime
        : doorsTime.substring(0, separator);
    if (_whenForDate(startsAt, now) == GigWhen.tonight) {
      return 'TONIGHT · DOORS $doors';
    }

    return '${weekdayNamesUpper[startsAt.weekday - 1]} · DOORS $doors';
  }

  bool get free => price == 0;
  String get priceLabel => free ? 'FREE' : '\$$price';
  int? get numericCapacity {
    final value = int.tryParse(cap.trim());
    return value != null && value > 0 ? value : null;
  }

  Gig copyWith({
    String? slug,
    String? title,
    String? venueId,
    int? price,
    DateTime? startsAt,
    DateTime? doorsAt,
    String? dateShort,
    String? dateLine,
    String? time,
    GigWhen? when,
    String? flyKey,
    List<String>? lineup,
    List<GigPerformer>? performers,
    int? going,
    List<String>? genres,
    String? desc,
    Ticketing? tix,
    String? externalUrl,
    String? flyerUrl,
    String? cap,
    AgeRequirement? ageRequirement,
    GigLifecycle? lifecycle,
    String? createdByBand,
    bool? discoveryListingReady,
  }) => Gig(
    id: id,
    slug: slug ?? this.slug,
    title: title ?? this.title,
    venueId: venueId ?? this.venueId,
    price: price ?? this.price,
    startsAt: startsAt ?? this.startsAt,
    doorsAt: doorsAt ?? this.doorsAt,
    dateShort: dateShort ?? this.dateShort,
    dateLine: dateLine ?? this.dateLine,
    time: time ?? this.time,
    when: when ?? this.when,
    flyKey: flyKey ?? this.flyKey,
    lineup: lineup ?? this.lineup,
    performers: performers ?? this.performers,
    going: going ?? this.going,
    genres: genres ?? this.genres,
    desc: desc ?? this.desc,
    tix: tix ?? this.tix,
    externalUrl: externalUrl ?? this.externalUrl,
    flyerUrl: flyerUrl ?? this.flyerUrl,
    cap: cap ?? this.cap,
    ageRequirement: ageRequirement ?? this.ageRequirement,
    lifecycle: lifecycle ?? this.lifecycle,
    createdByBand: createdByBand ?? this.createdByBand,
    discoveryListingReady: discoveryListingReady ?? this.discoveryListingReady,
  );
}

class PastGig {
  final String title;
  final String meta;

  const PastGig(this.title, this.meta);
}

enum FanHistoryStatus { rsvped }

/// A past RSVP shown on the signed-in fan's private profile.
///
/// This deliberately says only that the fan RSVPed. Earplug has no check-in
/// signal that would let the client claim verified attendance.
class FanHistoryItem {
  final String gigId;
  final String title;
  final DateTime startsAt;
  final String venueName;
  final List<String> bandNames;
  final String flyKey;
  final String? flyerUrl;
  final FanHistoryStatus status;

  const FanHistoryItem({
    required this.gigId,
    required this.title,
    required this.startsAt,
    required this.venueName,
    required this.bandNames,
    required this.flyKey,
    required this.flyerUrl,
    required this.status,
  });

  factory FanHistoryItem.fromJson(Map<String, dynamic> json) => FanHistoryItem(
    gigId: json['gigId'] as String,
    title: json['title'] as String,
    startsAt: DateTime.fromMillisecondsSinceEpoch(
      (json['startsAt'] as num).toInt(),
    ),
    venueName: json['venueName'] as String,
    bandNames: List<String>.from(json['bandNames'] as List),
    flyKey: json['flyKey'] as String,
    flyerUrl: json['flyerUrl'] as String?,
    status: FanHistoryStatus.values.byName(json['status'] as String),
  );

  /// Compatibility for the original compact history row while the richer
  /// profile presentation can use the structured fields directly.
  String get meta => Gig.dateShortFor(startsAt.millisecondsSinceEpoch);
}

class Band {
  final String id;
  final String slug;
  final String name;
  final List<String> genres;
  final String area;
  final Color color;
  final String initials;
  final int followers;
  final String bio;
  final String? linkIg;
  final String? linkBc;
  final String? linkYt;
  final String? credits;
  final String? avatarUrl;
  final String? bannerUrl;
  final bool _avatarUrlResolved;
  final bool _bannerUrlResolved;

  /// Legacy shared artwork URL retained for older/demo payloads.
  final String? heroUrl;
  final List<String> upcoming; // gig ids
  final List<PastGig> past;
  final bool profileComplete;
  final bool discoveryProfileReady;
  final bool isSummary;

  const Band({
    required this.id,
    this.slug = '',
    required this.name,
    required this.genres,
    required this.area,
    required this.color,
    required this.initials,
    required this.followers,
    required this.bio,
    this.linkIg,
    this.linkBc,
    this.linkYt,
    this.credits,
    this.avatarUrl,
    this.bannerUrl,
    this._avatarUrlResolved = false,
    this._bannerUrlResolved = false,
    this.heroUrl,
    this.upcoming = const [],
    this.past = const [],
    this.profileComplete = false,
    this.discoveryProfileReady = false,
    this.isSummary = false,
  });

  /// The public slug when available, with the internal ID as a rollout-safe
  /// fallback for legacy records.
  String get publicRef => slug.isEmpty ? id : slug;

  factory Band.fromJson(Map<String, dynamic> json) {
    final pastShows = json['pastShows'] as List? ?? const [];

    return Band(
      id: json['_id'] as String,
      slug: (json['slug'] as String?) ?? '',
      name: json['name'] as String,
      genres: List<String>.from(json['genres'] as List),
      area: json['area'] as String,
      color: _colorFromHex(json['colorHex'] as String),
      initials: json['initials'] as String,
      followers: (json['followerCount'] as num).toInt(),
      bio: (json['bio'] as String?) ?? '',
      linkIg: json['linkIg'] as String?,
      linkBc: json['linkBc'] as String?,
      linkYt: json['linkYt'] as String?,
      credits: json['credits'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      bannerUrl: json['bannerUrl'] as String?,
      avatarUrlResolved: json.containsKey('avatarUrl'),
      bannerUrlResolved: json.containsKey('bannerUrl'),
      heroUrl: json['heroUrl'] as String?,
      profileComplete: json['profileComplete'] == true,
      discoveryProfileReady: json['discoveryProfileReady'] == true,
      isSummary: !json.containsKey('bio'),
      upcoming: const [],
      past: [
        for (final show in pastShows)
          PastGig((show as Map)['title'] as String, show['meta'] as String),
      ],
    );
  }

  String get genreLine => genres.join(' · ');
  String get followersLabel => _compactCount(followers);
  String? get profileImageUrl =>
      _avatarUrlResolved ? avatarUrl : avatarUrl ?? heroUrl;
  String? get headerImageUrl =>
      _bannerUrlResolved ? bannerUrl : bannerUrl ?? heroUrl;

  Band copyWith({
    String? slug,
    String? name,
    List<String>? genres,
    String? area,
    String? initials,
    int? followers,
    String? bio,
    String? linkIg,
    String? linkBc,
    String? linkYt,
    String? credits,
    String? avatarUrl,
    String? bannerUrl,
    bool? avatarUrlResolved,
    bool? bannerUrlResolved,
    String? heroUrl,
    List<String>? upcoming,
    bool? profileComplete,
    bool? discoveryProfileReady,
    bool? isSummary,
  }) => Band(
    id: id,
    slug: slug ?? this.slug,
    name: name ?? this.name,
    genres: genres ?? this.genres,
    area: area ?? this.area,
    color: color,
    initials: initials ?? this.initials,
    followers: followers ?? this.followers,
    bio: bio ?? this.bio,
    linkIg: linkIg ?? this.linkIg,
    linkBc: linkBc ?? this.linkBc,
    linkYt: linkYt ?? this.linkYt,
    credits: credits ?? this.credits,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    bannerUrl: bannerUrl ?? this.bannerUrl,
    avatarUrlResolved: avatarUrlResolved ?? _avatarUrlResolved,
    bannerUrlResolved: bannerUrlResolved ?? _bannerUrlResolved,
    heroUrl: heroUrl ?? this.heroUrl,
    upcoming: upcoming ?? this.upcoming,
    past: past,
    profileComplete: profileComplete ?? this.profileComplete,
    discoveryProfileReady: discoveryProfileReady ?? this.discoveryProfileReady,
    isSummary: isSummary ?? this.isSummary,
  );
}

/// Profile-only data that intentionally stays out of feed and search payloads.
class BandProfileDetails {
  final String? credits;
  final String? linkIg;
  final String? linkBc;
  final String? linkYt;
  final List<String> memberNames;

  const BandProfileDetails({
    this.credits,
    this.linkIg,
    this.linkBc,
    this.linkYt,
    required this.memberNames,
  });

  factory BandProfileDetails.fromJson(Map<String, dynamic> json) =>
      BandProfileDetails(
        credits: json['credits'] as String?,
        linkIg: json['linkIg'] as String?,
        linkBc: json['linkBc'] as String?,
        linkYt: json['linkYt'] as String?,
        memberNames: List<String>.from(
          json['memberNames'] as List? ?? const [],
        ),
      );

  static const empty = BandProfileDetails(memberNames: []);
}

/// The seven task-oriented steps shown only to a band's administrators.
class BandSetupStatus {
  final bool profileComplete;
  final bool profileImageAdded;
  final bool musicAdded;
  final bool socialLinksAdded;
  final bool firstGigCreated;
  final bool membersInvited;
  final bool publicProfilePreviewed;

  const BandSetupStatus({
    required this.profileComplete,
    required this.profileImageAdded,
    required this.musicAdded,
    required this.socialLinksAdded,
    required this.firstGigCreated,
    required this.membersInvited,
    required this.publicProfilePreviewed,
  });

  factory BandSetupStatus.fromJson(Map<String, dynamic> json) =>
      BandSetupStatus(
        profileComplete: json['profileComplete'] == true,
        profileImageAdded: json['profileImageAdded'] == true,
        musicAdded: json['musicAdded'] == true,
        socialLinksAdded: json['socialLinksAdded'] == true,
        firstGigCreated: json['firstGigCreated'] == true,
        membersInvited: json['membersInvited'] == true,
        publicProfilePreviewed: json['publicProfilePreviewed'] == true,
      );

  List<bool> get steps => [
    profileComplete,
    profileImageAdded,
    musicAdded,
    socialLinksAdded,
    firstGigCreated,
    membersInvited,
    publicProfilePreviewed,
  ];

  int get completedCount => steps.where((step) => step).length;
}

class BandDiscoveryShow {
  final String gigId;
  final String projectId;
  final String title;
  final DateTime startsAt;

  const BandDiscoveryShow({
    required this.gigId,
    required this.projectId,
    required this.title,
    required this.startsAt,
  });

  factory BandDiscoveryShow.fromJson(Map<String, dynamic> json) =>
      BandDiscoveryShow(
        gigId: json['gigId'] as String,
        projectId: json['projectId'] as String,
        title: json['title'] as String,
        startsAt: DateTime.fromMillisecondsSinceEpoch(
          (json['startsAt'] as num).toInt(),
        ),
      );
}

class DiscoveryBoostWindow {
  final DateTime opensAt;
  final DateTime closesAt;
  final bool active;

  const DiscoveryBoostWindow({
    required this.opensAt,
    required this.closesAt,
    required this.active,
  });

  factory DiscoveryBoostWindow.fromJson(Map<String, dynamic> json) =>
      DiscoveryBoostWindow(
        opensAt: DateTime.fromMillisecondsSinceEpoch(
          (json['opensAt'] as num).toInt(),
        ),
        closesAt: DateTime.fromMillisecondsSinceEpoch(
          (json['closesAt'] as num).toInt(),
        ),
        active: json['active'] == true,
      );
}

/// The six independent criteria behind organic discovery activation.
class BandDiscoveryReadiness {
  final bool profileComplete;
  final bool profileImageReady;
  final bool clipReady;
  final bool publishedShowReady;
  final bool venuePosterReady;
  final bool publishedRevisionCurrent;
  final BandDiscoveryShow? relevantShow;
  final BandDiscoveryShow? nextEligibleShow;
  final DiscoveryBoostWindow? boostWindow;

  const BandDiscoveryReadiness({
    required this.profileComplete,
    required this.profileImageReady,
    required this.clipReady,
    required this.publishedShowReady,
    required this.venuePosterReady,
    required this.publishedRevisionCurrent,
    this.relevantShow,
    this.nextEligibleShow,
    this.boostWindow,
  });

  factory BandDiscoveryReadiness.fromJson(Map<String, dynamic> json) =>
      BandDiscoveryReadiness(
        profileComplete: json['profileComplete'] == true,
        profileImageReady: json['profileImageReady'] == true,
        clipReady: json['clipReady'] == true,
        publishedShowReady: json['publishedShowReady'] == true,
        venuePosterReady: json['venuePosterReady'] == true,
        publishedRevisionCurrent: json['publishedRevisionCurrent'] == true,
        relevantShow: switch (json['relevantShow']) {
          final Map<Object?, Object?> value => BandDiscoveryShow.fromJson(
            Map<String, dynamic>.from(value),
          ),
          _ => null,
        },
        nextEligibleShow: switch (json['nextEligibleShow']) {
          final Map<Object?, Object?> value => BandDiscoveryShow.fromJson(
            Map<String, dynamic>.from(value),
          ),
          _ => null,
        },
        boostWindow: switch (json['boostWindow']) {
          final Map<Object?, Object?> value => DiscoveryBoostWindow.fromJson(
            Map<String, dynamic>.from(value),
          ),
          _ => null,
        },
      );

  List<bool> get steps => [
    profileComplete,
    profileImageReady,
    clipReady,
    publishedShowReady,
    venuePosterReady,
    publishedRevisionCurrent,
  ];

  int get completedCount => steps.where((step) => step).length;
}

/// Every editable band-profile field, submitted in one backend transaction.
class BandProfileUpdate {
  final String bandId;
  final String name;
  final List<String> genres;
  final String area;
  final String bio;
  final String linkIg;
  final String linkBc;
  final String linkYt;
  final String credits;

  const BandProfileUpdate({
    required this.bandId,
    required this.name,
    required this.genres,
    required this.area,
    required this.bio,
    required this.linkIg,
    required this.linkBc,
    required this.linkYt,
    required this.credits,
  });
}

class BandInvite {
  final String bandId;
  final String token;
  final DateTime expiresAt;
  final bool revoked;
  final bool expired;

  const BandInvite({
    required this.bandId,
    required this.token,
    required this.expiresAt,
    required this.revoked,
    required this.expired,
  });

  factory BandInvite.fromJson(Map<String, dynamic> json) => BandInvite(
    bandId: json['bandId'] as String,
    token: json['token'] as String,
    expiresAt: DateTime.fromMillisecondsSinceEpoch(
      (json['expiresAt'] as num).toInt(),
    ),
    revoked: json['revoked'] == true,
    expired: json['expired'] == true,
  );

  String get url => publicWebUrl('join/$token');
}

/// The deliberately small public payload used before a recipient confirms.
class BandInviteResolution {
  final String bandId;
  final String bandName;
  final String initials;
  final Color color;

  const BandInviteResolution({
    required this.bandId,
    required this.bandName,
    required this.initials,
    required this.color,
  });

  factory BandInviteResolution.fromJson(Map<String, dynamic> json) =>
      BandInviteResolution(
        bandId: json['bandId'] as String,
        bandName: json['bandName'] as String,
        initials: json['initials'] as String,
        color: _colorFromHex(json['colorHex'] as String),
      );
}

class BandInviteAcceptance {
  final String bandId;
  final bool membershipCreated;

  const BandInviteAcceptance({
    required this.bandId,
    required this.membershipCreated,
  });

  factory BandInviteAcceptance.fromJson(Map<String, dynamic> json) =>
      BandInviteAcceptance(
        bandId: json['bandId'] as String,
        membershipCreated: json['membershipCreated'] == true,
      );
}

/// The small public payload shown before a band claims a lineup invitation.
class PerformerInviteResolution {
  final String performerName;
  final String gigTitle;

  const PerformerInviteResolution({
    required this.performerName,
    required this.gigTitle,
  });

  factory PerformerInviteResolution.fromJson(Map<String, dynamic> json) =>
      PerformerInviteResolution(
        performerName: json['performerName'] as String,
        gigTitle: json['gigTitle'] as String,
      );
}

enum MediaKind { video, photo }

class BandArchiveResult {
  const BandArchiveResult({
    required this.bandId,
    required this.archivedAt,
    required this.alreadyArchived,
  });

  final String bandId;
  final DateTime archivedAt;
  final bool alreadyArchived;

  factory BandArchiveResult.fromJson(Map<String, dynamic> json) =>
      BandArchiveResult(
        bandId: json['bandId'] as String,
        archivedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['archivedAt'] as num).toInt(),
        ),
        alreadyArchived: json['alreadyArchived'] == true,
      );
}

class BandArchiveStatus {
  const BandArchiveStatus({required this.bandId, required this.archivedAt});

  final String bandId;
  final DateTime? archivedAt;

  bool get archived => archivedAt != null;

  factory BandArchiveStatus.fromJson(Map<String, dynamic> json) =>
      BandArchiveStatus(
        bandId: json['bandId'] as String,
        archivedAt: json['archivedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (json['archivedAt'] as num).toInt(),
              ),
      );
}

class BandMedia {
  final String id;
  final String bandId;
  final MediaKind kind;
  final String? url;
  final String? thumbnailUrl;
  final String title;
  final String? caption;
  final int? sizeBytes;
  final int? views;
  final int? lengthSec;
  final bool pinned;
  final int order;
  final bool isHero;
  final bool isAvatar;
  final bool isBanner;

  const BandMedia({
    required this.id,
    required this.bandId,
    required this.kind,
    required this.url,
    this.thumbnailUrl,
    required this.title,
    required this.caption,
    required this.sizeBytes,
    required this.views,
    required this.lengthSec,
    required this.pinned,
    required this.order,
    required this.isHero,
    this.isAvatar = false,
    this.isBanner = false,
  });

  factory BandMedia.fromJson(Map<String, dynamic> json) => BandMedia(
    id: json['_id'] as String,
    bandId: json['bandId'] as String,
    kind: MediaKind.values.byName(json['kind'] as String),
    url: json['url'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    title: json['title'] as String,
    caption: json['caption'] as String?,
    sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
    views: (json['views'] as num?)?.toInt(),
    lengthSec: (json['lengthSec'] as num?)?.toInt(),
    pinned: json['pinned'] as bool,
    order: (json['order'] as num).toInt(),
    isHero: json['isHero'] as bool,
    isAvatar: json['isAvatar'] as bool? ?? false,
    isBanner: json['isBanner'] as bool? ?? json['isHero'] as bool,
  );

  bool get isVideo => kind == MediaKind.video;

  String get lenLabel {
    if (lengthSec == null) return '';
    final seconds = (lengthSec! % 60).toString().padLeft(2, '0');
    return '${lengthSec! ~/ 60}:$seconds';
  }

  String get viewsLabel =>
      views == null ? '' : '${_compactCount(views!)} views';

  BandMedia copyWith({bool? pinned, int? order, String? title}) => BandMedia(
    id: id,
    bandId: bandId,
    kind: kind,
    url: url,
    thumbnailUrl: thumbnailUrl,
    title: title ?? this.title,
    caption: caption,
    sizeBytes: sizeBytes,
    views: views,
    lengthSec: lengthSec,
    pinned: pinned ?? this.pinned,
    order: order ?? this.order,
    isHero: isHero,
    isAvatar: isAvatar,
    isBanner: isBanner,
  );
}

Color _colorFromHex(String value) {
  final hex = value.startsWith('#') ? value.substring(1) : value;
  return Color(0xFF000000 | int.parse(hex, radix: 16));
}

String _compactCount(num count) {
  if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(1)}K';
  }
  return count == count.roundToDouble() ? '${count.toInt()}' : '$count';
}
