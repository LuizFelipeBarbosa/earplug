import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/main.dart' show bandSlugFromUri, gigIdFromUri;
import 'package:earplug/models.dart';
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

  test('returning to a gig resubscribes to its public stream', () async {
    final auth = FakeAuthService();
    final repository = _NavigationRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(app.dispose);
    await _flushAsyncWork();

    app.openGig('g1');
    await _flushAsyncWork();
    expect(repository.publicGigCalls, 1);

    app.openBand('b1');
    await _flushAsyncWork();
    app.back();
    await _flushAsyncWork();

    expect(app.current.screen, Screen.gig);
    expect(app.current.param, 'g1');
    expect(repository.publicGigCalls, 2);
  });

  test('revisiting Explore does not fetch another page', () async {
    final auth = FakeAuthService();
    final repository = _NavigationRepository(auth: auth);
    final app = AppState(repository: repository, auth: auth);
    addTearDown(app.dispose);
    await _flushAsyncWork();

    app.go(Screen.explore);
    await _flushAsyncWork();
    expect(repository.listBandsCalls, 1);

    app.go(Screen.home);
    app.go(Screen.explore);
    await _flushAsyncWork();
    expect(repository.listBandsCalls, 1);

    app.loadMoreExploreBands();
    await _flushAsyncWork();
    expect(repository.listBandsCalls, 2);
  });
}

Future<void> _flushAsyncWork() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _NavigationRepository extends DemoRepository {
  _NavigationRepository({required super.auth});

  var publicGigCalls = 0;
  var listBandsCalls = 0;

  @override
  Stream<Gig?> publicGig(String gigId) {
    publicGigCalls++;
    return super.publicGig(gigId);
  }

  @override
  Future<BandPage> listBands({String? cursor, int numItems = 50}) async {
    listBandsCalls++;
    return BandPage(
      items: const [],
      continueCursor: cursor == null ? 'page-2' : null,
      isDone: cursor != null,
    );
  }
}
