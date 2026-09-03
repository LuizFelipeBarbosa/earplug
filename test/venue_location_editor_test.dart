import 'package:earplug/widgets/venue_location_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('venue editor without a name field emits field edits', (
    tester,
  ) async {
    var draft = const VenueLocationDraft();
    final harness = await pumpApp(
      tester,
      home: Scaffold(
        body: VenueLocationEditor(
          initial: draft,
          keyPrefix: 'editor-only',
          showNameField: false,
          onChanged: (value) => draft = value,
        ),
      ),
    );

    expect(find.byKey(const Key('editor-only-address')), findsOneWidget);
    expect(find.byKey(const Key('editor-only-area')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('editor-only-address')),
      '9 Pier Street',
    );
    await tester.pump();

    expect(draft.address, '9 Pier Street');
    harness.app.dispose();
  });
}
