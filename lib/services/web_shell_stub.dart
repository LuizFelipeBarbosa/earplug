import 'web_shell.dart';

WebShell createWebShell() => _StubWebShell();

class _StubWebShell implements WebShell {
  @override
  void removeSplash() {}

  @override
  void mark(String name) {}

  @override
  List<({String name, double ms})> marks() => const [];

  @override
  bool readA11yPreference() => false;

  @override
  void writeA11yPreference(bool enabled) {}
}
