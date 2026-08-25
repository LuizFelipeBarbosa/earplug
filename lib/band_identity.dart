/// Matches the backend's deterministic initials rule for band names.
String bandInitialsFor(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .toList();
  if (words.isEmpty) return '??';
  if (words.length == 1) {
    final word = words.single;
    return word.substring(0, word.length < 2 ? word.length : 2).toUpperCase();
  }
  return '${words[0][0]}${words[1][0]}'.toUpperCase();
}
