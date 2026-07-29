import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

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

class UserProfile {
  final String name;
  final String email;
  final List<String> genres;
  final int attendedCount;
  final DateTime createdAt;

  const UserProfile({
    required this.name,
    required this.email,
    required this.genres,
    required this.attendedCount,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: json['name'] as String,
    email: json['email'] as String,
    genres: List<String>.from(json['genres'] as List),
    attendedCount: (json['attendedCount'] as num).toInt(),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (json['createdAt'] as num).toInt(),
    ),
  );
}

/// Xeroxed-flyer color treatment: base color, faint horizontal stripes, ink.
class FlyerStyle {
  final Color base;
  final Color stripe;
  final Color fg;

  const FlyerStyle({
    required this.base,
    required this.stripe,
    required this.fg,
  });
}

enum GigWhen { tonight, week, later }

enum Ticketing { rsvp, external }

class Gig {
  final String id;
  final String title;
  final String venueId;
  final int price; // dollars; 0 == free
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
  final String cap;

  const Gig({
    required this.id,
    required this.title,
    required this.venueId,
    required this.price,
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
    this.cap = 'No cap',
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
      cap: json['cap'] as String,
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
    return '${_weekdays[startsAt.weekday - 1]} '
        '${_months[startsAt.month - 1]} ${startsAt.day}';
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
    return '${_weekdays[startsAt.weekday - 1]} · DOORS $doors';
  }

  static const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  bool get free => price == 0;
  String get priceLabel => free ? 'FREE' : '\$$price';
}

class PastGig {
  final String title;
  final String meta;

  const PastGig(this.title, this.meta);
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
    String? bio,
    String? linkIg,
    String? linkBc,
    List<String>? upcoming,
  }) => Band(
    id: id,
    name: name,
    genres: genres,
    area: area,
    color: color,
    initials: initials,
    followers: followers,
    bio: bio ?? this.bio,
    linkIg: linkIg ?? this.linkIg,
    linkBc: linkBc ?? this.linkBc,
    upcoming: upcoming ?? this.upcoming,
    past: past,
  );
}

class VideoClip {
  final String id;
  final String title;
  final String views;
  final String len;
  final bool pinned;

  const VideoClip({
    required this.id,
    required this.title,
    required this.views,
    required this.len,
    this.pinned = false,
  });

  factory VideoClip.fromJson(Map<String, dynamic> json) {
    final lengthSec = (json['lengthSec'] as num).toInt();
    final seconds = (lengthSec % 60).toString().padLeft(2, '0');
    return VideoClip(
      id: json['_id'] as String,
      title: json['title'] as String,
      views: '${_compactCount(json['views'] as num)} views',
      len: '${lengthSec ~/ 60}:$seconds',
      pinned: json['pinned'] as bool,
    );
  }

  VideoClip copyWith({bool? pinned}) => VideoClip(
    id: id,
    title: title,
    views: views,
    len: len,
    pinned: pinned ?? this.pinned,
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
