part of '../app_state.dart';

mixin _BookingState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  String get bandId;
  String get organizationId;
  ActiveIdentity get identity;
  OrganizationRole? organizerRoleFor(String organizationId);
  void go(Screen s, [String? param]);

  // ---- organizer side
  List<Booking> organizationBookings = const [];
  DataStatus organizationBookingsStatus = DataStatus.connecting;
  Object? _organizationBookingsLoadToken;

  Future<void> refreshOrganizationBookings([String? organizationId]) async {
    if (_disposed) return;
    final target = organizationId ?? this.organizationId;
    final token = Object();
    _organizationBookingsLoadToken = token;
    if (target.isEmpty) {
      organizationBookings = const [];
      organizationBookingsStatus = DataStatus.ready;
      notifyListeners();
      return;
    }
    try {
      final bookings = await repository.organizationBookings(target);
      if (_disposed || !identical(_organizationBookingsLoadToken, token)) {
        return;
      }
      organizationBookings = bookings;
      organizationBookingsStatus = DataStatus.ready;
    } catch (error) {
      if (_disposed || !identical(_organizationBookingsLoadToken, token)) {
        return;
      }
      organizationBookingsStatus = DataStatus.error;
      logError('organizationBookings', error);
    }
    notifyListeners();
  }

  // ---- band side
  List<Booking> bandBookings = const [];
  DataStatus bandBookingsStatus = DataStatus.connecting;
  Object? _bandBookingsLoadToken;

  Future<void> refreshBandBookings() async {
    if (_disposed) return;
    final token = Object();
    _bandBookingsLoadToken = token;
    if (bandId.isEmpty) {
      bandBookings = const [];
      bandBookingsStatus = DataStatus.ready;
      notifyListeners();
      return;
    }
    try {
      final bookings = await repository.bandBookings(bandId);
      if (_disposed || !identical(_bandBookingsLoadToken, token)) return;
      bandBookings = bookings;
      bandBookingsStatus = DataStatus.ready;
    } catch (error) {
      if (_disposed || !identical(_bandBookingsLoadToken, token)) return;
      bandBookingsStatus = DataStatus.error;
      logError('bandBookings', error);
    }
    notifyListeners();
  }

  // ---- detail cache
  final Map<String, Booking> _bookingById = {};
  final Map<String, BookingSide> _bookingSides = {};
  final Map<String, Object> _bookingByIdTokens = {};

  Booking? bookingById(String id) => _bookingById[id];

  Future<Booking?> loadBooking(
    String id, {
    bool refresh = false,
    BookingSide? viewAs,
  }) async {
    if (_disposed) return null;
    final cached = _bookingById[id];
    final sideMatches = viewAs == null || cached?.viewerSide == viewAs;
    if (!refresh && cached != null && sideMatches) return cached;
    final side = viewAs ?? _bookingSides[id];
    if (side != null) {
      _bookingSides[id] = side;
    } else {
      _bookingSides.remove(id);
    }
    final token = Object();
    _bookingByIdTokens[id] = token;
    try {
      final booking = await repository.booking(id, viewAs: side);
      if (_disposed || !identical(_bookingByIdTokens[id], token)) {
        return null;
      }
      if (booking != null && !identical(_bookingById[id], booking)) {
        _bookingById[id] = booking;
        notifyListeners();
      }
      return booking;
    } catch (error) {
      logError('booking', error);
      return null;
    }
  }

  void openBooking(String id, {BookingSide? viewAs}) {
    final side =
        viewAs ??
        switch (identity) {
          BandIdentity() => BookingSide.artist,
          OrganizerIdentity() => BookingSide.organizer,
          _ => null,
        };
    unawaited(loadBooking(id, viewAs: side));
    go(Screen.bookingDetail, id);
  }

  void openReviewCompose(String bookingId) =>
      go(Screen.reviewCompose, bookingId);

  // ---- identity for screens that already have a loaded booking
  ActiveIdentity identityForBooking(Booking booking) =>
      switch (booking.viewerSide) {
        BookingSide.organizer => OrganizerIdentity(
          booking.organizationId,
          organizerRoleFor(booking.organizationId),
        ),
        BookingSide.artist => BandIdentity(booking.bandId),
      };

  // ---- actions
  Future<String> sendOffer({
    required String applicationId,
    required int grossMinor,
    required CancellationTemplate cancellationTemplate,
    String? termsNotes,
    String? message,
  }) async {
    final result = await repository.sendOffer(
      applicationId: applicationId,
      grossMinor: grossMinor,
      cancellationTemplate: cancellationTemplate,
      termsNotes: termsNotes,
      message: message,
    );
    await refreshOrganizationBookings();
    return result.bookingId;
  }

  Future<Booking?> withdrawOffer(Booking booking) async {
    await repository.withdrawOffer(
      bookingId: booking.id,
      expectedRevision: booking.revision,
    );
    return _refreshAfterAction(booking);
  }

  Future<Booking?> respondToOffer(
    Booking booking, {
    required bool accept,
    String? message,
  }) async {
    await repository.respondToOffer(
      bookingId: booking.id,
      accept: accept,
      expectedRevision: booking.revision,
      message: message,
    );
    return _refreshAfterAction(booking);
  }

  Future<Booking?> cancelBooking(
    Booking booking, {
    required String reason,
  }) async {
    await repository.cancelBooking(
      bookingId: booking.id,
      reason: reason,
      expectedRevision: booking.revision,
      side: booking.viewerSide,
    );
    return _refreshAfterAction(booking);
  }

  Future<Booking?> _refreshAfterAction(Booking booking) async {
    final refreshed = await loadBooking(booking.id, refresh: true);
    if (booking.viewerSide == BookingSide.organizer) {
      await refreshOrganizationBookings(booking.organizationId);
    } else {
      await refreshBandBookings();
    }
    return refreshed;
  }

  Future<({String reviewId, bool visible})> submitReview({
    required String bookingId,
    required int rating,
    required List<String> categories,
    required String text,
  }) => repository.submitReview(
    bookingId: bookingId,
    rating: rating,
    categories: categories,
    text: text,
  );

  Future<BookingReviews?> loadBookingReviews(String bookingId) async {
    try {
      return await repository.reviewsForBooking(bookingId);
    } catch (error) {
      logError('reviewsForBooking', error);
      return null;
    }
  }

  // ---- band changes (chained after _OpportunityState)
  String _lastKnownBandIdForBookings = '';

  @override
  void _onBandChanged() {
    super._onBandChanged();
    if (_lastKnownBandIdForBookings == bandId) return;
    _lastKnownBandIdForBookings = bandId;
    unawaited(refreshBandBookings());
  }

  // ---- sign-out cleanup
  void _clearBookingState() {
    _organizationBookingsLoadToken = null;
    _bandBookingsLoadToken = null;
    _bookingByIdTokens.clear();
    _bookingSides.clear();
    _bookingById.clear();
    organizationBookings = const [];
    bandBookings = const [];
    organizationBookingsStatus = DataStatus.connecting;
    bandBookingsStatus = DataStatus.connecting;
    _lastKnownBandIdForBookings = '';
  }
}
