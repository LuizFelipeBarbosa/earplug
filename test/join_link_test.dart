import 'package:earplug/app_links.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('join token is preserved from a path-based web URL', () {
    expect(
      joinTokenFromUri(Uri.parse('https://earplug.dev/join/secret-token')),
      'secret-token',
    );
  });

  test('join token is preserved from a hash-based fallback URL', () {
    expect(
      joinTokenFromUri(Uri.parse('https://earplug.dev/#/join/secret-token')),
      'secret-token',
    );
  });

  test('ordinary app URLs do not enter the invitation flow', () {
    expect(joinTokenFromUri(Uri.parse('https://earplug.dev/explore')), isNull);
  });

  test('performer invitations are preserved from path and hash URLs', () {
    expect(
      performerInviteTokenFromUri(
        Uri.parse('https://earplug.dev/gig-invite/performer-token'),
      ),
      'performer-token',
    );
    expect(
      performerInviteTokenFromUri(
        Uri.parse('https://earplug.dev/#/gig-invite/performer-token'),
      ),
      'performer-token',
    );
  });

  test('shared gig URLs preserve the public gig id', () {
    expect(
      gigIdFromUri(Uri.parse('https://earplug.dev/g/public-gig-id')),
      'public-gig-id',
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

    expect(publicWebOrigin, 'https://earplug.dev');
    expect(invite.url, 'https://earplug.dev/join/secret-token');
  });
}
