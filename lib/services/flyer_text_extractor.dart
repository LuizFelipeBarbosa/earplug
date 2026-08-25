import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models.dart';

class FlyerTextExtraction {
  const FlyerTextExtraction(this.lines);

  final List<String> lines;

  String get text => lines.join('\n');
}

class FlyerClockTime {
  const FlyerClockTime(this.hour, this.minute);

  final int hour;
  final int minute;
}

class FlyerEntryProposal {
  const FlyerEntryProposal({
    required this.rawText,
    this.title,
    this.date,
    this.doors,
    this.start,
    this.venueId,
    this.venueName,
    this.price,
    this.bands = const [],
  });

  final String rawText;
  final String? title;
  final DateTime? date;
  final FlyerClockTime? doors;
  final FlyerClockTime? start;
  final String? venueId;
  final String? venueName;
  final int? price;
  final List<Band> bands;

  bool get hasSuggestions =>
      title != null ||
      date != null ||
      doors != null ||
      start != null ||
      venueId != null ||
      price != null ||
      bands.isNotEmpty;
}

/// Runs private, on-device OCR through Apple Vision or bundled ML Kit.
class FlyerTextExtractor {
  const FlyerTextExtractor();

  static const _channel = MethodChannel('earplug/flyer_ocr');

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<FlyerTextExtraction?> extract(Uint8List bytes) async {
    if (!isSupported) return null;
    final result = await _channel.invokeListMethod<String>('extractText', {
      'bytes': bytes,
    });
    if (result == null) return null;
    final lines = result
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    return FlyerTextExtraction(lines);
  }
}

/// Converts OCR text into conservative suggestions. Nothing returned here is
/// applied until the user reviews and confirms it in the gig form.
class FlyerEntryParser {
  const FlyerEntryParser();

  FlyerEntryProposal parse(
    FlyerTextExtraction extraction, {
    required List<Venue> venues,
    required List<Band> bands,
    DateTime? now,
  }) {
    final lines = extraction.lines;
    final normalized = lines.map(_normalize).toList(growable: false);
    final normalizedText = normalized.join(' ');
    final readableText = lines.join(' ').toLowerCase();
    final venue = _bestNamedMatch(
      normalizedText,
      venues,
      (venue) => venue.name,
    );
    final matchedBands = [
      for (final band in bands)
        if (_containsName(normalizedText, band.name)) band,
    ];
    final date = _dateFrom(readableText, now ?? DateTime.now());
    final doors = _labeledTime(readableText, 'doors');
    final start =
        _labeledTime(readableText, 'start') ??
        _labeledTime(readableText, 'show') ??
        _unlabeledTime(readableText, excluding: doors);
    final price = _priceFrom(readableText);

    final metadata = <String>{
      if (venue != null) _normalize(venue.name),
      for (final band in matchedBands) _normalize(band.name),
    };
    final title = _titleFrom(lines, metadata);

    return FlyerEntryProposal(
      rawText: extraction.text,
      title: title,
      date: date,
      doors: doors,
      start: start,
      venueId: venue?.id,
      venueName: venue?.name,
      price: price,
      bands: matchedBands,
    );
  }

  T? _bestNamedMatch<T>(
    String text,
    List<T> candidates,
    String Function(T candidate) name,
  ) {
    final matches = candidates
        .where((candidate) => _containsName(text, name(candidate)))
        .toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => name(b).length.compareTo(name(a).length));
    return matches.first;
  }

  bool _containsName(String text, String name) {
    final normalizedName = _normalize(name);
    if (normalizedName.length < 3) return false;
    return RegExp('(^| )${RegExp.escape(normalizedName)}( |\$)').hasMatch(text);
  }

  String? _titleFrom(List<String> lines, Set<String> knownNames) {
    for (final line in lines.take(8)) {
      final normalized = _normalize(line);
      if (normalized.length < 3 ||
          knownNames.contains(normalized) ||
          _looksLikeMetadata(normalized)) {
        continue;
      }
      return line.trim();
    }
    return null;
  }

  bool _looksLikeMetadata(String value) =>
      value.contains(
        RegExp(r'\b(doors|start|show|tickets?|cover|rsvp|all ages)\b'),
      ) ||
      value.contains(RegExp(r'\$\s*\d+')) ||
      value.contains(RegExp(r'\b\d{1,2}[:/]\d{1,2}\b')) ||
      value.contains(
        RegExp(r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)'),
      );

  DateTime? _dateFrom(String text, DateTime now) {
    const months = {
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };
    final named = RegExp(
      r'\b(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\s+(\d{1,2})(?:st|nd|rd|th)?(?:\s*,?\s*(\d{2,4}))?\b',
    ).firstMatch(text);
    if (named != null) {
      final month = months[named.group(1)]!;
      final day = int.parse(named.group(2)!);
      final year = _normalizedYear(named.group(3), now.year);
      return _validFutureDate(year, month, day, now);
    }

    final numeric = RegExp(
      r'\b(\d{1,2})[/.](\d{1,2})(?:[/.](\d{2,4}))?\b',
    ).firstMatch(text);
    if (numeric == null) return null;
    return _validFutureDate(
      _normalizedYear(numeric.group(3), now.year),
      int.parse(numeric.group(1)!),
      int.parse(numeric.group(2)!),
      now,
    );
  }

  int _normalizedYear(String? value, int fallback) {
    if (value == null) return fallback;
    final parsed = int.parse(value);
    return parsed < 100 ? 2000 + parsed : parsed;
  }

  DateTime? _validFutureDate(int year, int month, int day, DateTime now) {
    var date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    if (date.isBefore(DateTime(now.year, now.month, now.day)) &&
        year == now.year) {
      date = DateTime(year + 1, month, day);
    }
    return date;
  }

  FlyerClockTime? _labeledTime(String text, String label) {
    final match = RegExp(
      '\\b$label(?:\\s+(?:at|open))?\\s*[:@-]?\\s*'
      '(\\d{1,2})(?::(\\d{2}))?(?:\\s*(am|pm))?'
      '(?!\\s*(?:am|pm)\\b)(?=\\s|/|\$)',
    ).firstMatch(text);
    return match == null ? null : _clockTime(match);
  }

  FlyerClockTime? _unlabeledTime(String text, {FlyerClockTime? excluding}) {
    for (final match in RegExp(
      r'\b(\d{1,2})(?::(\d{2}))(?:\s*(am|pm))?'
      r'(?!\s*(?:am|pm)\b)(?=\s|/|$)',
    ).allMatches(text)) {
      final time = _clockTime(match);
      if (time != null &&
          (excluding == null ||
              time.hour != excluding.hour ||
              time.minute != excluding.minute)) {
        return time;
      }
    }
    return null;
  }

  FlyerClockTime? _clockTime(RegExpMatch match) {
    var hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2) ?? '0');
    final meridiem = match.group(3);
    if (hour == null || minute == null || minute > 59) return null;
    if (meridiem != null) {
      if (hour < 1 || hour > 12) return null;
      if (hour == 12) hour = 0;
      if (meridiem == 'pm') hour += 12;
    } else if (hour > 23) {
      return null;
    }
    return FlyerClockTime(hour, minute);
  }

  int? _priceFrom(String text) {
    if (RegExp(r'\bfree(?:\s+(?:show|admission|entry))?\b').hasMatch(text)) {
      return 0;
    }
    final match = RegExp(r'\$\s*(\d{1,4})\b').firstMatch(text);
    return match == null ? null : int.parse(match.group(1)!);
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9$]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
