import 'dart:io';
import 'dart:ui' as ui;

import 'package:earplug/app_state.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/design_rules.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';
import 'support/ui_test_helpers.dart';

/// Every app route is exercised with real demo state. Set EP_DESIGN_CAPTURE to
/// a directory to export the rendered pages for visual review.
void main() {
  final capture = Platform.environment['EP_DESIGN_CAPTURE'];
  final captureView = Platform.environment['EP_DESIGN_VIEW'];
  const views = [
    (
      name: 'mobile-dark',
      size: Size(390, 844),
      brightness: Brightness.dark,
      scale: 1.0,
    ),
    (
      name: 'mobile-light',
      size: Size(390, 844),
      brightness: Brightness.light,
      scale: 1.0,
    ),
    (
      name: 'desktop',
      size: Size(1280, 900),
      brightness: Brightness.light,
      scale: 1.0,
    ),
    (
      name: 'large-text',
      size: Size(360, 800),
      brightness: Brightness.dark,
      scale: 1.5,
    ),
  ];

  setUpAll(() async {
    for (final (family, path) in [
      ('Archivo', 'assets/fonts/Archivo-Regular.ttf'),
      ('Archivo Black', 'assets/fonts/ArchivoBlack-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(family)..addFont(rootBundle.load(path));
      await loader.load();
    }
  });

  for (final view in views) {
    if (captureView != null && view.name != captureView) continue;
    for (final screen in Screen.values) {
      testWidgets('${view.name}: ${screen.name} has a usable layout', (
        tester,
      ) async {
        final auth = FakeAuthService();
        if (screen != Screen.auth) await auth.signInDemo();
        final repository = StubRepository(auth: auth)
          ..platformAdmin = true
          ..returns(
            'myOrganizationApplication',
            screen == Screen.orgApplicationStatus
                ? DemoData.submittedOrganizationApplication
                : null,
          )
          ..returns(
            'checkoutStatus',
            const CheckoutStatus(
              bookingId: 'bk1',
              paymentStatus: PaymentRecordStatus.paid,
              bookingStatus: BookingStatus.confirmed,
            ),
          );
        final boundaryKey = GlobalKey();
        final harness = await pumpApp(
          tester,
          auth: auth,
          repository: repository,
          home: Theme(
            data: buildEpTheme(view.brightness),
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(view.scale)),
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: const RootShell(),
                ),
              ),
            ),
          ),
        );
        tester.view.physicalSize = view.size;
        final app = harness.app;
        if (organizerTabScreens.contains(screen) || screen == Screen.orgJoin) {
          app.switchToOrganization('org1');
        } else if (bandTabScreens.contains(screen) ||
            screen == Screen.bandMedia ||
            screen == Screen.gigCreate) {
          app.switchToBand('b1');
        }
        app.setMapMode(false);
        if ({
          Screen.myTickets,
          Screen.ticket,
          Screen.ticketCheckoutReturn,
          Screen.ticketCheckoutCancel,
        }.contains(screen)) {
          app.hostedUrlLauncher = (_) async {};
          final reservation = await app.reserveTickets('g8', 1);
          final sessionId = await app.startTicketCheckout(reservation.orderId);
          if (screen != Screen.ticketCheckoutCancel) {
            await repository.simulateTicketCheckoutCompleted(sessionId);
            await app.loadMyTickets();
          }
          switch (screen) {
            case Screen.ticket:
              app.openTicket(app.myTickets.single.id);
            case Screen.ticketCheckoutReturn:
              app.go(screen, sessionId);
            case Screen.ticketCheckoutCancel:
              app.go(screen, reservation.orderId);
            default:
              app.go(screen);
          }
        } else {
          switch (screen) {
            case Screen.gigCreate:
              app.startGigCreate();
            case Screen.band || Screen.bandPreview || Screen.bandMedia:
              app.go(screen, 'b1');
            case Screen.gig:
              app.openGig('g1');
            case Screen.venue || Screen.orgVenueEdit:
              app.go(screen, 'v1');
            case Screen.opportunityDetail || Screen.opportunityApplicants:
              app.go(screen, 'opp1');
            case Screen.opportunityEdit:
              app.go(screen, 'opp2');
            case Screen.bookingDetail || Screen.checkoutCancel:
              app.go(screen, 'bk1');
            case Screen.reviewCompose:
              app.go(screen, 'bk4');
            case Screen.checkoutReturn:
              app.go(screen, 'design-preview');
            case Screen.stripeReturn:
              app.go(screen, 'invalid');
            case Screen.adminApplication:
              app.go(screen, 'application-review-1');
            case Screen.orgJoin:
              app.go(screen, 'design-preview');
            default:
              app.go(screen);
          }
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: screen.name);
        expectNoFieldInCard(tester);
        if (capture != null) {
          await _capture(
            tester,
            boundaryKey,
            '$capture/${view.name}/${screen.name}.png',
          );
        }
        final scrollables = find.descendant(
          of: find.byType(Scaffold).first,
          matching: find.byType(Scrollable),
        );
        final vertical = tester
            .stateList<ScrollableState>(scrollables)
            .where((state) => state.position.axis == Axis.vertical);
        if (vertical.isNotEmpty) {
          final position = vertical.first.position;
          // Advance through lazy lists so intermediate form sections and rows
          // are laid out, rather than only testing the initial viewport.
          for (var step = 0; step < 16 && position.extentAfter > 0; step++) {
            position.jumpTo(
              (position.pixels + view.size.height * .7).clamp(
                position.minScrollExtent,
                position.maxScrollExtent,
              ),
            );
            await tester.pumpAndSettle();
            final failure = tester.takeException();
            if (failure != null && capture != null) {
              await _capture(
                tester,
                boundaryKey,
                '$capture/${view.name}/${screen.name}-overflow.png',
              );
            }
            expect(failure, isNull, reason: '${screen.name}, scroll $step');
          }
          expectNoFieldInCard(tester);
          if (capture != null) {
            await _capture(
              tester,
              boundaryKey,
              '$capture/${view.name}/${screen.name}-bottom.png',
            );
          }
        }
        await openAllFormSections(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: '${screen.name}, expanded sections',
        );
        final inputs = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.enabled != false &&
              !widget.readOnly,
        );
        if (inputs.evaluate().isNotEmpty) {
          await tester.ensureVisible(inputs.first);
          await tester.tap(inputs.first);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.name}, keyboard open',
          );
          for (final footer in find.byType(StickyActionBar).evaluate()) {
            final bounds = tester.getRect(find.byWidget(footer.widget));
            expect(
              bounds.bottom,
              lessThanOrEqualTo(view.size.height - 280),
              reason: '${screen.name}, footer above keyboard',
            );
          }
          if (capture != null) {
            await _capture(
              tester,
              boundaryKey,
              '$capture/${view.name}/${screen.name}-keyboard.png',
            );
          }
          tester.view.viewInsets = const FakeViewPadding();
        }
        if (screen == Screen.gigCreate || screen == Screen.opportunityEdit) {
          await _auditCreationSteps(
            tester,
            app,
            screen,
            view.size,
            boundaryKey,
            capture == null ? null : '$capture/${view.name}',
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String path) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _auditCreationSteps(
  WidgetTester tester,
  AppState app,
  Screen screen,
  Size size,
  GlobalKey boundary,
  String? capture,
) async {
  tester.view.viewInsets = const FakeViewPadding();
  FocusManager.instance.primaryFocus?.unfocus();
  final originalCount = screen == Screen.opportunityEdit
      ? (await app.repository.manageOpportunities(app.organizationId)).length
      : null;
  if (screen == Screen.gigCreate) {
    app.setGfName('Form audit gig');
    app.setGfVenue('v1');
    app.setGfDate(DateTime.now().add(const Duration(days: 30)));
  } else {
    app.openOpportunityEditor('new');
  }
  await tester.pumpAndSettle();
  final count = screen == Screen.gigCreate ? 4 : 5;
  for (var step = 0; step < count; step++) {
    if (screen == Screen.opportunityEdit && step == 0) {
      await tester.enterText(
        find.byKey(const Key('opp-edit-title')),
        'Form audit opportunity',
      );
      await chooseFormSelection(
        tester,
        'Venue',
        'The Foghorn Club · Mission, San Francisco',
      );
      final date = find.byKey(const Key('opp-edit-date'));
      await tester.ensureVisible(date);
      await tester.tap(date);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();
    } else if (screen == Screen.opportunityEdit && step == 1) {
      await tester.tap(find.byKey(const Key('opp-edit-slot-add')));
      await tester.pumpAndSettle();
    }
    expect(tester.widget<EpFormSteps>(find.byType(EpFormSteps)).current, step);
    await openAllFormSections(tester);
    expectNoFieldInCard(tester);
    expect(
      tester.takeException(),
      isNull,
      reason: '${screen.name}, step $step',
    );
    if (capture != null) {
      await _capture(
        tester,
        boundary,
        '$capture/${screen.name}-step-$step.png',
      );
    }
    // Intermediate controls and the primary action must coexist with the keyboard.
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    final bar = find.byType(StickyActionBar).last;
    expect(tester.getRect(bar).bottom, lessThanOrEqualTo(size.height - 280));
    expect(
      tester.takeException(),
      isNull,
      reason: '${screen.name}, step $step keyboard',
    );
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    if (step < count - 1) {
      final next = find.widgetWithText(FilledButton, 'Continue');
      expect(next.hitTestable(), findsOneWidget);
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
  }
  if (screen == Screen.gigCreate) {
    expect(app.gfPublished, isFalse);
    expect(app.gfName, 'Form audit gig');
  } else {
    expect(
      (await app.repository.manageOpportunities(app.organizationId)).length,
      originalCount,
    );
  }
}
