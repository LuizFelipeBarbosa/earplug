import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('validation opens the invalid section and focuses its field', (
    tester,
  ) async {
    final form = GlobalKey<EpFormState>();
    final name = TextEditingController();
    final focus = FocusNode();
    addTearDown(name.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEpTheme(),
        home: Scaffold(
          body: EpFormLayout(
            body: SingleChildScrollView(
              child: EpForm(
                key: form,
                child: EpDisclosure(
                  title: 'Profile',
                  summary: 'Add your name',
                  child: EpLabeledField(
                    label: 'Name',
                    hint: 'Your name',
                    controller: name,
                    focusNode: focus,
                    fieldKey: const Key('name'),
                    required: true,
                  ),
                ),
              ),
            ),
            footer: StickyActionBar(
              primaryLabel: 'Save',
              onPrimary: () => form.currentState!.validate(),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('name')), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter name.'), findsOneWidget);
    expect(focus.hasFocus, isTrue);
    await tester.enterText(find.byKey(const Key('name')), 'Jordan');
    await tester.pump();
    expect(find.text('Enter name.'), findsNothing);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(name.text, 'Jordan');
    expect(form.currentState!.validate(), isTrue);
  });

  testWidgets(
    'desktop Tab stays within the form before returning to navigation',
    (tester) async {
      await pumpApp(
        tester,
        home: const RootShell(),
        beforePump: (app) => app.startBandCreate(),
      );
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pumpAndSettle();
      final name = find.byKey(const ValueKey('create-band-name'));
      final area = find.byKey(const ValueKey('create-home-base'));
      await tester.tap(name);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final input = tester.widget<EditableText>(
        find.descendant(of: area, matching: find.byType(EditableText)),
      );
      expect(input.focusNode.hasFocus, isTrue);
    },
  );

  testWidgets(
    'search picker preserves cancelled selections and enforces its limit',
    (tester) async {
      var selected = <String>{'Punk'};
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEpTheme(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => EpSelectionField<String>(
                label: 'Genres',
                multiple: true,
                maxSelected: 2,
                options: const [
                  (value: 'Punk', label: 'Punk'),
                  (value: 'Noise', label: 'Noise'),
                  (value: 'Jazz', label: 'Jazz'),
                ],
                selected: selected,
                onChanged: (value) => update(() => selected = value),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Punk'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Noise'));
      await tester.pump();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Jazz'),
            )
            .onChanged,
        isNull,
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(selected, {'Punk'});
      await tester.tap(find.text('Punk'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'noi');
      await tester.pump();
      expect(find.widgetWithText(CheckboxListTile, 'Punk'), findsNothing);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Noise'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(selected, {'Punk', 'Noise'});
    },
  );

  for (final (size, scale) in [
    (const Size(390, 844), 1.0),
    (const Size(360, 800), 1.5),
    (const Size(1280, 900), 1.0),
  ]) {
    testWidgets(
      'host submit owns space above navigation and keyboard at $size/$scale',
      (tester) async {
        final auth = FakeAuthService();
        await auth.signInDemo();
        final repository = DemoRepository(auth: auth);
        final draft = await repository.saveOrganizationApplicationDraft(
          kind: ApplicationKind.host,
          orgType: OrganizationType.privateHost,
          orgName: 'Jordan Lee',
          contactName: 'Jordan Lee',
          businessEmail: 'jordan@example.com',
          phone: '415-555-0101',
          hostDisplayName: 'Jordan Lee',
          hostPhone: '415-555-0101',
          hostArea: 'San Francisco',
          hostAgreementAccepted: true,
        );
        await repository.attachApplicationDocument(
          applicationId: draft.applicationId,
          storageId: 'id-document',
        );
        await pumpApp(
          tester,
          auth: auth,
          repository: repository,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: const RootShell(),
            ),
          ),
          beforePump: (app) => app.openHostApply(),
        );
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        final continueButton = find.widgetWithText(FilledButton, 'Continue');
        expect(continueButton.hitTestable(), findsOneWidget);
        await tester.tap(continueButton);
        await tester.pumpAndSettle();
        expect(
          (await repository.myOrganizationApplication())!.status,
          OrganizationApplicationStatus.draft,
        );
        final submit = find.widgetWithText(FilledButton, 'Submit application');
        expect(submit.hitTestable(), findsOneWidget);
        if (size.width < 960) {
          final navTop = tester.getTopLeft(find.byType(FanTabBar)).dy;
          expect(tester.getBottomLeft(submit).dy, lessThan(navTop));
        }
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        expect(submit.hitTestable(), findsOneWidget);
        expect(
          tester.getBottomLeft(submit).dy,
          lessThanOrEqualTo(size.height - 280),
        );
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(
          (await repository.myOrganizationApplication())!.status,
          OrganizationApplicationStatus.submitted,
        );
      },
    );
  }
}
