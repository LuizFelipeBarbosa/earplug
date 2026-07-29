import 'dart:async';
import 'dart:convert';

import 'package:convex_flutter/convex_flutter.dart';

class ConvexService {
  ConvexClient? _client;

  Future<void> init(String url) async {
    await ConvexClient.initialize(ConvexConfig(deploymentUrl: url));
    _client = ConvexClient.instance;
  }

  /// Returns the decoded top-level JSON value as-is, including `null`.
  Future<dynamic> query(String name, [Map<String, dynamic>? args]) async {
    final client = _requireClient();
    await _waitUntilConnected(client);
    return _decode(await client.query(name, args ?? {}));
  }

  /// Returns the decoded top-level JSON value as-is, including `null`.
  Future<dynamic> mutation(String name, [Map<String, dynamic>? args]) async {
    final client = _requireClient();
    await _waitUntilConnected(client);
    return _decode(await client.mutation(name: name, args: args ?? {}));
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
    final client = _requireClient();
    SubscriptionHandle? handle;
    var currentGeneration = 0;
    late final StreamController<T> controller;

    Future<void> startSubscription(int generation) async {
      try {
        await _waitUntilConnected(client);
        if (generation != currentGeneration) return;

        final subscription = await client.subscribe(
          name: name,
          args: args,
          onUpdate: (value) {
            if (generation != currentGeneration) return;

            try {
              final decoded = jsonDecode(value);
              controller.add(parse(decoded));
            } catch (error, stackTrace) {
              controller.addError(error, stackTrace);
            }
          },
          onError: (message, value) {
            if (generation != currentGeneration) return;

            final detail = value == null ? message : '$message: $value';
            controller.addError(Exception(detail));
          },
        );

        if (generation == currentGeneration) {
          handle = subscription;
        } else {
          subscription.cancel();
        }
      } catch (error, stackTrace) {
        if (generation == currentGeneration) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller = StreamController<T>.broadcast(
      onListen: () {
        final generation = ++currentGeneration;
        unawaited(startSubscription(generation));
      },
      onCancel: () {
        currentGeneration++;
        handle?.cancel();
        handle = null;
      },
    );

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
    final client = _requireClient();
    final fetchToken = _fetchToken;
    if (fetchToken == null) {
      await client.clearAuth();
      return;
    }
    await client.setAuthWithRefresh(fetchToken: fetchToken);
  }

  ConvexClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('ConvexService has not been initialized');
    }
    return client;
  }

  Future<void> _waitUntilConnected(ConvexClient client) async {
    if (client.isConnected) return;
    await client.connectionState.firstWhere(
      (state) => state == WebSocketConnectionState.connected,
    );
  }

  dynamic _decode(String value) => jsonDecode(value);
}
