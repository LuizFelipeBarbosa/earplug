import 'package:flutter_test/flutter_test.dart';

import 'package:earplug/app_state.dart';

void main() {
  group('AppState', () {
    test('starts on home feed with all demo gigs', () {
      final app = AppState();
      expect(app.current.screen, Screen.home);
      expect(app.feed.length, 7);
    });

    test('filters combine: free + tonight', () {
      final app = AppState();
      app.toggleFree();
      app.toggleDateFilter(DateFilter.tonight);
      expect(app.feed.map((g) => g.id), ['g1']);
    });

    test('RSVP requires auth, then completes the pending action', () {
      final app = AppState();
      app.openGig('g1');
      app.requestRsvp('g1');
      expect(app.current.screen, Screen.auth);
      app.login();
      app.finishAuth();
      expect(app.rsvps, contains('g1'));
      expect(app.current.screen, Screen.gig);
    });

    test('publishing a gig adds it to the feed and band gigs', () {
      final app = AppState();
      app.setGfName('Test Show');
      app.setGfDate('Fri Aug 14');
      app.setGfVenue('v1');
      expect(app.canPublishGig, isTrue);
      app.publishGig();
      expect(app.allGigs.last.title, 'Test Show');
      expect(app.allGigs.last.lineup, ['b1']);
      expect(app.current.screen, Screen.gigMgr);
    });

    test('band creation switches to band view as admin', () {
      final app = AppState();
      app.startBandCreate();
      app.setNbName('Static Bloom Two');
      app.nbNext();
      app.addNbInvite('alex');
      app.createBand();
      expect(app.bandId, 'nb');
      expect(app.myBand!.initials, 'SB');
      expect(app.myBand!.followers, 2);
      expect(app.current.screen, Screen.bandDash);
    });
  });
}
