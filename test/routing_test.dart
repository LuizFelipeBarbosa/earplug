import 'package:earplug/app_links.dart';
import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/main.dart'
    show
        bandSlugFromUri,
        bookingIdFromUri,
        checkoutCancelBookingFromUri,
        checkoutSessionFromUri,
        gigIdFromUri,
        joinTokenFromUri,
        opportunityRefFromUri,
        orgInviteTokenFromUri,
        organizerApplyFromUri,
        performerInviteTokenFromUri,
        shouldEnableWebSemantics,
        stripeReturnFromUri,
        venueRefFromUri;
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/async.dart';

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

  test('venue and organization invitation routes preserve their values', () {
    expect(
      venueRefFromUri(Uri.parse('https://earplug.app/venues/the-foghorn-club')),
      'the-foghorn-club',
    );
    expect(
      orgInviteTokenFromUri(Uri.parse('https://earplug.app/apply/abc')),
      'abc',
    );
  });

  test('opportunity routes preserve their references', () {
    expect(
      opportunityRefFromUri(
        Uri.parse('https://earplug.app/opportunities/friday-night-live'),
      ),
      'friday-night-live',
    );
  });

  test('Checkout return and cancellation routes preserve query values', () {
    expect(
      checkoutSessionFromUri(
        Uri.parse(
          'https://earplug.app/checkout/return?session_id=%20cs_123%20',
        ),
      ),
      'cs_123',
    );
    expect(
      checkoutCancelBookingFromUri(
        Uri.parse('https://earplug.app/checkout/cancel?booking=%20bk1%20'),
      ),
      'bk1',
    );
  });

  test('Stripe return and refresh routes preserve both identity prefixes', () {
    for (final (path, query, expected) in const [
      ('band/stripe/return', 'band', 'band:b1'),
      ('band/stripe/refresh', 'band', 'band-refresh:b1'),
      ('org/stripe/return', 'org', 'org:b1'),
      ('org/stripe/refresh', 'org', 'org-refresh:b1'),
    ]) {
      expect(
        stripeReturnFromUri(
          Uri.parse('https://earplug.app/$path?$query=%20b1%20'),
        ),
        expected,
      );
    }
  });

  test('payment routes support hash fallback and prefer real path values', () {
    expect(
      checkoutSessionFromUri(
        Uri.parse('https://earplug.app/#/checkout/return?session_id=cs_123'),
      ),
      'cs_123',
    );
    expect(
      checkoutCancelBookingFromUri(
        Uri.parse('https://earplug.app/#checkout/cancel?booking=bk1'),
      ),
      'bk1',
    );
    expect(
      stripeReturnFromUri(
        Uri.parse('https://earplug.app/#/org/stripe/refresh?org=org1'),
      ),
      'org-refresh:org1',
    );
    expect(
      checkoutSessionFromUri(
        Uri.parse(
          'https://earplug.app/checkout/return?session_id=path'
          '#/checkout/return?session_id=fragment',
        ),
      ),
      'path',
    );
    expect(
      checkoutSessionFromUri(
        Uri.parse(
          'https://earplug.app/checkout/return?session_id=%20'
          '#/checkout/return?session_id=fragment',
        ),
      ),
      'fragment',
    );
  });

  test('payment routes require exact non-empty segments and query values', () {
    for (final (parser, path, query) in [
      (checkoutSessionFromUri, 'checkout/return', 'session_id'),
      (checkoutCancelBookingFromUri, 'checkout/cancel', 'booking'),
      (stripeReturnFromUri, 'band/stripe/return', 'band'),
      (stripeReturnFromUri, 'band/stripe/refresh', 'band'),
      (stripeReturnFromUri, 'org/stripe/return', 'org'),
      (stripeReturnFromUri, 'org/stripe/refresh', 'org'),
    ]) {
      for (final suffix in [
        path,
        '$path?$query=',
        '$path?$query=%20',
        '$path?wrong=value',
        'prefix/$path?$query=value',
        '$path/extra?$query=value',
        '${path}ing?$query=value',
      ]) {
        expect(
          parser(Uri.parse('https://earplug.app/$suffix')),
          isNull,
          reason: suffix,
        );
        expect(
          parser(Uri.parse('https://earplug.app/#/$suffix')),
          isNull,
          reason: 'fragment: $suffix',
        );
      }
      expect(
        parser(Uri.parse('https://earplug.app/$path/?$query=value')),
        isNotNull,
      );
    }
  });

  test('signed-out booking links resume after authentication', () async {
    final auth = FakeAuthService();
    final app = AppState.demo(auth: auth, initialBookingId: 'bk1');
    addTearDown(app.dispose);
    expect(app.current.screen, Screen.auth);
    expect(app.pending?.kind, PendingKind.booking);
    expect(app.pending?.id, 'bk1');
    expect(app.bookingById('bk1'), isNull);

    await auth.signInDemo();
    await flushAsyncWork();
    await app.finishAuth();
    expect(app.current.screen, Screen.bookingDetail);
    expect(app.current.param, 'bk1');
    expect(app.pending, isNull);
    expect(await app.loadBooking('bk1'), isNotNull);
    app.back();
    expect(app.current.screen, Screen.home);
  });

  test('signed-in booking links wait for authentication setup', () async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final app = AppState.demo(auth: auth, initialBookingId: 'bk1');
    addTearDown(app.dispose);
    expect(app.current.screen, Screen.bookingDetail);
    expect(app.current.param, 'bk1');
    expect(app.pending, isNull);
    await flushAsyncWork();
    expect(app.bookingById('bk1'), isNotNull);
  });

  test('booking routes preserve their ids in path and hash URLs', () {
    expect(
      bookingIdFromUri(Uri.parse('https://earplug.app/bookings/abc')),
      'abc',
    );
    expect(
      bookingIdFromUri(Uri.parse('https://earplug.app/#/bookings/abc')),
      'abc',
    );
    expect(bookingIdFromUri(Uri.parse('https://earplug.app/bookings')), isNull);
  });

  test(
    'organizer application route is reloadable and distinct from invitations',
    () {
      for (final url in [
        'https://earplug.app/org/apply',
        'https://earplug.app/org/apply/',
        'https://earplug.app/org/apply?__clerk_status=verified',
      ]) {
        final uri = Uri.parse(url);
        expect(organizerApplyFromUri(uri), isTrue, reason: url);
        expect(orgInviteTokenFromUri(uri), isNull, reason: url);
        expect(bandSlugFromUri(uri), isNull, reason: url);
      }
      for (final path in [
        'org',
        'apply',
        'apply/invitation',
        'org/apply/extra',
        '#/org/apply',
      ]) {
        expect(
          organizerApplyFromUri(Uri.parse('https://earplug.app/$path')),
          isFalse,
        );
      }
    },
  );

  test(
    'a fresh application route restores sign-in intent after OAuth reload',
    () async {
      final auth = FakeAuthService();
      final app = AppState.demo(
        auth: auth,
        initialOrganizerApply: organizerApplyFromUri(
          Uri.parse('https://earplug.app/org/apply?__clerk_status=verified'),
        ),
      );
      addTearDown(app.dispose);
      expect(app.current.screen, Screen.auth);
      expect(app.pending?.kind, PendingKind.orgApply);
      expect(app.authConfirmationKind, PendingKind.orgApply);
      expect(app.authStep, 1);

      // Clerk restores its session after the app has reconstructed navigation.
      await auth.signInDemo();
      await flushAsyncWork();
      await app.finishAuth();
      expect(app.current.screen, Screen.orgApply);
      expect(app.pending, isNull);
      app.back();
      expect(app.current.screen, Screen.home);
    },
  );

  test('signed-in startup opens the organizer application directly', () async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final app = AppState.demo(auth: auth, initialOrganizerApply: true);
    addTearDown(app.dispose);
    await flushAsyncWork();
    expect(app.current.screen, Screen.orgApply);
    expect(app.pending, isNull);
    app.back();
    expect(app.current.screen, Screen.home);
  });

  test('bare marketplace prefixes preserve existing band links', () {
    for (final segment in const {
      'venues',
      'orgs',
      'apply',
      't',
      'org',
      'band',
      'checkout',
      'admin',
      'opportunities',
    }) {
      expect(
        bandSlugFromUri(Uri.parse('https://earplug.app/$segment')),
        segment,
        reason: '$segment remains a valid backend-issued band slug',
      );
    }
  });

  test('marketplace detail routes are not treated as band slugs', () {
    for (final path in const [
      'venues/the-foghorn-club',
      'apply/invite-token',
      'opportunities/friday-night-live',
    ]) {
      expect(bandSlugFromUri(Uri.parse('https://earplug.app/$path')), isNull);
    }
  });

  test('organization invitation tokens seed the join placeholder', () async {
    final auth = FakeAuthService();
    final resolved = AppState.demo(
      repository: DemoRepository(auth: auth),
      auth: auth,
      initialOrgInviteToken: 'tok123',
    );
    addTearDown(resolved.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(resolved.current.screen, Screen.orgJoin);
    expect(resolved.current.param, 'tok123');
  });

  test('opportunity references seed the detail placeholder', () async {
    final auth = FakeAuthService();
    final app = AppState.demo(
      auth: auth,
      repository: DemoRepository(auth: auth),
      initialOpportunityRef: 'friday-night-live',
    );
    addTearDown(app.dispose);
    await flushAsyncWork();

    expect(app.current.screen, Screen.opportunityDetail);
    expect(app.current.param, 'friday-night-live');
  });

  test('signed-in unknown bookings seed the detail placeholder', () async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final app = AppState.demo(
      auth: auth,
      repository: DemoRepository(auth: auth),
      initialBookingId: 'abc',
    );
    addTearDown(app.dispose);
    await flushAsyncWork();

    expect(app.current.screen, Screen.bookingDetail);
    expect(app.current.param, 'abc');
  });

  test(
    'Checkout sessions seed the return placeholder without an auth gate',
    () async {
      final app = AppState.demo(initialCheckoutSessionId: ' cs_123 ');
      addTearDown(app.dispose);
      await flushAsyncWork();

      expect(app.current.screen, Screen.checkoutReturn);
      expect(app.current.param, 'cs_123');
      expect(app.pending, isNull);
      expect(app.canGoBack, isFalse);
    },
  );

  test('Checkout cancellations seed the cancellation placeholder', () async {
    final app = AppState.demo(initialCheckoutCancelBookingId: ' bk1 ');
    addTearDown(app.dispose);
    await flushAsyncWork();

    expect(app.current.screen, Screen.checkoutCancel);
    expect(app.current.param, 'bk1');
    expect(app.pending, isNull);
  });

  test('Stripe returns seed the return placeholder', () async {
    for (final param in const [
      'band:b1',
      'band-refresh:b1',
      'org:org1',
      'org-refresh:org1',
    ]) {
      final app = AppState.demo(initialStripeReturn: ' $param ');
      addTearDown(app.dispose);
      await flushAsyncWork();

      expect(app.current.screen, Screen.stripeReturn);
      expect(app.current.param, param);
      expect(app.pending, isNull);
    }
  });

  test(
    'blank payment return parameters leave the home route unchanged',
    () async {
      final app = AppState.demo(
        initialCheckoutSessionId: ' ',
        initialCheckoutCancelBookingId: ' ',
        initialStripeReturn: ' ',
      );
      addTearDown(app.dispose);
      await flushAsyncWork();

      expect(app.current.screen, Screen.home);
    },
  );

  test(
    'Stripe return identities use the route instead of ambient context',
    () async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final app = AppState.demo(auth: auth);
      addTearDown(app.dispose);
      await flushAsyncWork();
      app.switchToBand('b1');
      app.switchToOrganization('org1');
      await flushAsyncWork();

      for (final prefix in const ['band', 'band-refresh']) {
        app.go(Screen.stripeReturn, '$prefix:other-band');
        expect(app.identity, isA<BandIdentity>());
        expect((app.identity as BandIdentity).bandId, 'other-band');
      }
      for (final prefix in const ['org', 'org-refresh']) {
        app.go(Screen.stripeReturn, '$prefix:other-org');
        expect(app.identity, isA<OrganizerIdentity>());
        expect((app.identity as OrganizerIdentity).organizationId, 'other-org');
        app.go(Screen.stripeReturn, '$prefix:org1');
        expect(
          (app.identity as OrganizerIdentity).role,
          OrganizationRole.owner,
        );
      }
      app.go(Screen.stripeReturn);
      expect(app.identity, isA<PersonalIdentity>());
      app.go(Screen.stripeReturn, 'unknown:id');
      expect(app.identity, isA<PersonalIdentity>());
    },
  );

  test(
    'a root band slug resolves to its profile and unknown slugs stay missing',
    () async {
      final auth = FakeAuthService();
      final repository = DemoRepository(auth: auth);
      final resolved = AppState.demo(
        repository: repository,
        auth: auth,
        initialBandSlug: 'foghorn-diet',
      );
      addTearDown(resolved.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(resolved.current.screen, Screen.band);
      expect(resolved.current.param, 'b1');

      final missing = AppState.demo(
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
    final app = AppState.demo(
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
    final app = AppState.demo(
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
    final app = AppState.demo(
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
    final app = AppState.demo(repository: repository, auth: auth);
    addTearDown(app.dispose);
    await flushAsyncWork();

    app.openGig('g1');
    await flushAsyncWork();
    expect(repository.publicGigCalls, 1);

    app.openBand('b1');
    await flushAsyncWork();
    app.back();
    await flushAsyncWork();

    expect(app.current.screen, Screen.gig);
    expect(app.current.param, 'g1');
    expect(repository.publicGigCalls, 2);
  });

  test('revisiting Explore does not fetch another page', () async {
    final auth = FakeAuthService();
    final repository = _NavigationRepository(auth: auth);
    final app = AppState.demo(repository: repository, auth: auth);
    addTearDown(app.dispose);
    await flushAsyncWork();

    app.go(Screen.explore);
    await flushAsyncWork();
    expect(repository.listBandsCalls, 1);

    app.go(Screen.home);
    app.go(Screen.explore);
    await flushAsyncWork();
    expect(repository.listBandsCalls, 1);

    app.loadMoreExploreBands();
    await flushAsyncWork();
    expect(repository.listBandsCalls, 2);
  });

  test('join token is preserved from a path-based web URL', () {
    expect(
      joinTokenFromUri(Uri.parse('https://earplug.app/join/secret-token')),
      'secret-token',
    );
  });

  test('join token is preserved from a hash-based fallback URL', () {
    expect(
      joinTokenFromUri(Uri.parse('https://earplug.app/#/join/secret-token')),
      'secret-token',
    );
  });

  test('ordinary app URLs do not enter the invitation flow', () {
    expect(joinTokenFromUri(Uri.parse('https://earplug.app/explore')), isNull);
  });

  test('performer invitations are preserved from path and hash URLs', () {
    expect(
      performerInviteTokenFromUri(
        Uri.parse('https://earplug.app/gig-invite/performer-token'),
      ),
      'performer-token',
    );
    expect(
      performerInviteTokenFromUri(
        Uri.parse('https://earplug.app/#/gig-invite/performer-token'),
      ),
      'performer-token',
    );
  });

  test('band invitations use the canonical public website', () {
    final invite = BandInvite(
      bandId: 'band-id',
      token: 'secret-token',
      expiresAt: DateTime(2026, 9),
      revoked: false,
      expired: false,
    );

    expect(publicWebOrigin, 'https://earplug.app');
    expect(invite.url, 'https://earplug.app/join/secret-token');
  });

  group('shouldEnableWebSemantics', () {
    test("query '1' enables semantics regardless of the stored preference", () {
      expect(shouldEnableWebSemantics(queryValue: '1', stored: false), isTrue);
      expect(shouldEnableWebSemantics(queryValue: '1', stored: true), isTrue);
    });

    test(
      "query '0' disables semantics regardless of the stored preference",
      () {
        expect(
          shouldEnableWebSemantics(queryValue: '0', stored: false),
          isFalse,
        );
        expect(
          shouldEnableWebSemantics(queryValue: '0', stored: true),
          isFalse,
        );
      },
    );

    test('a missing query uses the stored preference', () {
      expect(
        shouldEnableWebSemantics(queryValue: null, stored: false),
        isFalse,
      );
      expect(shouldEnableWebSemantics(queryValue: null, stored: true), isTrue);
    });
  });
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
