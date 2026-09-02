import 'package:convex_flutter/convex_flutter.dart';

abstract interface class ConvexTransportSubscription {
  void cancel();
}

/// The portion of [ConvexClient] used by [ConvexService].
abstract interface class ConvexTransport {
  Future<void> initialize(String url);

  Future<String> query(String name, Map<String, dynamic> args);

  Future<String> mutation({
    required String name,
    required Map<String, dynamic> args,
  });

  Future<ConvexTransportSubscription> subscribe({
    required String name,
    required Map<String, dynamic> args,
    required void Function(String) onUpdate,
    required void Function(String, String?) onError,
  });

  bool get isConnected;

  Stream<WebSocketConnectionState> get connectionState;

  Duration get operationTimeout;

  Future<void> setAuthWithRefresh({
    required Future<String?> Function() fetchToken,
  });

  Future<void> clearAuth();
}

/// Production transport backed by the package-wide [ConvexClient] singleton.
class ConvexClientTransport implements ConvexTransport {
  ConvexClient? _client;

  @override
  Future<void> initialize(String url) async {
    await ConvexClient.initialize(ConvexConfig(deploymentUrl: url));
    _client = ConvexClient.instance;
  }

  @override
  Future<String> query(String name, Map<String, dynamic> args) {
    return _requireClient().query(name, args);
  }

  @override
  Future<String> mutation({
    required String name,
    required Map<String, dynamic> args,
  }) {
    return _requireClient().mutation(name: name, args: args);
  }

  @override
  Future<ConvexTransportSubscription> subscribe({
    required String name,
    required Map<String, dynamic> args,
    required void Function(String) onUpdate,
    required void Function(String, String?) onError,
  }) async {
    final handle = await _requireClient().subscribe(
      name: name,
      args: args,
      onUpdate: onUpdate,
      onError: onError,
    );
    return _ConvexClientSubscription(handle);
  }

  @override
  bool get isConnected => _requireClient().isConnected;

  @override
  Stream<WebSocketConnectionState> get connectionState {
    return _requireClient().connectionState;
  }

  @override
  Duration get operationTimeout => _requireClient().config.operationTimeout;

  @override
  Future<void> setAuthWithRefresh({
    required Future<String?> Function() fetchToken,
  }) async {
    await _requireClient().setAuthWithRefresh(fetchToken: fetchToken);
  }

  @override
  Future<void> clearAuth() => _requireClient().clearAuth();

  ConvexClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('Convex transport has not been initialized');
    }
    return client;
  }
}

class _ConvexClientSubscription implements ConvexTransportSubscription {
  const _ConvexClientSubscription(this._handle);

  final SubscriptionHandle _handle;

  @override
  void cancel() => _handle.cancel();
}
