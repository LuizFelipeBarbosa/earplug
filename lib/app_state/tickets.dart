part of '../app_state.dart';

mixin _TicketState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  Future<bool>? get _authReady;
  void go(Screen s, [String? param]);
  Future<void> Function(String url) get hostedUrlLauncher;

  List<TicketSummary> myTickets = const [];
  bool myTicketsLoaded = false;
  final Map<String, TicketSummary> _ticketById = {};
  TicketReservation? pendingReservation;
  final Map<String, TicketSales> _salesByGig = {};
  String? ticketReferralBandSlug;

  // Invalidate pending loads and polls when the session is cleared.
  Object _ticketSessionToken = Object();
  Object? _myTicketsLoadToken;

  Future<void> loadMyTickets({bool refresh = false}) async {
    if (_disposed) return;
    if (myTicketsLoaded && !refresh) return;
    final token = Object();
    _myTicketsLoadToken = token;
    try {
      await _authReady;
      if (_disposed || !identical(_myTicketsLoadToken, token)) return;
      final tickets = await repository.myTickets();
      if (_disposed || !identical(_myTicketsLoadToken, token)) return;
      myTickets = tickets;
      myTicketsLoaded = true;
      _ticketById
        ..clear()
        ..addEntries(tickets.map((ticket) => MapEntry(ticket.id, ticket)));
      notifyListeners();
    } catch (error) {
      logError('myTickets', error);
    }
  }

  TicketSummary? ticketById(String id) => _ticketById[id];

  Future<TicketSummary?> loadTicket(String id, {bool refresh = false}) async {
    if (_disposed) return null;
    final cached = _ticketById[id];
    if (!refresh && cached != null) return cached;
    final token = _ticketSessionToken;
    try {
      await _authReady;
      if (_disposed || !identical(_ticketSessionToken, token)) return null;
      final ticket = await repository.ticket(id);
      if (_disposed || !identical(_ticketSessionToken, token)) return null;
      if (ticket != null) {
        _ticketById[id] = ticket;
        final index = myTickets.indexWhere((item) => item.id == id);
        if (index != -1) {
          myTickets = [...myTickets]..[index] = ticket;
        }
        notifyListeners();
      }
      return ticket;
    } catch (error) {
      logError('ticket', error);
      if (_disposed || !identical(_ticketSessionToken, token)) return null;
      return _ticketById[id];
    }
  }

  Future<TicketReservation> reserveTickets(
    String gigId,
    int quantity, {
    String? referralBandSlug,
  }) async {
    final token = _ticketSessionToken;
    final reservation = await repository.reserveTickets(
      gigId: gigId,
      quantity: quantity,
      referralBandSlug: referralBandSlug ?? ticketReferralBandSlug,
    );
    if (_disposed || !identical(_ticketSessionToken, token)) return reservation;
    pendingReservation = reservation;
    notifyListeners();
    return reservation;
  }

  Future<void> releaseReservation() async {
    if (_disposed) return;
    final reservation = pendingReservation;
    if (reservation == null) return;
    final orderId = reservation.orderId;
    pendingReservation = null;
    notifyListeners();
    try {
      await repository.cancelTicketReservation(orderId);
    } catch (error) {
      if (error.toString().toLowerCase().contains('already')) return;
      logError('cancelTicketReservation', error);
    }
  }

  Future<String> startTicketCheckout(String orderId) async {
    final result = await repository.startTicketCheckout(orderId);
    if (!_disposed) await hostedUrlLauncher(result.url);
    return result.sessionId;
  }

  Future<TicketOrderState?> awaitTicketCheckout(
    String sessionId, {
    Duration timeout = const Duration(seconds: 60),
    Duration interval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    final token = _ticketSessionToken;
    TicketOrderState? completed;
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed || !identical(_ticketSessionToken, token)) return null;
      try {
        final status = await repository.ticketOrderStatus(sessionId);
        if (_disposed || !identical(_ticketSessionToken, token)) return null;
        if (status != null &&
            const {
              TicketOrderStatus.paid,
              TicketOrderStatus.expired,
              TicketOrderStatus.cancelled,
              TicketOrderStatus.refunded,
            }.contains(status.status)) {
          completed = status;
          break;
        }
      } catch (error) {
        logError('ticketOrderStatus', error);
      }
      if (_disposed || !identical(_ticketSessionToken, token)) return null;
      if (!DateTime.now().isBefore(deadline)) break;
      await Future<void>.delayed(interval);
    }
    if (_disposed || !identical(_ticketSessionToken, token)) return null;
    if (completed != null) {
      pendingReservation = null;
      notifyListeners();
      unawaited(loadMyTickets(refresh: true));
    }
    return completed;
  }

  Future<TicketSales?> loadTicketSales(
    String gigId, {
    bool refresh = false,
  }) async {
    if (_disposed) return null;
    final cached = _salesByGig[gigId];
    if (!refresh && cached != null) return cached;
    final token = _ticketSessionToken;
    try {
      final sales = await repository.ticketSalesForGig(gigId);
      if (_disposed || !identical(_ticketSessionToken, token)) return sales;
      _salesByGig[gigId] = sales;
      notifyListeners();
      return sales;
    } catch (error) {
      logError('ticketSalesForGig', error);
      return _salesByGig[gigId];
    }
  }

  TicketSales? salesFor(String gigId) => _salesByGig[gigId];

  Future<TicketDoorResult> organizerCheckIn(String gigId, String payload) =>
      repository.organizerCheckIn(gigId: gigId, payload: payload);

  Future<DoorCounts> organizerDoorRoster(String gigId) =>
      repository.organizerDoorRoster(gigId);

  void openTicket(String id) => go(Screen.ticket, id);

  void openMyTickets() => go(Screen.myTickets);

  // ---- sign-out cleanup
  void _clearTicketState() {
    _ticketSessionToken = Object();
    _myTicketsLoadToken = null;
    myTickets = const [];
    myTicketsLoaded = false;
    _ticketById.clear();
    pendingReservation = null;
    _salesByGig.clear();
  }
}
