import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/main.dart' show bandSlugFromUri, gigIdFromUri;
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('route parsing distinguishes gigs, bands, and reserved roots', () {
    expect(
      gigIdFromUri(Uri.parse('https://earplug.app/g/same-night')),
      'same-night',
    );
    expect(
      bandSlugFromUri(Uri.parse('https://earplug.app/static-bloom')),
      'static-bloom',
    );
    expect(
      bandSlugFromUri(Uri.parse('https://earplug.app/g/same-night')),
      isNull,
    );
    expect(
      bandSlugFromUri(Uri.parse('https://earplug.app/join/token')),
      isNull,
    );
    expect(bandSlugFromUri(Uri.parse('https://earplug.app/check-in')), isNull);
  });

  test(
    'a root band slug resolves to its profile and unknown slugs stay missing',
    () async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      final resolved = AppState(
        repository: repository,
        auth: auth,
        initialBandSlug: 'foghorn-diet',
      );
      addTearDown(resolved.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(resolved.current.screen, Screen.band);
      expect(resolved.current.param, 'b1');

      final missing = AppState(
        repository: repository,
        auth: auth,
        initialBandSlug: 'no-such-band',
      );
      addTearDown(missing.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(missing.publicBandMissing('no-such-band'), isTrue);
    },
  );

  test('unknown gig references become a friendly missing state', () async {
    final auth = FakeAuthService();
    final app = AppState(
      repository: DemoRepository(auth: auth),
      auth: auth,
      initialGigId: 'malformed-reference',
    );
    addTearDown(app.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(app.publicGigMissing('malformed-reference'), isTrue);
    expect(app.publicGigError('malformed-reference'), isNull);
  });

  test('in-app back exits a directly opened gig to the Gigs home', () async {
    final auth = FakeAuthService();
    final app = AppState(
      repository: DemoRepository(auth: auth),
      auth: auth,
      initialGigId: 'g1',
    );
    addTearDown(app.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(app.current.screen, Screen.gig);
    expect(app.canGoBack, isFalse);
    app.back();
    expect(app.current.screen, Screen.home);
  });

  test('in-app back pops an internal gig without revisiting auth', () async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final app = AppState(
      repository: DemoRepository(auth: auth),
      auth: auth,
    );
    addTearDown(app.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    app.openMyGigsTab();
    app.openGig('g1');
    expect(app.current.screen, Screen.gig);
    expect(app.canGoBack, isTrue);

    app.back();

    expect(app.current.screen, Screen.myGigs);
    expect(app.authed, isTrue);
  });
}
