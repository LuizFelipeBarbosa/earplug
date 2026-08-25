import 'package:earplug/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('join token is preserved from a path-based web URL', () {
    expect(
      joinTokenFromUri(Uri.parse('https://earplug.app/join/secret-token')),
      'secret-token',
    );
  });

  test('join token is preserved from a hash-based fallback URL', () {
    expect(
      joinTokenFromUri(Uri.parse('https://earplug.app/#/join/secret-token')),
      'secret-token',
    );
  });

  test('ordinary app URLs do not enter the invitation flow', () {
    expect(joinTokenFromUri(Uri.parse('https://earplug.app/explore')), isNull);
  });
}
