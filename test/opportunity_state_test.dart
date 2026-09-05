import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('browse includes only open public opportunities', (tester) async {
    final harness = await pumpApp(tester, home: const SizedBox.shrink());
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    await harness.app.refreshBrowse();

    expect(harness.app.browse.status, DataStatus.ready);
    expect(harness.app.browse.items.map((item) => item.opportunity.id), [
      'opp1',
    ]);
    harness.app.dispose();
  });

  testWidgets('band browse includes invitations and application status', (
    tester,
  ) async {
    final harness = await pumpApp(tester, home: const SizedBox.shrink());
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();

    harness.app.switchToBand('b1');
    await tester.pumpAndSettle();
    // Switching bands refreshes applications through the navigation hook.
    expect(harness.app.myApplications.map((item) => item.application.id), [
      'app1',
    ]);
    await harness.app.refreshBrowse();

    expect(
      harness.app.browse.invited.map((item) => item.opportunity.id),
      contains('opp3'),
    );
    expect(
      harness.app.browse.items.single.myApplicationStatus,
      ArtistApplicationStatus.submitted,
    );
    harness.app.dispose();
  });

  testWidgets('a completed browse page does not load more opportunities', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledOpportunityRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.app.refreshBrowse();
    expect(harness.app.browse.isDone, isTrue);
    final items = harness.app.browse.items;
    final calls = repository.browseCalls;

    await harness.app.loadMoreOpportunities();

    expect(harness.app.browse.items, hasLength(items.length));
    expect(harness.app.browse.items, same(items));
    expect(repository.browseCalls, calls);
    harness.app.dispose();
  });

  testWidgets('refresh browse skips empty pages until it finds items', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledOpportunityRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    final item = (await repository.resolveOpportunity('opp1'))!;
    repository.browsePages = [
      const OpportunityPage(items: [], continueCursor: 'c1', isDone: false),
      const OpportunityPage(items: [], continueCursor: 'c2', isDone: false),
      OpportunityPage(items: [item], continueCursor: 'c3', isDone: true),
    ];
    var notifications = 0;
    harness.app.addListener(() => notifications++);

    await harness.app.refreshBrowse();

    expect(harness.app.browse.items, [item]);
    expect(harness.app.browse.isDone, isTrue);
    expect(harness.app.browse.cursor, 'c3');
    expect(harness.app.browse.status, DataStatus.ready);
    expect(repository.browseCalls, 3);
    expect(repository.browseRequests.map((request) => request.cursor), [
      null,
      'c1',
      'c2',
    ]);
    expect(notifications, 1);
    harness.app.dispose();
  });

  testWidgets('empty browse chains stop after five fetches per action', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledOpportunityRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    repository.browsePages = [
      for (var i = 1; i <= 11; i++)
        OpportunityPage(items: const [], continueCursor: 'c$i', isDone: false),
    ];
    var notifications = 0;
    harness.app.addListener(() => notifications++);

    await harness.app.refreshBrowse();

    expect(repository.browseCalls, 5);
    expect(harness.app.browse.items, isEmpty);
    expect(harness.app.browse.cursor, 'c5');
    expect(harness.app.browse.isDone, isFalse);
    expect(harness.app.browse.status, DataStatus.ready);
    expect(notifications, 1);

    await harness.app.loadMoreOpportunities();

    expect(repository.browseCalls, 10);
    expect(repository.browseRequests.map((request) => request.cursor), [
      null,
      for (var i = 1; i < 10; i++) 'c$i',
    ]);
    expect(harness.app.browse.items, isEmpty);
    expect(harness.app.browse.cursor, 'c10');
    expect(harness.app.browse.isDone, isFalse);
    expect(notifications, 2);
    harness.app.dispose();
  });

  testWidgets('load more skips empty pages even with existing browse items', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledOpportunityRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    final existingItem = (await repository.resolveOpportunity('opp1'))!;
    final newItem = (await repository.resolveOpportunity(
      'opp3',
      bandId: 'b1',
    ))!;
    final invited = [newItem];
    harness.app.browse = OpportunityBrowseState(
      items: [existingItem],
      invited: invited,
      cursor: 'start',
      status: DataStatus.ready,
    );
    repository.browsePages = [
      const OpportunityPage(items: [], continueCursor: 'c1', isDone: false),
      const OpportunityPage(items: [], continueCursor: 'c2', isDone: false),
      OpportunityPage(items: [newItem], continueCursor: 'c3', isDone: false),
    ];
    var notifications = 0;
    harness.app.addListener(() => notifications++);

    await harness.app.loadMoreOpportunities();

    expect(harness.app.browse.items, [existingItem, newItem]);
    expect(harness.app.browse.invited, same(invited));
    expect(harness.app.browse.cursor, 'c3');
    expect(harness.app.browse.isDone, isFalse);
    expect(harness.app.browse.status, DataStatus.ready);
    expect(repository.browseCalls, 3);
    expect(repository.browseRequests.map((request) => request.cursor), [
      'start',
      'c1',
      'c2',
    ]);
    expect(repository.invitedCalls, 0);
    expect(notifications, 1);
    harness.app.dispose();
  });

  testWidgets('browse stays connecting until pages and invitations finish', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledOpportunityRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    harness.app.switchToBand('b1');
    await tester.pumpAndSettle();
    final item = harness.app.browse.items.single;
    final invited = harness.app.browse.invited;
    final browseCalls = repository.browseCalls;
    final invitedCalls = repository.invitedCalls;
    final pendingPage = Completer<OpportunityPage>();
    final pendingInvited = Completer<List<BrowseItem>>();
    repository.browsePages = [
      const OpportunityPage(items: [], continueCursor: 'c1', isDone: false),
      pendingPage.future,
    ];
    repository.pendingInvited = pendingInvited;
    const filters = OpportunityFilters(genre: 'rock');
    var notifications = 0;
    harness.app.addListener(() => notifications++);

    harness.app.setBrowseFilters(filters);
    final connectingBrowse = harness.app.browse;
    await tester.pump();

    expect(repository.browseCalls, browseCalls + 2);
    expect(repository.invitedCalls, invitedCalls);
    expect(harness.app.browse, same(connectingBrowse));
    expect(harness.app.browse.status, DataStatus.connecting);
    expect(notifications, 1); // The filter change, with no intermediate pages.
    for (final request in repository.browseRequests.skip(browseCalls)) {
      expect(request.bandId, 'b1');
      expect(request.filters, same(filters));
    }

    pendingPage.complete(
      OpportunityPage(items: [item], continueCursor: null, isDone: true),
    );
    await tester.pump();

    expect(repository.invitedCalls, invitedCalls + 1);
    expect(harness.app.browse, same(connectingBrowse));
    expect(notifications, 1);

    pendingInvited.complete(invited);
    await tester.pump();

    expect(harness.app.browse.status, DataStatus.ready);
    expect(harness.app.browse.items, [item]);
    expect(harness.app.browse.invited, same(invited));
    expect(notifications, 2);
    harness.app.dispose();
  });

  for (final stalePageIsEmpty in [true, false]) {
    testWidgets(
      'filter changes discard stale ${stalePageIsEmpty ? 'empty' : 'nonempty'} '
      'pages mid-chain',
      (tester) async {
        final auth = FakeAuthService();
        final repository = _ControlledOpportunityRepository(auth: auth);
        final harness = await pumpApp(
          tester,
          auth: auth,
          repository: repository,
          home: const SizedBox.shrink(),
        );
        final staleItem = (await repository.resolveOpportunity('opp1'))!;
        final newItem = (await repository.resolveOpportunity(
          'opp3',
          bandId: 'b1',
        ))!;
        final stalePage = Completer<OpportunityPage>();
        final newPage = Completer<OpportunityPage>();
        repository.browsePages = [
          const OpportunityPage(items: [], continueCursor: 'c1', isDone: false),
          stalePage.future,
          newPage.future,
        ];
        var notifications = 0;
        harness.app.addListener(() => notifications++);
        final loading = harness.app.refreshBrowse();
        await tester.pump();
        expect(repository.browseCalls, 2);
        expect(notifications, 0);

        const newFilters = OpportunityFilters(genre: 'jazz');
        harness.app.setBrowseFilters(newFilters);
        newPage.complete(
          OpportunityPage(
            items: [newItem],
            continueCursor: 'new',
            isDone: true,
          ),
        );
        await tester.pump();
        final newBrowse = harness.app.browse;
        expect(newBrowse.items, [newItem]);
        expect(newBrowse.status, DataStatus.ready);
        expect(notifications, 2);

        stalePage.complete(
          OpportunityPage(
            items: stalePageIsEmpty ? [] : [staleItem],
            continueCursor: 'stale',
            isDone: false,
          ),
        );
        await loading;

        expect(harness.app.browse, same(newBrowse));
        expect(harness.app.browse.cursor, 'new');
        expect(harness.app.browse.isDone, isTrue);
        expect(repository.browseCalls, 3);
        expect(repository.browseRequests.map((request) => request.cursor), [
          null,
          'c1',
          null,
        ]);
        expect(repository.browseRequests.last.filters, same(newFilters));
        expect(notifications, 2);
        harness.app.dispose();
      },
    );
  }

  for (final loadMore in [false, true]) {
    testWidgets(
      '${loadMore ? 'load more' : 'refresh'} preserves browse values when a '
      'later page fails',
      (tester) async {
        final auth = FakeAuthService();
        final repository = _ControlledOpportunityRepository(auth: auth);
        final harness = await pumpApp(
          tester,
          auth: auth,
          repository: repository,
          home: const SizedBox.shrink(),
        );
        final item = (await repository.resolveOpportunity('opp1'))!;
        final previousBrowse = OpportunityBrowseState(
          items: [item],
          invited: [item],
          cursor: 'previous',
          status: DataStatus.ready,
        );
        harness.app.browse = previousBrowse;
        final pendingPage = Completer<OpportunityPage>();
        repository.browsePages = [
          const OpportunityPage(items: [], continueCursor: 'c1', isDone: false),
          pendingPage.future,
        ];
        var notifications = 0;
        harness.app.addListener(() => notifications++);
        final loading = loadMore
            ? harness.app.loadMoreOpportunities()
            : harness.app.refreshBrowse();
        await tester.pump();
        expect(harness.app.browse, same(previousBrowse));
        expect(notifications, 0);

        pendingPage.completeError(StateError('later page failed'));
        await loading;

        expect(harness.app.browse.status, DataStatus.error);
        expect(harness.app.browse.error, contains('later page failed'));
        expect(harness.app.browse.items, same(previousBrowse.items));
        expect(harness.app.browse.invited, same(previousBrowse.invited));
        expect(harness.app.browse.cursor, previousBrowse.cursor);
        expect(harness.app.browse.isDone, previousBrowse.isDone);
        expect(repository.browseCalls, 2);
        expect(notifications, 1);
        harness.app.dispose();
      },
    );
  }

  testWidgets('organizer opportunities include drafts first', (tester) async {
    final harness = await pumpApp(tester, home: const SizedBox.shrink());

    await harness.app.refreshOpportunities('org1');

    // All three fixtures belong to org1, including invite-only opp3.
    final opportunities = harness.app.opportunitiesFor('org1');
    expect(opportunities.map((opportunity) => opportunity.id), [
      'opp2',
      'opp1',
      'opp3',
    ]);
    expect(opportunities.first.status, OpportunityStatus.draft);
    expect(harness.app.opportunitiesStatus('org1'), DataStatus.ready);
    harness.app.dispose();
  });

  testWidgets('gig write policy follows the repository flag', (tester) async {
    final harness = await pumpApp(tester, home: const SizedBox.shrink());
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    expect(harness.app.gigWritePolicy, isTrue);

    (harness.app.repository as DemoRepository).demoBandGigWrites = false;
    await harness.app.refreshGigWritePolicy();

    expect(harness.app.gigWritePolicy, isFalse);
    harness.app.dispose();
  });

  testWidgets('sign-out clears opportunity state', (tester) async {
    final harness = await pumpApp(tester, home: const SizedBox.shrink());
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    harness.app.switchToBand('b1');
    await tester.pumpAndSettle();
    await harness.app.refreshBrowse();
    await harness.app.refreshOpportunities('org1');
    expect(harness.app.browse.items, isNotEmpty);

    await harness.app.signOut();

    expect(harness.app.browse.items, isEmpty);
    expect(harness.app.browse.invited, isEmpty);
    expect(harness.app.myApplications, isEmpty);
    expect(harness.app.opportunitiesFor('org1'), isEmpty);
    expect(harness.app.gigWritePolicy, isTrue);
    harness.app.dispose();
  });

  testWidgets('late opportunity loads cannot restore signed-out state', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledOpportunityRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    final page = await repository.browseOpportunities();
    final pendingPage = Completer<OpportunityPage>();
    repository.pendingPage = pendingPage;
    final loading = harness.app.refreshBrowse();

    await harness.app.signOut();
    pendingPage.complete(page);
    await loading;

    expect(harness.app.browse.items, isEmpty);
    expect(harness.app.browse.status, DataStatus.connecting);
    harness.app.dispose();
  });

  testWidgets('background repository errors preserve previous values', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledOpportunityRepository(auth: auth)
      ..demoBandGigWrites = false;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const SizedBox.shrink(),
    );
    await harness.auth.signInDemo();
    await tester.pumpAndSettle();
    harness.app.switchToBand('b1');
    await tester.pumpAndSettle();
    final items = harness.app.browse.items;
    final applications = harness.app.myApplications;
    repository.failLoads = true;

    harness.app.switchToBand('b2');
    await tester.pumpAndSettle();

    expect(harness.app.browse.status, DataStatus.error);
    expect(harness.app.browse.error, contains('UnimplementedError'));
    expect(harness.app.browse.items, same(items));
    expect(harness.app.myApplications, same(applications));
    expect(harness.app.gigWritePolicy, isFalse);
    expect(await harness.app.resolveOpportunity('opp1'), isNull);
    harness.app.dispose();
  });
}

class _ControlledOpportunityRepository extends DemoRepository {
  _ControlledOpportunityRepository({required super.auth});

  int browseCalls = 0;
  int invitedCalls = 0;
  final browseRequests =
      <({String? cursor, String? bandId, OpportunityFilters? filters})>[];
  List<FutureOr<OpportunityPage>>? browsePages;
  bool failLoads = false;
  Completer<OpportunityPage>? pendingPage;
  Completer<List<BrowseItem>>? pendingInvited;

  @override
  Future<OpportunityPage> browseOpportunities({
    String? cursor,
    int numItems = 25,
    String? bandId,
    OpportunityFilters? filters,
  }) {
    browseCalls++;
    browseRequests.add((cursor: cursor, bandId: bandId, filters: filters));
    if (failLoads) throw UnimplementedError('browseOpportunities');
    final pages = browsePages;
    if (pages != null) return Future.value(pages.removeAt(0));
    return pendingPage?.future ??
        super.browseOpportunities(
          cursor: cursor,
          numItems: numItems,
          bandId: bandId,
          filters: filters,
        );
  }

  @override
  Future<List<BrowseItem>> invitedOpportunities(String bandId) {
    invitedCalls++;
    return pendingInvited?.future ?? super.invitedOpportunities(bandId);
  }

  @override
  Future<List<BandApplication>> myApplications(String bandId) {
    if (failLoads) throw UnimplementedError('myApplications');
    return super.myApplications(bandId);
  }

  @override
  Future<GigWritePolicy> gigWritePolicy() {
    if (failLoads) throw UnimplementedError('gigWritePolicy');
    return super.gigWritePolicy();
  }

  @override
  Future<BrowseItem?> resolveOpportunity(String ref, {String? bandId}) {
    if (failLoads) throw UnimplementedError('resolveOpportunity');
    return super.resolveOpportunity(ref, bandId: bandId);
  }
}
