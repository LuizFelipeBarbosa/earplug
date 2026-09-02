import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'web_shell.dart';

WebShell createWebShell() => _BrowserWebShell();

class _BrowserWebShell implements WebShell {
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
}
