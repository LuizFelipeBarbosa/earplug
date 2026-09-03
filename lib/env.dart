import 'dart:convert';

/// Which backend/auth pairing a build is wired to.
enum DeploymentTier {
  development('DEV'),
  production('PROD');

  const DeploymentTier(this.label);

  final String label;
}

abstract final class Env {
  static const String convexUrl = String.fromEnvironment('CONVEX_URL');
  static const String clerkPublishableKey = String.fromEnvironment(
    'CLERK_PUBLISHABLE_KEY',
  );
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );
  static const String stadiaMapsApiKey = String.fromEnvironment(
    'STADIA_MAPS_API_KEY',
  );
  static const bool emailSignInEnabled = bool.fromEnvironment(
    'EMAIL_SIGN_IN_ENABLED',
  );
  static const bool googleSignInEnabled = bool.fromEnvironment(
    'GOOGLE_SIGN_IN_ENABLED',
  );
  static const bool appleSignInEnabled = bool.fromEnvironment(
    'APPLE_SIGN_IN_ENABLED',
  );

  /// Demo mode must be asked for. It used to also switch itself on whenever
  /// `convexUrl` was empty, which meant a build that simply forgot
  /// `--dart-define=CONVEX_URL` served six invented bands as if they were real.
  /// A missing URL is now a startup error — see `main()`.
  static const bool demo = bool.fromEnvironment('EARPLUG_DEMO');

  /// The one production Convex deployment.
  ///
  /// A Convex URL carries no marker saying which tier it is — dev and prod
  /// hosts are the same shape — so without naming production somewhere the app
  /// cannot tell live user data from scratch data. This is the only safe place
  /// to name it: the value is already public in every built bundle.
  static const String productionConvexDeployment = 'decisive-iguana-759';

  /// `https://decisive-iguana-759.convex.cloud` -> `decisive-iguana-759`.
  static String get convexDeployment {
    final host = Uri.tryParse(convexUrl)?.host ?? '';
    final dot = host.indexOf('.');
    return dot == -1 ? host : host.substring(0, dot);
  }

  static DeploymentTier get convexTier =>
      convexDeployment == productionConvexDeployment
      ? DeploymentTier.production
      : DeploymentTier.development;

  /// Clerk publishable keys are `pk_<tier>_<base64 of "host$">`, so the key
  /// alone determines both the tier and the Frontend API host.
  ///
  /// Deriving the host is what makes the two impossible to mismatch. This app
  /// previously hardcoded the development Frontend API host, so a production
  /// key still loaded clerk-js from the test instance and no configuration
  /// could override it.
  static DeploymentTier? get clerkTier {
    if (clerkPublishableKey.startsWith('pk_live_')) {
      return DeploymentTier.production;
    }
    if (clerkPublishableKey.startsWith('pk_test_')) {
      return DeploymentTier.development;
    }
    return null;
  }

  static String? get clerkFrontendApiHost {
    final prefix = switch (clerkTier) {
      DeploymentTier.production => 'pk_live_',
      DeploymentTier.development => 'pk_test_',
      null => null,
    };
    if (prefix == null) return null;

    final payload = clerkPublishableKey.substring(prefix.length);
    if (payload.isEmpty) return null;
    // Clerk omits base64 padding; Dart's decoder requires it.
    final padded = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');

    final String decoded;
    try {
      decoded = utf8.decode(base64.decode(padded));
    } on FormatException {
      return null;
    }
    final host = decoded.endsWith(r'$')
        ? decoded.substring(0, decoded.length - 1)
        : decoded;
    return host.isEmpty ? null : host;
  }

  static String? get clerkScriptUrl {
    final host = clerkFrontendApiHost;
    if (host == null) return null;
    return 'https://$host/npm/@clerk/clerk-js@5/dist/clerk.browser.js';
  }

  /// Null when the build is coherent, otherwise the reason it must not run.
  ///
  /// A mismatched pair is more dangerous than a missing one. Sign-in succeeds
  /// against whichever Clerk instance the key names, the Convex deployment
  /// then rejects or fails to match that identity, and every query comes back
  /// empty — which reads as deleted data rather than as misconfiguration.
  static String? get configurationError {
    if (convexUrl.isEmpty) {
      return 'CONVEX_URL is not set, so there is no backend to load.\n\n'
          'Build with --dart-define=CONVEX_URL=…, or pass\n'
          '--dart-define=EARPLUG_DEMO=true for the offline demo.';
    }
    if (clerkPublishableKey.isEmpty) {
      return 'CLERK_PUBLISHABLE_KEY is not set, so nobody can sign in.\n\n'
          'Build with --dart-define=CLERK_PUBLISHABLE_KEY=pk_…';
    }
    if (clerkTier == null || clerkFrontendApiHost == null) {
      return 'CLERK_PUBLISHABLE_KEY is not a readable Clerk key.\n\n'
          'It must start with pk_test_ or pk_live_ and encode a\n'
          'Frontend API host.';
    }
    if (clerkTier != convexTier) {
      return 'Environment mismatch. Refusing to start.\n\n'
          'A ${clerkTier!.label} Clerk key is paired with the '
          '${convexTier.label} Convex\ndeployment "$convexDeployment".\n\n'
          'Pair pk_live_ with "$productionConvexDeployment",\n'
          'or pk_test_ with any other deployment.';
    }
    return null;
  }
}
