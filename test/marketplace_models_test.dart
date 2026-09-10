import 'dart:convert';

import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Map<String, dynamic> _jsonRoundTrip(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

void main() {
  test('derived status sets', () {
    const active = {
      BookingStatus.offerSent,
      BookingStatus.artistAccepted,
      BookingStatus.awaitingPayment,
      BookingStatus.confirmed,
      BookingStatus.completed,
      BookingStatus.paid,
      BookingStatus.disputed,
    };
    const live = {
      BookingStatus.confirmed,
      BookingStatus.completed,
      BookingStatus.paid,
    };
    for (final status in BookingStatus.values) {
      expect(
        status.isActive,
        active.contains(status),
        reason: status.wireValue,
      );
      expect(status.isLive, live.contains(status), reason: status.wireValue);
    }

    for (final status in [
      PaymentRecordStatus.pending,
      PaymentRecordStatus.checkoutOpen,
      PaymentRecordStatus.failed,
      PaymentRecordStatus.expired,
    ]) {
      expect(status.isOpen, isTrue);
    }
    for (final status in [
      PaymentRecordStatus.paid,
      PaymentRecordStatus.refunded,
      PaymentRecordStatus.partiallyRefunded,
      PaymentRecordStatus.unknown,
    ]) {
      expect(status.isOpen, isFalse);
    }

    for (final status in [
      ArtistApplicationStatus.submitted,
      ArtistApplicationStatus.underReview,
      ArtistApplicationStatus.shortlisted,
      ArtistApplicationStatus.offered,
    ]) {
      expect(status.isActive, isTrue);
    }
    for (final status in [
      ArtistApplicationStatus.booked,
      ArtistApplicationStatus.declined,
      ArtistApplicationStatus.withdrawn,
      ArtistApplicationStatus.expired,
    ]) {
      expect(status.isActive, isFalse);
    }
  });

  group('dispute and admin booking models', () {
    test('Booking admin viewer marker is optional and strictly boolean', () {
      expect(Booking.fromJson({}).viewerIsPlatformAdmin, isFalse);
      expect(DemoData.bookings['bk1']!.viewerIsPlatformAdmin, isFalse);
      expect(
        Booking.fromJson(
          _jsonRoundTrip({'viewerIsPlatformAdmin': true}),
        ).viewerIsPlatformAdmin,
        isTrue,
      );
      for (final value in <Object?>[null, false, 'true', 1, []]) {
        expect(
          Booking.fromJson({
            'viewerIsPlatformAdmin': value,
          }).viewerIsPlatformAdmin,
          isFalse,
        );
      }
    });
  });

  group('private booking and safety models', () {
    test('Opportunity reads private requests with no public venue', () {
      final opportunity = Opportunity.fromJson({
        'mode': 'privateBooking',
        'privateEvent': true,
        'privateLocationId': 'location-1',
        'venue': null,
        'venueType': 'private',
        'area': 'Mission',
      });
      expect(opportunity.mode, OpportunityMode.privateBooking);
      expect(opportunity.privateEvent, isTrue);
      expect(opportunity.privateLocationId, 'location-1');
      expect(opportunity.venue, isNull);
      expect(opportunity.venueType, VenueType.private);
      expect(opportunity.area, 'Mission');
      for (final json in <Map<String, dynamic>>[
        {},
        {'privateEvent': 'true', 'privateLocationId': 1},
      ]) {
        final empty = Opportunity.fromJson(json);
        expect(empty.privateEvent, isFalse);
        expect(empty.privateLocationId, isNull);
        expect(empty.mode, OpportunityMode.unknown);
      }
    });

    test('Booking parses withheld and disclosed private locations', () {
      const areaOnly = {
        'label': 'Courtyard',
        'area': 'Mission',
        'city': 'San Francisco',
      };
      for (final locationJson in [
        areaOnly,
        {...areaOnly, 'addr': null, 'lat': null, 'lng': null, 'notes': null},
      ]) {
        final booking = Booking.fromJson({
          'venue': null,
          'privateEvent': true,
          'privateLocation': locationJson,
        });
        expect(booking.venue, isNull);
        expect(booking.privateEvent, isTrue);
        expect(booking.privateLocation!.label, 'Courtyard');
        expect(booking.privateLocation!.area, 'Mission');
        expect(booking.privateLocation!.city, 'San Francisco');
        expect(booking.privateLocation!.addr, isNull);
        expect(booking.privateLocation!.lat, isNull);
        expect(booking.privateLocation!.lng, isNull);
        expect(booking.privateLocation!.notes, isNull);
        expect(booking.cancellationKind, isNull);
      }
      final disclosed = Booking.fromJson({
        'privateEvent': true,
        'privateLocation': {
          ...areaOnly,
          'addr': '120 Demo Lane',
          'lat': 37.75,
          'lng': -122,
          'notes': 'Side gate',
        },
        'cancellationKind': 'safety',
      });
      expect(disclosed.privateLocation!.addr, '120 Demo Lane');
      expect(disclosed.privateLocation!.lat, 37.75);
      expect(disclosed.privateLocation!.lng, -122.0);
      expect(disclosed.privateLocation!.notes, 'Side gate');
      expect(disclosed.cancellationKind, CancellationKind.safety);
      for (final value in ['future', 1]) {
        expect(
          Booking.fromJson({'cancellationKind': value}).cancellationKind,
          CancellationKind.unknown,
        );
      }
      for (final json in <Map<String, dynamic>>[
        {},
        {'venue': null, 'privateLocation': null},
        {
          'venue': false,
          'privateLocation': <Object?>[],
          'privateEvent': 'true',
        },
      ]) {
        final empty = Booking.fromJson(json);
        expect(empty.venue, isNull);
        expect(empty.privateLocation, isNull);
        expect(empty.privateEvent, isFalse);
        expect(empty.cancellationKind, isNull);
      }
      final malformed = BookingPrivateLocation.fromJson({
        'label': 7,
        'addr': false,
        'lat': 'bad',
        'lng': <Object?>[],
        'notes': 1,
      });
      expect(malformed.label, '');
      expect(malformed.addr, isNull);
      expect(malformed.lat, isNull);
      expect(malformed.lng, isNull);
      expect(malformed.notes, isNull);
    });

    test('host application fields and review rows parse optional kind', () {
      const applicationJson = {
        '_id': 'host-application',
        'kind': 'host',
        'orgType': 'privateHost',
        'hostDisplayName': 'Jordan',
        'hostPhone': '415-555-0100',
        'hostArea': 'Mission',
        'hostAgreementAcceptedAt': 1800000000000,
      };
      final application = OrganizationApplication.fromJson(applicationJson);
      expect(application.kind, ApplicationKind.host);
      expect(application.orgType, OrganizationType.privateHost);
      expect(application.hostDisplayName, 'Jordan');
      expect(application.hostPhone, '415-555-0100');
      expect(application.hostArea, 'Mission');
      expect(
        application.hostAgreementAcceptedAt,
        DateTime.fromMillisecondsSinceEpoch(1800000000000),
      );
      final row = AdminApplicationRow.fromJson({
        'kind': 'host',
        'application': applicationJson,
      });
      expect(row.kind, ApplicationKind.host);
      expect(row.application.kind, ApplicationKind.host);
      expect(
        AdminApplicationRow.fromJson({'kind': 'future'}).kind,
        ApplicationKind.unknown,
      );
      expect(AdminApplicationRow.fromJson({}).kind, isNull);
      for (final json in <Map<String, dynamic>>[
        {},
        {
          'kind': null,
          'hostDisplayName': 7,
          'hostPhone': false,
          'hostArea': <Object?>[],
          'hostAgreementAcceptedAt': 'bad',
        },
      ]) {
        final empty = OrganizationApplication.fromJson(json);
        expect(empty.kind, isNull);
        expect(empty.hostDisplayName, isNull);
        expect(empty.hostPhone, isNull);
        expect(empty.hostArea, isNull);
        expect(empty.hostAgreementAcceptedAt, isNull);
      }
      expect(
        OrganizationApplication.fromJson({'kind': 'future'}).kind,
        ApplicationKind.unknown,
      );
    });
  });

  group('paid ticket models', () {
    const gigJson = {
      '_id': 'gig-1',
      'title': 'Paid Show',
      'venueId': 'venue-1',
      'price': 0,
      'startsAt': 1800000000000,
      'doorsTime': '7PM / 8PM',
      'flyKey': 'paper',
      'lineup': ['band-1'],
      'genres': ['indie'],
      'desc': 'An evening of local bands.',
      'ticketing': 'paid',
      'ticketPriceMinor': 2500,
      'cap': '40',
    };
    const ticketGigJson = {
      'id': 'gig-1',
      'title': 'Paid Show',
      'slug': 'paid-show',
      'startsAt': 1800000000000,
      'doorsAt': 1799996400000,
      'venueName': 'The Vault',
      'lifecycle': 'published',
    };

    test('GigProject parses paid ticketing and nullable ticket fields', () {
      const projectJson = {
        '_id': 'project-1',
        'bandId': 'band-1',
        'status': 'draft',
        'revision': 1,
        'price': 0,
        'flyKey': 'paper',
        'overlay': true,
        'desc': 'An evening of local bands.',
        'ticketing': 'paid',
        'cap': '40',
        'updatedAt': 1800000000000,
        'performers': <Map<String, dynamic>>[],
      };
      final project = GigProject.fromJson(
        _jsonRoundTrip({
          ...projectJson,
          'ticketPriceMinor': 2500.0,
          'ticketCapacity': 40.0,
        }),
      );
      expect(project.ticketing, Ticketing.paid);
      expect(project.ticketPriceMinor, 2500);
      expect(project.ticketCapacity, 40);

      final missing = GigProject.fromJson(_jsonRoundTrip(projectJson));
      expect(missing.ticketing, Ticketing.paid);
      expect(missing.ticketPriceMinor, isNull);
      expect(missing.ticketCapacity, isNull);

      final explicitNull = GigProject.fromJson({
        ...projectJson,
        'ticketPriceMinor': null,
        'ticketCapacity': null,
      });
      expect(explicitNull.ticketPriceMinor, isNull);
      expect(explicitNull.ticketCapacity, isNull);
    });

    test('Gig parses band and organization ticket sellers', () {
      for (final (kind, name) in [
        (TicketSellerKind.band, 'Test Band'),
        (TicketSellerKind.organization, 'Test Org'),
      ]) {
        final gig = Gig.fromJson(
          _jsonRoundTrip({
            ...gigJson,
            'ticketSeller': {'kind': kind.name, 'name': name},
          }),
        );
        expect(gig.ticketSeller, isNotNull);
        expect(gig.ticketSeller!.kind, kind);
        expect(gig.ticketSeller!.name, name);
      }
    });

    test('Gig accepts missing and null ticket sellers', () {
      expect(Gig.fromJson(gigJson).ticketSeller, isNull);
      expect(
        Gig.fromJson({...gigJson, 'ticketSeller': null}).ticketSeller,
        isNull,
      );
    });

    test('Gig uses minor-unit pricing and defaults the currency to USD', () {
      final gig = Gig.fromJson(gigJson);
      expect(gig.tix, Ticketing.paid);
      expect(gig.ticketPriceMinor, 2500);
      expect(gig.ticketCurrency, isNull);
      expect(gig.priceLabel, r'$25.00');
      expect(gig.sellsTickets, isTrue);
      expect(
        Gig.fromJson({...gigJson, 'ticketCurrency': 'eur'}).priceLabel,
        'EUR 25.00',
      );
    });

    test(
      'Gig price-label fallbacks for external ticketing and missing minor-unit price',
      () {
        expect(
          Gig.fromJson({
            ...gigJson,
            'ticketing': 'external',
            'price': 12,
          }).priceLabel,
          r'$12',
        );
        expect(
          Gig.fromJson({
            ...gigJson,
            'ticketPriceMinor': null,
            'price': 12,
          }).priceLabel,
          r'$12',
        );
      },
    );

    test('Gig retains ticket pricing when copied or relabeled', () {
      final gig = Gig.fromJson({...gigJson, 'ticketCurrency': 'usd'});
      final copy = gig.copyWith(going: 2);
      expect(copy.ticketPriceMinor, 2500);
      expect(copy.ticketCurrency, 'usd');
      expect(gig.sameListing(copy), isTrue);
      expect(gig.sameListing(gig.copyWith(ticketPriceMinor: 3000)), isFalse);
      expect(gig.sameListing(gig.copyWith(ticketCurrency: 'eur')), isFalse);
      final relabeled = gig.relabeled(now: gig.startsAt);
      expect(relabeled.ticketPriceMinor, 2500);
      expect(relabeled.ticketCurrency, 'usd');
    });

    test('Opportunity parses nullable paid-ticket fields', () {
      final opportunity = Opportunity.fromJson({
        'ticketing': 'paid',
        'ticketPriceMinor': 2500.0,
        'ticketCapacity': 40.0,
        'ticketCurrency': 'usd',
      });
      expect(opportunity.ticketing, OpportunityTicketing.paid);
      expect(opportunity.ticketPriceMinor, 2500);
      expect(opportunity.ticketCapacity, 40);
      expect(opportunity.ticketCurrency, 'usd');
      final missing = Opportunity.fromJson(const {});
      expect(missing.ticketPriceMinor, isNull);
      expect(missing.ticketCapacity, isNull);
      expect(missing.ticketCurrency, isNull);
    });

    test('TicketGigSummary parses lifecycles with a published fallback', () {
      for (final value in GigLifecycle.values) {
        expect(
          TicketGigSummary.fromJson({
            ...ticketGigJson,
            'lifecycle': value.name,
          }).lifecycle,
          value,
        );
      }
      for (final value in ['bogus', null, 42]) {
        expect(
          TicketGigSummary.fromJson({
            ...ticketGigJson,
            'lifecycle': value,
          }).lifecycle,
          GigLifecycle.published,
        );
      }
    });

    test('TicketReservation parses pricing and expiry', () {
      final reservation = TicketReservation.fromJson({
        'orderId': 'order-1',
        'quantity': 2.0,
        'unitPriceMinor': 2500,
        'unitFeeMinor': 175,
        'subtotalMinor': 5000,
        'feeMinor': 350,
        'totalMinor': 5350,
        'currency': 'usd',
        'reservedUntil': 1800000000000,
      });
      expect(reservation.orderId, 'order-1');
      expect(reservation.quantity, 2);
      expect(reservation.unitPriceMinor, 2500);
      expect(reservation.unitFeeMinor, 175);
      expect(reservation.subtotalMinor, 5000);
      expect(reservation.feeMinor, 350);
      expect(reservation.totalMinor, 5350);
      expect(reservation.currency, 'usd');
      expect(reservation.total, const Money(5350, 'usd'));
      expect(
        reservation.reservedUntil,
        DateTime.fromMillisecondsSinceEpoch(1800000000000),
      );
    });

    test('TicketSummary parses the ticket and nested gig', () {
      final ticket = TicketSummary.fromJson({
        'id': 'ticket-1',
        'orderId': 'order-1',
        'gigId': 'gig-1',
        'token': 'earplug:ticket:v2:token-1',
        'status': 'used',
        'checkedInAt': 1800000000000,
        'createdAt': 1799900000000,
        'gig': ticketGigJson,
      });
      expect(ticket.id, 'ticket-1');
      expect(ticket.orderId, 'order-1');
      expect(ticket.gigId, 'gig-1');
      expect(ticket.token, 'earplug:ticket:v2:token-1');
      expect(ticket.status, TicketStatus.used);
      expect(
        ticket.checkedInAt,
        DateTime.fromMillisecondsSinceEpoch(1800000000000),
      );
      expect(
        ticket.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1799900000000),
      );
      expect(ticket.gig.id, 'gig-1');
      expect(ticket.gig.title, 'Paid Show');
      expect(ticket.gig.slug, 'paid-show');
      expect(
        ticket.gig.startsAt,
        DateTime.fromMillisecondsSinceEpoch(1800000000000),
      );
      expect(
        ticket.gig.doorsAt,
        DateTime.fromMillisecondsSinceEpoch(1799996400000),
      );
      expect(ticket.gig.venueName, 'The Vault');
      expect(ticket.gig.lifecycle, GigLifecycle.published);
      expect(TicketSummary.fromJson({'_id': 'ticket-2'}).id, 'ticket-2');
      expect(TicketGigSummary.fromJson({'_id': 'gig-2'}).id, 'gig-2');
    });

    test('TicketOrderState parses the checkout state and total', () {
      final state = TicketOrderState.fromJson({
        'orderId': 'order-1',
        'gigId': 'gig-1',
        'gigSlug': 'paid-show',
        'status': 'paid',
        'quantity': 2,
        'totalMinor': 5350,
        'currency': 'usd',
      });
      expect(state.orderId, 'order-1');
      expect(state.gigId, 'gig-1');
      expect(state.gigSlug, 'paid-show');
      expect(state.status, TicketOrderStatus.paid);
      expect(state.quantity, 2);
      expect(state.totalMinor, 5350);
      expect(state.currency, 'usd');
      expect(state.total, const Money(5350, 'usd'));
    });

    test('TicketSales parses counts and Money totals', () {
      final sales = TicketSales.fromJson({
        'capacity': 40,
        'sold': 2,
        'reserved': 3,
        'available': 35,
        'ordersPaid': 1,
        'grossMinor': 5000,
        'feeMinor': 350,
        'netMinor': 5000,
        'currency': 'usd',
      });
      expect(sales.capacity, 40);
      expect(sales.sold, 2);
      expect(sales.reserved, 3);
      expect(sales.available, 35);
      expect(sales.ordersPaid, 1);
      expect(sales.grossMinor, 5000);
      expect(sales.feeMinor, 350);
      expect(sales.netMinor, 5000);
      expect(sales.currency, 'usd');
      expect(sales.gross, const Money(5000, 'usd'));
      expect(sales.fees, const Money(350, 'usd'));
      expect(sales.net, const Money(5000, 'usd'));
    });

    test('defensive parsing never throws', () {
      // Band.fromJson and Gig.fromJson require complete core payloads and throw
      // on {}. Their copy/merge and ownership/pricing tests retain valid fixtures.
      final parsers = <String, Object? Function(Map<String, dynamic>)>{
        'AdminApplicationPage': AdminApplicationPage.fromJson,
        'AdminApplicationRow': AdminApplicationRow.fromJson,
        'AdminBookingRow': AdminBookingRow.fromJson,
        'AdminBookingsPage': AdminBookingsPage.fromJson,
        'AdminOverview': AdminOverview.fromJson,
        'ApplicantRow': ApplicantRow.fromJson,
        'ApplicationCounts': ApplicationCounts.fromJson,
        'ApplicationDocument': ApplicationDocument.fromJson,
        'ApplicationVenueDraft': ApplicationVenueDraft.fromJson,
        'ArtistApplication': ArtistApplication.fromJson,
        'ArtistInsights': ArtistInsights.fromJson,
        'Attribution': Attribution.fromJson,
        'BandApplication': BandApplication.fromJson,
        'Booking': Booking.fromJson,
        'BookingOffer': BookingOffer.fromJson,
        'BookingPrivateLocation': BookingPrivateLocation.fromJson,
        'BookingReviews': BookingReviews.fromJson,
        'BookingVenue': BookingVenue.fromJson,
        'BrowseItem': BrowseItem.fromJson,
        'CheckoutStatus': CheckoutStatus.fromJson,
        'Dispute': Dispute.fromJson,
        'DisputeRow': DisputeRow.fromJson,
        'DisputesPage': DisputesPage.fromJson,
        'DoorCounts': DoorCounts.fromJson,
        'EstimatedDraw': EstimatedDraw.fromJson,
        'FeeBreakdown': FeeBreakdown.fromJson,
        'FeeRates': FeeRates.fromJson,
        'FinanceBookings': FinanceBookings.fromJson,
        'FinanceOverview': FinanceOverview.fromJson,
        'FinanceSnapshot': FinanceSnapshot.fromJson,
        'FinanceTickets': FinanceTickets.fromJson,
        'FinanceTransaction': FinanceTransaction.fromJson,
        'InsightBucket': InsightBucket.fromJson,
        'InsightPartition': InsightPartition.fromJson,
        'InsightsBand': InsightsBand.fromJson,
        'InsightsWindow': InsightsWindow.fromJson,
        'OfferInstallment': OfferInstallment.fromJson,
        'Opportunity': Opportunity.fromJson,
        'OpportunityPage': OpportunityPage.fromJson,
        'OpportunitySlot': OpportunitySlot.fromJson,
        'Organization': Organization.fromJson,
        'OrganizationApplication': OrganizationApplication.fromJson,
        'PaymentRecord': PaymentRecord.fromJson,
        'Payout': Payout.fromJson,
        'PendingPayment': (json) =>
            PendingPayment.fromJson(json, currency: 'eur'),
        'PrivateLocation': PrivateLocation.fromJson,
        'PublicReview': PublicReview.fromJson,
        'RefundPreview': RefundPreview.fromJson,
        'RefundRecord': RefundRecord.fromJson,
        'Review': Review.fromJson,
        'ReviewSummary': ReviewSummary.fromJson,
        'SafetyReport': SafetyReport.fromJson,
        'SafetyReportRow': SafetyReportRow.fromJson,
        'SafetyReportsPage': SafetyReportsPage.fromJson,
        'StatementExport': StatementExport.fromJson,
        'StatementTotal': StatementTotal.fromJson,
        'StatementTransaction': StatementTransaction.fromJson,
        'StripeAccountStatus': StripeAccountStatus.fromJson,
        'TicketDoorResult': TicketDoorResult.fromJson,
        'TicketGigSummary': TicketGigSummary.fromJson,
        'TicketOrderState': TicketOrderState.fromJson,
        'TicketReservation': TicketReservation.fromJson,
        'TicketSales': TicketSales.fromJson,
        'TicketSummary': TicketSummary.fromJson,
        'TransactionsPage': TransactionsPage.fromJson,
        'Venue': Venue.fromJson,
        'VenueConsent': VenueConsent.fromJson,
        'VenueConsentRow': VenueConsentRow.fromJson,
      };
      const malformed = <String, dynamic>{
        '_id': 7,
        'id': false,
        'disputeId': 7,
        'bookingId': false,
        'bandId': false,
        'consentId': 7,
        'opportunityId': false,
        'venueId': <Object?>[],
        'venueOrganizationId': <String, dynamic>{},
        'requestingOrganizationId': false,
        'organizationId': false,
        'paymentRecordId': 8,
        'reportId': 7,
        'orderId': 7,
        'ticketOrderId': 4,
        'reviewId': false,
        'side': 42,
        'category': 42,
        'status': 42,
        'resolution': 42,
        'bookingStatus': 42,
        'opportunityStatus': 42,
        'state': 42,
        'kind': 42,
        'fundsState': 42,
        'paymentStatus': 42,
        'authorSide': 42,
        'reporterSide': 42,
        'template': 42,
        'cancelledBy': 42,
        'reason': 42,
        'response': 42,
        'role': 42,
        'slotRole': false,
        'text': false,
        'message': 7,
        'note': <Object?>[],
        'notes': false,
        'label': 9,
        'key': false,
        'name': <Object?>[],
        'addr': false,
        'area': false,
        'city': false,
        'slug': 7,
        'currency': 7,
        'bookingTitle': false,
        'opportunityTitle': <Object?>[],
        'organizationName': 1,
        'bandName': <Object?>[],
        'venueName': 1,
        'requestingOrganizationName': <Object?>[],
        'adminNote': 1,
        'openDisputeId': false,
        'holdReason': 7,
        'termsNotes': false,
        'counterpartyEmail': 7,
        'contactEmail': false,
        'stripeRef': <Object?>[],
        'source': 42,
        'requestedRefundMinor': 'bad',
        'resolvedRefundMinor': 'bad',
        'paidMinor': 'bad',
        'refundedMinor': false,
        'bookingCommissionBps': 'bad',
        'ticketingFeeBps': false,
        'ticketingFeeFixedMinor': <Object?>[],
        'amountMinor': 'bad',
        'refundMinor': false,
        'forfeitedMinor': 'bad',
        'artistPayoutMinor': 'bad',
        'shareBps': 'bad',
        'grossMinor': false,
        'commissionBps': 'bad',
        'commissionMinor': 'bad',
        'artistNetMinor': 'bad',
        'availableMinor': 'bad',
        'pendingMinor': false,
        'dueMinor': <Object?>[],
        'disputedMinor': <String, dynamic>{},
        'feeMinor': <Object?>[],
        'refundedOrgMinor': 'bad',
        'netMinor': 'bad',
        'estimatedProcessingMinor': true,
        'guaranteeMinor': 'bad',
        'askMinor': 'bad',
        'quantity': 'bad',
        'unitPriceMinor': 'bad',
        'unitFeeMinor': 'bad',
        'subtotalMinor': 'bad',
        'totalMinor': 'bad',
        'revision': 'bad',
        'installmentIndex': 'bad',
        'activeCount': 'bad',
        'ordersPaid': 'bad',
        'rating': 'bad',
        'count': 'bad',
        'mean': 'bad',
        'completedBookings': false,
        'cancellations': <Object?>[],
        'events': 'bad',
        'checkIns': <Object?>[],
        'referral': <Object?>[],
        'follow': 'bad',
        'unattributed': false,
        'low': false,
        'high': 'bad',
        'confidence': 42,
        'basis': 42,
        'followers': 'bad',
        'rsvpTotal': 'bad',
        'ticketsSold': <Object?>[],
        'returningAttendees': <String, dynamic>{},
        'lat': 'bad',
        'lng': <Object?>[],
        'createdAt': 'bad',
        'updatedAt': 'bad',
        'resolvedAt': 'bad',
        'decidedAt': 'bad',
        'startsAt': 'bad',
        'endsAt': false,
        'doorsAt': 'bad',
        'dueAt': <String, dynamic>{},
        'paidAt': false,
        'scheduledFor': 'bad',
        'paymentDueAt': 'bad',
        'fetchedAt': 'bad',
        'occurredAt': 'bad',
        'firstStartsAt': 'bad',
        'lastStartsAt': <String, dynamic>{},
        'reservedUntil': 'bad',
        'checkedInAt': 'bad',
        'submittedAt': 'bad',
        'visibleAt': 'bad',
        'windowClosesAt': 'bad',
        'configured': 'true',
        'slotRequired': 'true',
        'stripeAccountId': 'acct_demo',
        'chargesEnabled': 'true',
        'payoutsEnabled': 1,
        'detailsSubmitted': 'true',
        'canPay': 'true',
        'stripeReady': 'true',
        'canSubmit': 'true',
        'truncated': 'true',
        'suppressed': 'true',
        'returningSuppressed': 'true',
        'fee': 'not a map',
        'venue': false,
        'currentOffer': 42,
        'gig': false,
        'application': false,
        'opportunity': false,
        'reviewSummary': 'not a map',
        'mine': 42,
        'theirs': <Object?>[],
        'snapshot': <Object?>[],
        'bookings': false,
        'tickets': 'bad',
        'band': false,
        'window': <Object?>[],
        'attribution': false,
        'byArea': <Object?>[],
        'byVenueType': 3,
        'byWeekday': true,
        'byPriceBand': 'bad',
        'estimatedDraw': false,
        'counts': false,
        'hostApplications': false,
        'requirementsDue': 'external_account',
        'payoutHoldReasons': [false, 'future_hold', null],
        'genres': ['indie', null, 12],
        'invitedBandIds': [null, 'band-1'],
        'categories': ['sound', 42, null],
        'installments': [null, 'bad'],
        'slots': [false, <String, dynamic>{}],
        'pendingPayments': [null, 'bad'],
        'buckets': [null, false],
        'page': [null, false],
        'items': false,
        'isDone': 'true',
        'continueCursor': 3,
        'csv': false,
        'rows': 'bad',
        'transactions': [false, <String, dynamic>{}],
        'totalsByKind': [null, <String, dynamic>{}],
      };
      final payloads = <String, Map<String, dynamic>>{
        'empty': {},
        'null': {for (final key in malformed.keys) key: null},
        'wrong types': malformed,
        'non-finite': {
          ...malformed,
          'bookingCommissionBps': double.nan,
          'amountMinor': double.nan,
          'grossMinor': double.nan,
          'paidMinor': double.nan,
          'availableMinor': double.nan,
          'createdAt': double.nan,
          'startsAt': double.nan,
          'dueAt': double.nan,
          'fetchedAt': double.nan,
          'firstStartsAt': double.nan,
          'quantity': double.nan,
          'count': double.nan,
          'events': double.nan,
        },
      };
      for (final entry in parsers.entries) {
        final parser = entry.value;
        for (final payload in payloads.entries) {
          expect(
            () => parser(payload.value),
            returnsNormally,
            reason: '${entry.key}.fromJson(${payload.key})',
          );
        }
      }

      final enums = <String, (Object? Function(Object?), Object?)>{
        'AddressDisclosure.fromWire': (
          AddressDisclosure.fromWire,
          AddressDisclosure.public,
        ),
        'AdminBookingFilter.fromWire': (
          AdminBookingFilter.fromWire,
          AdminBookingFilter.unknown,
        ),
        'ApplicationDecision.fromWire': (
          ApplicationDecision.fromWire,
          ApplicationDecision.underReview,
        ),
        'ApplicationKind.fromWire': (
          ApplicationKind.fromWire,
          ApplicationKind.unknown,
        ),
        'ArtistApplicationReviewAction.fromWire': (
          ArtistApplicationReviewAction.fromWire,
          ArtistApplicationReviewAction.underReview,
        ),
        'ArtistApplicationStatus.fromWire': (
          ArtistApplicationStatus.fromWire,
          ArtistApplicationStatus.submitted,
        ),
        'BookingCancelledBy.fromWire': (
          BookingCancelledBy.fromWire,
          BookingCancelledBy.system,
        ),
        'BookingSide.fromWire': (BookingSide.fromWire, BookingSide.artist),
        'BookingStatus.fromWire': (
          BookingStatus.fromWire,
          BookingStatus.unknown,
        ),
        'CancellationKind.fromWire': (
          CancellationKind.fromWire,
          CancellationKind.unknown,
        ),
        'CancellationTemplate.fromWire': (
          CancellationTemplate.fromWire,
          CancellationTemplate.standard,
        ),
        'DisputeCategory.fromWire': (
          DisputeCategory.fromWire,
          DisputeCategory.unknown,
        ),
        'DisputeResolution.fromWire': (
          DisputeResolution.fromWire,
          DisputeResolution.unknown,
        ),
        'DisputeSide.fromWire': (DisputeSide.fromWire, DisputeSide.unknown),
        'DisputeStatus.fromWire': (
          DisputeStatus.fromWire,
          DisputeStatus.unknown,
        ),
        'DrawBasis.fromWire': (DrawBasis.fromWire, DrawBasis.unknown),
        'DrawConfidence.fromWire': (
          DrawConfidence.fromWire,
          DrawConfidence.unknown,
        ),
        'FundsState.fromWire': (FundsState.fromWire, FundsState.unknown),
        'GigOwnerKind.fromWire': (GigOwnerKind.fromWire, GigOwnerKind.band),
        'LedgerKind.fromWire': (LedgerKind.fromWire, LedgerKind.unknown),
        'OfferResponse.fromWire': (
          OfferResponse.fromWire,
          OfferResponse.withdrawn,
        ),
        'OpportunityMode.fromWire': (
          OpportunityMode.fromWire,
          OpportunityMode.unknown,
        ),
        'OpportunityStatus.fromWire': (
          OpportunityStatus.fromWire,
          OpportunityStatus.draft,
        ),
        'OpportunityTicketing.fromWire': (
          OpportunityTicketing.fromWire,
          OpportunityTicketing.none,
        ),
        'OpportunityVisibility.fromWire': (
          OpportunityVisibility.fromWire,
          OpportunityVisibility.publicListing,
        ),
        'OrganizationApplicationStatus.fromWire': (
          OrganizationApplicationStatus.fromWire,
          OrganizationApplicationStatus.draft,
        ),
        'OrganizationRole.fromWire': (
          OrganizationRole.fromWire,
          OrganizationRole.door,
        ),
        'OrganizationStatus.fromWire': (
          OrganizationStatus.fromWire,
          OrganizationStatus.pending,
        ),
        'OrganizationType.fromWire': (
          OrganizationType.fromWire,
          OrganizationType.other,
        ),
        'PaymentRecordStatus.fromWire': (
          PaymentRecordStatus.fromWire,
          PaymentRecordStatus.unknown,
        ),
        'PayoutKind.fromWire': (PayoutKind.fromWire, PayoutKind.completion),
        'PayoutStatus.fromWire': (PayoutStatus.fromWire, PayoutStatus.unknown),
        'RefundReason.fromWire': (RefundReason.fromWire, RefundReason.unknown),
        'RefundStatus.fromWire': (RefundStatus.fromWire, RefundStatus.unknown),
        'SafetyCategory.fromWire': (
          SafetyCategory.fromWire,
          SafetyCategory.unknown,
        ),
        'SlotRole.fromWire': (SlotRole.fromWire, SlotRole.support),
        'SlotStatus.fromWire': (SlotStatus.fromWire, SlotStatus.open),
        'StripeAccountState.fromWire': (
          StripeAccountState.fromWire,
          StripeAccountState.unknown,
        ),
        'TicketDoorKind.fromWire': (
          TicketDoorKind.fromWire,
          TicketDoorKind.unknown,
        ),
        'TicketOrderStatus.fromWire': (
          TicketOrderStatus.fromWire,
          TicketOrderStatus.unknown,
        ),
        'TicketStatus.fromWire': (TicketStatus.fromWire, TicketStatus.unknown),
        'VenueConsentStatus.fromWire': (
          VenueConsentStatus.fromWire,
          VenueConsentStatus.unknown,
        ),
        'VenueType.fromWire': (VenueType.fromWire, VenueType.other),
        'AgeRequirement.fromJson': (
          AgeRequirement.fromJson,
          AgeRequirement.allAges,
        ),
        // These enums have no fromWire method; use their existing JSON parsers.
        'Ticketing via Gig.fromJson': (
          (value) => Gig.fromJson({...gigJson, 'ticketing': value}).tix,
          Ticketing.rsvp,
        ),
        'GigLifecycle via TicketGigSummary.fromJson': (
          (value) => TicketGigSummary.fromJson({'lifecycle': value}).lifecycle,
          GigLifecycle.published,
        ),
      };
      for (final entry in enums.entries) {
        final (fromWire, fallback) = entry.value;
        for (final value in [null, 'bogus', 42]) {
          expect(fromWire(value), fallback, reason: '${entry.key}($value)');
        }
      }
    });
  });

  group('Venue.fromJson', () {
    test('treats legacy payloads as exact and capability-unaware', () {
      final venue = Venue.fromJson({
        '_id': 'legacy-venue',
        'name': 'Legacy Hall',
        'area': 'Oakland',
        'addr': '100 Broadway, Oakland',
        'lat': 37.8044,
        'lng': -122.2712,
      });

      expect(venue.precision, LocationPrecision.exact);
      expect(venue.supportsApproxLocation, isFalse);
      expect(venue.exactAddress, venue.addr);
      expect(venue.exactPoint, venue.point);
      expect(venue.approx.centroid, venue.point);
      expect(venue.approx.label, venue.area);
      expect(venue.description, isNull);
      expect(venue.venueType, isNull);
      expect(venue.capacityPublic, isNull);
    });

    test('uses the approximate centroid when exact address is withheld', () {
      final venue = Venue.fromJson({
        '_id': 'private-venue',
        'name': 'Private Room',
        'area': 'Mission, San Francisco',
        'addr': 'Mission, San Francisco',
        'lat': 37.75,
        'lng': -122.42,
        'slug': 'private-room',
        'description': 'Cozy backroom bar with a small stage.',
        'venueType': 'bar',
        'capacityPublic': 180,
        'approxLocation': {
          'lat': 37.7599,
          'lng': -122.4148,
          'label': 'Mission, San Francisco',
        },
        'addressDisclosure': 'onTicket',
        'exactAddr': null,
        'verified': true,
      });

      expect(venue.precision, LocationPrecision.approximate);
      expect(venue.supportsApproxLocation, isTrue);
      expect(venue.point, const LatLng(37.7599, -122.4148));
      expect(venue.exactPoint, isNull);
      expect(venue.exactAddress, isNull);
      expect(venue.description, 'Cozy backroom bar with a small stage.');
      expect(venue.venueType, VenueType.bar);
      expect(venue.capacityPublic, 180);
    });
  });

  test('OrganizationApplication tolerates missing optional fields', () {
    final application = OrganizationApplication.fromJson({
      '_id': 'application-1',
      'status': 'draft',
      'orgName': 'New Room',
      'orgType': 'venueOperator',
      'contactName': 'Alex Doe',
      'businessEmail': 'alex@example.com',
      'revision': 1,
      'createdAt': 1000,
      'updatedAt': 2000,
    });

    expect(application.website, isNull);
    expect(application.organizerAgreementAcceptedAt, isNull);
    expect(application.phone, isNull);
    expect(application.venue, isNull);
    expect(application.documents, isEmpty);
    expect(application.reviewNote, isNull);
    expect(application.decidedAt, isNull);
    expect(application.resultingOrganizationId, isNull);
    expect(application.resultingVenueId, isNull);
    expect(application.editable, isTrue);

    expect(() => OrganizationApplication.fromJson(const {}), returnsNormally);
    final empty = OrganizationApplication.fromJson(const {});
    expect(empty.status, OrganizationApplicationStatus.draft);
    expect(empty.orgType, OrganizationType.other);
    expect(empty.documents, isEmpty);
    expect(empty.revision, 0);
  });

  test('OrganizationApplication parses organizer agreement acceptance', () {
    final application = OrganizationApplication.fromJson(
      _jsonRoundTrip({'organizerAgreementAcceptedAt': 1800000000000.0}),
    );
    expect(
      application.organizerAgreementAcceptedAt,
      DateTime.fromMillisecondsSinceEpoch(1800000000000),
    );

    for (final value in <Object?>[null, '1800000000000', false, [], {}]) {
      expect(
        OrganizationApplication.fromJson({
          'organizerAgreementAcceptedAt': value,
        }).organizerAgreementAcceptedAt,
        isNull,
      );
    }
  });

  group('Booking.fromJson', () {
    const feeJson = {
      'grossMinor': 15000,
      'commissionBps': 1000,
      'commissionMinor': 1500,
      'artistNetMinor': 13500,
      'currency': 'usd',
    };
    const offerJson = {
      'revision': 2,
      'message': 'Looking forward to the show.',
      'sentAt': 1799800000000,
      'expiresAt': 1799900000000,
      'response': 'accepted',
      'installments': [
        {'label': 'Full payment', 'amountMinor': 15000, 'dueAt': 1799990000000},
      ],
    };
    const venueJson = {
      '_id': 'venue-1',
      'name': 'Signal Room',
      'slug': 'signal-room',
      'approxLabel': 'Oakland',
      'exactAddress': '100 Broadway, Oakland',
    };
    const bookingJson = {
      '_id': 'booking-1',
      'opportunityId': 'opportunity-1',
      'opportunityTitle': 'Friday Showcase',
      'opportunitySlug': 'friday-showcase',
      'slotId': 'slot-1',
      'slotRole': 'headliner',
      'slotRequired': true,
      'organizationId': 'organization-1',
      'organizationName': 'Signal Collective',
      'bandId': 'band-1',
      'bandName': 'The Night Shifts',
      'bandSlug': 'the-night-shifts',
      'applicationId': 'application-1',
      'status': 'cancelled_by_organizer',
      'revision': 3,
      'startsAt': 1800000000000,
      'doorsAt': 1799996400000,
      'fee': feeJson,
      'cancellationTemplate': 'standard',
      'termsNotes': 'House PA provided.',
      'organizerAcceptedTermsAt': 1799800000000,
      'artistAcceptedTermsAt': 1799810000000,
      'confirmedAt': 1799820000000,
      'completedAt': 1800010000000,
      'cancelledAt': 1800020000000,
      'cancelledBy': 'organizer',
      'cancelReason': 'Venue unavailable.',
      'expiresAt': 1799900000000,
      'currentOffer': offerJson,
      'venue': venueJson,
      'publicGigId': 'gig-1',
      'publicGigSlug': 'night-shifts-at-signal-room',
      'counterpartyEmail': 'band@example.com',
      'viewerSide': 'organizer',
    };

    test('preserves nulls for every nullable booking and venue field', () {
      final booking = Booking.fromJson({
        ...bookingJson,
        'doorsAt': null,
        'termsNotes': null,
        'artistAcceptedTermsAt': null,
        'confirmedAt': null,
        'completedAt': null,
        'cancelledAt': null,
        'cancelledBy': null,
        'cancelReason': null,
        'expiresAt': null,
        'currentOffer': null,
        'publicGigId': null,
        'publicGigSlug': null,
        'counterpartyEmail': null,
        'venue': {
          ...venueJson,
          'slug': null,
          'approxLabel': null,
          'exactAddress': null,
        },
      });

      expect(booking.doorsAt, isNull);
      expect(booking.termsNotes, isNull);
      expect(booking.artistAcceptedTermsAt, isNull);
      expect(booking.confirmedAt, isNull);
      expect(booking.completedAt, isNull);
      expect(booking.cancelledAt, isNull);
      expect(booking.cancelledBy, isNull);
      expect(booking.cancelReason, isNull);
      expect(booking.expiresAt, isNull);
      expect(booking.currentOffer, isNull);
      expect(booking.publicGigId, isNull);
      expect(booking.publicGigSlug, isNull);
      expect(booking.counterpartyEmail, isNull);
      expect(booking.venue!.slug, isNull);
      expect(booking.venue!.approxLabel, isNull);
      expect(booking.venue!.exactAddress, isNull);
    });

    test(
      'BookingOffer preserves unanswered responses and optional messages',
      () {
        final offer = BookingOffer.fromJson({
          ...offerJson,
          'message': null,
          'response': null,
        });
        expect(offer.message, isNull);
        expect(offer.response, isNull);
        expect(BookingOffer.fromJson(const {}).installments, isEmpty);
        final malformed = BookingOffer.fromJson({
          'response': 'something_new',
          'installments': [
            null,
            'invalid',
            {'label': 5, 'amountMinor': 'free'},
          ],
        });
        expect(malformed.response, OfferResponse.withdrawn);
        expect(malformed.installments.single.label, '');
        expect(malformed.installments.single.amountMinor, 0);
        expect(
          malformed.installments.single.dueAt,
          DateTime.fromMillisecondsSinceEpoch(0),
        );
      },
    );

    test('FeeBreakdown exposes snapshot amounts as Money', () {
      final fee = FeeBreakdown.fromJson(feeJson);
      expect(fee.grossMinor, 15000);
      expect(fee.commissionBps, 1000);
      expect(fee.commissionMinor, 1500);
      expect(fee.artistNetMinor, 13500);
      expect(fee.currency, 'usd');
      expect(fee.gross.label, '\$150.00');
      expect(fee.commission.label, '\$15.00');
      expect(fee.artistNet.label, '\$135.00');
    });
  });

  group('Phase 3b payment models', () {
    test('StripeAccountStatus parses nullable card payment status', () {
      final status = StripeAccountStatus.fromJson({
        'cardPaymentsStatus': 'active',
      });
      expect(status.cardPaymentsStatus, 'active');
      expect(StripeAccountStatus.fromJson({}).cardPaymentsStatus, isNull);
      expect(
        StripeAccountStatus.fromJson({
          'cardPaymentsStatus': null,
        }).cardPaymentsStatus,
        isNull,
      );
      const none = StripeAccountStatus.none();
      expect(none.cardPaymentsStatus, isNull);
      expect(none.canSellTickets, isFalse);
    });

    test('Stripe ticket sales require charges and active card payments', () {
      for (final (chargesEnabled, cardPaymentsStatus, expected) in [
        (true, 'active', true),
        (false, 'active', false),
        (true, null, false),
        (false, null, false),
        (true, 'pending', false),
        (false, 'pending', false),
      ]) {
        final status = StripeAccountStatus.fromJson({
          'chargesEnabled': chargesEnabled,
          'cardPaymentsStatus': cardPaymentsStatus,
        });
        expect(status.chargesEnabled, chargesEnabled);
        expect(status.cardPaymentsStatus, cardPaymentsStatus);
        expect(status.canSellTickets, expected);
      }
    });

    test('PaymentRecord parses every field and exposes its Money amount', () {
      final payment = PaymentRecord.fromJson({
        '_id': 'payment-1',
        'installmentIndex': 2,
        'label': 'Final payment',
        'amountMinor': 12345,
        'currency': 'usd',
        'dueAt': 1800000000000,
        'status': 'paid',
        'paidAt': 1799900000000,
        'canPay': false,
      });
      expect(payment.id, 'payment-1');
      expect(payment.installmentIndex, 2);
      expect(payment.label, 'Final payment');
      expect(payment.amountMinor, 12345);
      expect(payment.currency, 'usd');
      expect(payment.dueAt, DateTime.fromMillisecondsSinceEpoch(1800000000000));
      expect(payment.status, PaymentRecordStatus.paid);
      expect(
        payment.paidAt,
        DateTime.fromMillisecondsSinceEpoch(1799900000000),
      );
      expect(payment.canPay, isFalse);
      expect(payment.amount.label, '\$123.45');
      expect(PaymentRecord.fromJson({'canPay': true}).canPay, isTrue);
    });

    test('Payout parses every field and exposes its Money amount', () {
      final payout = Payout.fromJson({
        '_id': 'payout-1',
        'kind': 'forfeit',
        'amountMinor': 8500,
        'currency': 'usd',
        'status': 'held',
        'scheduledFor': 1800000000000,
        'paidAt': 1800000100000,
        'holdReason': 'dispute',
      });
      expect(payout.id, 'payout-1');
      expect(payout.kind, PayoutKind.forfeit);
      expect(payout.amountMinor, 8500);
      expect(payout.currency, 'usd');
      expect(payout.status, PayoutStatus.held);
      expect(
        payout.scheduledFor,
        DateTime.fromMillisecondsSinceEpoch(1800000000000),
      );
      expect(payout.paidAt, DateTime.fromMillisecondsSinceEpoch(1800000100000));
      expect(payout.holdReason, 'dispute');
      expect(payout.amount.label, '\$85.00');
    });

    test('RefundRecord parses every field and exposes its Money amount', () {
      final refund = RefundRecord.fromJson({
        '_id': 'refund-1',
        'paymentRecordId': 'payment-1',
        'amountMinor': 5000,
        'currency': 'usd',
        'status': 'succeeded',
        'reason': 'organizer_cancel',
        'stripeRefundId': 're_demo',
        'createdAt': 1800000000000,
      });
      expect(refund.id, 'refund-1');
      expect(refund.amountMinor, 5000);
      expect(refund.currency, 'usd');
      expect(refund.status, RefundStatus.succeeded);
      expect(refund.reason, RefundReason.organizerCancel);
      expect(
        refund.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1800000000000),
      );
      expect(refund.amount.label, '\$50.00');
    });
  });

  group('Gig marketplace ownership', () {
    const gigJson = {
      '_id': 'gig-1',
      'slug': 'friday-showcase',
      'title': 'Friday Showcase',
      'venueId': 'venue-1',
      'price': 0,
      'startsAt': 1800000000000,
      'doorsAt': 1799996400000,
      'doorsTime': '7PM / 8PM',
      'flyKey': 'paper',
      'lineup': ['band-1'],
      'genres': ['indie'],
      'desc': 'An evening of local bands.',
      'ticketing': 'rsvp',
      'cap': '150',
    };

    test('parses organization ownership and preserves it when copied', () {
      final gig = Gig.fromJson({
        ...gigJson,
        'ownerKind': 'organization',
        'opportunityId': 'opportunity-1',
      });
      expect(gig.publicRef, 'friday-showcase');
      expect(Gig.fromJson({...gigJson, 'slug': null}).publicRef, 'gig-1');
      expect(gig.ownerKind, GigOwnerKind.organization);
      expect(gig.opportunityId, 'opportunity-1');
      final copy = gig.copyWith(going: 12);
      expect(copy.ownerKind, GigOwnerKind.organization);
      expect(copy.opportunityId, 'opportunity-1');
      expect(gig.sameListing(copy), isTrue);
      expect(
        gig.sameListing(gig.copyWith(ownerKind: GigOwnerKind.band)),
        isFalse,
      );
      expect(
        gig.sameListing(gig.copyWith(opportunityId: 'opportunity-2')),
        isFalse,
      );
      final relabeled = gig.relabeled(now: gig.startsAt);
      expect(relabeled.ownerKind, GigOwnerKind.organization);
      expect(relabeled.opportunityId, 'opportunity-1');
    });

    test(
      'defaults legacy payloads to band ownership without an opportunity',
      () {
        final gig = Gig.fromJson(gigJson);
        expect(gig.ownerKind, GigOwnerKind.band);
        expect(gig.opportunityId, isNull);
        expect(gig.tix, Ticketing.rsvp);
        for (final value in GigOwnerKind.values) {
          expect(GigOwnerKind.fromWire(value.wireValue), value);
        }
        for (final value in [null, 'something_new', 42]) {
          final malformed = Gig.fromJson({
            ...gigJson,
            'ownerKind': value,
            'opportunityId': 42,
          });
          expect(malformed.ownerKind, GigOwnerKind.band);
          expect(malformed.opportunityId, isNull);
        }
      },
    );
  });

  group('marketplace reviews', () {
    const publicReviewJson = {
      'reviewId': 'review-1',
      'rating': 5,
      'categories': ['communication', 'sound'],
      'text': 'Great show and clear communication.',
      'submittedAt': 1800010000000,
      'monthLabel': 'January 2027',
      'opportunityTitle': 'Friday Showcase',
    };

    test('PublicReview parses both counterparty listing shapes', () {
      for (final counterparty in [
        {'organizationName': 'Signal Collective'},
        {'bandName': 'The Night Shifts'},
      ]) {
        final review = PublicReview.fromJson({
          ...publicReviewJson,
          ...counterparty,
        });
        expect(review.reviewId, 'review-1');
        expect(review.rating, 5);
        expect(review.categories, ['communication', 'sound']);
        expect(review.text, 'Great show and clear communication.');
        expect(
          review.submittedAt,
          DateTime.fromMillisecondsSinceEpoch(1800010000000),
        );
        expect(review.monthLabel, 'January 2027');
        expect(review.opportunityTitle, 'Friday Showcase');
        expect(review.counterpartyName, counterparty.values.single);
      }
      expect(
        PublicReview.fromJson({
          ...publicReviewJson,
          'organizationName': 'Signal Collective',
          'bandName': 'The Night Shifts',
        }).counterpartyName,
        'Signal Collective',
      );
      expect(
        PublicReview.fromJson({
          ...publicReviewJson,
          'organizationName': 42,
          'bandName': 'The Night Shifts',
        }).counterpartyName,
        'The Night Shifts',
      );
      expect(PublicReview.fromJson(publicReviewJson).counterpartyName, '');
    });

    test(
      'BookingReviews preserves null reviews before either side submits',
      () {
        final reviews = BookingReviews.fromJson({
          'mine': null,
          'theirs': null,
          'windowClosesAt': 1801000000000,
          'canSubmit': true,
        });
        expect(reviews.mine, isNull);
        expect(reviews.theirs, isNull);
        expect(
          reviews.windowClosesAt,
          DateTime.fromMillisecondsSinceEpoch(1801000000000),
        );
        expect(reviews.canSubmit, isTrue);
      },
    );

    test('review categories retain the backend order', () {
      expect(reviewCategories, [
        'professionalism',
        'punctuality',
        'communication',
        'sound',
        'hospitality',
        'payment',
      ]);
    });
  });

  group('ReviewSummary', () {
    const summaryJson = {
      'count': 4,
      'mean': 4.75,
      'completedBookings': 6,
      'cancellations': 1,
    };
    const bandJson = {
      '_id': 'band-1',
      'name': 'The Night Shifts',
      'genres': ['indie'],
      'area': 'Oakland',
      'colorHex': '#1435F0',
      'initials': 'NS',
      'followerCount': 218,
      'bio': 'A Bay Area band.',
    };

    test(
      'Band preserves profile review summaries across copies and feed merges',
      () {
        final band = Band.fromJson({...bandJson, 'reviewSummary': summaryJson});
        expect(Band.fromJson({...bandJson, 'slug': 'b'}).publicRef, 'b');
        expect(Band.fromJson({...bandJson, 'slug': null}).publicRef, 'band-1');
        final replacement = ReviewSummary.fromJson({
          ...summaryJson,
          'count': 5,
        });
        expect(
          band.copyWith(name: 'Updated name').reviewSummary,
          same(band.reviewSummary),
        );
        expect(
          band.copyWith(reviewSummary: replacement).reviewSummary,
          same(replacement),
        );
        final feedBand = Band.fromJson({...bandJson, 'followerCount': 300});
        for (final summary in [
          feedBand,
          feedBand.copyWith(reviewSummary: replacement),
        ]) {
          final merged = band.mergeSummary(summary, upcoming: ['gig-1']);
          expect(merged.reviewSummary, same(band.reviewSummary));
          expect(merged.followers, 300);
          expect(merged.upcoming, ['gig-1']);
        }
      },
    );
  });

  group('marketplace Phase 2 models', () {
    const slotJson = {
      '_id': 'slot-1',
      'order': 1,
      'role': 'headliner',
      'setLengthMin': 60,
      'guaranteeMinor': 25000,
      'required': true,
      'status': 'booked',
      'bandId': 'band-1',
    };
    const opportunityJson = {
      '_id': 'opportunity-1',
      'organizationId': 'organization-1',
      'mode': 'publicEvent',
      'venueId': 'venue-1',
      'venue': {
        '_id': 'venue-1',
        'name': 'Signal Room',
        'area': 'Oakland',
        'addr': '100 Broadway, Oakland',
        'lat': 37.8044,
        'lng': -122.2712,
        'venueType': 'club',
      },
      'title': 'Friday Showcase',
      'desc': 'An evening of local bands.',
      'eventType': 'showcase',
      'expectedAttendance': 120,
      'genres': ['indie', 'rock'],
      'startsAt': 1800000000000,
      'doorsAt': 1799996400000,
      'endsAt': 1800007200000,
      'ageRequirement': '21Plus',
      'equipment': 'House PA and drum kit',
      'requirements': 'Bring your own cymbals',
      'flyKey': 'showcase',
      'flyerUrl': 'https://example.com/flyer.jpg',
      'applicationsCloseAt': 1799900000000,
      'visibility': 'inviteOnly',
      'ticketing': 'external',
      'externalUrl': 'https://example.com/tickets',
      'status': 'applications_closed',
      'slug': 'friday-showcase',
      'revision': 3,
      'applicationCount': 4,
      'slots': [slotJson],
      'invitedBandIds': ['band-1', 'band-2'],
      'createdAt': 1799800000000,
      'updatedAt': 1799850000000,
      'area': 'Oakland',
      'venueType': 'club',
      'currency': 'USD',
    };
    const applicationJson = {
      '_id': 'application-1',
      'opportunityId': 'opportunity-1',
      'slotId': 'slot-1',
      'bandId': 'band-1',
      'status': 'under_review',
      'message': 'We would love to play.',
      'askMinor': 30000,
      'availabilityNote': 'Available all evening',
      'lineupNote': 'Four-piece band',
      'decidedAt': 1799850000000,
      'createdAt': 1799800000000,
      'updatedAt': 1799860000000,
    };

    test('Opportunity and OpportunitySlot accept null optional fields', () {
      final opportunity = Opportunity.fromJson({
        ...opportunityJson,
        'mode': 'privateBooking',
        'venueId': null,
        'venue': null,
        'eventType': null,
        'expectedAttendance': null,
        'genres': <String>[],
        'doorsAt': null,
        'endsAt': null,
        'equipment': null,
        'requirements': null,
        'flyerUrl': null,
        'externalUrl': null,
        'slots': <Map<String, dynamic>>[],
        'invitedBandIds': <String>[],
        'venueType': null,
      });

      expect(opportunity.mode, OpportunityMode.privateBooking);
      expect(opportunity.venueId, isNull);
      expect(opportunity.venue, isNull);
      expect(opportunity.eventType, isNull);
      expect(opportunity.expectedAttendance, isNull);
      expect(opportunity.genres, isEmpty);
      expect(opportunity.doorsAt, isNull);
      expect(opportunity.endsAt, isNull);
      expect(opportunity.equipment, isNull);
      expect(opportunity.requirements, isNull);
      expect(opportunity.flyerUrl, isNull);
      expect(opportunity.externalUrl, isNull);
      expect(opportunity.slots, isEmpty);
      expect(opportunity.invitedBandIds, isEmpty);
      expect(opportunity.venueType, isNull);

      final slot = OpportunitySlot.fromJson({
        ...slotJson,
        'setLengthMin': null,
        'bandId': null,
        'required': false,
      });
      expect(slot.setLengthMin, isNull);
      expect(slot.bandId, isNull);
      expect(slot.required, isFalse);
    });

    test('OpportunityFilters omits nulls and uses the correct wire keys', () {
      expect(const OpportunityFilters().toJson(), <String, dynamic>{});
      expect(
        const OpportunityFilters(
          area: 'Oakland',
          genre: 'indie',
          venueType: VenueType.club,
          minGuaranteeMinor: 25000,
        ).toJson(),
        {
          'area': 'Oakland',
          'genre': 'indie',
          'venueType': 'club',
          'minGuaranteeMinor': 25000,
        },
      );
    });

    test('SlotInput only includes setLengthMin when provided', () {
      expect(
        const SlotInput(
          role: SlotRole.opener,
          guaranteeMinor: 0,
          required: false,
        ).toJson(),
        {'role': 'opener', 'guaranteeMinor': 0, 'required': false},
      );
      expect(
        const SlotInput(
          role: SlotRole.headliner,
          setLengthMin: 60,
          guaranteeMinor: 25000,
          required: true,
        ).toJson(),
        {
          'role': 'headliner',
          'setLengthMin': 60,
          'guaranteeMinor': 25000,
          'required': true,
        },
      );
    });

    test('BrowseItem leaves missing and null application statuses null', () {
      final absent = BrowseItem.fromJson({
        'opportunity': opportunityJson,
        'invited': false,
      });
      final explicitNull = BrowseItem.fromJson({
        'opportunity': opportunityJson,
        'invited': false,
        'myApplicationStatus': null,
      });

      expect(absent.invited, isFalse);
      expect(absent.myApplicationStatus, isNull);
      expect(explicitNull.myApplicationStatus, isNull);
    });

    test('ArtistApplication parses all fields and nullable details', () {
      final application = ArtistApplication.fromJson(applicationJson);

      expect(application.id, 'application-1');
      expect(application.opportunityId, 'opportunity-1');
      expect(application.slotId, 'slot-1');
      expect(application.bandId, 'band-1');
      expect(application.status, ArtistApplicationStatus.underReview);
      expect(application.message, 'We would love to play.');
      expect(application.askMinor, 30000);
      expect(application.availabilityNote, 'Available all evening');
      expect(application.lineupNote, 'Four-piece band');
      expect(
        application.decidedAt,
        DateTime.fromMillisecondsSinceEpoch(1799850000000),
      );
      expect(
        application.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1799800000000),
      );
      expect(
        application.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(1799860000000),
      );

      final nullable = ArtistApplication.fromJson({
        ...applicationJson,
        'askMinor': null,
        'availabilityNote': null,
        'lineupNote': null,
        'decidedAt': null,
      });
      expect(nullable.askMinor, isNull);
      expect(nullable.availabilityNote, isNull);
      expect(nullable.lineupNote, isNull);
      expect(nullable.decidedAt, isNull);
    });

    test('ApplicantRow and BandApplication parse nested models', () {
      final applicant = ApplicantRow.fromJson({
        'application': applicationJson,
        'band': {
          '_id': 'band-1',
          'name': 'Signal Band',
          'genres': ['indie'],
          'area': 'Oakland',
          'colorHex': '#123456',
          'initials': 'SB',
          'followerCount': 123,
          'heroUrl': 'https://example.com/band.jpg',
        },
        'contactEmail': 'band@example.com',
      });
      final bandApplication = BandApplication.fromJson({
        'application': applicationJson,
        'opportunity': opportunityJson,
      });

      expect(applicant.application.id, 'application-1');
      expect(applicant.band.id, 'band-1');
      expect(applicant.band.name, 'Signal Band');
      expect(applicant.band.genres, ['indie']);
      expect(applicant.band.color.toARGB32(), 0xFF123456);
      expect(applicant.band.followers, 123);
      expect(applicant.band.isSummary, isTrue);
      expect(applicant.band.profileImageUrl, 'https://example.com/band.jpg');
      expect(applicant.contactEmail, 'band@example.com');
      expect(bandApplication.application.id, 'application-1');
      expect(bandApplication.opportunity.id, 'opportunity-1');
    });
  });

  group('marketplace finance models', () {
    const snapshotJson = {
      'availableMinor': 12000.0,
      'pendingMinor': 3400,
      'currency': 'eur',
      'fetchedAt': 1800000000000,
    };
    const bookingJson = {
      'dueMinor': 1000,
      'paidMinor': 2000,
      'refundedMinor': 300,
      'disputedMinor': 400,
      'activeCount': 2,
    };
    const ticketJson = {
      'ordersPaid': 3,
      'grossMinor': 4500,
      'feeMinor': 225,
      'refundedMinor': 600,
      'refundedOrgMinor': 500,
      'netMinor': 4000,
      'estimatedProcessingMinor': 150,
      'truncated': true,
    };
    const pendingJson = {
      'bookingId': 'booking-1',
      'paymentRecordId': 'payment-1',
      'opportunityTitle': 'Show',
      'label': 'Deposit',
      'amountMinor': 1000,
      'dueAt': 1800000000000,
    };
    const transactionJson = {
      'id': 'ledger-1',
      'kind': 'ticketSale',
      'amountMinor': 4500,
      'currency': 'eur',
      'fundsState': 'available',
      'occurredAt': 1800000000000,
      'label': 'Show',
      'bookingId': 'booking-1',
      'ticketOrderId': 'order-1',
      'stripeRef': 'pi_1',
    };

    test('FinanceSnapshot parses balances, currency, and timestamp', () {
      final snapshot = FinanceSnapshot.fromJson(snapshotJson);
      expect(snapshot.availableMinor, 12000);
      expect(snapshot.pendingMinor, 3400);
      expect(snapshot.currency, 'eur');
      expect(snapshot.available, const Money(12000, 'eur'));
      expect(snapshot.pending, const Money(3400, 'eur'));
      expect(snapshot.fetchedAt.millisecondsSinceEpoch, 1800000000000);
    });

    test('PendingPayment and FinanceOverview use the parent currency', () {
      final pending = PendingPayment.fromJson(pendingJson, currency: 'eur');
      expect(pending.bookingId, 'booking-1');
      expect(pending.paymentRecordId, 'payment-1');
      expect(pending.opportunityTitle, 'Show');
      expect(pending.label, 'Deposit');
      expect(pending.amountMinor, 1000);
      expect(pending.currency, 'eur');
      expect(pending.amount, const Money(1000, 'eur'));
      expect(pending.dueAt.millisecondsSinceEpoch, 1800000000000);
      final overview = FinanceOverview.fromJson({
        'stripeReady': true,
        'snapshot': snapshotJson,
        'bookings': bookingJson,
        'tickets': ticketJson,
        'pendingPayments': [pendingJson],
        'currency': 'eur',
      });
      expect(overview.stripeReady, isTrue);
      expect(overview.snapshot!.available, const Money(12000, 'eur'));
      expect(overview.pendingPayments.single.amount, const Money(1000, 'eur'));
      expect(overview.dueAmount, const Money(1000, 'eur'));
      expect(overview.paidAmount, const Money(2000, 'eur'));
      expect(overview.refundedAmount, const Money(300, 'eur'));
      expect(overview.disputedAmount, const Money(400, 'eur'));
      expect(overview.ticketGrossAmount, const Money(4500, 'eur'));
      expect(overview.ticketFeeAmount, const Money(225, 'eur'));
      expect(overview.ticketRefundedAmount, const Money(600, 'eur'));
      expect(overview.ticketRefundedOrgAmount, const Money(500, 'eur'));
      expect(overview.ticketNetAmount, const Money(4000, 'eur'));
      expect(overview.ticketEstimatedProcessingAmount, const Money(150, 'eur'));
      for (final value in [null, false, 'invalid']) {
        expect(FinanceOverview.fromJson({'snapshot': value}).snapshot, isNull);
      }
    });

    test('FinanceTransaction parses money, references, and wire enums', () {
      final transaction = FinanceTransaction.fromJson(transactionJson);
      expect(transaction.id, 'ledger-1');
      expect(transaction.kind, LedgerKind.ticketSale);
      expect(transaction.amount, const Money(4500, 'eur'));
      expect(transaction.fundsState, FundsState.available);
      expect(transaction.occurredAt.millisecondsSinceEpoch, 1800000000000);
      expect(transaction.label, 'Show');
      expect(transaction.bookingId, 'booking-1');
      expect(transaction.ticketOrderId, 'order-1');
      expect(transaction.stripeRef, 'pi_1');
    });

    test('TransactionsPage parses the page list and pagination fields', () {
      for (final key in ['page']) {
        final page = TransactionsPage.fromJson({
          key: [transactionJson],
          'isDone': false,
          'continueCursor': 'next',
        });
        expect(page.items.single.id, 'ledger-1');
        expect(page.isDone, isFalse);
        expect(page.continueCursor, 'next');
      }
      final page = TransactionsPage.fromJson({
        'page': <Object?>[],
        'isDone': true,
        'continueCursor': null,
      });
      expect(page.items, isEmpty);
      expect(page.isDone, isTrue);
      expect(page.continueCursor, isNull);
      expect(
        TransactionsPage.fromJson({
          'page': <Object?>[],
          'items': [transactionJson],
        }).items,
        isEmpty,
      );
    });

    test('StatementExport parses CSV and export metadata', () {
      final statement = StatementExport.fromJson({
        'csv': 'date,type\n2026-09-06,charge',
        'rows': 1.0,
        'truncated': true,
      });
      expect(statement.csv, 'date,type\n2026-09-06,charge');
      expect(statement.rows, 1);
      expect(statement.truncated, isTrue);
      expect(statement.transactions, isEmpty);
      expect(statement.totalsByKind, isEmpty);
    });

    test(
      'PayoutStatement and its rows round-trip nullable payment details',
      () {
        const rowJson = {
          'payoutId': 'payout-1',
          'bookingId': 'booking-1',
          'bookingTitle': 'Night Shift',
          'organizationName': 'Night Shift Collective',
          'kind': 'completion',
          'status': 'reversed',
          'paidAt': 1800000000000,
          'netMinor': 8750,
          'reversedMinor': 1250,
          'currency': 'usd',
          'grossMinor': 10000,
          'commissionMinor': 1250,
          'stripeTransferId': 'tr_1',
        };
        for (final nullable in [false, true]) {
          final json = {
            ...rowJson,
            if (nullable) ...{
              'grossMinor': null,
              'commissionMinor': null,
              'stripeTransferId': null,
            },
          };
          final statement = PayoutStatement.fromJson(
            _jsonRoundTrip({
              'payouts': [json],
              'totalNetMinor': 7500,
              'truncated': true,
            }),
          );
          expect(statement.totalNetMinor, 7500);
          expect(statement.truncated, isTrue);
          for (final row in [
            statement.payouts.single,
            PayoutStatementRow.fromJson(_jsonRoundTrip(json)),
          ]) {
            expect(row.payoutId, 'payout-1');
            expect(row.bookingId, 'booking-1');
            expect(row.bookingTitle, 'Night Shift');
            expect(row.organizationName, 'Night Shift Collective');
            expect(row.kind, PayoutKind.completion);
            expect(row.status, PayoutStatus.reversed);
            expect(row.paidAt.millisecondsSinceEpoch, 1800000000000);
            expect(row.netMinor, 8750);
            expect(row.reversedMinor, 1250);
            expect(row.currency, 'usd');
            expect(row.grossMinor, nullable ? isNull : 10000);
            expect(row.commissionMinor, nullable ? isNull : 1250);
            expect(row.stripeTransferId, nullable ? isNull : 'tr_1');
          }
        }
        final empty = PayoutStatement.fromJson(_jsonRoundTrip({}));
        expect(empty.payouts, isEmpty);
        expect(empty.totalNetMinor, 0);
        expect(empty.truncated, isFalse);
      },
    );
  });

  group('marketplace insights models', () {
    const bucketJson = {'key': 'Oakland', 'events': 5, 'checkIns': 42};
    const partitionJson = {
      'buckets': [bucketJson],
      'suppressed': false,
    };
    const attributionJson = {
      'referral': 12,
      'follow': 20,
      'unattributed': 10,
      'suppressed': true,
    };
    const drawJson = {
      'low': 30,
      'high': 50,
      'confidence': 'medium',
      'events': 5,
      'basis': 'checkIns',
    };
    const windowJson = {
      'events': 5,
      'truncated': true,
      'firstStartsAt': 1800000000000,
      'lastStartsAt': 1801000000000,
    };
    const bandJson = {'bandId': 'band-1', 'name': 'Signal Band'};

    test('ArtistInsights parses every nested model and nullable draw', () {
      final insights = ArtistInsights.fromJson({
        'band': bandJson,
        'window': windowJson,
        'followers': 100,
        'rsvpTotal': 80,
        'ticketsSold': 60,
        'checkIns': 42,
        'returningAttendees': 8,
        'returningSuppressed': true,
        'attribution': attributionJson,
        'byArea': partitionJson,
        'byVenueType': partitionJson,
        'byWeekday': partitionJson,
        'byPriceBand': partitionJson,
        'estimatedDraw': drawJson,
      });
      expect(insights.band.bandId, 'band-1');
      expect(insights.window.events, 5);
      expect(insights.followers, 100);
      expect(insights.rsvpTotal, 80);
      expect(insights.ticketsSold, 60);
      expect(insights.checkIns, 42);
      expect(insights.returningAttendees, 8);
      expect(insights.returningSuppressed, isTrue);
      expect(insights.attribution.follow, 20);
      for (final partition in [
        insights.byArea,
        insights.byVenueType,
        insights.byWeekday,
        insights.byPriceBand,
      ]) {
        expect(partition.buckets.single.checkIns, 42);
        expect(partition.suppressed, isFalse);
      }
      expect(insights.estimatedDraw!.confidence, DrawConfidence.medium);
      for (final value in [null, false, 'invalid']) {
        expect(
          ArtistInsights.fromJson({'estimatedDraw': value}).estimatedDraw,
          isNull,
        );
      }
    });

    test('non-finite numbers and invalid timestamp ranges never throw', () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(InsightBucket.fromJson({'events': value}).events, 0);
      }
      for (final value in [
        double.nan,
        double.infinity,
        8640000000000001,
        -8640000000000001,
        -9223372036854775808,
        1e100,
        -1e100,
      ]) {
        expect(
          FinanceSnapshot.fromJson({
            'fetchedAt': value,
          }).fetchedAt.millisecondsSinceEpoch,
          0,
        );
        expect(
          InsightsWindow.fromJson({'firstStartsAt': value}).firstStartsAt,
          isNull,
        );
      }
    });
  });
}
