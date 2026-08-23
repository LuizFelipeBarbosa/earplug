import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/screens/home.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

// Purging the seeded demo rows made a genuinely empty feed reachable for the
// first time, so the two reasons a feed can be empty have to read differently.

const _noGigs =
    'No upcoming gigs yet.\nWhen a band books one, it shows up here.';
const _noMatches =
    'Nothing matches those filters.\nLoosen them up and see what is out there.';

void main() {
  testWidgets('an empty backend blames nobody', (tester) async {
    final app = await _pumpHome(tester, empty: true);

    expect(app.allGigs, isEmpty);
    expect(find.text(_noGigs), findsOne);
    expect(find.text(_noMatches), findsNothing);
    expect(find.text('0 GIGS NEAR YOU · NEAREST FIRST'), findsOne);
  });

  testWidgets('a filter that excludes everything blames the filter', (
    tester,
  ) async {
    final app = await _pumpHome(tester, empty: false);
    expect(app.allGigs, isNotEmpty);

    app.toggleGenre('klezmer'); // no demo gig carries this genre
    await tester.pumpAndSettle();

    expect(app.feed, isEmpty);
    expect(find.text(_noMatches), findsOne);
    expect(find.text(_noGigs), findsNothing);
  });
}

Future<AppState> _pumpHome(WidgetTester tester, {required bool empty}) async {
  final auth = FakeAuthService();
  final harness = await pumpApp(
    tester,
    auth: auth,
    repository: empty ? _EmptyFeedRepository(auth: auth) : null,
    home: const Scaffold(body: HomeScreen()),
  );
  return harness.app;
}

/// Stands in for the cleaned dev deployment: reachable, healthy, nothing booked.
class _EmptyFeedRepository extends DemoRepository {
  _EmptyFeedRepository({required super.auth});

  @override
  Stream<FeedSnapshot> feed() =>
      Stream.value(const FeedSnapshot(gigs: [], venues: {}, bands: {}));
}
