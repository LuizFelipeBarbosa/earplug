import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'connection_budget.dart';
import 'convex_debug_stats.dart';
import 'convex_transport.dart';

class ConvexService {
  ConvexService({ConvexTransport? transport})
    : _transport = transport ?? ConvexClientTransport();

  static const _cancelGracePeriod = Duration(milliseconds: 250);

  /// Process-global because the production transport mirrors Convex's singleton.
  static final ValueNotifier<ConvexDebugStats> debugStats = ValueNotifier(
    const ConvexDebugStats(
      activeSubscriptions: 0,
      transitionsReceived: 0,
      bytesReceived: 0,
      duplicatePayloadsSkipped: 0,
      lastTransitionBytes: 0,
    ),
  );

  final ConvexTransport _transport;
  final Map<String, _SharedSubscription> _subscriptions = {};
  bool _initialized = false;

  /// Injected transports initialize here too, so tests can use a no-op fake.
  Future<void> init(String url) async {
    await _transport.initialize(url);
    _initialized = true;
  }

  /// Returns the decoded top-level JSON value as-is, including `null`.
  Future<dynamic> query(String name, [Map<String, dynamic>? args]) async {
    final transport = _requireTransport();
    final result = await _runConnected(
      transport,
      () => transport.query(name, args ?? {}),
    );
    return _decode(result);
  }

  /// Returns the decoded top-level JSON value as-is, including `null`.
  Future<dynamic> mutation(String name, [Map<String, dynamic>? args]) async {
    final transport = _requireTransport();
    final result = await _runConnected(
      transport,
      () => transport.mutation(name: name, args: args ?? {}),
    );
    return _decode(result);
  }

  /// Passes each decoded payload directly to [parse].
  ///
  /// A JSON `null` payload is passed through as `null`, so parsers may handle
  /// it when the subscribed function can return null.
  Stream<T> subscribe<T>(
    String name,
    Map<String, dynamic> args,
    T Function(dynamic decoded) parse,
  ) {
    _requireTransport();
    final key = _canonicalKey(name, args);
    _SharedSubscription? attachedEntry;
    late final _TypedSharedListener<T> listener;
    late final StreamController<T> controller;

    controller = StreamController<T>.broadcast(
      onListen: () {
        attachedEntry = _attachListener(
          key: key,
          name: name,
          args: args,
          listener: listener,
        );
      },
      onCancel: () {
        final entry = attachedEntry;
        attachedEntry = null;
        if (entry != null) {
          _detachListener(entry, listener);
        }
      },
    );
    listener = _TypedSharedListener<T>(controller: controller, parse: parse);
    return controller.stream;
  }

  Future<String?> Function()? _fetchToken;

  void setTokenFetcher(Future<String?> Function()? fetchToken) {
    _fetchToken = fetchToken;
    unawaited(refreshAuth());
  }

  /// Re-applies the current token fetcher — call after the user signs in or
  /// out so the websocket picks up the new identity immediately. Completes
  /// once the new identity has been sent to the server.
  Future<void> refreshAuth() async {
    final transport = _requireTransport();
    final fetchToken = _fetchToken;
    if (fetchToken == null) {
      await transport.clearAuth();
      return;
    }
    await transport.setAuthWithRefresh(fetchToken: fetchToken);
  }

  _SharedSubscription _attachListener({
    required String key,
    required String name,
    required Map<String, dynamic> args,
    required _SharedListener listener,
  }) {
    final entry = _subscriptions.putIfAbsent(key, () {
      _changeActiveSubscriptionCount(1);
      return _SharedSubscription(
        key: key,
        name: name,
        args: Map<String, dynamic>.unmodifiable(args),
      );
    });

    final wasEmpty = entry.listenerCount == 0;
    if (entry.listeners.add(listener)) {
      entry.listenerCount++;
    }

    if (wasEmpty) {
      entry.cancelTimer?.cancel();
      entry.cancelTimer = null;
    }

    if (entry.errored && (entry.handle != null || entry.isStarting)) {
      entry.handle?.cancel();
      entry
        ..handle = null
        ..errored = false
        ..lastRaw = null
        ..lastDecoded = null
        ..hasDecodedValue = false;
      _startSubscription(entry);
    } else if (entry.handle == null && !entry.isStarting) {
      _startSubscription(entry);
    }

    if (entry.hasDecodedValue) {
      listener.emit(entry.lastDecoded);
    }
    return entry;
  }

  void _detachListener(_SharedSubscription entry, _SharedListener listener) {
    if (!entry.listeners.remove(listener)) return;

    entry.listenerCount--;
    if (entry.listenerCount != 0) return;

    entry.cancelTimer = Timer(_cancelGracePeriod, () {
      if (entry.listenerCount != 0) return;

      entry.cancelTimer = null;
      entry.generation++;
      entry.handle?.cancel();
      entry.handle = null;
      entry.isStarting = false;
      if (identical(_subscriptions[entry.key], entry)) {
        _subscriptions.remove(entry.key);
        _changeActiveSubscriptionCount(-1);
      }
    });
  }

  void _startSubscription(_SharedSubscription entry) {
    entry.isStarting = true;
    final generation = ++entry.generation;
    unawaited(_startSubscriptionForGeneration(entry, generation));
  }

  Future<void> _startSubscriptionForGeneration(
    _SharedSubscription entry,
    int generation,
  ) async {
    try {
      final handle = await _runConnected(
        _transport,
        () => _transport.subscribe(
          name: entry.name,
          args: entry.args,
          onUpdate: (raw) {
            if (generation != entry.generation) return;
            _handleUpdate(entry, raw);
          },
          onError: (message, value) {
            if (generation != entry.generation) return;
            entry
              ..errored = true
              ..lastRaw = null
              ..lastDecoded = null
              ..hasDecodedValue = false;
            final detail = value == null ? message : '$message: $value';
            _addErrorToListeners(entry, Exception(detail));
          },
        ),
      );

      if (generation == entry.generation &&
          identical(_subscriptions[entry.key], entry)) {
        entry.handle = handle;
        entry.isStarting = false;
      } else {
        handle.cancel();
      }
    } catch (error, stackTrace) {
      if (generation == entry.generation &&
          identical(_subscriptions[entry.key], entry)) {
        entry.isStarting = false;
        _addErrorToListeners(entry, error, stackTrace);
      }
    }
  }

  void _handleUpdate(_SharedSubscription entry, String raw) {
    entry.errored = false;
    final isDuplicate = entry.lastRaw != null && raw == entry.lastRaw;
    _recordTransition(raw.length, isDuplicate: isDuplicate);
    if (isDuplicate) return;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (error, stackTrace) {
      _addErrorToListeners(entry, error, stackTrace);
      return;
    }

    entry
      ..lastRaw = raw
      ..lastDecoded = decoded
      ..hasDecodedValue = true;
    for (final listener in List<_SharedListener>.of(entry.listeners)) {
      listener.emit(decoded);
    }
  }

  void _addErrorToListeners(
    _SharedSubscription entry,
    Object error, [
    StackTrace? stackTrace,
  ]) {
    for (final listener in List<_SharedListener>.of(entry.listeners)) {
      listener.addError(error, stackTrace);
    }
  }

  ConvexTransport _requireTransport() {
    if (!_initialized) {
      throw StateError('ConvexService has not been initialized');
    }
    return _transport;
  }

  Future<T> _runConnected<T>(
    ConvexTransport transport,
    Future<T> Function() operation,
  ) {
    return runWithConnectionBudget(
      connected: transport.isConnected,
      connectionStates: transport.connectionState,
      timeout: transport.operationTimeout,
      operation: operation,
    );
  }

  void _changeActiveSubscriptionCount(int delta) {
    final current = debugStats.value;
    debugStats.value = current.copyWith(
      activeSubscriptions: current.activeSubscriptions + delta,
    );
  }

  void _recordTransition(int bytes, {required bool isDuplicate}) {
    final current = debugStats.value;
    debugStats.value = current.copyWith(
      transitionsReceived: current.transitionsReceived + 1,
      bytesReceived: current.bytesReceived + bytes,
      duplicatePayloadsSkipped:
          current.duplicatePayloadsSkipped + (isDuplicate ? 1 : 0),
      lastTransitionBytes: bytes,
      lastTransitionAt: DateTime.now(),
    );
  }

  dynamic _decode(String value) => jsonDecode(value);
}

class _SharedSubscription {
  _SharedSubscription({
    required this.key,
    required this.name,
    required this.args,
  });

  final String key;
  final String name;
  final Map<String, dynamic> args;
  final Set<_SharedListener> listeners = {};
  ConvexTransportSubscription? handle;
  Timer? cancelTimer;
  String? lastRaw;
  Object? lastDecoded;
  bool hasDecodedValue = false;
  bool errored = false;
  bool isStarting = false;
  int listenerCount = 0;
  int generation = 0;
}

abstract interface class _SharedListener {
  void emit(Object? decoded);

  void addError(Object error, [StackTrace? stackTrace]);
}

class _TypedSharedListener<T> implements _SharedListener {
  const _TypedSharedListener({required this.controller, required this.parse});

  final StreamController<T> controller;
  final T Function(dynamic decoded) parse;

  @override
  void emit(Object? decoded) {
    try {
      controller.add(parse(decoded));
    } catch (error, stackTrace) {
      controller.addError(error, stackTrace);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    controller.addError(error, stackTrace);
  }
}

String _canonicalKey(String name, Map<String, dynamic> args) {
  return '$name|${jsonEncode(_sortMapKeys(args))}';
}

Object? _sortMapKeys(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return <String, dynamic>{
      for (final key in keys) key: _sortMapKeys(value[key]),
    };
  }
  if (value is List<dynamic>) {
    return <Object?>[for (final item in value) _sortMapKeys(item)];
  }
  return value;
}
