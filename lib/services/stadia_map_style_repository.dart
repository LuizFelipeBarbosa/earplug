import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:http/http.dart' as http;

class MapStyleConfigurationException implements Exception {
  const MapStyleConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StadiaMapStyleRepository {
  StadiaMapStyleRepository({
    this.apiKey = '',
    http.Client? httpClient,
    this.cacheStyleBundles = true,
    this.resolveProvider,
  }) : _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null;

  static const lightStyleUrl =
      'https://tiles.stadiamaps.com/styles/alidade_smooth.json';
  static const darkStyleUrl =
      'https://tiles.stadiamaps.com/styles/alidade_smooth_dark.json';

  final String apiKey;
  final bool cacheStyleBundles;
  final Future<vt.VectorTileProvider?> Function(String sourceId)?
  resolveProvider;
  final http.Client _client;
  final bool _ownsClient;
  final Map<Brightness, Future<vt.Style>> _loads = {};
  final Map<Brightness, vt.Style> _styles = {};
  final Map<Brightness, int> _epochs = {};
  bool _disposed = false;

  Future<vt.Style> load(Brightness brightness) {
    if (_disposed) {
      return Future.error(StateError('Map style repository is disposed.'));
    }
    return _loads.putIfAbsent(brightness, () {
      final epoch = _epochs[brightness] ?? 0;
      return _load(brightness, epoch);
    });
  }

  Future<vt.Style> _load(Brightness brightness, int epoch) async {
    if (!kIsWeb && apiKey.isEmpty) {
      throw const MapStyleConfigurationException(
        'STADIA_MAPS_API_KEY is required for native maps.',
      );
    }

    final baseUrl = brightness == Brightness.dark
        ? darkStyleUrl
        : lightStyleUrl;
    final uri = apiKey.isEmpty
        ? baseUrl
        : Uri.parse(
            baseUrl,
          ).replace(queryParameters: {'api_key': apiKey}).toString();
    final style = await vt.StyleReader(
      uri: uri,
      httpClient: _client,
      logger: kDebugMode ? const vt.Logger.console() : const vt.Logger.noop(),
      cache: cacheStyleBundles,
      refreshAfter: const Duration(hours: 12),
      resolveProvider: resolveProvider,
    ).read();

    if (_disposed || (_epochs[brightness] ?? 0) != epoch) {
      style.dispose();
      throw StateError('Map style load was superseded.');
    }
    _styles[brightness] = style;

    final opposite = brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    unawaited(load(opposite).catchError((Object _) => style));
    return style;
  }

  void retry(Brightness brightness) {
    _epochs[brightness] = (_epochs[brightness] ?? 0) + 1;
    _loads.remove(brightness);
    _styles.remove(brightness)?.dispose();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final brightness in Brightness.values) {
      _epochs[brightness] = (_epochs[brightness] ?? 0) + 1;
    }
    for (final style in _styles.values) {
      style.dispose();
    }
    _styles.clear();
    _loads.clear();
    if (_ownsClient) _client.close();
  }
}
