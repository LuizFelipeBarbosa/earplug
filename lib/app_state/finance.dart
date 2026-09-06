part of '../app_state.dart';

mixin _FinanceState on _AppStateCore {
  // ---- requires (declared by sibling mixins or AppState)
  String get organizationId;
  Future<bool>? get _authReady;
  void resetTo(Screen s);
  void go(Screen s, [String? param]);

  FinanceOverview? financeOverview;
  bool financeLoading = false;
  Object? financeError;
  List<FinanceTransaction> transactions = const [];
  String? transactionsCursor;
  bool transactionsDone = false;
  bool transactionsLoading = false;
  final Map<String, ArtistInsights> _insightsByApplication = {};
  final Map<String, ArtistInsights> _insightsByBand = {};

  Future<void> Function(String filename, String text) textFileDownloader =
      (filename, text) async => webShell.downloadTextFile(filename, text);

  // Invalidate pending loads when superseded or when the session is cleared.
  Object? _financeLoadToken;
  Object? _balanceLoadToken;
  Object? _transactionsLoadToken;
  final Map<String, Object> _applicationInsightsLoadTokens = {};
  final Map<String, Object> _bandInsightsLoadTokens = {};

  Future<void> loadFinance({bool refresh = false}) async {
    if (_disposed) return;
    if (financeOverview != null && !refresh) return;
    final token = Object();
    _financeLoadToken = token;
    _balanceLoadToken = null;
    financeLoading = true;
    notifyListeners();
    try {
      await _authReady;
      if (_disposed || !identical(_financeLoadToken, token)) return;
      final target = organizationId;
      if (target.isEmpty) {
        financeLoading = false;
        notifyListeners();
        return;
      }
      final overview = await repository.financeOverview(target);
      if (_disposed || !identical(_financeLoadToken, token)) return;
      financeLoading = false;
      if (organizationId != target) {
        notifyListeners();
        return;
      }
      financeOverview = overview;
      financeError = null;
      notifyListeners();
      if (overview.stripeReady) unawaited(refreshFinanceBalance());
    } catch (error) {
      logError('financeOverview', error);
      if (_disposed || !identical(_financeLoadToken, token)) return;
      financeError = error;
      financeLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshFinanceBalance() async {
    if (_disposed) return;
    final target = organizationId;
    final token = Object();
    _balanceLoadToken = token;
    if (target.isEmpty) return;
    try {
      await _authReady;
      if (_disposed ||
          organizationId != target ||
          !identical(_balanceLoadToken, token)) {
        return;
      }
      final snapshot = await repository.refreshFinanceBalance(target);
      if (_disposed ||
          organizationId != target ||
          !identical(_balanceLoadToken, token)) {
        return;
      }
      final overview = financeOverview;
      if (snapshot == null || overview == null) return;
      financeOverview = FinanceOverview(
        stripeReady: overview.stripeReady,
        snapshot: snapshot,
        bookings: overview.bookings,
        tickets: overview.tickets,
        pendingPayments: overview.pendingPayments,
        currency: overview.currency,
      );
      notifyListeners();
    } catch (error) {
      logError('refreshFinanceBalance', error);
    }
  }

  Future<void> loadTransactions({bool reset = false}) async {
    if (_disposed || transactionsLoading) return;
    if (!reset && transactionsDone) return;
    if (reset) {
      transactions = const [];
      transactionsCursor = null;
      transactionsDone = false;
    }
    final token = Object();
    _transactionsLoadToken = token;
    transactionsLoading = true;
    notifyListeners();
    try {
      await _authReady;
      if (_disposed || !identical(_transactionsLoadToken, token)) return;
      final target = organizationId;
      if (target.isEmpty) {
        transactionsLoading = false;
        notifyListeners();
        return;
      }
      final page = await repository.financeTransactions(
        target,
        numItems: 25,
        cursor: reset ? null : transactionsCursor,
      );
      if (_disposed || !identical(_transactionsLoadToken, token)) return;
      transactionsLoading = false;
      if (organizationId != target) {
        notifyListeners();
        return;
      }
      transactions = [...transactions, ...page.items];
      transactionsCursor = page.continueCursor;
      transactionsDone = page.isDone;
      notifyListeners();
    } catch (error) {
      logError('financeTransactions', error);
      if (_disposed || !identical(_transactionsLoadToken, token)) return;
      transactionsLoading = false;
      notifyListeners();
    }
  }

  Future<StatementExport> exportStatement(DateTime from, DateTime to) async {
    final result = await repository.exportStatement(
      organizationId,
      from: from,
      to: to,
    );
    await textFileDownloader(
      'earplug-statement-${_dateStamp(from)}-${_dateStamp(to)}.csv',
      result.csv,
    );
    return result;
  }

  Future<ArtistInsights?> loadApplicantInsights(
    String applicationId, {
    bool refresh = false,
  }) async {
    if (_disposed) return null;
    final cached = _insightsByApplication[applicationId];
    if (!refresh && cached != null) return cached;
    final token = Object();
    _applicationInsightsLoadTokens[applicationId] = token;
    try {
      final insights = await repository.artistInsights(applicationId);
      if (_disposed ||
          !identical(_applicationInsightsLoadTokens[applicationId], token)) {
        return null;
      }
      _insightsByApplication[applicationId] = insights;
      notifyListeners();
      return insights;
    } catch (error) {
      logError('artistInsights', error);
      if (_disposed ||
          !identical(_applicationInsightsLoadTokens[applicationId], token)) {
        return null;
      }
      return _insightsByApplication[applicationId];
    }
  }

  ArtistInsights? insightsForApplication(String applicationId) =>
      _insightsByApplication[applicationId];

  Future<ArtistInsights?> loadMyBandInsights(
    String bandId, {
    bool refresh = false,
  }) async {
    if (_disposed) return null;
    final cached = _insightsByBand[bandId];
    if (!refresh && cached != null) return cached;
    final token = Object();
    _bandInsightsLoadTokens[bandId] = token;
    try {
      final insights = await repository.myBandInsights(bandId);
      if (_disposed || !identical(_bandInsightsLoadTokens[bandId], token)) {
        return null;
      }
      _insightsByBand[bandId] = insights;
      notifyListeners();
      return insights;
    } catch (error) {
      logError('myBandInsights', error);
      if (_disposed || !identical(_bandInsightsLoadTokens[bandId], token)) {
        return null;
      }
      return _insightsByBand[bandId];
    }
  }

  ArtistInsights? bandInsights(String bandId) => _insightsByBand[bandId];

  Future<int> updateOpportunityTicketing({
    required String opportunityId,
    required int expectedRevision,
    required int ticketPriceMinor,
    required int ticketCapacity,
  }) => repository.updateOpportunityTicketing(
    opportunityId: opportunityId,
    expectedRevision: expectedRevision,
    ticketPriceMinor: ticketPriceMinor,
    ticketCapacity: ticketCapacity,
  );

  void openFinance() => resetTo(Screen.orgFinance);

  void openTransactions() => go(Screen.orgTransactions);

  // ---- organization changes
  String _lastKnownOrganizationIdForFinance = '';

  @override
  void _onOrganizationChanged() {
    if (_lastKnownOrganizationIdForFinance == organizationId) return;
    _lastKnownOrganizationIdForFinance = organizationId;
    if (organizationId.isEmpty) {
      _clearFinanceState();
      notifyListeners();
      return;
    }
    unawaited(loadFinance(refresh: true));
  }

  // ---- sign-out cleanup
  void _clearFinanceState() {
    _financeLoadToken = null;
    _balanceLoadToken = null;
    _transactionsLoadToken = null;
    _applicationInsightsLoadTokens.clear();
    _bandInsightsLoadTokens.clear();
    financeOverview = null;
    financeLoading = false;
    financeError = null;
    transactions = const [];
    transactionsCursor = null;
    transactionsDone = false;
    transactionsLoading = false;
    _insightsByApplication.clear();
    _insightsByBand.clear();
    _lastKnownOrganizationIdForFinance = '';
  }
}

String _dateStamp(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
