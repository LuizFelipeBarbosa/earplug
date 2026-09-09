// dart format width=100
import 'dart:async';

import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/foundation.dart' show protected;

import 'fakes.dart' show HttpUploadDemoRepository;

/// A configurable [DemoRepository] with the same default authentication as
/// [HttpUploadDemoRepository]. Unconfigured methods use the real demo behavior.
///
/// Method keys are plain strings, not a generated enum. A typo such as
/// `stub.fail('myBnds')` silently does nothing: the `myBands` override never sees
/// it, so the test that configured the typo can fail confusingly. This is an
/// accepted tradeoff; copy names from [EarplugRepository].
///
/// ```dart
/// final stub = StubRepository()..fail('me');
/// ```
///
/// ```dart
/// final stub = StubRepository()..returns('venues', <Venue>[]);
/// ```
///
/// ```dart
/// final stub = StubRepository()
///   ..wraps<List<Venue>>('venues', (real) => real.take(1).toList());
/// ```
///
/// Streams support only [fail], [failOnce], [returns], and call counts. Stream
/// calls are counted immediately; failures are emitted as stream errors and
/// [returns] must supply a Stream of the method's declared type. [gate] and
/// [wraps] apply only to Future-returning methods.
class StubRepository extends DemoRepository {
  StubRepository({AuthService? auth}) : super(auth: auth ?? FakeAuthService());

  final _calls = <String, int>{};
  final _failures = <String, ({Object error, bool once})>{};
  final _returns = <String, Object?>{};
  final _wraps = <String, FutureOr<Object?> Function(Object?)>{};
  final _gates = <String, Completer<void>>{};

  /// Every call to [method] throws [error], defaulting to
  /// `StateError('<method> failed')`. Replaces any previous failure setting.
  void fail(String method, [Object? error]) {
    _failures[method] = (error: error ?? StateError('$method failed'), once: false);
  }

  /// The first call to [method] throws [error]; later calls fall through to
  /// returns, wraps, or real behavior. Replaces any previous failure setting.
  void failOnce(String method, [Object? error]) {
    _failures[method] = (error: error ?? StateError('$method failed'), once: true);
  }

  /// Resolves calls to [method] with [value], bypassing the real implementation
  /// and any wrapper. Future-returning methods also accept a Future as [value].
  void returns(String method, Object? value) => _returns[method] = value;

  /// Runs the real implementation of [method], then transforms its result
  /// through [f]. [T] must match the result type of the method's Future.
  void wraps<T>(String method, FutureOr<T> Function(T real) f) {
    _wraps[method] = (real) => f(real as T);
  }

  /// Returns a new gate which calls to [method] must await before resolving.
  /// Complete it to release waiting calls; replaces the gate for future calls.
  Completer<void> gate(String method) => _gates[method] = Completer<void>();

  /// How many times [method] has been called so far, including gated calls.
  int callsTo(String method) => _calls[method] ?? 0;

  /// An unmodifiable snapshot of all call counts by method name.
  Map<String, int> get calls => Map.unmodifiable(_calls);

  /// Dispatches Future calls in order: count, gate, failure, canned value,
  /// real implementation, then wrapper. Canned values bypass real and wrapper.
  @protected
  Future<T> intercept<T>(String method, Future<T> Function() real) async {
    _calls[method] = callsTo(method) + 1;
    final gate = _gates[method];
    if (gate != null) await gate.future;
    _throwIfFailed(method);
    if (_returns.containsKey(method)) {
      final value = _returns[method];
      return (value is Future<Object?> ? await value : value) as T;
    }
    final result = await real();
    final wrap = _wraps[method];
    if (wrap == null) return result;
    final wrapped = wrap(result);
    return (wrapped is Future<Object?> ? await wrapped : wrapped) as T;
  }

  void _throwIfFailed(String method) {
    final failure = _failures[method];
    if (failure == null) return;
    if (failure.once) _failures.remove(method);
    throw failure.error;
  }

  Stream<T> _interceptStream<T>(String method, Stream<T> Function() real) {
    _calls[method] = callsTo(method) + 1;
    try {
      _throwIfFailed(method);
    } catch (error, stackTrace) {
      return Stream<T>.error(error, stackTrace);
    }
    if (_returns.containsKey(method)) return _returns[method] as Stream<T>;
    return real();
  }

  @override
  Future<BandInviteAcceptance> acceptBandInvite(String token) =>
      intercept('acceptBandInvite', () => super.acceptBandInvite(token));
  @override
  Future<OrganizationInviteAcceptance> acceptOrganizationInvite(String token) =>
      intercept('acceptOrganizationInvite', () => super.acceptOrganizationInvite(token));
  @override
  Future<String> addBandMedia({
    required String bandId,
    required MediaKind kind,
    required String storageId,
    String? thumbnailStorageId,
    required String title,
    String? caption,
    int? lengthSec,
  }) => intercept(
    'addBandMedia',
    () => super.addBandMedia(
      bandId: bandId,
      kind: kind,
      storageId: storageId,
      thumbnailStorageId: thumbnailStorageId,
      title: title,
      caption: caption,
      lengthSec: lengthSec,
    ),
  );
  @override
  Future<AdminBookingsPage> adminBookings({
    required AdminBookingFilter filter,
    String? cursor,
    int numItems = 25,
  }) => intercept(
    'adminBookings',
    () => super.adminBookings(filter: filter, cursor: cursor, numItems: numItems),
  );
  @override
  Future<BandArchiveResult> archiveBand(String bandId) =>
      intercept('archiveBand', () => super.archiveBand(bandId));
  @override
  Future<ArtistInsights> artistInsights(String applicationId) =>
      intercept('artistInsights', () => super.artistInsights(applicationId));
  @override
  Future<Band?> band(String bandId) => intercept('band', () => super.band(bandId));
  @override
  Future<BandArchiveStatus> bandArchiveStatus(String bandId) =>
      intercept('bandArchiveStatus', () => super.bandArchiveStatus(bandId));
  @override
  Future<List<Booking>> bandBookings(String bandId) =>
      intercept('bandBookings', () => super.bandBookings(bandId));
  @override
  Future<BandDiscoveryReadiness> bandDiscoveryReadiness(String bandId, {DateTime? now}) =>
      intercept('bandDiscoveryReadiness', () => super.bandDiscoveryReadiness(bandId, now: now));
  @override
  Future<BandHistory> bandHistory(String bandId) =>
      intercept('bandHistory', () => super.bandHistory(bandId));
  @override
  Future<BandInvite?> bandInvite(String bandId) =>
      intercept('bandInvite', () => super.bandInvite(bandId));
  @override
  Future<PayoutStatement> bandPayoutStatement(
    String bandId, {
    required DateTime from,
    required DateTime to,
  }) =>
      intercept('bandPayoutStatement', () => super.bandPayoutStatement(bandId, from: from, to: to));
  @override
  Future<StripeAccountStatus> bandPayoutStatus(String bandId) =>
      intercept('bandPayoutStatus', () => super.bandPayoutStatus(bandId));
  @override
  Future<BandProfileDetails> bandProfileDetails(String bandId) =>
      intercept('bandProfileDetails', () => super.bandProfileDetails(bandId));
  @override
  Future<BandRecap> bandRecap(String bandId) =>
      intercept('bandRecap', () => super.bandRecap(bandId));
  @override
  Future<BandSetupStatus> bandSetupStatus(String bandId) =>
      intercept('bandSetupStatus', () => super.bandSetupStatus(bandId));
  @override
  Future<Booking?> booking(String bookingId, {BookingSide? viewAs}) =>
      intercept('booking', () => super.booking(bookingId, viewAs: viewAs));
  @override
  Future<OpportunityPage> browseOpportunities({
    String? cursor,
    int numItems = 25,
    String? bandId,
    OpportunityFilters? filters,
    OpportunityMode? mode,
  }) => intercept(
    'browseOpportunities',
    () => super.browseOpportunities(
      cursor: cursor,
      numItems: numItems,
      bandId: bandId,
      filters: filters,
      mode: mode,
    ),
  );
  @override
  Future<void> cancelTicketReservation(String orderId) =>
      intercept('cancelTicketReservation', () => super.cancelTicketReservation(orderId));
  @override
  Future<DoorCheckInResult> checkInTicket({required String projectId, required String payload}) =>
      intercept('checkInTicket', () => super.checkInTicket(projectId: projectId, payload: payload));
  @override
  Future<CheckoutStatus?> checkoutStatus(String sessionId) =>
      intercept('checkoutStatus', () => super.checkoutStatus(sessionId));
  @override
  Future<String> claimPerformerInvite({required String token, required String bandId}) => intercept(
    'claimPerformerInvite',
    () => super.claimPerformerInvite(token: token, bandId: bandId),
  );
  @override
  Future<void> clearAvatar() => intercept('clearAvatar', super.clearAvatar);
  @override
  Future<void> clearBandAvatar(String bandId) =>
      intercept('clearBandAvatar', () => super.clearBandAvatar(bandId));
  @override
  Future<BandInvite> createBandInvite(String bandId) =>
      intercept('createBandInvite', () => super.createBandInvite(bandId));
  @override
  Future<void> deleteCurrentUser() => intercept('deleteCurrentUser', super.deleteCurrentUser);
  @override
  Future<List<Dispute>> disputesForBooking(String bookingId) =>
      intercept('disputesForBooking', () => super.disputesForBooking(bookingId));
  @override
  Future<DoorRoster> doorRoster(String projectId) =>
      intercept('doorRoster', () => super.doorRoster(projectId));
  @override
  Future<void> ensureRsvp(String gigId) => intercept('ensureRsvp', () => super.ensureRsvp(gigId));
  @override
  Future<void> ensureSave(String gigId) => intercept('ensureSave', () => super.ensureSave(gigId));
  @override
  Future<void> ensureUser({String? name}) =>
      intercept('ensureUser', () => super.ensureUser(name: name));
  @override
  Future<StatementExport> exportStatement(
    String organizationId, {
    required DateTime from,
    required DateTime to,
  }) =>
      intercept('exportStatement', () => super.exportStatement(organizationId, from: from, to: to));
  @override
  Future<FeeRates> feeRates({String? organizationId}) =>
      intercept('feeRates', () => super.feeRates(organizationId: organizationId));
  @override
  Stream<FeedSnapshot> feed() => _interceptStream('feed', super.feed);
  @override
  Future<FinanceOverview> financeOverview(String organizationId) =>
      intercept('financeOverview', () => super.financeOverview(organizationId));
  @override
  Future<TransactionsPage> financeTransactions(
    String organizationId, {
    required int numItems,
    String? cursor,
  }) => intercept(
    'financeTransactions',
    () => super.financeTransactions(organizationId, numItems: numItems, cursor: cursor),
  );
  @override
  Future<String> generateAvatarUploadUrl() =>
      intercept('generateAvatarUploadUrl', super.generateAvatarUploadUrl);
  @override
  Future<String> generateMediaUploadUrl(String bandId) =>
      intercept('generateMediaUploadUrl', () => super.generateMediaUploadUrl(bandId));
  @override
  Future<GigProject> getGigProject(String projectId) =>
      intercept('getGigProject', () => super.getGigProject(projectId));
  @override
  Stream<Map<String, int>> goingCounts() => _interceptStream('goingCounts', super.goingCounts);
  @override
  Future<List<FanHistoryItem>> history() => intercept('history', super.history);
  @override
  Future<List<BrowseItem>> invitedOpportunities(String bandId) =>
      intercept('invitedOpportunities', () => super.invitedOpportunities(bandId));
  @override
  Future<BandPage> listBands({String? cursor, int numItems = 50}) =>
      intercept('listBands', () => super.listBands(cursor: cursor, numItems: numItems));
  @override
  Future<List<GigProject>> manageGigs(String bandId) =>
      intercept('manageGigs', () => super.manageGigs(bandId));
  @override
  Future<List<Opportunity>> manageOpportunities(String organizationId) =>
      intercept('manageOpportunities', () => super.manageOpportunities(organizationId));
  @override
  Future<UserProfile?> me() => intercept('me', super.me);
  @override
  Future<List<BandMedia>> mediaFor(String bandId) =>
      intercept('mediaFor', () => super.mediaFor(bandId));
  @override
  Future<void> moveMediaWithinKind(String mediaId, String direction) =>
      intercept('moveMediaWithinKind', () => super.moveMediaWithinKind(mediaId, direction));
  @override
  Future<List<BandApplication>> myApplications(String bandId) =>
      intercept('myApplications', () => super.myApplications(bandId));
  @override
  Future<ArtistInsights> myBandInsights(String bandId) =>
      intercept('myBandInsights', () => super.myBandInsights(bandId));
  @override
  Stream<List<BandMembership>> myBands() => _interceptStream('myBands', super.myBands);
  @override
  Stream<Interactions> myInteractions() => _interceptStream('myInteractions', super.myInteractions);
  @override
  Future<OrganizationApplication?> myOrganizationApplication() =>
      intercept('myOrganizationApplication', super.myOrganizationApplication);
  @override
  Stream<List<OrganizationMembership>> myOrganizations() =>
      _interceptStream('myOrganizations', super.myOrganizations);
  @override
  Future<List<TicketSummary>> myTickets() => intercept('myTickets', super.myTickets);
  @override
  Future<String> openDispute({
    required String bookingId,
    required DisputeSide side,
    required DisputeCategory category,
    required String text,
    int? requestedRefundMinor,
  }) => intercept(
    'openDispute',
    () => super.openDispute(
      bookingId: bookingId,
      side: side,
      category: category,
      text: text,
      requestedRefundMinor: requestedRefundMinor,
    ),
  );
  @override
  Future<DisputesPage> openDisputes({String? cursor, int numItems = 25}) =>
      intercept('openDisputes', () => super.openDisputes(cursor: cursor, numItems: numItems));
  @override
  Future<Opportunity?> opportunity(String opportunityId) =>
      intercept('opportunity', () => super.opportunity(opportunityId));
  @override
  Future<List<Booking>> organizationBookings(
    String organizationId, {
    List<BookingStatus>? statuses,
  }) => intercept(
    'organizationBookings',
    () => super.organizationBookings(organizationId, statuses: statuses),
  );
  @override
  Future<OrganizationDashboard> organizationDashboard(String organizationId) =>
      intercept('organizationDashboard', () => super.organizationDashboard(organizationId));
  @override
  Future<StripeAccountStatus> organizationStripeStatus(String organizationId) =>
      intercept('organizationStripeStatus', () => super.organizationStripeStatus(organizationId));
  @override
  Future<DoorCounts> organizerDoorRoster(String gigId) =>
      intercept('organizerDoorRoster', () => super.organizerDoorRoster(gigId));
  @override
  Future<List<PaymentRecord>> paymentsForBooking(String bookingId) =>
      intercept('paymentsForBooking', () => super.paymentsForBooking(bookingId));
  @override
  Future<List<Payout>> payoutsForBand(String bandId) =>
      intercept('payoutsForBand', () => super.payoutsForBand(bandId));
  @override
  Future<List<Payout>> payoutsForBooking(String bookingId) =>
      intercept('payoutsForBooking', () => super.payoutsForBooking(bookingId));
  @override
  Future<RefundPreview> previewCancellation(
    String bookingId, {
    BookingSide? side,
    required DateTime now,
  }) => intercept(
    'previewCancellation',
    () => super.previewCancellation(bookingId, side: side, now: now),
  );
  @override
  Future<List<PrivateLocation>> privateLocationsFor(String organizationId) =>
      intercept('privateLocationsFor', () => super.privateLocationsFor(organizationId));
  @override
  Stream<Gig?> publicGig(String ref) => _interceptStream('publicGig', () => super.publicGig(ref));
  @override
  Future<String> publishGigDraft(String projectId) =>
      intercept('publishGigDraft', () => super.publishGigDraft(projectId));
  @override
  Future<void> refreshAuth() => intercept('refreshAuth', super.refreshAuth);
  @override
  Future<StripeAccountStatus> refreshBandAccountStatus(String bandId) =>
      intercept('refreshBandAccountStatus', () => super.refreshBandAccountStatus(bandId));
  @override
  Future<FinanceSnapshot?> refreshFinanceBalance(String organizationId) =>
      intercept('refreshFinanceBalance', () => super.refreshFinanceBalance(organizationId));
  @override
  Future<StripeAccountStatus> refreshOrganizationAccountStatus(String organizationId) => intercept(
    'refreshOrganizationAccountStatus',
    () => super.refreshOrganizationAccountStatus(organizationId),
  );
  @override
  Future<List<RefundRecord>> refundsForBooking(String bookingId) =>
      intercept('refundsForBooking', () => super.refundsForBooking(bookingId));
  @override
  Future<void> removeOrganizationMember({required String organizationId, required String userId}) =>
      intercept(
        'removeOrganizationMember',
        () => super.removeOrganizationMember(organizationId: organizationId, userId: userId),
      );
  @override
  Future<TicketReservation> reserveTickets({
    required String gigId,
    required int quantity,
    String? referralBandSlug,
  }) => intercept(
    'reserveTickets',
    () =>
        super.reserveTickets(gigId: gigId, quantity: quantity, referralBandSlug: referralBandSlug),
  );
  @override
  Future<void> resolveDispute(
    String disputeId, {
    required DisputeResolution resolution,
    int? refundMinor,
    String? adminNote,
  }) => intercept(
    'resolveDispute',
    () => super.resolveDispute(
      disputeId,
      resolution: resolution,
      refundMinor: refundMinor,
      adminNote: adminNote,
    ),
  );
  @override
  Future<BrowseItem?> resolveOpportunity(String ref, {String? bandId}) =>
      intercept('resolveOpportunity', () => super.resolveOpportunity(ref, bandId: bandId));
  @override
  Future<PerformerInviteResolution?> resolvePerformerInvite(String token) =>
      intercept('resolvePerformerInvite', () => super.resolvePerformerInvite(token));
  @override
  Future<void> revokeBandInvite(String bandId) =>
      intercept('revokeBandInvite', () => super.revokeBandInvite(bandId));
  @override
  Future<BandInvite> rotateBandInvite(String bandId) =>
      intercept('rotateBandInvite', () => super.rotateBandInvite(bandId));
  @override
  Future<List<Band>> searchBands(String q) => intercept('searchBands', () => super.searchBands(q));
  @override
  Future<void> setBandAvatar({required String bandId, required String mediaId}) =>
      intercept('setBandAvatar', () => super.setBandAvatar(bandId: bandId, mediaId: mediaId));
  @override
  Future<void> setBandBanner({required String bandId, required String mediaId}) =>
      intercept('setBandBanner', () => super.setBandBanner(bandId: bandId, mediaId: mediaId));
  @override
  Future<void> setProfileTutorialCompleted(bool completed) =>
      intercept('setProfileTutorialCompleted', () => super.setProfileTutorialCompleted(completed));
  @override
  Future<void> setVenueAddressDisclosure({
    required String venueId,
    required AddressDisclosure disclosure,
  }) => intercept(
    'setVenueAddressDisclosure',
    () => super.setVenueAddressDisclosure(venueId: venueId, disclosure: disclosure),
  );
  @override
  Future<String> startBandOnboarding(String bandId) =>
      intercept('startBandOnboarding', () => super.startBandOnboarding(bandId));
  @override
  Future<void> startDisputeReview(String disputeId) =>
      intercept('startDisputeReview', () => super.startDisputeReview(disputeId));
  @override
  Future<String> startOrganizationOnboarding(String organizationId) => intercept(
    'startOrganizationOnboarding',
    () => super.startOrganizationOnboarding(organizationId),
  );
  @override
  Future<TicketSummary?> ticket(String ticketId) =>
      intercept('ticket', () => super.ticket(ticketId));
  @override
  Future<TicketOrderState?> ticketOrderStatus(String sessionId) =>
      intercept('ticketOrderStatus', () => super.ticketOrderStatus(sessionId));
  @override
  Future<TicketSales> ticketSalesForGig(String gigId) =>
      intercept('ticketSalesForGig', () => super.ticketSalesForGig(gigId));
  @override
  Future<void> toggleFollow(String bandId) =>
      intercept('toggleFollow', () => super.toggleFollow(bandId));
  @override
  Future<void> toggleRsvp(String gigId, {bool? on}) =>
      intercept('toggleRsvp', () => super.toggleRsvp(gigId, on: on));
  @override
  Future<void> toggleSave(String gigId) => intercept('toggleSave', () => super.toggleSave(gigId));
  @override
  Stream<List<Gig>> upcomingGigsForBand(String bandId) =>
      _interceptStream('upcomingGigsForBand', () => super.upcomingGigsForBand(bandId));
  @override
  Future<void> updateBandProfile(BandProfileUpdate update) =>
      intercept('updateBandProfile', () => super.updateBandProfile(update));
  @override
  Future<void> updateFanOnboarding({
    FanCity? preferredCity,
    FanGenreChoice? genreChoice,
    bool? collapsed,
    List<String>? genres,
  }) => intercept(
    'updateFanOnboarding',
    () => super.updateFanOnboarding(
      preferredCity: preferredCity,
      genreChoice: genreChoice,
      collapsed: collapsed,
      genres: genres,
    ),
  );
  @override
  Future<void> updateFanProfile({
    required String name,
    required String? bio,
    required FanCity? homeLocation,
    required List<String> genres,
    required bool locationPersonalizationEnabled,
    required bool followedBandUpdatesEnabled,
  }) => intercept(
    'updateFanProfile',
    () => super.updateFanProfile(
      name: name,
      bio: bio,
      homeLocation: homeLocation,
      genres: genres,
      locationPersonalizationEnabled: locationPersonalizationEnabled,
      followedBandUpdatesEnabled: followedBandUpdatesEnabled,
    ),
  );
  @override
  Future<int> updateOpportunityTicketing({
    required String opportunityId,
    required int expectedRevision,
    required int ticketPriceMinor,
    required int ticketCapacity,
  }) => intercept(
    'updateOpportunityTicketing',
    () => super.updateOpportunityTicketing(
      opportunityId: opportunityId,
      expectedRevision: expectedRevision,
      ticketPriceMinor: ticketPriceMinor,
      ticketCapacity: ticketCapacity,
    ),
  );
  @override
  Future<void> updateVenueProfile({
    required String venueId,
    String? name,
    String? description,
    VenueType? venueType,
    int? capacityPublic,
    String? neighborhood,
    String? city,
  }) => intercept(
    'updateVenueProfile',
    () => super.updateVenueProfile(
      venueId: venueId,
      name: name,
      description: description,
      venueType: venueType,
      capacityPublic: capacityPublic,
      neighborhood: neighborhood,
      city: city,
    ),
  );
  @override
  Future<List<VenueConsentRow>> venueConsentsForOrganization(
    String organizationId, {
    VenueConsentStatus? status,
  }) => intercept(
    'venueConsentsForOrganization',
    () => super.venueConsentsForOrganization(organizationId, status: status),
  );
  @override
  Future<VenueDetail?> venueDetail(String venueId) =>
      intercept('venueDetail', () => super.venueDetail(venueId));
  @override
  Future<List<Venue>> venues() => intercept('venues', super.venues);
  @override
  Stream<List<Venue>> watchVenues() => _interceptStream('watchVenues', super.watchVenues);
}
