import 'package:earplug/main.dart' show shouldEnableWebSemantics;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldEnableWebSemantics', () {
    test("query '1' enables semantics regardless of the stored preference", () {
      expect(shouldEnableWebSemantics(queryValue: '1', stored: false), isTrue);
      expect(shouldEnableWebSemantics(queryValue: '1', stored: true), isTrue);
    });

    test(
      "query '0' disables semantics regardless of the stored preference",
      () {
        expect(
          shouldEnableWebSemantics(queryValue: '0', stored: false),
          isFalse,
        );
        expect(
          shouldEnableWebSemantics(queryValue: '0', stored: true),
          isFalse,
        );
      },
    );

    test('a missing query uses the stored preference', () {
      expect(
        shouldEnableWebSemantics(queryValue: null, stored: false),
        isFalse,
      );
      expect(shouldEnableWebSemantics(queryValue: null, stored: true), isTrue);
    });
  });
}
