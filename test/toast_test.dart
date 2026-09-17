import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/main.dart';
import 'package:earplug/services/appearance_controller.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('toast sits just above the mobile tab bar', (tester) async {
    const viewport = Size(402, 900);
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final appearance = await AppearanceController.load();
    addTearDown(appearance.dispose);

    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    app.setMapMode(false);

    await tester.pumpWidget(
      EarplugApp(
        appearance: appearance,
        repository: repository,
        auth: auth,
        appState: app,
      ),
    );
    await tester.pumpAndSettle();
    expect(app.dataStatus, DataStatus.ready);
    expect(app.identity, isA<PersonalIdentity>());

    app.say('Showing gigs near your current location.');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    const message = 'Showing gigs near your current location.';
    expect(find.text(message), findsOneWidget);
    final toast = tester.getRect(find.byKey(const ValueKey('toast')));
    final expectedBottom = viewport.height - (EpLayout.tabBarHeight + 12);
    expect((toast.bottom - expectedBottom).abs(), lessThanOrEqualTo(1));
    expect(toast.center.dy, greaterThan(viewport.height * 0.75));
  });
}
