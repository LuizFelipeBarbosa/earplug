import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'web_shell.dart';

WebShell createWebShell() => _BrowserWebShell();

class _BrowserWebShell implements WebShell {
  static const _a11yPreferenceKey = 'ep:a11y';

  @override
  void downloadTextFile(String filename, String text) {
    final bytes = Uint8List.fromList(utf8.encode(text));
    downloadBytes(filename, bytes, 'text/csv');
  }

  @override
  void downloadBytes(String filename, Uint8List bytes, String mimeType) {
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final objectUrl = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = objectUrl
      ..download = filename;
    try {
      web.document.body?.append(anchor);
      anchor.click();
    } finally {
      anchor.remove();
      Timer(const Duration(seconds: 60), () {
        web.URL.revokeObjectURL(objectUrl);
      });
    }
  }

  @override
  void removeSplash() {
    web.document.getElementById('ep-splash')?.remove();
  }

  @override
  void mark(String name) {
    web.window.performance.mark(name);
  }

  @override
  List<({String name, double ms})> marks() {
    return [
      for (final entry
          in web.window.performance.getEntriesByType('mark').toDart)
        (name: entry.name, ms: entry.startTime),
    ];
  }

  @override
  bool readA11yPreference() {
    try {
      return web.window.localStorage.getItem(_a11yPreferenceKey) == '1';
    } catch (_) {
      return false;
    }
  }

  @override
  void writeA11yPreference(bool enabled) {
    try {
      if (enabled) {
        web.window.localStorage.setItem(_a11yPreferenceKey, '1');
      } else {
        web.window.localStorage.removeItem(_a11yPreferenceKey);
      }
    } catch (_) {}
  }
}
