import 'package:earplug/initials.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_sheet.dart';
import 'package:earplug/widgets/ep_states.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home) => MaterialApp(theme: buildEpTheme(), home: home);

/// The outermost [W] inside the widget under test [T], skipping the ones the
/// framework's own chrome (Scaffold, buttons) adds around and below it.
Finder _inside<T extends Widget, W extends Widget>() =>
    find.descendant(of: find.byType(T), matching: find.byType(W)).first;

void main() {
  group('initials', () {
    test('initialsFirstLast takes the first and last words', () {
      expect(initialsFirstLast('Jordan Lee'), 'JL');
      expect(initialsFirstLast('Jordan Ada Lee'), 'JL');
      expect(initialsFirstLast('  Jordan  '), 'J');
      expect(initialsFirstLast('   '), '?');
      expect(initialsFirstLast('', fallback: 'EF'), 'EF');
      expect(initialsFirstLast('ábel élise'), 'áé');
    });

    test('initialsFirstWords takes the first two words', () {
      expect(initialsFirstWords('jordan ada lee'), 'JA');
      expect(initialsFirstWords('jordan ada', upper: false), 'ja');
      expect(initialsFirstWords(null), '??');
      expect(initialsFirstWords('   ', fallback: 'EF'), 'EF');
      expect(initialsFirstWords('Jordan (host)'), 'J(');
      expect(initialsFirstWords('Jordan (host)', stripPunctuation: true), 'JH');
      expect(initialsFirstWords('(!) Jordan', stripPunctuation: true), 'J');
    });
  });

  group('EpLoadError', () {
    testWidgets('shows the message and fires RETRY', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: EpLoadError(
              message: 'Could not load venues.',
              onRetry: () => retried++,
            ),
          ),
        ),
      );
      expect(find.text('Could not load venues.'), findsOne);
      await tester.tap(find.widgetWithText(EpButton, 'RETRY'));
      await tester.pump();
      expect(retried, 1);

      final padding = tester.widget<Padding>(_inside<EpLoadError, Padding>());
      expect(padding.padding, const EdgeInsets.only(top: 56));
      final column = tester.widget<Column>(_inside<EpLoadError, Column>());
      expect(column.crossAxisAlignment, CrossAxisAlignment.center);
      expect(
        tester.widget<Text>(find.text('Could not load venues.')).textAlign,
        isNull,
      );
    });

    testWidgets('honours alignment, text alignment and spacing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: EpLoadError(
              message: 'Could not load.',
              onRetry: () {},
              topPadding: 24,
              gap: 8,
              textAlign: TextAlign.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
            ),
          ),
        ),
      );
      final padding = tester.widget<Padding>(_inside<EpLoadError, Padding>());
      expect(padding.padding, const EdgeInsets.only(top: 24));
      final column = tester.widget<Column>(_inside<EpLoadError, Column>());
      expect(column.crossAxisAlignment, CrossAxisAlignment.stretch);
      expect(
        tester.widget<Text>(find.text('Could not load.')).textAlign,
        TextAlign.center,
      );
      final gap = tester.widget<SizedBox>(_inside<EpLoadError, SizedBox>());
      expect(gap.height, 8);
    });
  });

  group('EpNotAuthorized', () {
    testWidgets('keeps the admin key and the back button', (tester) async {
      var backs = 0;
      await tester.pumpWidget(
        _app(
          EpNotAuthorized(
            message: 'Only platform admins can review.',
            onBack: () => backs++,
          ),
        ),
      );
      expect(find.byKey(const Key('admin-not-authorized')), findsOne);
      final text = tester.widget<Text>(
        find.text('Only platform admins can review.'),
      );
      expect(text.textAlign, TextAlign.center);
      await tester.tap(find.widgetWithText(EpButton, 'BACK TO FAN VIEW'));
      await tester.pump();
      expect(backs, 1);
    });

    testWidgets('a custom action replaces the back button', (tester) async {
      await tester.pumpWidget(
        _app(
          EpNotAuthorized(
            message: 'No access.',
            onBack: () {},
            action: const Text('SIGN IN'),
          ),
        ),
      );
      expect(find.text('SIGN IN'), findsOne);
      expect(find.text('BACK TO FAN VIEW'), findsNothing);
    });
  });

  group('EpInlineRetry', () {
    testWidgets('fires RETRY through the given key', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: EpInlineRetry(
              message: 'Could not load applicants.',
              onRetry: () => retried++,
              retryKey: const Key('applicants-retry'),
            ),
          ),
        ),
      );
      expect(find.text('Could not load applicants.'), findsOne);
      expect(find.byType(SizedBox), findsNothing);
      await tester.tap(find.byKey(const Key('applicants-retry')));
      await tester.pump();
      expect(retried, 1);
    });

    testWidgets('honours topGap and alignment', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: EpInlineRetry(
              message: 'Could not load.',
              onRetry: () {},
              topGap: 24,
              crossAxisAlignment: CrossAxisAlignment.start,
            ),
          ),
        ),
      );
      final column = tester.widget<Column>(find.byType(Column).first);
      expect(column.crossAxisAlignment, CrossAxisAlignment.start);
      expect(tester.widget<SizedBox>(find.byType(SizedBox)).height, 24);
      expect(find.widgetWithText(TextButton, 'RETRY'), findsOne);
    });
  });

  testWidgets('EpCenteredPage caps width and stretches its children', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        const EpCenteredPage(
          children: [Text('Payment received'), SizedBox(height: 12)],
        ),
      ),
    );
    expect(find.text('Payment received'), findsOne);
    final boxFinder = _inside<EpCenteredPage, ConstrainedBox>();
    expect(tester.widget<ConstrainedBox>(boxFinder).constraints.maxWidth, 480);
    expect(tester.getSize(boxFinder).width, 480);
    final scroll = tester.widget<SingleChildScrollView>(
      _inside<EpCenteredPage, SingleChildScrollView>(),
    );
    expect(scroll.padding, const EdgeInsets.fromLTRB(20, 24, 20, 40));
    final column = tester.widget<Column>(_inside<EpCenteredPage, Column>());
    expect(column.crossAxisAlignment, CrossAxisAlignment.stretch);
    expect(column.mainAxisSize, MainAxisSize.min);
  });

  group('epConfirm', () {
    Future<Future<bool>> open(WidgetTester tester) async {
      late Future<bool> result;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  result = epConfirm(
                    context,
                    title: 'DISCARD CHANGES?',
                    body: 'Unsaved edits will be lost.',
                    confirmLabel: 'DISCARD',
                    keepKey: const Key('confirm-keep'),
                    confirmKey: const Key('confirm-go'),
                  );
                },
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOne);
      expect(find.text('DISCARD CHANGES?'), findsOne);
      expect(find.text('Unsaved edits will be lost.'), findsOne);
      return result;
    }

    testWidgets('KEEP resolves false', (tester) async {
      final result = await open(tester);
      expect(find.widgetWithText(TextButton, 'KEEP'), findsOne);
      await tester.tap(find.byKey(const Key('confirm-keep')));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('CONFIRM resolves true', (tester) async {
      final result = await open(tester);
      expect(find.widgetWithText(FilledButton, 'DISCARD'), findsOne);
      await tester.tap(find.byKey(const Key('confirm-go')));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('dismissing through the barrier resolves false', (
      tester,
    ) async {
      final result = await open(tester);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('EpConfirmSheet', () {
    Future<void> open(
      WidgetTester tester, {
      String? caption,
      required Future<void> Function() onConfirm,
    }) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showEpSheet(
                  context,
                  (_) => EpConfirmSheet(
                    header: 'Remove member?',
                    caption: caption,
                    confirmLabel: 'REMOVE',
                    confirmKey: const Key('band-member-confirm'),
                    onConfirm: onConfirm,
                  ),
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(find.byType(EpConfirmSheet), findsOne);
    }

    testWidgets('confirm awaits the callback then closes', (tester) async {
      var confirmed = 0;
      await open(tester, onConfirm: () async => confirmed++);
      expect(find.text('REMOVE MEMBER?'), findsOne);
      expect(find.byType(EpSheetShell), findsOne);
      await tester.tap(find.byKey(const Key('band-member-confirm')));
      await tester.pumpAndSettle();
      expect(confirmed, 1);
      expect(find.byType(EpConfirmSheet), findsNothing);
    });

    testWidgets('KEEP closes without confirming', (tester) async {
      var confirmed = 0;
      await open(tester, onConfirm: () async => confirmed++);
      expect(find.byType(OutlinedButton), findsOne);
      await tester.tap(find.widgetWithText(TextButton, 'KEEP'));
      await tester.pumpAndSettle();
      expect(confirmed, 0);
      expect(find.byType(EpConfirmSheet), findsNothing);
    });

    testWidgets('caption renders only when given', (tester) async {
      await open(tester, onConfirm: () async {});
      expect(
        find.descendant(
          of: find.byType(EpConfirmSheet),
          matching: find.byType(Text),
        ),
        findsNWidgets(3),
      );
      await tester.tap(find.widgetWithText(TextButton, 'KEEP'));
      await tester.pumpAndSettle();

      await open(
        tester,
        caption: 'They lose access to the band immediately.',
        onConfirm: () async {},
      );
      final caption = tester.widget<Text>(
        find.text('They lose access to the band immediately.'),
      );
      expect(caption.maxLines, 2);
      expect(caption.overflow, TextOverflow.ellipsis);
    });
  });

  group('EpSheetTitleRow', () {
    testWidgets('uppercases the title and closes the route', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showEpSheet(
                  context,
                  (_) => const EpSheetTitleRow(title: 'Edit notes'),
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT NOTES'), findsOne);
      expect(find.bySemanticsLabel('Edit notes'), findsOne);
      await tester.tap(find.widgetWithText(TextButton, 'CLOSE'));
      await tester.pumpAndSettle();
      expect(find.byType(EpSheetTitleRow), findsNothing);
    });

    testWidgets('trailing replaces the Close button', (tester) async {
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: EpSheetTitleRow(title: 'Filters', trailing: Text('RESET')),
          ),
        ),
      );
      expect(find.text('FILTERS'), findsOne);
      expect(find.text('RESET'), findsOne);
      expect(find.text('CLOSE'), findsNothing);
    });
  });
}
