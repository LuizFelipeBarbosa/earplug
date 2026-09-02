import 'web_shell_stub.dart' if (dart.library.js_interop) 'web_shell_web.dart';

export 'web_shell_stub.dart' if (dart.library.js_interop) 'web_shell_web.dart';

abstract class WebShell {
  void removeSplash();

  void mark(String name);

  List<({String name, double ms})> marks();

  /// Returns whether eager web semantics were enabled in this browser.
  bool readA11yPreference();

  /// Persists or clears the browser preference for eager web semantics.
  void writeA11yPreference(bool enabled);
}

final WebShell webShell = createWebShell();
