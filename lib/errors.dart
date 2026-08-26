import 'package:flutter/foundation.dart';

/// What the app says when something went wrong that it cannot explain to the
/// user in their own terms. One string so every surface says it the same way.
const String genericErrorMessage = 'Something broke. Try again.';

/// Profile setup writes deserve a useful recovery message even when the
/// backend's detailed error is intentionally kept out of the UI.
const String profileSetupSaveErrorMessage =
    "Couldn't save your profile setup. Try again.";

/// The new-fan card writes several fields through one backend mutation.
const String fanSetupSaveErrorMessage =
    "Couldn't save your setup choices. Try again.";

/// Records a failure the caller deliberately swallows.
///
/// Swallowing is often right — a background refresh that fails should not take
/// the screen down with it — but doing it silently leaves nothing to debug.
/// [what] names the operation, e.g. `'createBand'`.
void logError(String what, Object error) {
  debugPrint('$what failed: $error');
}
