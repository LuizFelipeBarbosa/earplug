import 'dart:convert';
import 'dart:typed_data';

import 'package:earplug/models.dart';
import 'package:earplug/services/media_picker.dart';
import 'package:flutter/material.dart' show Color;

/// A decodable 1x1 PNG — for tests that put the picked photo on screen.
PickedMedia photoFixture({String filename = 'band_photo.png'}) {
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  return PickedMedia(
    bytes: bytes,
    filename: filename,
    contentType: 'image/png',
    sizeBytes: bytes.lengthInBytes,
  );
}

/// Three opaque bytes — for tests that only carry the photo around, never
/// decode it.
PickedMedia stubPhotoFixture({String filename = 'backstage.jpg'}) =>
    PickedMedia(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: filename,
      contentType: 'image/jpeg',
      sizeBytes: 3,
    );

/// Three opaque bytes standing in for a clip.
PickedMedia videoFixture({String filename = 'riptide_live.mp4'}) => PickedMedia(
  bytes: Uint8List.fromList([1, 2, 3]),
  filename: filename,
  contentType: 'video/mp4',
  sizeBytes: 3,
);

/// A published RSVP gig at `v1`. Date strings derive from [startsAt] unless
/// a test needs specific copy.
Gig gigFixture({
  required String id,
  String? title,
  String venueId = 'v1',
  int price = 0,
  DateTime? startsAt,
  DateTime? doorsAt,
  String time = '8PM / 9PM',
  String? dateShort,
  String? dateLine,
  GigWhen? when,
  String flyKey = 'paper',
  List<String> lineup = const [],
  List<GigPerformer> performers = const [],
  int going = 0,
  List<String> genres = const [],
  String desc = '',
  Ticketing tix = Ticketing.rsvp,
  String? flyerUrl,
  String cap = 'No cap',
  GigLifecycle lifecycle = GigLifecycle.published,
  String? createdByBand,
  bool discoveryListingReady = false,
}) {
  final starts = startsAt ?? DateTime.now().add(const Duration(days: 2));
  final startsMs = starts.millisecondsSinceEpoch;
  return Gig(
    id: id,
    title: title ?? id,
    venueId: venueId,
    price: price,
    startsAt: starts,
    doorsAt: doorsAt,
    dateShort: dateShort ?? Gig.dateShortFor(startsMs),
    dateLine: dateLine ?? Gig.dateLineFor(startsMs, time),
    time: time,
    when: when ?? Gig.whenFor(startsMs),
    flyKey: flyKey,
    lineup: lineup,
    performers: performers,
    going: going,
    genres: genres,
    desc: desc,
    tix: tix,
    flyerUrl: flyerUrl,
    cap: cap,
    lifecycle: lifecycle,
    createdByBand: createdByBand,
    discoveryListingReady: discoveryListingReady,
  );
}

/// A minimal punk band with one follower.
Band bandFixture({
  required String id,
  String? slug,
  String? name,
  List<String> genres = const ['punk'],
  String area = 'Oakland',
  Color color = const Color(0xFF7B8FFF),
  String initials = 'BD',
  int followers = 1,
  String bio = '',
  String? linkIg,
  String? linkBc,
  String? linkYt,
  String? credits,
  bool profileComplete = false,
  bool discoveryProfileReady = false,
}) => Band(
  id: id,
  slug: slug ?? '',
  name: name ?? id,
  genres: genres,
  area: area,
  color: color,
  initials: initials,
  followers: followers,
  bio: bio,
  linkIg: linkIg,
  linkBc: linkBc,
  linkYt: linkYt,
  credits: credits,
  profileComplete: profileComplete,
  discoveryProfileReady: discoveryProfileReady,
);

/// A pinned 30-second clip on `b1`.
BandMedia videoMediaFixture({
  String title = 'Clip',
  String? thumbnailUrl,
  int views = 2,
}) => BandMedia(
  id: 'm1',
  bandId: 'b1',
  kind: MediaKind.video,
  url: 'https://example.com/video.mp4',
  thumbnailUrl: thumbnailUrl,
  title: title,
  caption: null,
  sizeBytes: 10,
  views: views,
  lengthSec: 30,
  pinned: true,
  order: 0,
  isHero: false,
);
