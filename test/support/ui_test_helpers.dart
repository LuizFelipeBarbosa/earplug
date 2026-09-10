import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Functional tests identify copy independently of its typography. Dedicated
/// form tests assert sentence case and semantics explicitly.
Finder findUiText(String text, {bool skipOffstage = true}) =>
    find.textContaining(
      RegExp('^${RegExp.escape(text)}\$', caseSensitive: false),
      skipOffstage: skipOffstage,
    );

Finder findUiControl(Type type, String text) =>
    find.ancestor(of: findUiText(text), matching: find.byType(type));

Finder findUiSemantics(String text) => find.bySemanticsLabel(
  RegExp('^${RegExp.escape(text)}\$', caseSensitive: false),
);

/// Opens only the disclosure ancestors of a control, through their visible UI.
Future<void> revealFormKey(WidgetTester tester, Key key) async {
  if (find.byKey(key).hitTestable().evaluate().isNotEmpty) return;
  final target = find.byKey(key, skipOffstage: false);
  if (target.evaluate().isEmpty) return;
  final titles = <String>[];
  tester.element(target.first).visitAncestorElements((element) {
    if (element.widget case EpDisclosure(:final title)) titles.add(title);
    return true;
  });
  for (final title in titles.reversed) {
    final disclosure = find
        .ancestor(of: findUiText(title), matching: find.byType(EpDisclosure))
        .first;
    if (disclosure.evaluate().isEmpty) continue;
    final toggle = find
        .descendant(
          of: disclosure,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.expanded != null,
          ),
        )
        .first;
    if (tester.widget<Semantics>(toggle).properties.expanded == false) {
      final tile = find.widgetWithText(ListTile, title).first;
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }
  }
  if (find.byKey(key).evaluate().isNotEmpty) {
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
  }
}

Future<void> openFormSection(WidgetTester tester, String title) async {
  final tile = find.widgetWithText(ListTile, title).first;
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> openAllFormSections(WidgetTester tester) async {
  final titles = tester
      .widgetList<EpDisclosure>(find.byType(EpDisclosure, skipOffstage: false))
      .map((section) => section.title)
      .toList();
  for (final title in titles) {
    final tile = find.widgetWithText(ListTile, title);
    if (tile.evaluate().isEmpty) continue;
    final expanded = find
        .ancestor(
          of: tile.first,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.expanded != null,
          ),
        )
        .first;
    if (tester.widget<Semantics>(expanded).properties.expanded == false) {
      await tester.ensureVisible(tile.first);
      await tester.tap(tile.first);
      await tester.pumpAndSettle();
    }
  }
}

Future<void> chooseBandGenres(WidgetTester tester, List<String> toggles) async {
  final field = find.byKey(const ValueKey('band-genres-field'));
  await tester.ensureVisible(field);
  await tester.tap(
    find.descendant(of: field, matching: find.byType(OutlinedButton)).first,
  );
  await tester.pumpAndSettle();
  for (final genre in toggles) {
    final option = findUiControl(CheckboxListTile, genre);
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pump();
  }
  await tester.tap(findUiControl(FilledButton, 'Done'));
  await tester.pumpAndSettle();
}

Future<void> chooseFormSelection(
  WidgetTester tester,
  String label,
  String option,
) async {
  final field = find.byWidgetPredicate(
    (widget) =>
        widget is EpSelectionField &&
        widget.label.toLowerCase() == label.toLowerCase(),
  );
  await tester.ensureVisible(field);
  await tester.tap(
    find.descendant(of: field, matching: find.byType(OutlinedButton)),
  );
  await tester.pumpAndSettle();
  final row = findUiControl(ListTile, option);
  await tester.ensureVisible(row.last);
  await tester.tap(row.last);
  await tester.pumpAndSettle();
}

Future<void> toggleFormSelection(
  WidgetTester tester,
  String label,
  String option,
) async {
  final field = find.byWidgetPredicate(
    (widget) => widget is EpSelectionField && widget.label == label,
  );
  await tester.ensureVisible(field);
  await tester.tap(
    find.descendant(of: field, matching: find.byType(OutlinedButton)),
  );
  await tester.pumpAndSettle();
  final row = findUiControl(CheckboxListTile, option);
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();
}
