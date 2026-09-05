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
  bool failLoads = false;
  Completer<OpportunityPage>? pendingPage;

  @override
  Future<OpportunityPage> browseOpportunities({
    String? cursor,
    int numItems = 25,
    String? bandId,
    OpportunityFilters? filters,
  }) {
    browseCalls++;
    if (failLoads) throw UnimplementedError('browseOpportunities');
    return pendingPage?.future ??
        super.browseOpportunities(
          cursor: cursor,
          numItems: numItems,
          bandId: bandId,
          filters: filters,
        );
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
