@TestOn('browser')
library;

import 'package:earplug/app_state.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/async.dart';

void main() {
  for (final route in [
    (
      path: '/org/apply',
      inviteToken: null,
      bookingId: null,
      screen: Screen.auth,
    ),
    (
      path: '/apply/invitation-token',
      inviteToken: 'invitation-token',
      bookingId: null,
      screen: Screen.orgJoin,
    ),
    (
      path: '/bookings/bk1',
      inviteToken: null,
      bookingId: 'bk1',
      screen: Screen.auth,
    ),
  ]) {
    test(
      '${route.path} startup preserves the Clerk callback parameters',
      () async {
        final originalUrl = web.window.location.href;
        final originalState = web.window.history.state;
        addTearDown(() {
          web.window.history.replaceState(originalState, '', originalUrl);
        });
        final callbackPath =
            '${route.path}?__clerk_status=verified&__clerk_created_session=placeholder';
        web.window.history.replaceState(null, '', callbackPath);

        final app = AppState.demo(
          auth: FakeAuthService(),
          initialOrganizerApply: route.path == '/org/apply',
          initialOrgInviteToken: route.inviteToken,
          initialBookingId: route.bookingId,
        );
        addTearDown(app.dispose);
        await flushAsyncWork();

        expect(app.current.screen, route.screen);
        expect(app.authed, isFalse);
        expect(
          '${web.window.location.pathname}${web.window.location.search}',
          callbackPath,
        );
        if (route.bookingId != null) {
          expect(app.pending?.kind, PendingKind.booking);
          expect(app.pending?.id, route.bookingId);
        } else if (route.inviteToken == null) {
          expect(app.pending?.kind, PendingKind.orgApply);
        } else {
          expect(app.current.param, route.inviteToken);
        }
      },
    );
  }
}
