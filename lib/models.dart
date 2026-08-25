import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

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

enum FanCity { sf, oak }

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
    preferredCity: switch (json['preferredCity']) {
      final String value => FanCity.values.byName(value),
      _ => null,
    },
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
    homeLocation: switch (json['homeLocation']) {
      'sf' => FanCity.sf,
      'oak' => FanCity.oak,
      _ => null,
    },
    locationPersonalizationEnabled:
        json['locationPersonalizationEnabled'] is bool
        ? json['locationPersonalizationEnabled'] as bool
        : false,
    followedBandUpdatesEnabled: json['followedBandUpdatesEnabled'] is bool
        ? json['followedBandUpdatesEnabled'] as bool
        : true,
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
  final String title;
  final String venueId;
  final int price; // dollars; 0 == free
  final DateTime startsAt;
  final String dateShort; // "TUE JUL 28"
  final String dateLine; // "TONIGHT · DOORS 8PM"
  final String time; // "8PM / 9PM"
  final GigWhen when;
  final String flyKey;
  final List<String> lineup; // band ids
  final int going;
  final List<String> genres;
  final String desc;
  final Ticketing tix;
  final String? externalUrl;
  final String? flyerUrl;
  final String cap;
  final AgeRequirement ageRequirement;

  const Gig({
    required this.id,
    required this.title,
    required this.venueId,
    required this.price,
    required this.startsAt,
    required this.dateShort,
    required this.dateLine,
    required this.time,
    required this.when,
    required this.flyKey,
    required this.lineup,
    required this.going,
    required this.genres,
    required this.desc,
    required this.tix,
    this.externalUrl,
    this.flyerUrl,
    this.cap = 'No cap',
    this.ageRequirement = AgeRequirement.allAges,
  });

  factory Gig.fromJson(Map<String, dynamic> json) {
    final startsAt = (json['startsAt'] as num).toInt();
    final doorsTime = json['doorsTime'] as String;
    final now = DateTime.now();

    return Gig(
      id: json['_id'] as String,
      title: json['title'] as String,
      venueId: json['venueId'] as String,
      price: (json['price'] as num).toInt(),
      startsAt: DateTime.fromMillisecondsSinceEpoch(startsAt),
      dateShort: dateShortFor(startsAt),
      dateLine: dateLineFor(startsAt, doorsTime, now: now),
      time: doorsTime,
      when: whenFor(startsAt, now: now),
      flyKey: json['flyKey'] as String,
      lineup: List<String>.from(json['lineup'] as List),
      going: (json['goingCount'] as num).toInt(),
      genres: List<String>.from(json['genres'] as List),
      desc: json['desc'] as String,
      tix: Ticketing.values.byName(json['ticketing'] as String),
      externalUrl: json['externalUrl'] as String?,
      flyerUrl: json['flyerUrl'] as String?,
      cap: json['cap'] as String,
      ageRequirement: AgeRequirement.fromJson(json['ageRequirement']),
    );
  }

  static GigWhen whenFor(int startsAtMs, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMs);
    final isTonight =
        startsAt.year == current.year &&
        startsAt.month == current.month &&
        startsAt.day == current.day;
    if (isTonight) return GigWhen.tonight;
    if (startsAt.difference(current) < const Duration(days: 7)) {
      return GigWhen.week;
    }
    return GigWhen.later;
  }

  static String dateShortFor(int startsAtMs) {
    final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMs);
    return '${weekdayNamesUpper[startsAt.weekday - 1]} '
        '${monthNamesUpper[startsAt.month - 1]} ${startsAt.day}';
  }

  static String dateLineFor(int startsAtMs, String doorsTime, {DateTime? now}) {
    final separator = doorsTime.indexOf(' / ');
    final doors = separator == -1
        ? doorsTime
        : doorsTime.substring(0, separator);
    if (whenFor(startsAtMs, now: now) == GigWhen.tonight) {
      return 'TONIGHT · DOORS $doors';
    }

    final startsAt = DateTime.fromMillisecondsSinceEpoch(startsAtMs);
    return '${weekdayNamesUpper[startsAt.weekday - 1]} · DOORS $doors';
  }

  bool get free => price == 0;
  String get priceLabel => free ? 'FREE' : '\$$price';
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
  final String? heroUrl;
  final List<String> upcoming; // gig ids
  final List<PastGig> past;

  const Band({
    required this.id,
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
    this.heroUrl,
    this.upcoming = const [],
    this.past = const [],
  });

  factory Band.fromJson(Map<String, dynamic> json) {
    final pastShows = json['pastShows'] as List? ?? const [];

    return Band(
      id: json['_id'] as String,
      name: json['name'] as String,
      genres: List<String>.from(json['genres'] as List),
      area: json['area'] as String,
      color: _colorFromHex(json['colorHex'] as String),
      initials: json['initials'] as String,
      followers: (json['followerCount'] as num).toInt(),
      bio: json['bio'] as String,
      linkIg: json['linkIg'] as String?,
      linkBc: json['linkBc'] as String?,
      linkYt: json['linkYt'] as String?,
      credits: json['credits'] as String?,
      heroUrl: json['heroUrl'] as String?,
      upcoming: const [],
      past: [
        for (final show in pastShows)
          PastGig((show as Map)['title'] as String, show['meta'] as String),
      ],
    );
  }

  String get genreLine => genres.join(' · ');
  String get followersLabel => _compactCount(followers);

  Band copyWith({
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
    String? heroUrl,
    List<String>? upcoming,
  }) => Band(
    id: id,
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
    heroUrl: heroUrl ?? this.heroUrl,
    upcoming: upcoming ?? this.upcoming,
    past: past,
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

  const BandInvite({
    required this.bandId,
    required this.token,
    required this.expiresAt,
    required this.revoked,
  });

  factory BandInvite.fromJson(Map<String, dynamic> json) => BandInvite(
    bandId: json['bandId'] as String,
    token: json['token'] as String,
    expiresAt: DateTime.fromMillisecondsSinceEpoch(
      (json['expiresAt'] as num).toInt(),
    ),
    revoked: json['revoked'] == true,
  );

  String get url => 'https://earplug.app/join/$token';
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

enum MediaKind { video, photo }

class BandMedia {
  final String id;
  final String bandId;
  final MediaKind kind;
  final String? url;
  final String title;
  final String? caption;
  final int? sizeBytes;
  final int? views;
  final int? lengthSec;
  final bool pinned;
  final int order;
  final bool isHero;

  const BandMedia({
    required this.id,
    required this.bandId,
    required this.kind,
    required this.url,
    required this.title,
    required this.caption,
    required this.sizeBytes,
    required this.views,
    required this.lengthSec,
    required this.pinned,
    required this.order,
    required this.isHero,
  });

  factory BandMedia.fromJson(Map<String, dynamic> json) => BandMedia(
    id: json['_id'] as String,
    bandId: json['bandId'] as String,
    kind: MediaKind.values.byName(json['kind'] as String),
    url: json['url'] as String?,
    title: json['title'] as String,
    caption: json['caption'] as String?,
    sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
    views: (json['views'] as num?)?.toInt(),
    lengthSec: (json['lengthSec'] as num?)?.toInt(),
    pinned: json['pinned'] as bool,
    order: (json['order'] as num).toInt(),
    isHero: json['isHero'] as bool,
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
    title: title ?? this.title,
    caption: caption,
    sizeBytes: sizeBytes,
    views: views,
    lengthSec: lengthSec,
    pinned: pinned ?? this.pinned,
    order: order ?? this.order,
    isHero: isHero,
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
