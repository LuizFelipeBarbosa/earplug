import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/opportunity_edit.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

void main() {
  testWidgets('new draft saves explicitly, then opens and locks slots', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'new');
    final originalIds = (await repository.manageOpportunities(
      'org1',
    )).map((opportunity) => opportunity.id).toSet();
    expect(find.byType(StatusPill), findsNothing);
    expect(_action(tester, 'open').onPrimary, isNull);
    expect(
      find.descendant(
        of: find.byType(EpCard),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );

    await _enterText(tester, 'opp-edit-title', 'Basement Saturday');
    await _tap(tester, 'opp-edit-venue-v1');
    final date = _futureDate(30);
    await _pickDate(tester, 'opp-edit-date', date);
    await _pickDate(tester, 'opp-edit-deadline', _futureDate(20));
    await _tap(tester, 'opp-edit-slot-add');
    await _tap(tester, 'opp-edit-slot-0-role-support');
    await _enterText(tester, 'opp-edit-slot-0-guarantee', '150');
    await _enterText(tester, 'opp-edit-slot-0-length', '45');
    await _tap(tester, 'opp-edit-slot-0-required');
    await tester.pump(const Duration(seconds: 2));
    expect(
      (await repository.manageOpportunities(
        'org1',
      )).map((opportunity) => opportunity.id).toSet(),
      originalIds,
    );
    expect(_action(tester, 'open').onPrimary, isNull);

    await _tapAction(tester, 'save');
    final saved = (await repository.manageOpportunities(
      'org1',
    )).singleWhere((opportunity) => opportunity.title == 'Basement Saturday');
    expect(saved.status, OpportunityStatus.draft);
    expect(saved.venueId, 'v1');
    expect(saved.startsAt, DateTime(date.year, date.month, date.day, 21));
    expect(saved.doorsAt, DateTime(date.year, date.month, date.day, 20));
    expect(saved.slots.single.role, SlotRole.support);
    expect(saved.slots.single.guaranteeMinor, 15000);
    expect(saved.slots.single.setLengthMin, 45);
    expect(saved.slots.single.required, isTrue);
    expect(
      harness.app
          .opportunitiesFor('org1')
          .any((opportunity) => opportunity.id == saved.id),
      isTrue,
    );
    expect(_action(tester, 'open').onPrimary, isNotNull);

    // OPEN must persist edits made since the explicit save before transitioning.
    await _enterText(tester, 'opp-edit-title', 'Basement Saturday Live');
    await _tapAction(tester, 'open');
    final opened = (await repository.opportunity(saved.id))!;
    expect(opened.status, OpportunityStatus.open);
    expect(opened.title, 'Basement Saturday Live');
    await _reveal(
      tester,
      find.byKey(const ValueKey('opp-edit-slot-0-guarantee')),
    );
    expect(_field(tester, 'opp-edit-slot-0-guarantee').enabled, isFalse);
    expect(_field(tester, 'opp-edit-slot-0-length').enabled, isFalse);
    expect(
      tester
          .widget<EpChip>(
            find.byKey(const ValueKey('opp-edit-slot-0-role-support')),
          )
          .onTap,
      isNull,
    );
    expect(
      tester
          .widget<SwitchRow>(
            find.byKey(const ValueKey('opp-edit-slot-0-required')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('opp-edit-slot-0-remove')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('opp-edit-slot-add')),
          )
          .onPressed,
      isNull,
    );
    await _reveal(
      tester,
      find.text('Slots are locked once applications are open.'),
    );
    expect(
      find.text('Slots are locked once applications are open.'),
      findsOneWidget,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets('existing open opportunity is prefilled, saves and closes', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final fixture = (await repository.opportunity('opp1'))!;
    final harness = await _pumpEditor(tester, auth, repository, 'opp1');
    expect(_field(tester, 'opp-edit-title').controller!.text, fixture.title);
    final venue = tester.widget<EpChip>(
      find.byKey(const ValueKey('opp-edit-venue-v1')),
    );
    expect(venue.active, isTrue);
    expect(venue.onTap, isNull);
    await _reveal(tester, find.byKey(const ValueKey('opp-edit-desc')));
    expect(_field(tester, 'opp-edit-desc').controller!.text, fixture.desc);
    await _enterText(
      tester,
      'opp-edit-desc',
      'Updated backline and load-in details.',
    );
    await _tapAction(tester, 'save');
    final updated = (await repository.opportunity('opp1'))!;
    expect(updated.desc, 'Updated backline and load-in details.');
    expect(updated.slots.map((slot) => slot.id), [
      'opp1-headliner',
      'opp1-support',
    ]);
    await _tapAction(tester, 'close');
    expect(
      (await repository.opportunity('opp1'))!.status,
      OpportunityStatus.applicationsClosed,
    );
    expect(_action(tester, 'reopen').onPrimary, isNotNull);
    expect(
      harness.app
          .opportunitiesFor('org1')
          .singleWhere((opportunity) => opportunity.id == 'opp1')
          .status,
      OpportunityStatus.applicationsClosed,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets('delete draft removes it and navigates back', (tester) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp2');
    await _reveal(tester, find.byKey(const ValueKey('opp-edit-delete')));
    // DangerZone's caption makes its center fall outside the actual button.
    await tester.tap(find.widgetWithText(TextButton, 'DELETE DRAFT'));
    await tester.pumpAndSettle();
    expect(await repository.opportunity('opp2'), isNull);
    expect(harness.app.current.screen, Screen.orgDash);
    expect(harness.app.canGoBack, isFalse);
    expect(
      harness.app
          .opportunitiesFor('org1')
          .any((opportunity) => opportunity.id == 'opp2'),
      isFalse,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets('saved opportunities invite and remove bands immediately', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp1');
    final band = (await repository.band('b1'))!;
    await _invite(tester, band);
    final chipFinder = find.byKey(const ValueKey('opp-edit-invite-b1'));
    await _reveal(tester, chipFinder);
    expect(tester.widget<EpChip>(chipFinder).label, band.name);
    expect(
      (await repository.opportunity('opp1'))!.invitedBandIds,
      contains('b1'),
    );
    await _removeInvite(tester, 'b1');
    expect(
      (await repository.opportunity('opp1'))!.invitedBandIds,
      isNot(contains('b1')),
    );
    expect(chipFinder, findsNothing);
    await _disposeApp(tester, harness.app);
  });

  testWidgets(
    'revision conflict reloads the last saved fields and shows feedback',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _ConflictOnceRepository(auth: auth);
      final harness = await _pumpEditor(tester, auth, repository, 'opp1');
      await _enterText(tester, 'opp-edit-title', 'First saved title');
      await _tapAction(tester, 'save');
      expect(
        (await repository.opportunity('opp1'))!.title,
        'First saved title',
      );
      await _enterText(tester, 'opp-edit-title', 'Conflicting title');
      await _tapAction(tester, 'save');
      expect(find.byKey(const ValueKey('opp-edit-feedback')), findsOneWidget);
      expect(find.textContaining('changed elsewhere'), findsOneWidget);
      await _reveal(tester, find.byKey(const ValueKey('opp-edit-title')));
      expect(
        _field(tester, 'opp-edit-title').controller!.text,
        'First saved title',
      );
      await _enterText(tester, 'opp-edit-title', 'Recovered title');
      await _tapAction(tester, 'save');
      expect((await repository.opportunity('opp1'))!.title, 'Recovered title');
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets('unsaved invitations stay local and leaving creates no draft', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'new');
    final originalCount = (await repository.manageOpportunities('org1')).length;
    await _enterText(tester, 'opp-edit-title', 'Never saved');
    await _invite(tester, (await repository.band('b1'))!);
    await tester.pump(const Duration(seconds: 2));
    expect(
      (await repository.manageOpportunities('org1')).length,
      originalCount,
    );
    await _reveal(tester, find.byType(CircleIconButton));
    await tester.tap(find.byType(CircleIconButton));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.orgDash);
    expect(
      (await repository.manageOpportunities('org1')).length,
      originalCount,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets('save needs only core fields and flushes queued invites', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'new');
    final originalCount = (await repository.manageOpportunities('org1')).length;
    await _tapAction(tester, 'save');
    expect(find.text('Needs: title, venue, date'), findsOneWidget);
    expect(
      (await repository.manageOpportunities('org1')).length,
      originalCount,
    );
    await _enterText(tester, 'opp-edit-title', 'Minimal draft');
    await _tap(tester, 'opp-edit-venue-v1');
    await _pickDate(tester, 'opp-edit-date', _futureDate(30));
    // Saving is allowed even when the deadline would prevent opening.
    await _pickDate(tester, 'opp-edit-deadline', _futureDate(31));
    await _invite(tester, (await repository.band('b1'))!);
    await _invite(tester, (await repository.band('b2'))!);
    await _removeInvite(tester, 'b2');
    await _tapAction(tester, 'save');
    final saved = (await repository.manageOpportunities(
      'org1',
    )).singleWhere((opportunity) => opportunity.title == 'Minimal draft');
    expect(saved.status, OpportunityStatus.draft);
    expect(saved.invitedBandIds, ['b1']);
    expect(_action(tester, 'open').onPrimary, isNull);
    expect(
      find.text('Needs: at least one slot, deadline before start'),
      findsOneWidget,
    );
    await _disposeApp(tester, harness.app);
  });

  testWidgets(
    'closed applications validate and reopen with the chosen deadline',
    (tester) async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      await repository.closeOpportunityApplications('opp1');
      final harness = await _pumpEditor(tester, auth, repository, 'opp1');
      final fixture = (await repository.opportunity('opp1'))!;
      await _pickDate(
        tester,
        'opp-edit-deadline',
        fixture.startsAt.add(const Duration(days: 1)),
      );
      await _tapAction(tester, 'reopen');
      expect(find.text('Needs: deadline before start'), findsWidgets);
      expect(
        (await repository.opportunity('opp1'))!.status,
        OpportunityStatus.applicationsClosed,
      );
      final deadline = _futureDate(7);
      await _pickDate(tester, 'opp-edit-deadline', deadline);
      await _tapAction(tester, 'reopen');
      final reopened = (await repository.opportunity('opp1'))!;
      expect(reopened.status, OpportunityStatus.open);
      expect(reopened.applicationsCloseAt, deadline);
      // A later save uses the revision returned by the transition's reload.
      await _enterText(tester, 'opp-edit-title', 'Reopened show');
      await _tapAction(tester, 'save');
      expect((await repository.opportunity('opp1'))!.title, 'Reopened show');
      await _disposeApp(tester, harness.app);
    },
  );

  testWidgets('cancellation requires confirmation and navigates back', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    final harness = await _pumpEditor(tester, auth, repository, 'opp1');
    await _reveal(tester, find.byKey(const ValueKey('opp-edit-cancel')));
    await tester.tap(find.widgetWithText(TextButton, 'CANCEL OPPORTUNITY'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'KEEP'));
    await tester.pumpAndSettle();
    expect(
      (await repository.opportunity('opp1'))!.status,
      OpportunityStatus.open,
    );
    await tester.tap(find.widgetWithText(TextButton, 'CANCEL OPPORTUNITY'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'CONFIRM'));
    await tester.pumpAndSettle();
    expect(
      (await repository.opportunity('opp1'))!.status,
      OpportunityStatus.cancelled,
    );
    expect(harness.app.current.screen, Screen.orgDash);
    await _disposeApp(tester, harness.app);
  });

  testWidgets(
    'loaded invitations show band names and terminal fields are read only',
    (tester) async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      await repository.cancelOpportunity('opp3');
      final harness = await _pumpEditor(tester, auth, repository, 'opp3');
      expect(_field(tester, 'opp-edit-title').enabled, isFalse);
      expect(find.byType(StickyActionBar), findsNothing);
      final chipFinder = find.byKey(const ValueKey('opp-edit-invite-b1'));
      await _reveal(tester, chipFinder);
      final chip = tester.widget<EpChip>(chipFinder);
      expect(chip.label, (await repository.band('b1'))!.name);
      expect(chip.onRemoved, isNull);
      expect(find.byType(DangerZone), findsNothing);
      await _disposeApp(tester, harness.app);
    },
  );
}

Future<void> _disposeApp(WidgetTester tester, AppState app) async {
  // pumpApp's provider owns AppState. Unmount first so its disposal does not
  // happen after the test's explicit cleanup and raise a framework exception.
  await tester.pumpWidget(const SizedBox.shrink());
  try {
    app.dispose();
  } on FlutterError catch (error) {
    if (!error.message.contains('used after being disposed')) rethrow;
  }
}

Future<AppHarness> _pumpEditor(
  WidgetTester tester,
  FakeAuthService auth,
  DemoRepository repository,
  String id,
) async {
  final harness = await pumpApp(
    tester,
    auth: auth,
    repository: repository,
    home: _EditorHost(opportunityId: id),
  );
  await enterOrganizer(tester, harness, 'org1');
  harness.app.openOpportunityEditor(id);
  await tester.pumpAndSettle();
  return harness;
}

// Mount the screen only after enterOrganizer, and observe app.back() without
// relying on the navigation placeholders in main.dart.
class _EditorHost extends StatelessWidget {
  const _EditorHost({required this.opportunityId});

  final String opportunityId;

  @override
  Widget build(BuildContext context) {
    final screen = context.select<AppState, Screen>(
      (app) => app.current.screen,
    );
    return screen == Screen.opportunityEdit
        ? OpportunityEditScreen(opportunityId: opportunityId)
        : const Material(child: SizedBox());
  }
}

TextField _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key)));

StickyActionBar _action(WidgetTester tester, String action) =>
    tester.widget<StickyActionBar>(find.byKey(ValueKey('opp-edit-$action')));

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final list = find
      .descendant(
        of: find.byType(OpportunityEditScreen),
        matching: find.byType(ListView),
      )
      .first;
  tester.widget<ListView>(list).controller!.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first,
    maxScrolls: 50,
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapAction(WidgetTester tester, String action) async {
  await tester.tap(find.byKey(ValueKey('opp-edit-$action')));
  await tester.pumpAndSettle();
}

Future<void> _enterText(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await _reveal(tester, finder);
  await tester.enterText(finder, value);
  await tester.pumpAndSettle();
}

DateTime _futureDate(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + days);
}

Future<void> _pickDate(WidgetTester tester, String key, DateTime date) async {
  await _tap(tester, key);
  await tester.tap(find.byTooltip('Switch to input'));
  await tester.pumpAndSettle();
  final dialog = find.byType(DatePickerDialog);
  final localizations = MaterialLocalizations.of(tester.element(dialog));
  await tester.enterText(
    find.descendant(of: dialog, matching: find.byType(TextField)),
    localizations.formatCompactDate(date),
  );
  await tester.tap(find.widgetWithText(TextButton, 'OK'));
  await tester.pumpAndSettle();
}

Future<void> _invite(WidgetTester tester, Band band) async {
  await _tap(tester, 'opp-edit-invite-add');
  await tester.enterText(
    find.byKey(const ValueKey('opp-edit-invite-search')),
    band.name,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('opp-edit-invite-result-${band.id}')));
  await tester.pumpAndSettle();
}

Future<void> _removeInvite(WidgetTester tester, String bandId) async {
  final chip = find.byKey(ValueKey('opp-edit-invite-$bandId'));
  await _reveal(tester, chip);
  await tester.tap(
    find.descendant(of: chip, matching: find.byIcon(Icons.close)),
  );
  await tester.pumpAndSettle();
}

class _ConflictOnceRepository extends DemoRepository {
  _ConflictOnceRepository({required super.auth});

  int _updates = 0;

  @override
  Future<int> updateOpportunity({
    required String opportunityId,
    required int expectedRevision,
    String? title,
    String? desc,
    String? venueId,
    String? eventType,
    int? expectedAttendance,
    List<String>? genres,
    DateTime? startsAt,
    DateTime? doorsAt,
    DateTime? endsAt,
    AgeRequirement? ageRequirement,
    String? equipment,
    String? requirements,
    String? flyKey,
    String? flyStorageId,
    DateTime? applicationsCloseAt,
    OpportunityVisibility? visibility,
    OpportunityTicketing? ticketing,
    String? externalUrl,
    List<SlotInput>? slots,
  }) async {
    if (++_updates == 2) throw StateError('Opportunity changed elsewhere');
    return super.updateOpportunity(
      opportunityId: opportunityId,
      expectedRevision: expectedRevision,
      title: title,
      desc: desc,
      venueId: venueId,
      eventType: eventType,
      expectedAttendance: expectedAttendance,
      genres: genres,
      startsAt: startsAt,
      doorsAt: doorsAt,
      endsAt: endsAt,
      ageRequirement: ageRequirement,
      equipment: equipment,
      requirements: requirements,
      flyKey: flyKey,
      flyStorageId: flyStorageId,
      applicationsCloseAt: applicationsCloseAt,
      visibility: visibility,
      ticketing: ticketing,
      externalUrl: externalUrl,
      slots: slots,
    );
  }
}
