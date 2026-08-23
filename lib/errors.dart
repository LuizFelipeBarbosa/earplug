import 'package:flutter/foundation.dart';

/// What the app says when something went wrong that it cannot explain to the
/// user in their own terms. One string so every surface says it the same way.
const String genericErrorMessage = 'Something broke. Try again.';

/// Records a failure the caller deliberately swallows.
///
/// Swallowing is often right — a background refresh that fails should not take
/// the screen down with it — but doing it silently leaves nothing to debug.
/// [what] names the operation, e.g. `'createBand'`.
void logError(String what, Object error) {
  debugPrint('$what failed: $error');
}
