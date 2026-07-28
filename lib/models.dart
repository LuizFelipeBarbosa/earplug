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
}

/// Xeroxed-flyer color treatment: base color, faint horizontal stripes, ink.
class FlyerStyle {
  final Color base;
  final Color stripe;
  final Color fg;

  const FlyerStyle({required this.base, required this.stripe, required this.fg});
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

  bool get free => price == 0;
  String get priceLabel => free ? 'FREE' : '\$$price';
}

class PastGig {
  final String title;
  final String meta;

  const PastGig(this.title, this.meta);
}

class Band {
  final String name;
  final List<String> genres;
  final String area;
  final Color color;
  final String initials;
  final int followers;
  final String bio;
  final List<String> upcoming; // gig ids
  final List<PastGig> past;

  const Band({
    required this.name,
    required this.genres,
    required this.area,
    required this.color,
    required this.initials,
    required this.followers,
    required this.bio,
    this.upcoming = const [],
    this.past = const [],
  });

  String get genreLine => genres.join(' · ');
  String get followersLabel => followers >= 1000
      ? '${(followers / 1000).toStringAsFixed(1)}K'
      : '$followers';

  Band copyWith({String? bio}) => Band(
        name: name,
        genres: genres,
        area: area,
        color: color,
        initials: initials,
        followers: followers,
        bio: bio ?? this.bio,
        upcoming: upcoming,
        past: past,
      );
}

class VideoClip {
  final String title;
  final String views;
  final String len;
  final bool pinned;

  const VideoClip({
    required this.title,
    required this.views,
    required this.len,
    this.pinned = false,
  });

  VideoClip copyWith({bool? pinned}) =>
      VideoClip(title: title, views: views, len: len, pinned: pinned ?? this.pinned);
}
