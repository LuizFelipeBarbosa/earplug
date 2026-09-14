import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/explore_friends.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final gig = DemoData.gigs.first;
  SocialUserCard person(String id, String name) =>
      SocialUserCard(userId: id, name: name);
  Widget host(Widget child) => MaterialApp(
    theme: buildEpTheme(),
    home: Scaffold(body: child),
  );

  testWidgets('signed out offers sign in', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      host(
        ExploreFriendsSection(
          entries: const [],
          signedIn: false,
          hasFriends: false,
          onFindPeople: () {},
          onSignIn: () => tapped = true,
          onOpenGig: (_) {},
          venueLine: (_) => 'Venue',
        ),
      ),
    );
    expect(find.byKey(const Key('explore-friends-sign-in')), findsOneWidget);
    await tester.tap(find.byKey(const Key('explore-friends-sign-in')));
    expect(tapped, isTrue);
  });

  testWidgets('signed in without friends offers find people', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      host(
        ExploreFriendsSection(
          entries: const [],
          signedIn: true,
          hasFriends: false,
          onFindPeople: () => tapped = true,
          onSignIn: () {},
          onOpenGig: (_) {},
          venueLine: (_) => 'Venue',
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('explore-find-people')));
    expect(tapped, isTrue);
  });

  testWidgets('signed in with no entries offers find people', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      host(
        ExploreFriendsSection(
          entries: const [],
          signedIn: true,
          hasFriends: true,
          onFindPeople: () => tapped = true,
          onSignIn: () {},
          onOpenGig: (_) {},
          venueLine: (_) => 'Venue',
        ),
      ),
    );
    expect(find.byKey(const Key('explore-find-people')), findsOneWidget);
    await tester.tap(find.byKey(const Key('explore-find-people')));
    expect(tapped, isTrue);
  });

  testWidgets('renders friend rows, sublines, avatars and see all', (
    tester,
  ) async {
    final entries = [
      (gig: gig, friends: [person('a', 'Maya')]),
      (
        gig: DemoData.gigs[1],
        friends: [person('a', 'Maya'), person('b', 'Dev')],
      ),
      (
        gig: DemoData.gigs[2],
        friends: [
          person('a', 'Maya'),
          person('b', 'Dev'),
          person('c', 'Lee'),
          person('d', 'Sam'),
        ],
      ),
    ];
    String? opened;
    var seeAll = false;
    await tester.pumpWidget(
      host(
        ExploreFriendsSection(
          entries: entries,
          signedIn: true,
          hasFriends: true,
          previewCount: 2,
          onFindPeople: () {},
          onSignIn: () {},
          onOpenGig: (id) => opened = id,
          venueLine: (_) => 'Venue',
          onSeeAll: () => seeAll = true,
        ),
      ),
    );
    expect(find.byKey(Key('explore-friends-gig-${gig.id}')), findsOneWidget);
    expect(
      find.byKey(Key('explore-friends-gig-${DemoData.gigs[1].id}')),
      findsOneWidget,
    );
    expect(find.byType(ExploreAvatarStack), findsNWidgets(2));
    expect(find.text('Maya is going'), findsOneWidget);
    expect(find.text('Maya and Dev are going'), findsOneWidget);
    expect(find.text('SEE ALL'), findsOneWidget);
    await tester.tap(find.text('SEE ALL'));
    await tester.tap(find.byKey(Key('explore-friends-gig-${gig.id}')));
    expect(seeAll, isTrue);
    expect(opened, gig.id);
  });
}
