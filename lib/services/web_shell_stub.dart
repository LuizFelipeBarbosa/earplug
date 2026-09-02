import 'web_shell.dart';

WebShell createWebShell() => _StubWebShell();

class _StubWebShell implements WebShell {
  @override
  void removeSplash() {}

  @override
  void mark(String name) {}

  @override
  List<({String name, double ms})> marks() => const [];
}
