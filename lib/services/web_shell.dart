import 'web_shell_stub.dart' if (dart.library.js_interop) 'web_shell_web.dart';

export 'web_shell_stub.dart' if (dart.library.js_interop) 'web_shell_web.dart';

abstract class WebShell {
  void removeSplash();

  void mark(String name);

  List<({String name, double ms})> marks();
}

final WebShell webShell = createWebShell();
