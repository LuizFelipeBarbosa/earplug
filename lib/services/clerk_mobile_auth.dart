import 'dart:async';

import 'package:clerk_auth/clerk_auth.dart';
import 'package:path_provider/path_provider.dart';

import '../env.dart';
import 'auth_service.dart';

AuthService createPlatformAuthService() {
  return ClerkMobileAuth(Env.clerkPublishableKey);
}

enum _EmailFlow { signIn, signUp }

final class ClerkMobileAuth implements AuthService {
  ClerkMobileAuth(String publishableKey) {
    _auth = _ObservableAuth(
      config: AuthConfig(
        publishableKey: publishableKey,
        persistor: DefaultPersistor(
          getCacheDirectory: getApplicationSupportDirectory,
        ),
        sessionTokenPolling: false,
      ),
      onUpdate: _handleAuthUpdate,
    );
  }

  late final _ObservableAuth _auth;
  final StreamController<bool> _signedInController =
      StreamController<bool>.broadcast();

  Future<void>? _initialization;
  _EmailFlow? _emailFlow;
  bool _lastSignedIn = false;

  @override
  bool get signedIn => _auth.isSignedIn;

  @override
  String? get displayName {
    final name = _auth.user?.name.trim();
    return name == null || name.isEmpty ? null : name;
  }

  @override
  Stream<bool> get signedInChanges => _signedInController.stream;

  @override
  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    if (_auth.config.publishableKey.isEmpty) {
      throw const AuthException('Clerk publishable key is missing.');
    }
    try {
      await _auth.initialize();
      _lastSignedIn = _auth.isSignedIn;
    } catch (error) {
      throw AuthException(_messageFor(error));
    }
  }

  @override
  Future<void> signInDemo() {
    throw const AuthException('Demo sign-in is unavailable.');
  }

  @override
  Future<void> startEmailSignIn(String email) async {
    await initialize();
    final identifier = email.trim();
    if (identifier.isEmpty) {
      throw const AuthException('Enter your email address.');
    }

    await _auth.resetClient();
    try {
      await _auth.attemptSignIn(
        identifier: identifier,
        strategy: Strategy.emailCode,
      );
      _emailFlow = _EmailFlow.signIn;
    } catch (error) {
      if (!_isMissingIdentifier(error)) {
        throw AuthException(_messageFor(error));
      }

      await _auth.resetClient();
      try {
        await _auth.attemptSignUp(
          emailAddress: identifier,
          strategy: Strategy.emailCode,
        );
        _emailFlow = _EmailFlow.signUp;
      } catch (signUpError) {
        throw AuthException(_messageFor(signUpError));
      }
    }
  }

  @override
  Future<bool> verifyEmailCode(String code) async {
    await initialize();
    if (code.length != Strategy.numericalCodeLength) return false;

    try {
      switch (_emailFlow) {
        case _EmailFlow.signIn:
          await _auth.attemptSignIn(strategy: Strategy.emailCode, code: code);
        case _EmailFlow.signUp:
          await _auth.attemptSignUp(strategy: Strategy.emailCode, code: code);
        case null:
          throw const AuthException('Send a verification code first.');
      }
      return _auth.isSignedIn;
    } catch (error) {
      if (error is AuthException) rethrow;
      throw AuthException(_messageFor(error));
    }
  }

  @override
  Future<void> signInWithOAuth(OAuthProvider provider) {
    throw const AuthException('Coming soon on mobile — use email');
  }

  @override
  Future<String?> fetchConvexToken() async {
    await initialize();
    if (!_auth.isSignedIn) return null;

    final token = await _auth.sessionToken(templateName: 'convex');
    return token.jwt;
  }

  @override
  Future<void> signOut() async {
    await initialize();
    await _auth.signOut();
    _emailFlow = null;
    _emitSignedInIfChanged();
  }

  void _handleAuthUpdate() {
    _emitSignedInIfChanged();
  }

  void _emitSignedInIfChanged() {
    final current = _auth.isSignedIn;
    if (current == _lastSignedIn) return;
    _lastSignedIn = current;
    _signedInController.add(current);
  }

  bool _isMissingIdentifier(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('form_identifier_not_found') ||
        text.contains('identifier_not_found') ||
        text.contains('identifier not found') ||
        text.contains("couldn't find") ||
        text.contains('no account');
  }

  String _messageFor(Object error) {
    final message = error.toString().trim();
    if (message.isEmpty || message.startsWith('Instance of ')) {
      return 'Clerk could not complete authentication.';
    }
    return message.replaceFirst(RegExp(r'^(Exception|ClerkError):\s*'), '');
  }
}

final class _ObservableAuth extends Auth {
  _ObservableAuth({required super.config, required this.onUpdate});

  final void Function() onUpdate;

  @override
  void update() {
    super.update();
    onUpdate();
  }
}
