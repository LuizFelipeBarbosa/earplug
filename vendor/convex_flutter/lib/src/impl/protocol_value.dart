import 'dart:convert';

/// Distinguishes a missing protocol field from a present JSON `null` result.
String? encodeProtocolValue(Map<String, dynamic> message, String field) {
  if (!message.containsKey(field)) return null;
  return jsonEncode(message[field]);
}
