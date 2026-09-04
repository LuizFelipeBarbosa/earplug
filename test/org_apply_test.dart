import 'dart:typed_data';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/org_application_status.dart';
import 'package:earplug/screens/org_apply.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_picker.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

void main() {
  testWidgets('full organizer application autosaves and submits', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final picker = FakeMediaPicker();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: _ApplicationHost(mediaPicker: picker),
      beforePump: (app) => app.go(Screen.orgApply),
    );
    addTearDown(() => _disposeApp(harness.app));

    await tester.enterText(
      find.byKey(const ValueKey('org-apply-name')),
      'Night Heron Club',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    final autosaved = await repository.myOrganizationApplication();
    expect(autosaved?.status, OrganizationApplicationStatus.draft);
    expect(autosaved?.orgName, 'Night Heron Club');
    expect(find.text('Draft saved'), findsOne);

    await tester.tap(find.byKey(const ValueKey('org-apply-kind-bar')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('org-apply-venue-name')))
          .controller
          ?.text,
      'Night Heron Club',
    );

    await tester.enterText(
      find.byKey(const ValueKey('org-apply-venue-address')),
      '22 V',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey('org-apply-venue-suggestion-0')),
    );
    await tester.pumpAndSettle();

    await _enterText(
      tester,
      const ValueKey('org-apply-contact-name'),
      'Rae Booker',
    );
    await _enterText(
      tester,
      const ValueKey('org-apply-email'),
      'rae@nightheron.example',
    );

    picker.nextPhoto = _licensePhoto;
    await _scrollDownToKey(tester, const ValueKey('org-apply-doc-add'));
    await tester.tap(find.byKey(const ValueKey('org-apply-doc-add')));
    await tester.pumpAndSettle();

    await _scrollDownToKey(tester, const ValueKey('org-apply-agree'));
    await tester.tap(find.byKey(const ValueKey('org-apply-agree')));
    await tester.pumpAndSettle();

    final actionBar = tester.widget<StickyActionBar>(
      find.byKey(const ValueKey('org-apply-submit')),
    );
    expect(actionBar.onPrimary, isNotNull);

    await tester.tap(find.byKey(const ValueKey('org-apply-submit')));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.orgApplicationStatus);
    expect(
      (await repository.myOrganizationApplication())?.status,
      OrganizationApplicationStatus.submitted,
    );
    expect(find.text('Submitted'), findsOneWidget);
  });

  testWidgets('draft application reopens in the editor from the switcher', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    late AppState appUnderTest;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: _NonOwningAppHost(
        app: () => appUnderTest,
        child: const RootShell(),
      ),
      beforePump: (app) {
        appUnderTest = app;
        app.go(Screen.orgApply);
      },
    );

    await tester.enterText(
      find.byKey(const ValueKey('org-apply-name')),
      'Night Heron Club',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();

    harness.app.toFanView();
    await tester.pumpAndSettle();

    await tester.tap(find.text('SWITCH'));
    await tester.pumpAndSettle();
    expect(find.text('CONTINUE ORGANIZER APPLICATION'), findsOneWidget);

    await tester.tap(find.byKey(const Key('switcher-become-organizer')));
    await tester.pumpAndSettle();

    final nameField = find.byKey(const ValueKey('org-apply-name'));
    expect(nameField, findsOneWidget);
    expect(
      tester.widget<TextField>(nameField).controller?.text,
      'Night Heron Club',
    );
    expect(find.byKey(const Key('org-status-timeline')), findsNothing);

    harness.app.dispose();
  });

  testWidgets(
    'submit reports individual missing requirements and stays disabled',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      final picker = FakeMediaPicker();
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: OrgApplyScreen(mediaPicker: picker),
      );
      addTearDown(() => _disposeApp(harness.app));

      expect(
        tester
            .widget<StickyActionBar>(
              find.byKey(const ValueKey('org-apply-submit')),
            )
            .onPrimary,
        isNull,
      );
      expect(
        find.ancestor(
          of: find.byType(TextField),
          matching: find.byType(EpCard),
        ),
        findsNothing,
      );

      picker.nextPhoto = _licensePhoto;
      await _completeApplication(tester, picker: picker);
      await _scrollDownToKey(tester, const ValueKey('org-apply-missing'));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('org-apply-missing')))
            .data,
        contains('agreement checkbox'),
      );
      expect(
        tester
            .widget<StickyActionBar>(
              find.byKey(const ValueKey('org-apply-submit')),
            )
            .onPrimary,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('org-apply-agree')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StickyActionBar>(
              find.byKey(const ValueKey('org-apply-submit')),
            )
            .onPrimary,
        isNotNull,
      );

      final document =
          (await repository.myOrganizationApplication())!.documents.single;
      final removeKey = ValueKey('org-apply-doc-remove-${document.storageId}');
      await _scrollUpToKey(tester, removeKey);
      await tester.tap(find.byKey(removeKey));
      await tester.pumpAndSettle();
      await _scrollDownToKey(tester, const ValueKey('org-apply-missing'));

      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('org-apply-missing')))
            .data,
        contains('at least one document'),
      );
      expect(
        tester
            .widget<StickyActionBar>(
              find.byKey(const ValueKey('org-apply-submit')),
            )
            .onPrimary,
        isNull,
      );
    },
  );

  testWidgets('draft validation failure keeps typed organization edits', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _FailOnceRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const OrgApplyScreen(),
    );
    addTearDown(() => _disposeApp(harness.app));

    await tester.enterText(
      find.byKey(const ValueKey('org-apply-name')),
      'Night Heron Club',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await _scrollDownToKey(tester, const ValueKey('org-apply-feedback'));

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('org-apply-feedback')))
          .data,
      'Contact name is required',
    );
    await _scrollUpToKey(tester, const ValueKey('org-apply-name'));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('org-apply-name')))
          .controller
          ?.text,
      'Night Heron Club',
    );
  });

  testWidgets('needs info draft prefills fields and venue kind', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final saved = await repository.saveOrganizationApplicationDraft(
      orgName: 'Night Heron Club',
      orgType: OrganizationType.venueOperator,
      website: 'https://nightheron.example',
      contactName: 'Rae Booker',
      businessEmail: 'rae@nightheron.example',
      phone: '415-555-0101',
      venue: const ApplicationVenueDraft(
        name: 'Night Heron Club',
        addr: '22 Valencia Street',
        point: LatLng(37.76, -122.42),
        area: 'Mission',
        capacity: 180,
        venueType: VenueType.club,
      ),
    );
    final documentRevision = await repository.attachApplicationDocument(
      applicationId: saved.applicationId,
      storageId: 'license-document',
    );
    await repository.submitOrganizationApplication(
      applicationId: saved.applicationId,
      expectedRevision: documentRevision,
    );
    repository.platformAdmin = true;
    await repository.decideOrganizationApplication(
      applicationId: saved.applicationId,
      decision: ApplicationDecision.needsInfo,
      note: 'Add a photo of your liquor license.',
    );

    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const OrgApplyScreen(),
    );
    addTearDown(() => _disposeApp(harness.app));

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('org-apply-name')))
          .controller
          ?.text,
      'Night Heron Club',
    );
    expect(
      tester
          .widget<EpChip>(find.byKey(const ValueKey('org-apply-kind-bar')))
          .active,
      isFalse,
    );
    expect(
      tester
          .widget<EpChip>(find.byKey(const ValueKey('org-apply-kind-club')))
          .active,
      isTrue,
    );

    await _scrollDownToKey(tester, const ValueKey('org-apply-website'));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('org-apply-website')))
          .controller
          ?.text,
      'https://nightheron.example',
    );
  });
}

class _NonOwningAppHost extends StatelessWidget {
  const _NonOwningAppHost({required this.app, required this.child});

  final AppState Function() app;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider<AppState>.value(value: app(), child: child);
}

final _licensePhoto = PickedMedia(
  bytes: Uint8List.fromList([1, 2, 3]),
  filename: 'license.jpg',
  contentType: 'image/jpeg',
  sizeBytes: 3,
);

void _disposeApp(AppState app) {
  try {
    app.dispose();
  } on FlutterError catch (error) {
    if (!error.message.contains('used after being disposed')) rethrow;
  }
}

class _ApplicationHost extends StatelessWidget {
  const _ApplicationHost({required this.mediaPicker});

  final MediaPicker mediaPicker;

  @override
  Widget build(BuildContext context) {
    final screen = context.select<AppState, Screen>(
      (app) => app.current.screen,
    );
    return switch (screen) {
      Screen.orgApplicationStatus => const OrgApplicationStatusScreen(),
      _ => OrgApplyScreen(mediaPicker: mediaPicker),
    };
  }
}

class _FailOnceRepository extends DemoRepository {
  _FailOnceRepository({required super.auth});

  bool _shouldFail = true;

  @override
  Future<({String applicationId, int revision})>
  saveOrganizationApplicationDraft({
    String? applicationId,
    int? expectedRevision,
    required String orgName,
    required OrganizationType orgType,
    String? website,
    required String contactName,
    required String businessEmail,
    String? phone,
    ApplicationVenueDraft? venue,
  }) {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('Contact name is required');
    }
    return super.saveOrganizationApplicationDraft(
      applicationId: applicationId,
      expectedRevision: expectedRevision,
      orgName: orgName,
      orgType: orgType,
      website: website,
      contactName: contactName,
      businessEmail: businessEmail,
      phone: phone,
      venue: venue,
    );
  }
}

Future<void> _completeApplication(
  WidgetTester tester, {
  required FakeMediaPicker picker,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('org-apply-name')),
    'Night Heron Club',
  );
  await tester.tap(find.byKey(const ValueKey('org-apply-kind-bar')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('org-apply-venue-address')),
    '22 V',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(const ValueKey('org-apply-venue-suggestion-0')));
  await tester.pumpAndSettle();
  await _enterText(
    tester,
    const ValueKey('org-apply-contact-name'),
    'Rae Booker',
  );
  await _enterText(
    tester,
    const ValueKey('org-apply-email'),
    'rae@nightheron.example',
  );
  picker.nextPhoto = _licensePhoto;
  await _scrollDownToKey(tester, const ValueKey('org-apply-doc-add'));
  await tester.tap(find.byKey(const ValueKey('org-apply-doc-add')));
  await tester.pumpAndSettle();
  await _scrollDownToKey(tester, const ValueKey('org-apply-agree'));
}

Future<void> _enterText(
  WidgetTester tester,
  ValueKey<String> key,
  String text,
) async {
  await _scrollDownToKey(tester, key);
  await tester.enterText(find.byKey(key), text);
  await tester.pump();
}

Future<void> _scrollDownToKey(WidgetTester tester, ValueKey<String> key) =>
    _scrollToKey(tester, key, const Offset(0, -500));

Future<void> _scrollUpToKey(WidgetTester tester, ValueKey<String> key) =>
    _scrollToKey(tester, key, const Offset(0, 500));

Future<void> _scrollToKey(
  WidgetTester tester,
  ValueKey<String> key,
  Offset dragOffset,
) async {
  final target = find.byKey(key);
  for (var attempt = 0; attempt < 12 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(Scrollable).first, dragOffset);
    await tester.pump();
  }
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pump();
}
