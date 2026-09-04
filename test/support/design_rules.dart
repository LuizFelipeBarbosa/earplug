import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void expectNoFieldInCard(WidgetTester tester) {
  final offendingFields = <String>[];

  void collectOffenders<T extends Widget>(Finder finder, String fieldType) {
    for (final field in tester.widgetList<T>(finder)) {
      final cardAncestor = find.ancestor(
        of: find.byWidget(field),
        matching: find.byType(EpCard),
      );
      if (cardAncestor.evaluate().isEmpty) continue;

      final key = field.key?.toString() ?? 'no key';
      offendingFields.add('$fieldType: $key');
    }
  }

  collectOffenders<TextField>(find.byType(TextField), 'TextField');
  collectOffenders<TextFormField>(find.byType(TextFormField), 'TextFormField');

  expect(
    offendingFields,
    isEmpty,
    reason:
        'Text fields must not have an EpCard ancestor. '
        'Offending fields: ${offendingFields.join(', ')}',
  );
}
