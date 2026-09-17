import 'dart:async';
import 'dart:typed_data';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_payouts.dart';
import 'package:earplug/screens/gig_manager.dart';
import 'package:earplug/screens/org_dash.dart';
import 'package:earplug/screens/org_finance.dart';
import 'package:earplug/screens/org_settings.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/band_my_gigs_tab.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  testWidgets(
    'statement export is disabled without payouts and shows caption',
    (tester) async {
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: BandPayoutsScreen()),
        beforePump: (app) => app.switchToBand('b1'),
      );
      final export = find.byKey(const Key('band-payouts-export'));
      await tester.scrollUntilVisible(export, 200);
      expect(harness.app.bandPayouts, isEmpty);
      expect(tester.widget<EpButton>(export).kind, EpButtonKind.disabled);
      expect(
        find.text(
          'Statements are for your records. Stripe issues your tax forms.',
        ),
        findsOneWidget,
      );
      await tester.tap(export);
      await tester.pumpAndSettle();
      expect(find.byType(EpActionSheet), findsNothing);
    },
  );

  for (final preset in ['Year to date']) {
    testWidgets('$preset downloads the band payout statement PDF', (
      tester,
    ) async {
      final auth = FakeAuthService();
      final repository = _PayoutRepository(auth: auth);
      final downloads =
          <({String filename, Uint8List bytes, String mimeType})>[];
      await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const Scaffold(body: BandPayoutsScreen()),
        beforePump: (app) {
          app.switchToBand('b1');
          app.bytesFileDownloader = (filename, bytes, mimeType) async {
            downloads.add((
              filename: filename,
              bytes: bytes,
              mimeType: mimeType,
            ));
          };
        },
      );
      final export = find.byKey(const Key('band-payouts-export'));
      await tester.scrollUntilVisible(export, 200);
      await tester.ensureVisible(export);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EpButton>(export).kind,
        isNot(EpButtonKind.disabled),
      );
      final before = DateTime.now();
      await tester.tap(export);
      await tester.pumpAndSettle();
      final after = DateTime.now();
      expect(
        tester
            .widget<EpActionSheet>(find.byType(EpActionSheet))
            .items
            .map((item) => item.label),
        ['Year to date', 'Last year', 'Last 30 days'],
      );
      await tester.tap(find.text(preset));
      await tester.pumpAndSettle();

      final range = repository.statementRange!;
      expect(range.bandId, 'b1');
      switch (preset) {
        case 'Year to date':
          expect(range.from, DateTime(range.to.year));
        case 'Last year':
          expect(range.from, DateTime(before.year - 1));
          expect(
            range.to,
            DateTime(before.year).subtract(const Duration(milliseconds: 1)),
          );
        case 'Last 30 days':
          expect(range.to.difference(range.from), const Duration(days: 30));
      }
      if (preset != 'Last year') {
        expect(range.to.isBefore(before), isFalse);
        expect(range.to.isAfter(after), isFalse);
      }
      expect(downloads, hasLength(1));
      expect(downloads.single.filename, startsWith('earplug-payouts-b1-'));
      expect(downloads.single.filename, endsWith('.pdf'));
      expect(downloads.single.mimeType, 'application/pdf');
      expect(find.text('Statement downloaded (2 payouts)'), findsOneWidget);
    });
  }

  testWidgets('truncated statements explain that some payouts were left out', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final downloads = <({String filename, Uint8List bytes, String mimeType})>[];
    await pumpApp(
      tester,
      auth: auth,
      repository: _TruncatedPayoutRepository(auth: auth),
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) {
        app.switchToBand('b1');
        app.bytesFileDownloader = (filename, bytes, mimeType) async {
          downloads.add((filename: filename, bytes: bytes, mimeType: mimeType));
        };
      },
    );
    final export = find.byKey(const Key('band-payouts-export'));
    await tester.scrollUntilVisible(export, 200);
    await tester.ensureVisible(export);
    await tester.pumpAndSettle();
    await tester.tap(export);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 30 days'));
    await tester.pumpAndSettle();

    expect(downloads, hasLength(1));
    expect(
      find.text(
        'Statement downloaded (2 payouts). Some payouts were left out.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('statement download errors appear inline', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _PayoutRepository(auth: auth),
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) {
        app.switchToBand('b1');
        app.bytesFileDownloader = (_, _, _) async {
          throw StateError('Download failed');
        };
      },
    );
    final export = find.byKey(const Key('band-payouts-export'));
    await tester.scrollUntilVisible(export, 200);
    await tester.ensureVisible(export);
    await tester.pumpAndSettle();
    await tester.tap(export);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 30 days'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('band-payouts-error')), findsOneWidget);
    expect(find.textContaining('Download failed'), findsOneWidget);
    expect(find.textContaining('Statement downloaded'), findsNothing);
  });

  testWidgets('band setup launches Stripe and immediately shows onboarding', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) => app.switchToBand('b1'),
    );
    final launched = <String>[];
    harness.app.hostedUrlLauncher = (url) async => launched.add(url);

    expect(harness.app.bandPayoutStatus?.state, StripeAccountState.none);
    expect(find.byKey(const Key('band-payouts-status')), findsOneWidget);
    expect(find.byKey(const Key('band-payouts-history')), findsOneWidget);
    expect(find.text('No payouts yet.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('band-payouts-setup')));
    await tester.pumpAndSettle();

    expect(launched, ['https://demo.stripe/onboard/b1']);
    expect(harness.app.bandPayoutStatus?.state, StripeAccountState.onboarding);
    expect(find.text('Finish your Stripe setup'), findsOneWidget);
    expect(find.text('CONTINUE SETUP'), findsOneWidget);

    await tester.tap(find.byKey(const Key('band-payouts-setup')));
    await tester.pumpAndSettle();
    expect(launched, hasLength(2));
  });

  testWidgets('Stripe return enables payouts and the Express dashboard', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = DemoRepository(auth: auth);
    await repository.startBandOnboarding('b1');
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) => app.switchToBand('b1'),
    );
    final launched = <String>[];
    harness.app.hostedUrlLauncher = (url) async => launched.add(url);

    await tester.tap(find.byKey(const Key('band-payouts-refresh')));
    await tester.pumpAndSettle();
    expect(harness.app.bandPayoutStatus?.state, StripeAccountState.onboarding);

    await harness.app.handleStripeReturn(band: true, id: 'b1');
    await tester.pumpAndSettle();
    expect(harness.app.bandPayoutStatus?.state, StripeAccountState.enabled);
    expect(find.text('PAYOUTS ENABLED'), findsOneWidget);

    await tester.tap(find.byKey(const Key('band-payouts-refresh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('band-payouts-dashboard')));
    await tester.pumpAndSettle();
    expect(launched, ['https://demo.stripe/dashboard/b1']);
  });

  testWidgets('bands without card payments can enable ticket sales', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _stripeStatusRepository(
      auth: auth,
      state: StripeAccountState.enabled,
      cardPaymentsStatus: null,
    );
    await repository.startBandOnboarding('b1');
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) async {
        app.switchToBand('b1');
      },
    );
    final launched = <String>[];
    harness.app.hostedUrlLauncher = (url) async => launched.add(url);
    final button = find.byKey(const Key('band-payouts-enable-tickets'));

    expect(harness.app.bandPayoutStatus?.hasAccount, isTrue);
    expect(harness.app.bandPayoutStatus?.chargesEnabled, isTrue);
    expect(harness.app.bandPayoutStatus?.cardPaymentsStatus, isNull);
    expect(harness.app.bandPayoutStatus?.canSellTickets, isFalse);
    expect(button, findsOneWidget);
    expect(find.text('ENABLE TICKET SALES'), findsOneWidget);
    expect(find.text('TICKET SALES ENABLED'), findsNothing);
    expect(find.text(_ticketSalesCaption), findsOneWidget);

    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(launched, ['https://demo.stripe/ticketing/b1']);
    expect(find.byKey(const Key('band-payouts-error')), findsNothing);
  });

  testWidgets('bands with active card payments show ticket sales enabled', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _stripeStatusRepository(
        auth: auth,
        state: StripeAccountState.enabled,
        cardPaymentsStatus: 'active',
      ),
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) async {
        app.switchToBand('b1');
      },
    );

    expect(harness.app.bandPayoutStatus?.canSellTickets, isTrue);
    expect(find.text('TICKET SALES'), findsOneWidget);
    expect(find.text('TICKET SALES ENABLED'), findsOneWidget);
    final pill = tester.widget<EpBadge>(
      find.ancestor(
        of: find.text('TICKET SALES ENABLED'),
        matching: find.byType(EpBadge),
      ),
    );
    expect(pill.tone, EpBadgeTone.success);
    expect(find.byKey(const Key('band-payouts-enable-tickets')), findsNothing);
    expect(find.text(_ticketSalesCaption), findsOneWidget);
  });

  testWidgets('ticket sales stay hidden until a band has a Stripe account', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) async {
        app.switchToBand('b1');
      },
    );

    expect(harness.app.bandPayoutStatus?.hasAccount, isFalse);
    expect(find.text('SET UP PAYOUTS'), findsOneWidget);
    expect(find.text('TICKET SALES'), findsNothing);
    expect(find.byKey(const Key('band-payouts-enable-tickets')), findsNothing);
    expect(find.text('TICKET SALES ENABLED'), findsNothing);
    expect(find.text(_ticketSalesCaption), findsNothing);
  });

  testWidgets('ticket sales errors appear inline and clear on retry', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _stripeStatusRepository(
        auth: auth,
        state: StripeAccountState.enabled,
      ),
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) async {
        app.switchToBand('b1');
      },
    );
    final button = find.byKey(const Key('band-payouts-enable-tickets'));
    harness.app.hostedUrlLauncher = (_) async {
      throw StateError('Could not open ticket sales setup');
    };
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('band-payouts-error')), findsOneWidget);
    expect(
      find.textContaining('Could not open ticket sales setup'),
      findsOneWidget,
    );

    final launched = <String>[];
    harness.app.hostedUrlLauncher = (url) async => launched.add(url);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(launched, ['https://demo.stripe/ticketing/b1']);
    expect(find.byKey(const Key('band-payouts-error')), findsNothing);
  });

  testWidgets('payout history waits for the first load before showing empty', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final response = Completer<List<Payout>>();
    await pumpApp(
      tester,
      auth: auth,
      repository: _PayoutRepository(
        auth: auth,
        payoutsResponse: response.future,
      ),
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) => app.switchToBand('b1'),
      pumpFor: Duration.zero,
    );

    expect(find.byKey(const Key('band-payouts-history')), findsOneWidget);
    expect(find.text('No payouts yet.'), findsNothing);

    response.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('No payouts yet.'), findsOneWidget);
  });

  testWidgets(
    'payout history shows scheduled dates, kinds, amounts and holds',
    (tester) async {
      final auth = FakeAuthService();
      await pumpApp(
        tester,
        auth: auth,
        repository: _PayoutRepository(auth: auth),
        home: const Scaffold(body: BandPayoutsScreen()),
        beforePump: (app) => app.switchToBand('b1'),
      );

      final paidRow = find.byKey(const ValueKey('band-payout-p1'));
      expect(paidRow, findsOneWidget);
      expect(
        find.descendant(of: paidRow, matching: find.text('Sat Aug 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: paidRow,
          matching: find.text(r'Completion payout · $120.00'),
        ),
        findsOneWidget,
      );
      final paidPill = tester.widget<EpBadge>(
        find.descendant(of: paidRow, matching: find.byType(EpBadge)),
      );
      expect(paidPill.label, 'paid');
      expect(paidPill.tone, EpBadgeTone.success);

      final heldRow = find.byKey(const ValueKey('band-payout-p2'));
      expect(
        find.descendant(
          of: heldRow,
          matching: find.text(r'Forfeited payout · $40.00'),
        ),
        findsOneWidget,
      );
      expect(find.text('Waiting for bank details'), findsOneWidget);
      expect(
        find.descendant(
          of: paidRow,
          matching: find.text('Waiting for bank details'),
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<EpBadge>(
              find.descendant(of: heldRow, matching: find.byType(EpBadge)),
            )
            .tone,
        EpBadgeTone.warning,
      );
    },
  );

  testWidgets('band onboarding errors appear inline and clear on retry', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) => app.switchToBand('b1'),
    );
    harness.app.hostedUrlLauncher = (_) async {
      throw StateError('Could not open Stripe');
    };
    await tester.tap(find.byKey(const Key('band-payouts-setup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('band-payouts-error')), findsOneWidget);
    expect(find.textContaining('Could not open Stripe'), findsOneWidget);

    harness.app.hostedUrlLauncher = (_) async {};
    await tester.tap(find.byKey(const Key('band-payouts-setup')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('band-payouts-error')), findsNothing);
    expect(find.text('CONTINUE SETUP'), findsOneWidget);
  });

  testWidgets('band dashboard errors from the repository appear inline', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _stripeStatusRepository(
        auth: auth,
        state: StripeAccountState.enabled,
      ),
      home: const Scaffold(body: BandPayoutsScreen()),
      beforePump: (app) => app.switchToBand('b1'),
    );

    // The displayed status is enabled, but the demo account is still disabled.
    await tester.tap(find.byKey(const Key('band-payouts-dashboard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('band-payouts-error')), findsOneWidget);
    expect(find.textContaining('Finish Stripe setup first'), findsOneWidget);
  });

  for (final (description, requirementsDue, needsTaxInformation) in [
    ('ID number', ['external_account', 'individual.id_number'], true),
    ('no requirements', <String>[], false),
  ]) {
    testWidgets('band tax row handles $description', (tester) async {
      final auth = FakeAuthService();
      final detailsSubmitted = requirementsDue.isEmpty;
      await pumpApp(
        tester,
        auth: auth,
        repository: _stripeStatusRepository(
          auth: auth,
          state: detailsSubmitted
              ? StripeAccountState.enabled
              : StripeAccountState.restricted,
          detailsSubmitted: detailsSubmitted,
          requirementsDue: requirementsDue,
        ),
        home: const Scaffold(body: BandPayoutsScreen()),
        beforePump: (app) => app.switchToBand('b1'),
      );

      final row = find.byKey(const Key('stripe-tax-row'));
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('TAX DETAILS')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(
            'Stripe collects your tax information (W-9 / 1099) during onboarding. '
            'Update it in your Stripe dashboard.',
          ),
        ),
        findsOneWidget,
      );
      final pill = find.descendant(of: row, matching: find.byType(EpBadge));
      if (needsTaxInformation) {
        expect(tester.widget<EpBadge>(pill).label, 'ACTION NEEDED');
        expect(tester.widget<EpBadge>(pill).tone, EpBadgeTone.warning);
      } else {
        expect(pill, findsNothing);
      }
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.check)),
        needsTaxInformation ? findsNothing : findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(
            'Stripe needs your tax information before payouts continue.',
          ),
        ),
        needsTaxInformation ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const Key('band-payouts-tax-dashboard')),
        detailsSubmitted ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets(
    'restricted band with submitted details can manage tax details and retry errors',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _stripeStatusRepository(
        auth: auth,
        state: StripeAccountState.restricted,
        detailsSubmitted: true,
        requirementsDue: const ['individual.id_number'],
      );
      // Enable the demo dashboard link while the displayed status stays restricted.
      await repository.refreshBandAccountStatus('b1');
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const Scaffold(body: BandPayoutsScreen()),
        beforePump: (app) => app.switchToBand('b1'),
      );
      final button = find.byKey(const Key('band-payouts-tax-dashboard'));
      await tester.scrollUntilVisible(
        button,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(of: button, matching: find.text('MANAGE IN STRIPE')),
        findsOneWidget,
      );
      harness.app.hostedUrlLauncher = (_) async {
        throw StateError('Could not open Stripe');
      };
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('band-payouts-error')), findsOneWidget);
      expect(find.textContaining('Could not open Stripe'), findsOneWidget);

      final launched = <String>[];
      harness.app.hostedUrlLauncher = (url) async => launched.add(url);
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(launched, ['https://demo.stripe/dashboard/b1']);
      expect(find.byKey(const Key('band-payouts-error')), findsNothing);
    },
  );

  testWidgets(
    'restricted organization with submitted details can manage tax details and retry errors',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _stripeStatusRepository(
        auth: auth,
        state: StripeAccountState.restricted,
        detailsSubmitted: true,
        requirementsDue: const ['individual.id_number'],
      );
      // Enable the demo dashboard link while the displayed status stays restricted.
      await repository.refreshOrganizationAccountStatus('org1');
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const Scaffold(body: OrgFinanceScreen()),
        beforePump: (app) => app.switchToOrganization('org1'),
      );
      await enterOrganizer(tester, harness, 'org1');

      final section = find.byKey(const Key('org-finance-stripe-section'));
      final badge = tester.widget<EpBadge>(
        find.byKey(const Key('org-finance-stripe-badge')),
      );
      expect(badge.label.toUpperCase(), 'SETUP IN PROGRESS — FINISH IN STRIPE');
      expect(badge.tone, EpBadgeTone.attention);
      expect(find.text('CONTINUE SETUP'), findsOneWidget);
      expect(find.text('NEEDS INFORMATION'), findsOneWidget);
      expect(find.text('individual.id_number'), findsOneWidget);
      expect(
        find.descendant(of: section, matching: find.text('ACTION NEEDED')),
        findsOneWidget,
      );

      final button = find.byKey(const Key('org-finance-tax-dashboard'));
      expect(
        find.descendant(of: button, matching: find.text('MANAGE IN STRIPE')),
        findsOneWidget,
      );
      harness.app.hostedUrlLauncher = (_) async {
        throw StateError('Could not open Stripe');
      };
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('org-finance-stripe-error')), findsOneWidget);
      expect(find.textContaining('Could not open Stripe'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      final launched = <String>[];
      harness.app.hostedUrlLauncher = (url) async => launched.add(url);
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(launched, ['https://demo.stripe/dashboard/org1']);
      expect(find.byKey(const Key('org-finance-stripe-error')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  for (final (state, flagged) in [
    (StripeAccountState.restricted, true),
    (StripeAccountState.enabled, false),
  ]) {
    testWidgets('band payouts tile flags ${state.name} and opens payouts', (
      tester,
    ) async {
      final auth = FakeAuthService();
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: _stripeStatusRepository(
          auth: auth,
          state: state,
          cardPaymentsStatus: state == StripeAccountState.enabled
              ? 'active'
              : null,
        ),
        home: const Scaffold(body: GigManagerScreen()),
        beforePump: (app) {
          app.switchToBand('b1');
          app.resetTo(Screen.gigMgr);
        },
      );

      final tile = find.byKey(const Key('band-dash-payouts'));
      await tester.scrollUntilVisible(tile, 180, scrollable: _myGigsList());
      expect(tile, findsOneWidget);
      final badge = find.descendant(
        of: tile,
        matching: find.byKey(const Key('band-dash-payouts-badge')),
      );
      expect(badge, flagged ? findsOneWidget : findsNothing);
      expect(
        find.descendant(of: tile, matching: find.text('SET UP')),
        flagged ? findsOneWidget : findsNothing,
      );
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.bandPayouts);
    });
  }

  testWidgets('band members do not see the payouts tile', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returnsStream(
          'myBands',
          () => Stream.value([
            BandMembership(band: DemoData.bands['b1']!, role: 'member'),
          ]),
        )
        ..returnsStream(
          'myOrganizations',
          () => Stream.value([
            OrganizationMembership(
              organization: DemoData.organizations['org1']!,
              role: OrganizationRole.manager,
            ),
          ]),
        ),
      home: const Scaffold(body: GigManagerScreen()),
      beforePump: (app) {
        app.switchToBand('b1');
        app.resetTo(Screen.gigMgr);
      },
    );

    // Scroll past everything so an absent row is not merely off screen.
    await tester.drag(_myGigsList(), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.textContaining('PAST · '), findsOneWidget);
    expect(find.byKey(const Key('band-dash-payouts')), findsNothing);
  });

  testWidgets('organization owner can set up Stripe and open its dashboard', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: OrgFinanceScreen()),
      beforePump: (app) => app.switchToOrganization('org1'),
    );
    await enterOrganizer(tester, harness, 'org1');
    final launched = <String>[];
    harness.app.hostedUrlLauncher = (url) async => launched.add(url);

    final badge = find.byKey(const Key('org-finance-stripe-badge'));
    expect(tester.widget<EpBadge>(badge).label.toUpperCase(), 'SET UP');
    expect(
      find.text(
        'Not connected. Connect Stripe to sell tickets and receive payouts.',
      ),
      findsOneWidget,
    );
    final setup = find.byKey(const Key('org-finance-connect-stripe'));
    expect(
      find.descendant(of: setup, matching: find.text('CONNECT STRIPE')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('org-finance-stripe')), findsNothing);

    await tester.tap(setup);
    await tester.pumpAndSettle();
    expect(launched, ['https://demo.stripe/onboard/org1']);
    expect(
      tester.widget<EpBadge>(badge).label.toUpperCase(),
      'SETUP IN PROGRESS — FINISH IN STRIPE',
    );
    expect(find.textContaining('Setup in progress.'), findsOneWidget);
    expect(find.text('CONTINUE SETUP'), findsOneWidget);

    // Refresh fetches the status from the repository again.
    harness.app.organizationStripeStatus = null;
    await tester.tap(find.byKey(const Key('org-finance-stripe-refresh')));
    await tester.pumpAndSettle();
    expect(
      harness.app.organizationStripeStatus?.state,
      StripeAccountState.onboarding,
    );

    await harness.app.handleStripeReturn(band: false, id: 'org1');
    await tester.pumpAndSettle();
    expect(tester.widget<EpBadge>(badge).label.toUpperCase(), 'CONNECTED');
    expect(
      find.text('Connected. Payouts go to your Stripe account.'),
      findsOneWidget,
    );
    expect(setup, findsNothing);
    await tester.tap(find.byKey(const Key('org-finance-stripe')));
    await tester.pumpAndSettle();
    expect(launched.last, 'https://demo.stripe/dashboard/org1');
  });

  testWidgets('organization managers do not see the owner Stripe section', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returnsStream(
          'myBands',
          () => Stream.value([
            BandMembership(band: DemoData.bands['b1']!, role: 'member'),
          ]),
        )
        ..returnsStream(
          'myOrganizations',
          () => Stream.value([
            OrganizationMembership(
              organization: DemoData.organizations['org1']!,
              role: OrganizationRole.manager,
            ),
          ]),
        ),
      home: const Scaffold(body: OrgSettingsScreen()),
      beforePump: (app) => app.switchToOrganization('org1'),
    );
    await enterOrganizer(tester, harness, 'org1');
    expect(harness.app.organizerRoleFor('org1'), OrganizationRole.manager);
    await tester.scrollUntilVisible(
      find.byKey(const Key('org-settings-deactivate')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('org-settings-stripe')), findsNothing);
    expect(find.byKey(const Key('org-settings-stripe-setup')), findsNothing);
  });

  testWidgets('organization Stripe errors are separate from save feedback', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: OrgFinanceScreen()),
      beforePump: (app) => app.switchToOrganization('org1'),
    );
    await enterOrganizer(tester, harness, 'org1');
    harness.app.hostedUrlLauncher = (_) async {
      throw StateError('Could not open Stripe');
    };
    final setup = find.byKey(const Key('org-finance-connect-stripe'));
    await tester.tap(setup);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('org-finance-stripe-error')), findsOneWidget);
    expect(find.textContaining('Could not open Stripe'), findsOneWidget);
    // Inline next to the controls, not in the finance snackbar.
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const Key('org-settings-save-error')), findsNothing);

    harness.app.hostedUrlLauncher = (_) async {};
    await tester.tap(setup);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('org-finance-stripe-error')), findsNothing);
    expect(find.textContaining('Setup in progress'), findsOneWidget);
    expect(find.text('CONTINUE SETUP'), findsOneWidget);
  });

  for (final band in [true]) {
    testWidgets('${band ? 'band' : 'organization'} lists Stripe requirements', (
      tester,
    ) async {
      final auth = FakeAuthService();
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: _stripeStatusRepository(
          auth: auth,
          state: StripeAccountState.restricted,
        ),
        home: Scaffold(
          body: band ? const BandPayoutsScreen() : const OrgSettingsScreen(),
        ),
        beforePump: (app) =>
            band ? app.switchToBand('b1') : app.switchToOrganization('org1'),
      );
      if (!band) await enterOrganizer(tester, harness, 'org1');
      await tester.scrollUntilVisible(
        find.text('CONTINUE SETUP'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('individual.verification.document'), findsOneWidget);
      expect(find.text('external_account'), findsOneWidget);
      expect(
        find.text(band ? 'Stripe needs more information' : 'Needs information'),
        findsOneWidget,
      );
    });
  }

  for (final enabled in [false, true]) {
    testWidgets('organization dash finance readiness when enabled=$enabled', (
      tester,
    ) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: _stripeStatusRepository(
          auth: auth,
          state: enabled
              ? StripeAccountState.enabled
              : StripeAccountState.onboarding,
        ),
        home: const Scaffold(body: OrgDashScreen()),
        beforePump: (app) => app.switchToOrganization('org1'),
      );
      await enterOrganizer(tester, harness, 'org1');

      expect(find.text('Stripe setup arrives with bookings'), findsNothing);
      expect(find.byKey(const Key('org-dash-readiness-stripe')), findsNothing);
      expect(find.byKey(const Key('org-dash-readiness-payouts')), findsNothing);

      final badge = find.byKey(const Key('org-dash-finance-badge'));
      final financeStep = find.byKey(const Key('org-setup-finance'));
      if (enabled) {
        // Profile and finance are done, so no module and no badge.
        expect(find.byKey(const Key('band-readiness')), findsNothing);
        expect(financeStep, findsNothing);
        expect(badge, findsNothing);
        return;
      }
      expect(find.byKey(const Key('band-readiness')), findsOneWidget);
      expect(financeStep, findsOneWidget);
      final finance = find.byKey(const Key('org-dash-command-finance'));
      await tester.scrollUntilVisible(
        finance,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.descendant(of: finance, matching: badge), findsOneWidget);
      await tester.tap(finance);
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.orgFinance);
    });
  }
}

const _ticketSalesCaption =
    'Fans pay you directly through Stripe; EarPlug adds its fee at checkout.';

class _PayoutRepository extends StubRepository {
  _PayoutRepository({
    required super.auth,
    Future<List<Payout>>? payoutsResponse,
  }) {
    returns(
      'payoutsForBand',
      payoutsResponse ??
          Future.value(<Payout>[
            Payout(
              id: 'p1',
              kind: PayoutKind.completion,
              amountMinor: 12000,
              currency: 'usd',
              status: PayoutStatus.paid,
              scheduledFor: DateTime(2026, 8, 1),
              paidAt: DateTime(2026, 8, 2),
            ),
            Payout(
              id: 'p2',
              kind: PayoutKind.forfeit,
              amountMinor: 4000,
              currency: 'usd',
              status: PayoutStatus.held,
              scheduledFor: DateTime(2026, 8, 3),
              holdReason: 'Waiting for bank details',
            ),
          ]),
    );
  }

  ({String bandId, DateTime from, DateTime to})? statementRange;

  @override
  Future<PayoutStatement> bandPayoutStatement(
    String bandId, {
    required DateTime from,
    required DateTime to,
  }) async {
    statementRange = (bandId: bandId, from: from, to: to);
    // These history fixtures are not registered with the demo booking ledger.
    // Return both rows deterministically so export tests do not depend on today.
    final payouts = await payoutsForBand(bandId);
    return PayoutStatement(
      payouts: [
        for (final payout in payouts)
          PayoutStatementRow(
            payoutId: payout.id,
            bookingId: 'bk1',
            bookingTitle: 'Demo booking',
            organizationName: 'Demo organizer',
            kind: payout.kind,
            status: payout.status,
            paidAt: payout.paidAt ?? payout.scheduledFor,
            netMinor: payout.amountMinor,
            reversedMinor: 0,
            currency: payout.currency,
          ),
      ],
      totalNetMinor: payouts.fold(
        0,
        (total, payout) => total + payout.amountMinor,
      ),
      truncated: false,
    );
  }
}

class _TruncatedPayoutRepository extends _PayoutRepository {
  _TruncatedPayoutRepository({required super.auth});

  @override
  Future<PayoutStatement> bandPayoutStatement(
    String bandId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final statement = await super.bandPayoutStatement(
      bandId,
      from: from,
      to: to,
    );
    return PayoutStatement(
      payouts: statement.payouts,
      totalNetMinor: statement.totalNetMinor,
      truncated: true,
    );
  }
}

/// The MY GIGS list on the GIGS page, which now carries the payouts entry.
Finder _myGigsList() => find
    .descendant(
      of: find.byType(BandMyGigsTab),
      matching: find.byType(Scrollable),
    )
    .first;

StubRepository _stripeStatusRepository({
  required AuthService auth,
  required StripeAccountState state,
  String? cardPaymentsStatus,
  bool? detailsSubmitted,
  List<String>? requirementsDue,
}) {
  final status = StripeAccountStatus(
    state: state,
    hasAccount: state != StripeAccountState.none,
    chargesEnabled: state == StripeAccountState.enabled,
    cardPaymentsStatus: cardPaymentsStatus,
    payoutsEnabled: state == StripeAccountState.enabled,
    detailsSubmitted: detailsSubmitted ?? (state == StripeAccountState.enabled),
    requirementsDue:
        requirementsDue ??
        (state == StripeAccountState.restricted
            ? const ['individual.verification.document', 'external_account']
            : const []),
  );
  return StubRepository(auth: auth)
    ..returns('bandPayoutStatus', status)
    ..returns('organizationStripeStatus', status);
}
