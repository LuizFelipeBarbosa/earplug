import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/screens/gig_create.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('the flyer, its presses and every sheet render and drive the form',
      (tester) async {
    final app = await _pumpGigCreate(tester);

    // Header, live flyer and the four slot cards.
    expect(find.text('NEW GIG'), findsOne);
    expect(find.text('DRAFT'), findsOne);
    expect(find.text('TYPE YOUR GIG NAME'), findsOne);
    expect(find.text('+ DATE & DOORS'), findsOne);
    expect(find.text('WHEN · REQUIRED'), findsOne);
    expect(find.text('VENUE · REQUIRED'), findsOne);
    expect(find.text('Still needs a name + a date + a venue'), findsOne);

    // Typing on the poster fills the name card below it too.
    await tester.enterText(find.byType(TextField).first, 'Riptide Release');
    await tester.pump();
    expect(app.gfName, 'Riptide Release');
    expect(find.text('GIG NAME ✓'), findsOne);
    expect(find.text('Still needs a date + a venue'), findsOne);

    await tester.tap(find.byKey(const ValueKey('press-riso')));
    await tester.pump();
    expect(app.gfFly, 'riso');

    // When sheet — pick a day from the rolling calendar.
    await tester.tap(find.text('WHEN · REQUIRED'));
    await tester.pumpAndSettle();
    expect(find.text('WHEN IS IT'), findsOne);
    expect(find.text('DOORS 8PM'), findsOne);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await tester.tap(find.text('${tomorrow.day}').first);
    await tester.pump();
    expect(app.gfDate?.day, tomorrow.day);
    await tester.tap(find.text('DOORS 7PM'));
    await tester.pump();
    expect(app.gfDoorsLabel, '7PM');
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();

    // Venue sheet.
    await tester.tap(find.text('VENUE · REQUIRED'));
    await tester.pumpAndSettle();
    expect(find.text('WHERE IS IT'), findsOne);
    await tester.tap(find.text('THE FOGHORN CLUB'));
    await tester.pumpAndSettle();
    expect(app.gfVenueId, 'v1');
    expect(find.text('READY'), findsOne);
    expect(
      find.text('Ready — fans nearby see it the second you post.'),
      findsOne,
    );

    // Price sheet — a preset closes it, the custom field stays open.
    await tester.tap(find.text('PRICE'));
    await tester.pumpAndSettle();
    expect(find.text('COVER'), findsOne);
    await tester.enterText(find.widgetWithText(TextField, 'Other amount'), '7');
    await tester.pump();
    expect(app.gfPrice, '\$7');
    await tester.tap(find.text('\$10'));
    await tester.pumpAndSettle();
    expect(app.gfPrice, '\$10');

    // Tickets sheet — cap chips, then swap to an external link.
    await tester.tap(find.text('TICKETS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('100'));
    await tester.pump();
    expect(app.gfCap, '100');
    await tester.tap(find.text('External ticket link'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'https://…'),
      'https://dice.fm/riptide',
    );
    await tester.pump();
    expect(app.gfExt, 'https://dice.fm/riptide');
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();

    // Publish, then the live-flyer confirmation.
    await tester.tap(find.text('PUBLISH GIG'));
    await tester.pumpAndSettle();
    expect(app.gfPublished, isTrue);
    expect(find.text('PUBLISHED'), findsOne);
    expect(find.text("IT'S LIVE."), findsOne);
    expect(find.text('earplug.app/g/riptide-release'), findsOne);
    expect(app.allGigs.last.title, 'Riptide Release');
    expect(app.allGigs.last.flyKey, 'riso');

    await tester.tap(find.text('MAKE ANOTHER'));
    await tester.pumpAndSettle();
    expect(find.text('TYPE YOUR GIG NAME'), findsOne);
    expect(app.gfPrice, 'FREE');
  });

  testWidgets('uploaded art swaps the press for a drop slot and an overlay toggle',
      (tester) async {
    final app = await _pumpGigCreate(tester);
    expect(find.text('Text overlay'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('press-custom')));
    await tester.pump();
    expect(app.gfCustomFlyer, isTrue);
    expect(find.text('DROP YOUR FLYER'), findsOne);
    expect(find.text('Text overlay'), findsOne);
    expect(
      find.text('Drop your flyer art — the text stays editable on top.'),
      findsOne,
    );

    // Overlay off hides the printed details but keeps the slot cards.
    await tester.tap(find.text('Text overlay'));
    await tester.pump();
    expect(app.gfShowOverlay, isFalse);
    expect(find.text('+ DATE & DOORS'), findsNothing);
    expect(find.text('WHEN · REQUIRED'), findsOne);
  });
}

Future<AppState> _pumpGigCreate(WidgetTester tester) async {
  // A phone-sized surface: the design targets 402x874.
  tester.view.physicalSize = const Size(402, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final auth = FakeAuthService();
  final app = AppState(repository: DemoRepository(auth: auth), auth: auth);
  addTearDown(app.dispose);
  await tester.pumpAndSettle();
  app.startGigCreate();

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: buildEpTheme(),
        home: const Scaffold(body: GigCreateScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}
