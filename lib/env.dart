abstract final class Env {
  static const String convexUrl = String.fromEnvironment('CONVEX_URL');
  static const String clerkPublishableKey = String.fromEnvironment(
    'CLERK_PUBLISHABLE_KEY',
  );
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  static const appleSignInEnabled = bool.fromEnvironment('APPLE_SIGN_IN_ENABLED');

  /// Demo mode must be asked for. It used to also switch itself on whenever
  /// `convexUrl` was empty, which meant a build that simply forgot
  /// `--dart-define=CONVEX_URL` served six invented bands as if they were real.
  /// A missing URL is now a startup error — see `main()`.
  static const bool demo = bool.fromEnvironment('EARPLUG_DEMO');
}
