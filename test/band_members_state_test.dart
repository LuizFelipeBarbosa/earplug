import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/errors.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/async.dart';
import 'support/stub_repository.dart';

const _maya = 'u-maya';

void main() {
  group('AppState band members', () {
    late StubRepository repository;
    late AppState app;

    setUp(() async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      repository = StubRepository(auth: auth);
      app = AppState.demo(auth: auth, repository: repository);
      addTearDown(app.dispose);
      await flushAsyncWork();
    });

    /// Reads the list, which triggers the lazy load, and waits for it.
    Future<List<BandMember>> members() async {
      app.bandMembersFor('b1');
      await flushAsyncWork();
      return app.bandMembersFor('b1')!;
    }

    test('loads lazily on first read and caches the list', () async {
      expect(app.bandMembersFor('b1'), isNull);
      expect(repository.callsTo('bandMembers'), 1);

      final loaded = await members();
      expect(loaded, hasLength(1));
      expect(loaded.single.userId, DemoData.demoUserId);
      expect(loaded.single.name, 'Band admin');
      expect(loaded.single.role, BandMemberRole.admin);
      expect(loaded.single.isSelf, isTrue);

      app.bandMembersFor('b1');
      expect(repository.callsTo('bandMembers'), 1);
    });

    test('adding a member refreshes the list and profile details', () async {
      await members();
      app.profileDetailsFor('b1');
      await flushAsyncWork();
      expect(app.profileDetailsFor('b1')!.memberNames, ['Band admin']);
      final detailCalls = repository.callsTo('bandProfileDetails');

      await app.addBandMember('b1', _maya);

      expect(repository.callsTo('addBandMember'), 1);
      expect(app.bandMembersFor('b1')!.map((member) => member.name), [
        'Band admin',
        'Maya Okafor',
      ]);
      expect(app.profileDetailsFor('b1')!.memberNames, [
        'Band admin',
        'Maya Okafor',
      ]);
      expect(repository.callsTo('bandProfileDetails'), detailCalls + 1);
      expect(app.toast, isEmpty);
    });

    test('changing a role refreshes the list, admins first', () async {
      await members();
      await app.addBandMember('b1', _maya);

      await app.setBandMemberRole('b1', _maya, BandMemberRole.admin);
      await app.setBandMemberRole(
        'b1',
        DemoData.demoUserId,
        BandMemberRole.member,
      );

      final updated = app.bandMembersFor('b1')!;
      expect(updated.map((member) => member.name), [
        'Maya Okafor',
        'Band admin',
      ]);
      expect(updated.first.role, BandMemberRole.admin);
      expect(updated.last.role, BandMemberRole.member);
      expect(app.roleFor('b1'), 'member');
      expect(app.toast, isEmpty);
    });

    test('removing another member keeps memberships as they are', () async {
      await members();
      await app.addBandMember('b1', _maya);
      final membershipCalls = repository.callsTo('myBands');

      await app.removeBandMember('b1', _maya);

      expect(app.bandMembersFor('b1')!.map((member) => member.name), [
        'Band admin',
      ]);
      expect(app.profileDetailsFor('b1')!.memberNames, ['Band admin']);
      expect(repository.callsTo('myBands'), membershipCalls);
      expect(app.myBands, contains('b1'));
    });

    test('removing yourself restarts memberships and drops the band', () async {
      await members();
      await app.addBandMember('b1', _maya);
      await app.setBandMemberRole('b1', _maya, BandMemberRole.admin);
      final membershipCalls = repository.callsTo('myBands');

      await app.removeBandMember('b1', DemoData.demoUserId);
      await flushAsyncWork();

      expect(repository.callsTo('myBands'), membershipCalls + 1);
      expect(app.myBands, isNot(contains('b1')));
      expect(app.bandId, isEmpty);
      expect(app.bandMembersFor('b1')!.map((member) => member.name), [
        'Maya Okafor',
      ]);
    });

    test('a last-admin error says so and keeps the list', () async {
      final before = await members();
      repository.fail(
        'setBandMemberRole',
        StateError('Uncaught Error: Cannot demote the last admin.'),
      );

      await app.setBandMemberRole(
        'b1',
        DemoData.demoUserId,
        BandMemberRole.member,
      );

      expect(app.toast, 'Keep at least one admin.');
      expect(app.bandMembersFor('b1'), same(before));
      expect(app.roleFor('b1'), 'admin');
    });

    test('any other error says the generic message', () async {
      final before = await members();
      repository.fail('removeBandMember');

      await app.removeBandMember('b1', DemoData.demoUserId);

      expect(app.toast, genericErrorMessage);
      expect(app.bandMembersFor('b1'), same(before));
      expect(app.myBands, contains('b1'));
    });

    test('signing out clears the cached members', () async {
      await members();
      await app.signOut();
      await flushAsyncWork();
      final calls = repository.callsTo('bandMembers');

      expect(app.bandMembersFor('b1'), isNull);
      expect(repository.callsTo('bandMembers'), calls + 1);
    });
  });

  group('DemoRepository band members', () {
    late FakeAuthService auth;
    late DemoRepository repository;

    setUp(() async {
      auth = FakeAuthService();
      await auth.signInDemo();
      repository = DemoRepository(auth: auth);
    });

    test('adding is idempotent and derives memberNames', () async {
      await repository.addBandMember(bandId: 'b1', userId: _maya);
      await repository.addBandMember(bandId: 'b1', userId: _maya);
      await repository.addBandMember(
        bandId: 'b1',
        userId: 'u-dev',
        role: BandMemberRole.admin,
      );

      final members = await repository.bandMembers('b1');
      expect(members.map((member) => member.name), [
        'Band admin',
        'Dev Patel',
        'Maya Okafor',
      ]);
      expect(members.map((member) => member.isSelf), [true, false, false]);
      expect((await repository.bandProfileDetails('b1')).memberNames, [
        'Band admin',
        'Dev Patel',
        'Maya Okafor',
      ]);
      expect((await repository.bandSetupStatus('b1')).membersInvited, isTrue);
    });

    test('guards the last admin on demotion and removal', () async {
      await repository.addBandMember(bandId: 'b1', userId: _maya);

      await expectLater(
        repository.setBandMemberRole(
          bandId: 'b1',
          userId: DemoData.demoUserId,
          role: BandMemberRole.member,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('last admin'),
          ),
        ),
      );
      await expectLater(
        repository.removeBandMember(bandId: 'b1', userId: DemoData.demoUserId),
        throwsA(isA<StateError>()),
      );

      await repository.setBandMemberRole(
        bandId: 'b1',
        userId: _maya,
        role: BandMemberRole.admin,
      );
      await repository.removeBandMember(
        bandId: 'b1',
        userId: DemoData.demoUserId,
      );
      expect(await repository.myBands().first, isEmpty);
      expect(
        (await repository.bandMembers('b1')).map((member) => member.name),
        ['Maya Okafor'],
      );
    });

    test('only admins add members or change roles', () async {
      final invite = await repository.createBandInvite('b2');
      await repository.acceptBandInvite(invite.token);
      final members = await repository.bandMembers('b2');
      expect(members.single.role, BandMemberRole.member);
      expect(members.single.isSelf, isTrue);

      await expectLater(
        repository.addBandMember(bandId: 'b2', userId: _maya),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        repository.setBandMemberRole(
          bandId: 'b2',
          userId: DemoData.demoUserId,
          role: BandMemberRole.admin,
        ),
        throwsA(isA<StateError>()),
      );
      // Members may still leave on their own.
      await repository.removeBandMember(
        bandId: 'b2',
        userId: DemoData.demoUserId,
      );
      expect(await repository.bandMembers('b2'), isEmpty);
    });
  });
}
