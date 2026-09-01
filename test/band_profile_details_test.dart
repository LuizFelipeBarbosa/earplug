import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_profile.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('public profile renders optional details only when present', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _ProfileRepository(
        auth: auth,
        profileBand: DemoData.bands['b1']!.copyWith(
          linkIg: '@foghorn.diet',
          linkBc: 'foghorn.bandcamp.com',
          linkYt: 'youtube.com/@foghorn',
        ),
        details: const BandProfileDetails(
          credits: 'Recorded by Jo Rivera at Room Tone.',
          memberNames: ['Avery Stone', 'Jo Rivera'],
        ),
      ),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.byKey(const ValueKey('band-social-instagram')), findsOneWidget);
    expect(find.byKey(const ValueKey('band-social-bandcamp')), findsOneWidget);
    expect(find.byKey(const ValueKey('band-social-youtube')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Recorded by Jo Rivera at Room Tone.'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('CREDITS'), findsOne);
    expect(find.text('Recorded by Jo Rivera at Room Tone.'), findsOne);
    await tester.scrollUntilVisible(
      find.text('Avery Stone'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('BAND MEMBERS'), findsOne);
    expect(find.text('Avery Stone'), findsOne);
    expect(find.text('Jo Rivera'), findsOne);
  });

  testWidgets('empty optional details leave no empty public sections', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _ProfileRepository(
        auth: auth,
        profileBand: DemoData.bands['b1']!,
        details: BandProfileDetails.empty,
      ),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.byKey(const ValueKey('band-social-instagram')), findsNothing);
    expect(find.byKey(const ValueKey('band-social-bandcamp')), findsNothing);
    expect(find.byKey(const ValueKey('band-social-youtube')), findsNothing);
    expect(find.text('CREDITS'), findsNothing);
    expect(find.text('BAND MEMBERS'), findsNothing);
  });

  testWidgets('public profile renders only configured social icons', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _ProfileRepository(
        auth: auth,
        profileBand: DemoData.bands['b1']!.copyWith(
          linkIg: '@foghorn.diet',
          linkBc: '',
          linkYt: '',
        ),
        details: BandProfileDetails.empty,
      ),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.byKey(const ValueKey('band-social-instagram')), findsOneWidget);
    expect(find.byKey(const ValueKey('band-social-bandcamp')), findsNothing);
    expect(find.byKey(const ValueKey('band-social-youtube')), findsNothing);
  });

  testWidgets('admin preview has edit and return management controls', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      beforePump: (app) => app.go(Screen.bandPreview, 'b1'),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.text('PUBLIC PROFILE PREVIEW'), findsOne);
    expect(find.text('Edit profile'), findsOne);
    expect(find.text('Return to band dashboard'), findsOne);

    await tester.tap(find.text('Edit profile'));
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandEdit);

    harness.app.go(Screen.bandPreview, 'b1');
    await tester.pump();
    await tester.tap(find.text('Return to band dashboard'));
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandDash);
  });

  testWidgets('member preview can return but cannot edit', (tester) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _ProfileRepository(
        auth: auth,
        profileBand: DemoData.bands['b1']!,
        details: BandProfileDetails.empty,
        role: 'member',
      ),
      beforePump: (app) => app.go(Screen.bandPreview, 'b1'),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.text('PUBLIC PROFILE PREVIEW'), findsOne);
    expect(find.text('Return to band dashboard'), findsOne);
    expect(find.text('Edit profile'), findsNothing);

    await tester.tap(find.text('Return to band dashboard'));
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandDash);
  });

  testWidgets('ordinary visits retain the regular public header', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.text('BAND'), findsOne);
    expect(find.text('PUBLIC PROFILE PREVIEW'), findsNothing);
    expect(find.text('Return to band dashboard'), findsNothing);
    expect(find.text('Edit profile'), findsNothing);
  });

  testWidgets('press hero keeps follow as the sole primary profile action', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.byKey(const ValueKey('band-profile-hero-b1')), findsOne);
    expect(find.textContaining('FOLLOW ·'), findsOne);
    expect(find.byType(FilledButton), findsOne);
  });

  testWidgets('public profile badge follows derived profile completion', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _ProfileRepository(
        auth: auth,
        profileBand: DemoData.bands['b1']!,
        details: BandProfileDetails.empty,
      ),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );
    expect(find.byKey(const Key('profile-complete-badge')), findsOne);

    await tester.pumpWidget(const SizedBox.shrink());
    final incompleteAuth = FakeAuthService();
    await pumpApp(
      tester,
      auth: incompleteAuth,
      repository: _ProfileRepository(
        auth: incompleteAuth,
        profileBand: DemoData.bands['b1']!.copyWith(profileComplete: false),
        details: BandProfileDetails.empty,
      ),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );
    expect(find.byKey(const Key('profile-complete-badge')), findsNothing);
  });
}

class _ProfileRepository extends DemoRepository {
  _ProfileRepository({
    required super.auth,
    required this.profileBand,
    required this.details,
    this.role = 'admin',
  });

  final Band profileBand;
  final BandProfileDetails details;
  final String role;

  @override
  Stream<FeedSnapshot> feed() => Stream.value(
    FeedSnapshot(
      gigs: DemoData.gigs,
      venues: DemoData.venues,
      bands: {...DemoData.bands, profileBand.id: profileBand},
    ),
  );

  @override
  Stream<List<BandMembership>> myBands() =>
      Stream.value([BandMembership(band: profileBand, role: role)]);

  @override
  Future<BandProfileDetails> bandProfileDetails(String bandId) async => details;
}
