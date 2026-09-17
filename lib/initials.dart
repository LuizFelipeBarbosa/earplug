import 'package:flutter/widgets.dart';

final _whitespace = RegExp(r'\s+');
final _nonLetterOrDigit = RegExp(r'[^\p{L}\p{N}]', unicode: true);

/// First letter of the first and last words of [name]; a single word gives
/// one letter and a blank name gives [fallback]. Case is left as typed.
String initialsFirstLast(String name, {String fallback = '?'}) {
  final words = name
      .trim()
      .split(_whitespace)
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return fallback;
  if (words.length == 1) return words.first.characters.first;
  return '${words.first.characters.first}${words.last.characters.first}';
}

/// First letter of each of the first two words of [name], uppercased unless
/// [upper] is false. With [stripPunctuation], "Jordan (host)" gives "JH".
/// A null or blank name gives [fallback].
String initialsFirstWords(
  String? name, {
  String fallback = '??',
  bool upper = true,
  bool stripPunctuation = false,
}) {
  var words = (name ?? '').trim().split(_whitespace);
  if (stripPunctuation) {
    words = words
        .map((word) => word.replaceAll(_nonLetterOrDigit, ''))
        .toList();
  }
  final joined = words
      .where((word) => word.isNotEmpty)
      .take(2)
      .map((word) => word.characters.first)
      .join();
  final initials = upper ? joined.toUpperCase() : joined;
  return initials.isEmpty ? fallback : initials;
}
