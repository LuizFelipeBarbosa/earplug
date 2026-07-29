abstract final class Env {
  static const String convexUrl = String.fromEnvironment('CONVEX_URL');
  static const String clerkPublishableKey = String.fromEnvironment(
    'CLERK_PUBLISHABLE_KEY',
  );

  static bool get demo =>
      const bool.fromEnvironment('EARPLUG_DEMO') || convexUrl.isEmpty;
}
