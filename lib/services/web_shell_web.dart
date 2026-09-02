import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_shell.dart';

WebShell createWebShell() => _BrowserWebShell();

class _BrowserWebShell implements WebShell {
  static const _a11yPreferenceKey = 'ep:a11y';

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
