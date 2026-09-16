import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/opportunity_applicants.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/async.dart';
import 'support/harness.dart';

void main() {
  group('application subscriptions', () {
    late _WatchApplicationsRepository repository;
    late AppState app;
    late BandApplication application;

    setUp(() async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      repository = _WatchApplicationsRepository(auth: auth);
      app = AppState.demo(repository: repository, auth: auth);
      addTearDown(app.dispose);
      application = BandApplication(
        application: DemoData.artistApplications['app1']!,
        opportunity: DemoData.opportunities['opp1']!,
      );
      await flushAsyncWork();
    });

    test(
      'selecting a band follows each emission and notifies listeners',
      () async {
        app.switchToBand('b1');
        await flushAsyncWork();
        expect(repository.watchedBandIds, contains('b1'));
        final controller = repository.controllerFor('b1');
        var notifications = 0;
        app.addListener(() => notifications++);

        controller.add([application]);
        await flushAsyncWork();

        expect(app.myApplications.map((item) => item.application.id), ['app1']);
        expect(notifications, 1);

        controller.add([]);
        await flushAsyncWork();

        expect(app.myApplications, isEmpty);
        expect(notifications, 2);
      },
    );

    test(
      'switching bands cancels the first stream and subscribes again',
      () async {
        app.switchToBand('b1');
        await flushAsyncWork();
        final controllerA = repository.controllerFor('b1');
        expect(controllerA.hasListener, isTrue);

        app.switchToBand('b2');
        await flushAsyncWork();

        expect(controllerA.hasListener, isFalse);
        expect(repository.watchedBandIds, containsAllInOrder(['b1', 'b2']));
        expect(repository.controllerFor('b2').hasListener, isTrue);
      },
    );

    test('signing out empties applications and cancels the stream', () async {
      app.switchToBand('b1');
      await flushAsyncWork();
      final controller = repository.controllerFor('b1');
      controller.add([application]);
      await flushAsyncWork();
      expect(app.myApplications, isNotEmpty);

      await app.signOut();
      await flushAsyncWork();

      expect(app.myApplications, isEmpty);
      expect(controller.hasListener, isFalse);
    });

    test('a stream error preserves the last list without throwing', () async {
      app.switchToBand('b1');
      await flushAsyncWork();
      final controller = repository.controllerFor('b1');
      controller.add([application]);
      await flushAsyncWork();
      final applications = app.myApplications;
      expect(applications, isNotEmpty);

      controller.addError(StateError('boom'));
      await flushAsyncWork();

      expect(app.myApplications, same(applications));
    });

    test('refresh waits until the first emission is visible', () async {
      app.switchToBand('b1');
      await flushAsyncWork();
      final previousController = repository.controllerFor('b1');
      var completed = false;
      final refreshing = app.refreshMyApplications().then((_) {
        completed = true;
        expect(app.myApplications, [application]);
      });
      await flushAsyncWork();
      expect(completed, isFalse);
      expect(previousController.hasListener, isFalse);

      repository.controllerFor('b1').add([application]);
      await refreshing;

      expect(completed, isTrue);
    });

    test(
      'refresh completes on a first error and preserves previous values',
      () async {
        app.switchToBand('b1');
        await flushAsyncWork();
        repository.controllerFor('b1').add([application]);
        await flushAsyncWork();
        final applications = app.myApplications;
        final refreshing = app.refreshMyApplications();

        repository.controllerFor('b1').addError(StateError('refresh failed'));
        await refreshing;

        expect(app.myApplications, same(applications));
      },
    );

    test('marking applications viewed continues after an invalid id', () async {
      await app.markApplicationsViewed(['missing', 'app1']);

      final applications = await repository.myApplications('b1');
      expect(applications.single.application.viewedAt, isNotNull);
    });
  });

  testWidgets('organizer applicants load marks submitted applications viewed', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final initial = await repository.myApplications('b1');
    expect(
      initial.single.application.status,
      ArtistApplicationStatus.submitted,
    );
    expect(initial.single.application.viewedAt, isNull);

    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(
        body: OpportunityApplicantsScreen(opportunityId: 'opp1'),
      ),
      beforePump: (app) => app.switchToOrganization('org1'),
    );

    expect(find.byKey(const ValueKey('applicant-app1')), findsOneWidget);
    final updated = await harness.app.repository.myApplications('b1');
    expect(
      updated
          .singleWhere((item) => item.application.id == 'app1')
          .application
          .viewedAt,
      isNotNull,
    );
  });
}

class _WatchApplicationsRepository extends DemoRepository {
  _WatchApplicationsRepository({required super.auth});

  final List<String> watchedBandIds = [];
  final Map<String, StreamController<List<BandApplication>>> _controllers = {};

  StreamController<List<BandApplication>> controllerFor(String bandId) =>
      _controllers[bandId]!;

  @override
  Stream<List<BandApplication>> watchMyApplications(String bandId) {
    watchedBandIds.add(bandId);
    final controller = StreamController<List<BandApplication>>();
    addTearDown(controller.close);
    _controllers[bandId] = controller;
    return controller.stream;
  }
}
