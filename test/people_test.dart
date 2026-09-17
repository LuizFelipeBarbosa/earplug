import 'package:earplug/models.dart';
import 'package:earplug/screens/people.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

class _NoFriendsRepository extends StubRepository {
  _NoFriendsRepository({required super.auth});

  @override
  Future<SocialGraph> mySocial() async => SocialGraph.empty;

  @override
  Future<FriendsGoing> friendsGoing({
    required DateTime from,
    required DateTime to,
  }) async => FriendsGoing.empty;
}

const _suggestions = [
  SuggestedPerson(userId: 's1', name: 'Ada', sharedShows: 3),
  SuggestedPerson(userId: 's2', name: 'Bo', mutualFriends: 2),
  SuggestedPerson(userId: 's3', name: 'Cy', sharedShows: 3, mutualFriends: 1),
];

void main() {
  testWidgets('signed out shows left-aligned sign in and no search field', (
    tester,
  ) async {
    await pumpApp(tester, home: const PeopleScreen());
    final signIn = find.byKey(const Key('people-sign-in'));
    expect(signIn, findsOneWidget);
    expect(tester.getRect(signIn).left, closeTo(EpLayout.gutter, 1));
    final title = find.byType(EpDisplay).first;
    expect(tester.widget<EpDisplay>(title).text, 'Find people');
    expect(tester.getRect(title).left, closeTo(EpLayout.gutter, 1));
    expect(find.text('Sign in to find and follow people.'), findsOneWidget);
    expect(find.byKey(const Key('people-search-field')), findsNothing);
    expect(find.byType(EpEntityRow), findsNothing);
  });

  testWidgets('suggestions show shared shows and mutual friends', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = StubRepository(auth: auth)
      ..returns('suggestedPeople', (people: _suggestions, truncated: false));
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const PeopleScreen(),
    );

    expect(find.text('SUGGESTED · 3'), findsOneWidget);
    expect(find.text('3 shows together'), findsOneWidget);
    expect(find.text('2 mutual friends'), findsOneWidget);
    expect(find.text('3 shows together · 1 mutual friend'), findsOneWidget);
    for (final person in _suggestions) {
      expect(
        find.byKey(Key('people-suggested-${person.userId}')),
        findsOneWidget,
      );
      final follow = tester.widget<EpPill>(
        find.byKey(Key('people-follow-${person.userId}')),
      );
      expect(follow.label, 'Follow');
      expect(follow.selected, isFalse);
    }
  });

  testWidgets('following a suggestion immediately removes its row', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = StubRepository(auth: auth)
      ..returns('suggestedPeople', (people: _suggestions, truncated: false));
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const PeopleScreen(),
    );

    await tester.tap(find.byKey(const Key('people-follow-s1')));
    await tester.pump();

    expect(harness.app.isFollowingUser('s1'), isTrue);
    expect(find.byKey(const Key('people-suggested-s1')), findsNothing);
    expect(find.byKey(const Key('people-suggested-s2')), findsOneWidget);
    expect(find.text('SUGGESTED · 2'), findsOneWidget);
  });

  testWidgets(
    'suggestions use singular show copy and omit zero-count subtitles',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = StubRepository(auth: auth)
        ..returns('suggestedPeople', (
          people: const [
            SuggestedPerson(userId: 's1', name: 'Ada', sharedShows: 1),
            SuggestedPerson(userId: 's2', name: 'Bo'),
          ],
          truncated: false,
        ));
      await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const PeopleScreen(),
      );

      expect(find.text('1 show together'), findsOneWidget);
      final bo = tester.widget<EpEntityRow>(
        find.byKey(const Key('people-suggested-s2')),
      );
      expect(bo.sub, isNull);
    },
  );

  testWidgets('signed in shows friends section', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth),
      home: const PeopleScreen(),
    );
    expect(find.textContaining('YOUR FRIENDS · 1'), findsOneWidget);
    expect(find.byKey(const Key('people-result-u-maya')), findsOneWidget);
    expect(find.textContaining('SUGGESTED'), findsNothing);
  });

  testWidgets('signed in without friends shows a left-aligned muted note', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: _NoFriendsRepository(auth: auth),
      home: const PeopleScreen(),
    );

    expect(find.text('YOUR FRIENDS · 0'), findsOneWidget);
    final note = find.text(
      'No friends yet. Follow people you go to shows with.',
    );
    expect(note, findsOneWidget);
    expect(tester.getRect(note).left, closeTo(EpLayout.gutter, 1));
    expect(
      tester.widget<Text>(note).style?.color,
      tester.element(note).epColors.muted,
    );
  });

  testWidgets('search is debounced and offers follow controls', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth),
      home: const PeopleScreen(),
    );
    await tester.enterText(
      find.byKey(const Key('people-search-field')),
      'Lina',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('people-follow-u-lina')), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('people-result-u-lina')), findsOneWidget);
    expect(find.byKey(const Key('people-follow-u-lina')), findsOneWidget);
    await tester.tap(find.byKey(const Key('people-follow-u-lina')));
    await tester.pump();
    expect(find.text('FOLLOWING'), findsOneWidget);
  });

  testWidgets('clearing search restores suggestions and friends', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = StubRepository(auth: auth)
      ..returns('suggestedPeople', (people: _suggestions, truncated: false));
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const PeopleScreen(),
    );
    final field = find.byKey(const Key('people-search-field'));
    final clear = find.byKey(const Key('people-search-clear'));
    expect(clear, findsNothing);

    await tester.enterText(field, 'Lina');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('people-result-u-lina')), findsOneWidget);
    expect(find.text('SUGGESTED · 3'), findsNothing);

    await tester.tap(clear);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(clear, findsNothing);
    expect(find.text('SUGGESTED · 3'), findsOneWidget);
    expect(find.text('YOUR FRIENDS · 1'), findsOneWidget);
    expect(find.byKey(const Key('people-result-u-lina')), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    expect(harness.app.peopleResults, isEmpty);
  });
}
