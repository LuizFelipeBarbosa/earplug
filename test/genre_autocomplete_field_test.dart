import 'package:earplug/genres.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/genre_autocomplete_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('labels the field and updates the counter when adding a chip', (
    tester,
  ) async {
    final changes = <List<String>>[];
    const initial = <String>[];
    final selected = await _pumpField(
      tester,
      selected: initial,
      onChanged: changes.add,
    );

    expect(find.text('GENRES · REQUIRED'), findsOneWidget);
    expect(tester.widget<EpMonoText>(_key('count')).text, '0 OF 3');
    expect(_key('suggestions'), findsNothing);

    await tester.enterText(_key('input'), 'ro');
    await tester.pump();
    await tester.tap(_key('suggestion-0'));
    await tester.pump();

    expect(selected.value, ['rock']);
    expect(changes, [
      <String>['rock'],
    ]);
    expect(identical(changes.single, initial), isFalse);
    expect(initial, isEmpty);
    expect(_key('chip-rock'), findsOneWidget);
    final pill = tester.widget<EpPill>(find.byType(EpPill));
    expect(pill.label, 'rock');
    expect(pill.selected, isTrue);
    expect(pill.onPressed, isNull);
    expect(find.text('1 OF 3'), findsOneWidget);
    expect(_field(tester).controller!.text, isEmpty);
    expect(_field(tester).focusNode!.hasFocus, isTrue);
    expect(_key('suggestions'), findsNothing);
  });

  testWidgets('matches substrings and always puts the custom row last', (
    tester,
  ) async {
    await _pumpField(
      tester,
      suggestions: const ['rock', 'punk', 'post-punk', 'Prog Rock'],
    );
    await tester.enterText(_key('input'), 'ro');
    await tester.pump();

    expect(find.text('rock'), findsOneWidget);
    expect(find.text('Prog Rock'), findsOneWidget);
    expect(find.text('punk'), findsNothing);
    final rows = tester.widgetList<InkWell>(
      find.descendant(of: _key('suggestions'), matching: find.byType(InkWell)),
    );
    expect(rows.map((row) => row.key), [
      const Key('edit-genres-suggestion-0'),
      const Key('edit-genres-suggestion-1'),
      const Key('edit-genres-add-custom'),
    ]);
    expect(find.text('Add "ro"'), findsOneWidget);
    final palette = tester.element(_key('input')).epColors;
    expect(
      tester.widget<Text>(find.text('Add "ro"')).style!.color,
      palette.accent,
    );
    final icons = tester.widgetList<Icon>(
      find.descendant(
        of: _key('suggestions'),
        matching: find.byIcon(Icons.add),
      ),
    );
    expect(icons.length, 3);
    expect(
      icons.every((icon) => icon.color == palette.contentSecondary),
      isTrue,
    );
    expect(
      tester.getTopLeft(_key('suggestions')).dy,
      tester.getBottomLeft(_key('input')).dy,
    );
    expect(
      tester.getTopLeft(_key('add-custom')).dy,
      greaterThan(tester.getTopLeft(_key('suggestion-1')).dy),
    );
  });

  testWidgets('filters case-insensitively, excludes selected, caps at six', (
    tester,
  ) async {
    await _pumpField(
      tester,
      selected: const ['ROCK'],
      suggestions: const [
        'rock',
        'Prog Rock',
        'art rock',
        'punk',
        'post-rock',
        'garage rock',
        'hard rock',
        'soft rock',
        'folk rock',
      ],
    );
    await tester.enterText(_key('input'), 'RO');
    await tester.pump();

    final labels = tester.widgetList<Text>(
      find.descendant(of: _key('suggestions'), matching: find.byType(Text)),
    );
    expect(labels.map((label) => label.data), [
      'Prog Rock',
      'art rock',
      'post-rock',
      'garage rock',
      'hard rock',
      'soft rock',
      'Add "RO"',
    ]);
    expect(_key('suggestion-6'), findsNothing);
  });

  for (final enterKey in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  ]) {
    testWidgets('${enterKey.keyLabel} commits the highlighted match', (
      tester,
    ) async {
      final selected = await _pumpField(
        tester,
        suggestions: const ['rock', 'Prog Rock', 'punk'],
      );
      await tester.enterText(_key('input'), 'ro');
      await tester.pump();
      final tint = tester
          .element(_key('input'))
          .epColors
          .accent
          .withValues(alpha: .18);
      expect(_rowColor(tester, 'suggestion-0'), tint);
      expect(_rowColor(tester, 'suggestion-1'), isNull);
      final cursor = _field(tester).controller!.selection;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_rowColor(tester, 'suggestion-0'), isNull);
      expect(_rowColor(tester, 'suggestion-1'), tint);
      expect(_field(tester).controller!.selection, cursor);

      await tester.sendKeyEvent(enterKey);
      await tester.pump();
      expect(selected.value, ['Prog Rock']);
      expect(_key('chip-Prog Rock'), findsOneWidget);
      expect(_field(tester).controller!.text, isEmpty);
      expect(_field(tester).focusNode!.hasFocus, isTrue);
    });
  }

  testWidgets('arrows clamp at both ends and include the custom row', (
    tester,
  ) async {
    final selected = await _pumpField(tester);
    await tester.enterText(_key('input'), 'ro');
    await tester.pump();
    final tint = tester
        .element(_key('input'))
        .epColors
        .accent
        .withValues(alpha: .18);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(_rowColor(tester, 'suggestion-0'), tint);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_rowColor(tester, 'add-custom'), tint);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(_rowColor(tester, 'suggestion-0'), tint);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected.value, ['ro']);
  });

  testWidgets('clamps the active row when typing or selected genres change', (
    tester,
  ) async {
    final selected = await _pumpField(
      tester,
      suggestions: const ['rock', 'prog', 'punk'],
    );
    await tester.enterText(_key('input'), 'r');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.enterText(_key('input'), 'ro');
    await tester.pump();
    selected.value = ['ROCK', 'PROG'];
    await tester.pump();
    final tint = tester
        .element(_key('input'))
        .epColors
        .accent
        .withValues(alpha: .18);
    expect(_rowColor(tester, 'add-custom'), tint);
    expect(_key('suggestion-0'), findsNothing);

    await tester.enterText(_key('input'), ' Ambient ');
    await tester.pump();
    expect(_rowColor(tester, 'add-custom'), tint);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected.value, ['ROCK', 'PROG', 'Ambient']);
  });

  testWidgets('clamps the active row when the suggestions prop changes', (
    tester,
  ) async {
    await _pumpField(tester, suggestions: const ['rock', 'prog']);
    await tester.enterText(_key('input'), 'ro');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    final selected = await _pumpField(tester, suggestions: const []);

    expect(_field(tester).controller!.text, 'ro');
    expect(
      _rowColor(tester, 'add-custom'),
      tester.element(_key('input')).epColors.accent.withValues(alpha: .18),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected.value, ['ro']);
  });

  testWidgets('IME Done adds trimmed custom text and prevents duplicates', (
    tester,
  ) async {
    final changes = <List<String>>[];
    final selected = await _pumpField(tester, onChanged: changes.add);
    await tester.enterText(_key('input'), '  Dream Pop  ');
    await tester.pump();
    expect(find.text('Add "Dream Pop"'), findsOneWidget);
    expect(_key('suggestion-0'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(selected.value, ['Dream Pop']);
    expect(_key('chip-Dream Pop'), findsOneWidget);
    expect(_field(tester).controller!.text, isEmpty);
    expect(_field(tester).focusNode!.hasFocus, isTrue);
    await tester.enterText(_key('input'), ' dReAm pOp ');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(selected.value, ['Dream Pop']);
    expect(changes.length, 1);
    expect(_field(tester).controller!.text, isEmpty);
    expect(_field(tester).focusNode!.hasFocus, isTrue);
  });

  testWidgets('tapping Add uses the custom text even when matches exist', (
    tester,
  ) async {
    final selected = await _pumpField(tester);
    await tester.enterText(_key('input'), ' Ro ');
    await tester.pump();
    await tester.tap(_key('add-custom'));
    await tester.pump();
    expect(selected.value, ['Ro']);
    expect(_field(tester).controller!.text, isEmpty);
    expect(_field(tester).focusNode!.hasFocus, isTrue);
  });

  testWidgets('empty and whitespace-only custom submissions are no-ops', (
    tester,
  ) async {
    final changes = <List<String>>[];
    await _pumpField(tester, onChanged: changes.add);
    await tester.enterText(_key('input'), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.enterText(_key('input'), '   ');
    await tester.pump();
    await tester.tap(_key('add-custom'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(changes, isEmpty);
    expect(find.byType(EpPill), findsNothing);
  });

  testWidgets('close has an accessible 44px target and emits a new list', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final changes = <List<String>>[];
    const initial = ['rock', 'punk'];
    final selected = await _pumpField(
      tester,
      selected: initial,
      onChanged: changes.add,
    );
    final close = find.descendant(
      of: _key('chip-rock'),
      matching: find.byType(IconButton),
    );
    expect(tester.getSize(close), const Size(44, 44));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Remove rock')),
      matchesSemantics(
        label: 'Remove rock',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    final icon = tester.widget<Icon>(
      find.descendant(of: close, matching: find.byIcon(Icons.close)),
    );
    expect(icon.color, tester.element(close).epColors.contentSecondary);
    await tester.tap(close);
    await tester.pump();

    expect(changes, [
      <String>['punk'],
    ]);
    expect(selected.value, ['punk']);
    expect(initial, ['rock', 'punk']);
    expect(identical(changes.single, initial), isFalse);
    expect(_key('chip-rock'), findsNothing);
    expect(find.text('1 OF 3'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'a pending commit at max preserves text and shows the limit note',
    (tester) async {
      final changes = <List<String>>[];
      final selected = await _pumpField(
        tester,
        selected: const ['rock', 'punk'],
        onChanged: changes.add,
      );
      await tester.enterText(_key('input'), 'Ambient');
      await tester.pump();
      // Another parent update fills the last slot before a pending IME commit.
      selected.value = ['rock', 'punk', 'post-punk'];
      await tester.pump();
      expect(_field(tester).enabled, isFalse);
      expect(_field(tester).decoration!.hintText, 'Genres full');
      expect(find.text('3 OF 3'), findsOneWidget);
      expect(_key('suggestions'), findsNothing);
      expect(_key('limit'), findsNothing);

      _field(tester).onSubmitted!('Ambient');
      await tester.pump();
      expect(_key('limit'), findsOneWidget);
      expect(find.text('Choose no more than three genres.'), findsOneWidget);
      expect(_field(tester).controller!.text, 'Ambient');
      expect(changes, isEmpty);
      expect(selected.value, ['rock', 'punk', 'post-punk']);

      await tester.tap(
        find.descendant(
          of: _key('chip-punk'),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pump();
      expect(_key('limit'), findsNothing);
      expect(_field(tester).enabled, isTrue);
      expect(_field(tester).decoration!.hintText, 'Add a genre');
      expect(_key('suggestions'), findsOneWidget);
      await tester.tap(_key('add-custom'));
      await tester.pump();
      expect(selected.value, ['rock', 'post-punk', 'Ambient']);
      expect(_field(tester).enabled, isFalse);
    },
  );

  testWidgets(
    'a duplicate attempt clears an existing limit note and the text',
    (tester) async {
      final selected = await _pumpField(
        tester,
        selected: const ['rock', 'punk', 'post-punk'],
      );
      final controller = _field(tester).controller!;
      controller.text = 'Ambient';
      _field(tester).onSubmitted!(controller.text);
      await tester.pump();
      expect(_key('limit'), findsOneWidget);

      controller.text = 'ROCK';
      _field(tester).onSubmitted!(controller.text);
      await tester.pump();
      expect(_key('limit'), findsNothing);
      expect(controller.text, isEmpty);
      expect(selected.value, ['rock', 'punk', 'post-punk']);
    },
  );

  testWidgets(
    'uses the shared genre default and custom keys and optional label',
    (tester) async {
      await _pumpField(tester, keyPrefix: 'create-genres', required: false);
      expect(find.text('GENRES'), findsOneWidget);
      expect(find.text('GENRES · REQUIRED'), findsNothing);
      expect(find.byKey(const Key('create-genres-count')), findsOneWidget);
      expect(find.byKey(const Key('create-genres-input')), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildEpTheme(),
          home: Scaffold(
            body: GenreAutocompleteField(selected: const [], onChanged: (_) {}),
          ),
        ),
      );
      expect(
        tester
            .widget<GenreAutocompleteField>(find.byType(GenreAutocompleteField))
            .suggestions,
        same(kGenres),
      );
      await tester.enterText(_key('input'), 'punk');
      await tester.pump();
      expect(
        find.descendant(of: _key('suggestions'), matching: find.text('punk')),
        findsOneWidget,
      );
      expect(find.text('post-punk'), findsOneWidget);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('uses outlined borders and the $brightness theme accent', (
      tester,
    ) async {
      await _pumpField(tester, brightness: brightness);
      final decoration = _field(tester).decoration!;
      final palette = tester.element(_key('input')).epColors;
      for (final border in [
        decoration.border,
        decoration.enabledBorder,
        decoration.disabledBorder,
      ]) {
        expect(border, isA<OutlineInputBorder>());
        expect(
          (border! as OutlineInputBorder).borderRadius,
          BorderRadius.circular(EpLayout.controlRadius),
        );
        expect(border.borderSide.color, palette.border);
      }
      final focused = decoration.focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, palette.accent);
      expect(focused.borderSide.width, 1.5);
      expect(
        focused.borderRadius,
        BorderRadius.circular(EpLayout.controlRadius),
      );
      expect(_field(tester).textInputAction, TextInputAction.done);
    });
  }

  for (final scale in [1.0, 1.5]) {
    testWidgets(
      '390px layout with three chips and dropdown at text scale $scale',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final selected = await _pumpField(
          tester,
          selected: const [
            'post-punk',
            'An extremely long custom genre that must fit on a narrow phone',
            'shoegaze',
          ],
          // Three chips and an open dropdown require a limit above three.
          max: 4,
          suggestions: const [
            'rock',
            'An extremely long progressive rock suggestion that wraps naturally',
          ],
        );
        await tester.enterText(_key('input'), 'ro');
        await tester.pump();
        expect(find.byType(EpPill), findsNWidgets(3));
        expect(find.text('3 OF 4'), findsOneWidget);
        expect(_key('suggestions'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(
          tester.getTopLeft(_key('chip-post-punk')).dy,
          lessThan(tester.getTopLeft(_key('input')).dy),
        );
        await tester.tap(_key('suggestion-0'));
        await tester.pump();
        expect(selected.value.last, 'rock');
        expect(_field(tester).enabled, isFalse);
        await tester.tap(
          find.descendant(
            of: _key('chip-rock'),
            matching: find.byType(IconButton),
          ),
        );
        await tester.pump();
        expect(_field(tester).enabled, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Finder _key(String suffix) => find.byKey(Key('edit-genres-$suffix'));

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(_key('input'));

Color? _rowColor(WidgetTester tester, String suffix) {
  final ink = tester.widget<Ink>(
    find.descendant(of: _key(suffix), matching: find.byType(Ink)),
  );
  return (ink.decoration as BoxDecoration?)?.color;
}

Future<ValueNotifier<List<String>>> _pumpField(
  WidgetTester tester, {
  List<String> selected = const [],
  List<String> suggestions = const ['rock', 'punk', 'post-punk'],
  ValueChanged<List<String>>? onChanged,
  int max = 3,
  String keyPrefix = 'edit-genres',
  bool required = true,
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final selection = ValueNotifier<List<String>>(selected);
  addTearDown(selection.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildEpTheme(brightness),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(EpLayout.gutter),
          child: ValueListenableBuilder<List<String>>(
            valueListenable: selection,
            builder: (context, genres, child) => GenreAutocompleteField(
              selected: genres,
              onChanged: (value) {
                onChanged?.call(value);
                selection.value = value;
              },
              max: max,
              suggestions: suggestions,
              keyPrefix: keyPrefix,
              required: required,
            ),
          ),
        ),
      ),
    ),
  );
  return selection;
}
