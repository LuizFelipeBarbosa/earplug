import 'package:earplug/screens/settings.dart';
import 'package:earplug/services/appearance_controller.dart';
import 'package:earplug/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'support/harness.dart';

const _key = 'appearance.themeMode.v1';

void main() {
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  test(
    'loads persisted values and defaults missing or invalid values',
    () async {
      expect((await _loadWith({})).mode, ThemeMode.system);
      expect((await _loadWith({_key: 'light'})).mode, ThemeMode.light);
      expect((await _loadWith({_key: 'dark'})).mode, ThemeMode.dark);
      expect((await _loadWith({_key: 'sepia'})).mode, ThemeMode.system);
    },
  );

  test('unreadable preferences fall back to system mode', () async {
    SharedPreferencesAsyncPlatform.instance = _ReadFailingStore();

    final controller = await AppearanceController.load();

    expect(controller.mode, ThemeMode.system);
  });

  test('updates immediately and persists a successful selection', () async {
    final store = InMemorySharedPreferencesAsync.empty();
    SharedPreferencesAsyncPlatform.instance = store;
    final preferences = SharedPreferencesAsync();
    final controller = await AppearanceController.load(
      preferences: preferences,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);

    final saved = await controller.setMode(ThemeMode.light);

    expect(controller.mode, ThemeMode.light);
    expect(notifications, 1);
    expect(saved, isTrue);
    expect(await preferences.getString(_key), 'light');
  });

  test(
    'keeps an immediate session-only update when persistence fails',
    () async {
      SharedPreferencesAsyncPlatform.instance = _WriteFailingStore();
      final controller = await AppearanceController.load();
      var notifications = 0;
      controller.addListener(() => notifications++);

      final saving = controller.setMode(ThemeMode.dark);

      expect(controller.mode, ThemeMode.dark);
      expect(notifications, 1);
      expect(await saving, isFalse);
    },
  );

  testWidgets('system mode follows platform brightness', (tester) async {
    final controller = await _loadWith({});
    addTearDown(controller.dispose);
    Brightness? renderedBrightness;

    Future<void> pump() => tester.pumpWidget(
      MaterialApp(
        theme: buildEpTheme(Brightness.light),
        darkTheme: buildEpTheme(Brightness.dark),
        themeMode: controller.mode,
        home: Builder(
          builder: (context) {
            renderedBrightness = Theme.of(context).brightness;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pump();
    expect(renderedBrightness, Brightness.dark);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    tester.binding.handlePlatformBrightnessChanged();
    await tester.pumpAndSettle();
    expect(renderedBrightness, Brightness.light);
  });

  testWidgets('settings exposes and updates System, Light, and Dark modes', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: SettingsScreen()));
    final segmented = find.byKey(const Key('appearance-mode'));
    expect(segmented, findsOne);
    expect(find.text('SYSTEM'), findsOne);
    expect(find.text('LIGHT'), findsOne);
    expect(find.text('DARK'), findsOne);

    await tester.tap(find.text('LIGHT'));
    await tester.pumpAndSettle();

    final control = tester.widget<SegmentedButton<ThemeMode>>(segmented);
    expect(control.selected, {ThemeMode.light});
  });
}

Future<AppearanceController> _loadWith(Map<String, Object> values) {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(values);
  return AppearanceController.load();
}

base class _ReadFailingStore extends InMemorySharedPreferencesAsync {
  _ReadFailingStore() : super.empty();

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) =>
      Future.error(StateError('read failed'));
}

base class _WriteFailingStore extends InMemorySharedPreferencesAsync {
  _WriteFailingStore() : super.empty();

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) => Future.error(StateError('write failed'));
}
