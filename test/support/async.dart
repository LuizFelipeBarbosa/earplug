/// Drains a few rounds of the event queue so stream subscriptions, awaited
/// repository calls, and the notifications they trigger all settle.
Future<void> flushAsyncWork() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
