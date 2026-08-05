import 'dart:async';
import 'dart:io';

import 'package:clerk_auth/clerk_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../env.dart';
import 'auth_service.dart';

AuthService createPlatformAuthService() {
  return ClerkMobileAuth(Env.clerkPublishableKey);
}

enum _CodeFlow { signIn, signUp }

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
  Future<void>? _googleInitialization;
  ({_CodeFlow flow, Strategy strategy})? _pendingCodeFlow;
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

  // Both gate on configuration where the web implementation just returns true,
  // and that asymmetry is deliberate rather than drift. Web signs in through
  // Clerk's hosted redirect, which needs no per-app credentials; these use the
  // native Apple and Google SDKs, which do. Offering a button that cannot
  // complete is worse than not offering it, so an unconfigured build hides them.
  // Set the values in config/*.json and ios/Config/Google.xcconfig — see
  // docs/environments.md.
  @override
  bool get supportsAppleSignIn => Platform.isIOS && Env.appleSignInEnabled;

  @override
  bool get supportsGoogleSignIn => Env.googleServerClientId.isNotEmpty;

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

    _pendingCodeFlow = null;
    await _auth.resetClient();
    try {
      await _auth.attemptSignIn(
        identifier: identifier,
        strategy: Strategy.emailCode,
      );
      _pendingCodeFlow = (flow: _CodeFlow.signIn, strategy: Strategy.emailCode);
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
        _pendingCodeFlow = (
          flow: _CodeFlow.signUp,
          strategy: Strategy.emailCode,
        );
      } catch (signUpError) {
        throw AuthException(_messageFor(signUpError));
      }
    }
  }

  @override
  Future<bool> verifyEmailCode(String code) {
    return _verifyCode(code, Strategy.emailCode);
  }

  @override
  Future<void> startPhoneSignIn(String phoneNumber) async {
    await initialize();
    final identifier = phoneNumber.trim();
    if (identifier.isEmpty) {
      throw const AuthException('Enter your phone number.');
    }

    _pendingCodeFlow = null;
    await _auth.resetClient();
    try {
      await _auth.attemptSignIn(
        identifier: identifier,
        strategy: Strategy.phoneCode,
      );
      _pendingCodeFlow = (flow: _CodeFlow.signIn, strategy: Strategy.phoneCode);
    } catch (error) {
      if (!_isMissingIdentifier(error)) {
        throw AuthException(_messageFor(error));
      }

      await _auth.resetClient();
      try {
        await _auth.attemptSignUp(
          phoneNumber: identifier,
          strategy: Strategy.phoneCode,
        );
        _pendingCodeFlow = (
          flow: _CodeFlow.signUp,
          strategy: Strategy.phoneCode,
        );
      } catch (signUpError) {
        throw AuthException(_messageFor(signUpError));
      }
    }
  }

  @override
  Future<bool> verifyPhoneCode(String code) {
    return _verifyCode(code, Strategy.phoneCode);
  }

  Future<bool> _verifyCode(String code, Strategy strategy) async {
    await initialize();
    if (code.length != Strategy.numericalCodeLength) return false;

    try {
      final pending = _pendingCodeFlow;
      if (pending == null || pending.strategy != strategy) {
        throw const AuthException('Send a verification code first.');
      }

      switch (pending.flow) {
        case _CodeFlow.signIn:
          await _auth.attemptSignIn(strategy: strategy, code: code);
        case _CodeFlow.signUp:
          await _auth.attemptSignUp(strategy: strategy, code: code);
      }
      return _auth.isSignedIn;
    } catch (error) {
      if (error is AuthException) rethrow;
      throw AuthException(_messageFor(error));
    }
  }

  @override
  Future<void> signInWithOAuth(OAuthProvider provider) async {
    await initialize();

    try {
      switch (provider) {
        case OAuthProvider.apple:
          final credential = await SignInWithApple.getAppleIDCredential(
            scopes: const [
              AppleIDAuthorizationScopes.email,
              AppleIDAuthorizationScopes.fullName,
            ],
          );
          await _signInWithIdToken(
            provider: IdTokenProvider.apple,
            token: credential.identityToken,
          );
        case OAuthProvider.google:
          await (_googleInitialization ??= GoogleSignIn.instance.initialize(
            serverClientId: Env.googleServerClientId.isEmpty
                ? null
                : Env.googleServerClientId,
          ));
          final account = await GoogleSignIn.instance.authenticate();
          await _signInWithIdToken(
            provider: IdTokenProvider.google,
            token: account.authentication.idToken,
          );
      }
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const AuthException('');
      }
      throw AuthException(_messageFor(error));
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException('');
      }
      throw AuthException(_messageFor(error));
    } catch (error) {
      if (error is AuthException) rethrow;
      throw AuthException(_messageFor(error));
    }
  }

  Future<void> _signInWithIdToken({
    required IdTokenProvider provider,
    required String? token,
  }) async {
    await _auth.idTokenSignIn(provider: provider, token: token);
    if (!_auth.isSignedIn &&
        (_auth.client.signIn?.isTransferable == true ||
            _auth.client.signUp?.isTransferable == true)) {
      await _auth.transfer();
    }
    if (!_auth.isSignedIn) {
      throw const AuthException('Sign-in was not completed.');
    }
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
    _pendingCodeFlow = null;
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
