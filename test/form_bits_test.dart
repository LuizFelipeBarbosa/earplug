import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EpLabeledField labels required fields and forwards input', (
    tester,
  ) async {
    final requiredController = TextEditingController();
    final optionalController = TextEditingController();
    addTearDown(requiredController.dispose);
    addTearDown(optionalController.dispose);
    var changedValue = '';

    await _pump(
      tester,
      Column(
        children: [
          EpLabeledField(
            label: 'BAND NAME',
            hint: 'Your band name',
            controller: requiredController,
            fieldKey: const ValueKey('required-field'),
            required: true,
            onChanged: (value) => changedValue = value,
            caption: 'This appears on your profile.',
          ),
          EpLabeledField(
            label: 'WEBSITE',
            hint: 'Website',
            controller: optionalController,
          ),
        ],
      ),
    );

    expect(find.text('BAND NAME · REQUIRED'), findsOneWidget);
    expect(find.text('WEBSITE'), findsOneWidget);
    expect(find.text('WEBSITE · REQUIRED'), findsNothing);
    expect(find.text('This appears on your profile.'), findsOneWidget);

    final field = find.byKey(const ValueKey('required-field'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'New Name');
    expect(changedValue, 'New Name');
    expect(
      find.ancestor(of: field, matching: find.byType(EpCard)),
      findsNothing,
    );
  });

  testWidgets('FieldLabel displays required and plain labels', (tester) async {
    await _pump(
      tester,
      const Column(
        children: [
          FieldLabel('HOME BASE', required: true),
          FieldLabel('ACCEPTED MEMBERS'),
        ],
      ),
    );

    expect(find.text('HOME BASE · REQUIRED'), findsOneWidget);
    expect(find.text('ACCEPTED MEMBERS'), findsOneWidget);
    expect(find.text('ACCEPTED MEMBERS · REQUIRED'), findsNothing);
  });

  testWidgets('InlineFormFeedback shrinks away without a message', (
    tester,
  ) async {
    await _pump(tester, const InlineFormFeedback());

    final feedback = find.byType(InlineFormFeedback);
    expect(
      find.descendant(of: feedback, matching: find.byType(Text)),
      findsNothing,
    );
    final box = tester.widget<SizedBox>(
      find.descendant(of: feedback, matching: find.byType(SizedBox)),
    );
    expect(box.width, 0);
    expect(box.height, 0);
  });

  testWidgets('InlineFormFeedback gives errors precedence over success', (
    tester,
  ) async {
    await _pump(
      tester,
      const InlineFormFeedback(
        error: 'Could not save.',
        success: 'Saved.',
        errorKey: ValueKey('error'),
        successKey: ValueKey('success'),
      ),
    );

    expect(find.byKey(const ValueKey('error')), findsOneWidget);
    expect(find.text('Could not save.'), findsOneWidget);
    expect(find.byKey(const ValueKey('success')), findsNothing);
    expect(find.text('Saved.'), findsNothing);
  });

  testWidgets('InlineFormFeedback shows success when there is no error', (
    tester,
  ) async {
    await _pump(
      tester,
      const InlineFormFeedback(
        success: 'Changes saved.',
        errorKey: ValueKey('error'),
        successKey: ValueKey('success'),
      ),
    );

    expect(find.byKey(const ValueKey('success')), findsOneWidget);
    expect(find.text('Changes saved.'), findsOneWidget);
    expect(find.byKey(const ValueKey('error')), findsNothing);
  });

  testWidgets('FormSection is flat by default and can be boxed explicitly', (
    tester,
  ) async {
    await _pump(
      tester,
      ListView(
        children: const [
          FormSection(
            title: 'Flat',
            description: 'Default treatment',
            child: SizedBox(key: ValueKey('flat-child')),
          ),
          FormSection(
            title: 'Boxed',
            description: 'Explicit treatment',
            boxed: true,
            child: SizedBox(key: ValueKey('boxed-child')),
          ),
        ],
      ),
    );

    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('flat-child')),
        matching: find.byType(EpCard),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('boxed-child')),
        matching: find.byType(EpCard),
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildEpTheme(),
      home: Scaffold(body: child),
    ),
  );
}
