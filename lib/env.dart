abstract final class Env {
  static const String convexUrl = String.fromEnvironment('CONVEX_URL');
  static const String clerkPublishableKey = String.fromEnvironment(
    'CLERK_PUBLISHABLE_KEY',
  );
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  static const appleSignInEnabled = bool.fromEnvironment('APPLE_SIGN_IN_ENABLED');

  static bool get demo =>
      const bool.fromEnvironment('EARPLUG_DEMO') || convexUrl.isEmpty;
}
