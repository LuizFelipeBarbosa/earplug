import 'dart:async';
import 'dart:js_interop';

import '../env.dart';
import 'auth_service.dart';

const _oauthPendingKey = 'earplug_clerk_oauth_pending';

AuthService createPlatformAuthService() {
  return ClerkWebAuth(Env.clerkPublishableKey);
}

enum _CodeFlow { signIn, signUp }

enum _CodeStrategy {
  email('email_code'),
  phone('phone_code');

  const _CodeStrategy(this.value);

  final String value;
}

final class ClerkWebAuth implements AuthService {
  ClerkWebAuth(this._publishableKey);

  final String _publishableKey;
  final StreamController<bool> _signedInController =
      StreamController<bool>.broadcast();

  late _Clerk _clerk;
  Future<void>? _initialization;
  _SignIn? _codeSignIn;
  _SignUp? _codeSignUp;
  _CodeFlow? _codeFlow;
  _CodeStrategy? _codeStrategy;
  bool _lastSignedIn = false;

  @override
  bool get signedIn => _initialization != null && _globalClerk?.user != null;

  @override
  String? get displayName {
    final user = _globalClerk?.user;
    final fullName = user?.fullName?.trim();
    if (fullName != null && fullName.isNotEmpty) return fullName;

    final parts = [
      user?.firstName,
      user?.lastName,
    ].whereType<String>().where((part) => part.trim().isNotEmpty);
    final name = parts.join(' ').trim();
    return name.isEmpty ? null : name;
  }

  @override
  Stream<bool> get signedInChanges => _signedInController.stream;

  @override
  bool get supportsEmailSignIn => Env.emailSignInEnabled;

  @override
  bool get supportsPhoneSignIn => Env.phoneSignInEnabled;

  @override
  bool get supportsAppleSignIn => Env.appleSignInEnabled;

  @override
  // Unlike mobile, Clerk's hosted web OAuth redirect needs no native client ID.
  bool get supportsGoogleSignIn => Env.googleSignInEnabled;

  @override
  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    if (_publishableKey.isEmpty) {
      throw const AuthException('Clerk publishable key is missing.');
    }

    if (_globalClerk == null) {
      await _loadClerkScript();
    }
    _clerk =
        _globalClerk ??
        (throw const AuthException('clerk-js did not expose window.Clerk.'));

    try {
      await _clerk.load().toDart;
      _lastSignedIn = _clerk.user != null;
      if (_lastSignedIn) _signedInController.add(true);
      _clerk.addListener(((JSAny? _) => _emitSignedInIfChanged()).toJS);
    } catch (error) {
      throw AuthException(_messageFor(error));
    }

    if (_window.sessionStorage.getItem(_oauthPendingKey) == 'true') {
      _window.sessionStorage.removeItem(_oauthPendingKey);
      try {
        await _clerk.handleRedirectCallback(_redirectCallbackToApp()).toDart;
      } catch (_) {
        // A failed OAuth callback must not block startup: the user just
        // arrives signed out and can retry from the door.
      }
      _emitSignedInIfChanged();
    }
  }

  /// Every post-OAuth outcome must land back in the app. Any URL left unset
  /// here falls back to Clerk's hosted account portal (accounts.dev), which
  /// strands new sign-ups outside the app.
  _RedirectCallbackOptions _redirectCallbackToApp() {
    final url = _rootUrl;
    return _RedirectCallbackOptions(
      signInFallbackRedirectUrl: url,
      signUpFallbackRedirectUrl: url,
      signInUrl: url,
      signUpUrl: url,
      firstFactorUrl: url,
      secondFactorUrl: url,
      resetPasswordUrl: url,
      continueSignUpUrl: url,
      verifyEmailAddressUrl: url,
      verifyPhoneNumberUrl: url,
    );
  }

  Future<void> _loadClerkScript() {
    // Derived from the publishable key rather than configured, so clerk-js can
    // never be fetched from a different Clerk instance than the key belongs to.
    final scriptUrl =
        Env.clerkScriptUrl ??
        (throw const AuthException(
          'Clerk publishable key does not encode a Frontend API host.',
        ));
    final completer = Completer<void>();
    final script = _document.createElement('script')
      ..src = scriptUrl
      ..type = 'text/javascript'
      ..setAttribute('data-clerk-publishable-key', _publishableKey)
      ..onload = (() {
        if (!completer.isCompleted) completer.complete();
      }).toJS
      ..onerror = ((JSAny? _) {
        if (!completer.isCompleted) {
          completer.completeError(
            const AuthException('Could not load clerk-js.'),
          );
        }
      }).toJS;
    _document.head.appendChild(script);
    return completer.future;
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

    _resetCodeFlow();
    try {
      _codeSignIn = await _clerk.client.signIn
          .create(
            _SignInCreateParams(identifier: identifier, strategy: 'email_code'),
          )
          .toDart;
      _codeFlow = _CodeFlow.signIn;
      _codeStrategy = _CodeStrategy.email;
    } catch (error) {
      if (!_isMissingIdentifier(error)) {
        throw AuthException(_messageFor(error));
      }

      try {
        final signUp = await _clerk.client.signUp
            .create(_SignUpCreateParams(emailAddress: identifier))
            .toDart;
        _codeSignUp = await signUp
            .prepareEmailAddressVerification(
              _VerificationPrepareParams(strategy: 'email_code'),
            )
            .toDart;
        _codeFlow = _CodeFlow.signUp;
        _codeStrategy = _CodeStrategy.email;
      } catch (signUpError) {
        throw AuthException(_messageFor(signUpError));
      }
    }
  }

  @override
  Future<bool> verifyEmailCode(String code) {
    return _verifyCode(code, _CodeStrategy.email);
  }

  @override
  Future<void> startPhoneSignIn(String phoneNumber) async {
    await initialize();
    final identifier = phoneNumber.trim();
    if (identifier.isEmpty) {
      throw const AuthException('Enter your phone number.');
    }

    _resetCodeFlow();
    try {
      _codeSignIn = await _clerk.client.signIn
          .create(
            _SignInCreateParams(identifier: identifier, strategy: 'phone_code'),
          )
          .toDart;
      _codeFlow = _CodeFlow.signIn;
      _codeStrategy = _CodeStrategy.phone;
    } catch (error) {
      if (!_isMissingIdentifier(error)) {
        throw AuthException(_messageFor(error));
      }

      try {
        final signUp = await _clerk.client.signUp
            .create(_SignUpCreateParams(phoneNumber: identifier))
            .toDart;
        _codeSignUp = await signUp
            .preparePhoneNumberVerification(
              _VerificationPrepareParams(strategy: 'phone_code'),
            )
            .toDart;
        _codeFlow = _CodeFlow.signUp;
        _codeStrategy = _CodeStrategy.phone;
      } catch (signUpError) {
        throw AuthException(_messageFor(signUpError));
      }
    }
  }

  @override
  Future<bool> verifyPhoneCode(String code) {
    return _verifyCode(code, _CodeStrategy.phone);
  }

  Future<bool> _verifyCode(String code, _CodeStrategy strategy) async {
    await initialize();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) return false;

    try {
      if (_codeStrategy != strategy) {
        throw const AuthException('Send a verification code first.');
      }

      final String? createdSessionId;
      switch (_codeFlow) {
        case _CodeFlow.signIn:
          final signIn = _codeSignIn;
          if (signIn == null) {
            throw const AuthException('Send a verification code first.');
          }
          final result = await signIn
              .attemptFirstFactor(
                _CodeAttemptParams(strategy: strategy.value, code: code),
              )
              .toDart;
          createdSessionId = result.createdSessionId;
        case _CodeFlow.signUp:
          final signUp = _codeSignUp;
          if (signUp == null) {
            throw const AuthException('Send a verification code first.');
          }
          final result = switch (strategy) {
            _CodeStrategy.email =>
              await signUp
                  .attemptEmailAddressVerification(
                    _CodeVerifyParams(code: code),
                  )
                  .toDart,
            _CodeStrategy.phone =>
              await signUp
                  .attemptPhoneNumberVerification(_CodeVerifyParams(code: code))
                  .toDart,
          };
          createdSessionId = result.createdSessionId;
        case null:
          throw const AuthException('Send a verification code first.');
      }

      return _activateSession(createdSessionId);
    } catch (error) {
      if (error is AuthException) rethrow;
      throw AuthException(_messageFor(error));
    }
  }

  Future<bool> _activateSession(String? createdSessionId) async {
    if (createdSessionId == null || createdSessionId.isEmpty) return false;
    await _clerk.setActive(_SetActiveParams(session: createdSessionId)).toDart;
    _emitSignedInIfChanged();
    return _clerk.user != null;
  }

  @override
  Future<void> signInWithOAuth(OAuthProvider provider) async {
    await initialize();
    final strategy = switch (provider) {
      OAuthProvider.google => 'oauth_google',
      OAuthProvider.apple => 'oauth_apple',
    };

    _window.sessionStorage.setItem(_oauthPendingKey, 'true');
    try {
      await _clerk.client.signIn
          .authenticateWithRedirect(
            _OAuthRedirectParams(
              strategy: strategy,
              redirectUrl: _rootUrl,
              redirectUrlComplete: _rootUrl,
            ),
          )
          .toDart;
    } catch (error) {
      _window.sessionStorage.removeItem(_oauthPendingKey);
      throw AuthException(_messageFor(error));
    }
  }

  @override
  Future<String?> fetchConvexToken() async {
    await initialize();
    final session = _clerk.session;
    if (session == null) return null;

    final token = await session
        .getToken(_TokenOptions(template: 'convex', skipCache: true))
        .toDart;
    return token?.toDart;
  }

  @override
  Future<void> signOut() async {
    await initialize();
    await _clerk.signOut().toDart;
    _resetCodeFlow();
    _emitSignedInIfChanged();
  }

  @override
  Future<void> deleteAccount() async {
    await initialize();
    final user = _clerk.user;
    if (user == null) {
      throw const AuthException('Sign in before deleting your account.');
    }
    try {
      await user.delete().toDart;
      _resetCodeFlow();
      _emitSignedInIfChanged();
    } catch (error) {
      throw AuthException(_messageFor(error));
    }
  }

  void _resetCodeFlow() {
    _codeFlow = null;
    _codeStrategy = null;
    _codeSignIn = null;
    _codeSignUp = null;
  }

  String get _rootUrl {
    final origin = _window.location.origin;
    return origin.endsWith('/') ? origin : '$origin/';
  }

  void _emitSignedInIfChanged() {
    final current = _clerk.user != null;
    if (current == _lastSignedIn) return;
    _lastSignedIn = current;
    _signedInController.add(current);
  }

  bool _isMissingIdentifier(Object error) {
    final text = _messageFor(error).toLowerCase();
    return text.contains('form_identifier_not_found') ||
        text.contains('identifier_not_found') ||
        text.contains('identifier not found') ||
        text.contains("couldn't find") ||
        text.contains('no account');
  }

  String _messageFor(Object error) {
    try {
      final clerkError = _ClerkError(error as JSObject);
      final errors = clerkError.errors?.toDart;
      if (errors != null && errors.isNotEmpty) {
        final detail = errors.first;
        final message = detail.longMessage ?? detail.message;
        if (message != null && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
      final message = clerkError.message;
      if (message != null && message.trim().isNotEmpty) {
        return message.trim();
      }
    } catch (_) {}

    final message = error.toString().trim();
    if (message.isEmpty || message.startsWith('Instance of ')) {
      return 'Clerk could not complete authentication.';
    }
    return message.replaceFirst(RegExp(r'^(Exception|Error):\s*'), '');
  }
}

@JS('window.Clerk')
external _Clerk? get _globalClerk;

@JS('window')
external _Window get _window;

@JS('document')
external _Document get _document;

@JS()
extension type _Window(JSObject _) implements JSObject {
  external _Location get location;
  external _Storage get sessionStorage;
}

@JS()
extension type _Location(JSObject _) implements JSObject {
  external String get origin;
}

@JS()
extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

@JS()
extension type _Document(JSObject _) implements JSObject {
  external _ScriptElement createElement(String tagName);
  external _Element get head;
}

@JS()
extension type _Element(JSObject _) implements JSObject {
  external void appendChild(JSObject child);
}

@JS()
extension type _ScriptElement(JSObject _) implements JSObject {
  external set src(String value);
  external set type(String value);
  external set onload(JSFunction value);
  external set onerror(JSFunction value);
  external void setAttribute(String name, String value);
}

@JS()
extension type _Clerk(JSObject _) implements JSObject {
  external _ClerkClient get client;
  external _ClerkSession? get session;
  external _ClerkUser? get user;
  external JSPromise<JSAny?> load();
  external JSFunction addListener(JSFunction listener);
  external JSPromise<JSAny?> handleRedirectCallback(
    _RedirectCallbackOptions options,
  );
  external JSPromise<JSAny?> setActive(_SetActiveParams params);
  external JSPromise<JSAny?> signOut();
}

@JS()
extension type _ClerkClient(JSObject _) implements JSObject {
  external _SignIn get signIn;
  external _SignUp get signUp;
}

@JS()
extension type _ClerkSession(JSObject _) implements JSObject {
  external JSPromise<JSString?> getToken(_TokenOptions options);
}

@JS()
extension type _ClerkUser(JSObject _) implements JSObject {
  external String? get fullName;
  external String? get firstName;
  external String? get lastName;
  external JSPromise<JSAny?> delete();
}

@JS()
extension type _SignIn(JSObject _) implements JSObject {
  external JSPromise<_SignIn> create(_SignInCreateParams params);
  external JSPromise<_SignIn> attemptFirstFactor(_CodeAttemptParams params);
  external JSPromise<JSAny?> authenticateWithRedirect(
    _OAuthRedirectParams params,
  );
  external String? get createdSessionId;
}

@JS()
extension type _SignUp(JSObject _) implements JSObject {
  external JSPromise<_SignUp> create(_SignUpCreateParams params);
  external JSPromise<_SignUp> prepareEmailAddressVerification(
    _VerificationPrepareParams params,
  );
  external JSPromise<_SignUp> attemptEmailAddressVerification(
    _CodeVerifyParams params,
  );
  external JSPromise<_SignUp> preparePhoneNumberVerification(
    _VerificationPrepareParams params,
  );
  external JSPromise<_SignUp> attemptPhoneNumberVerification(
    _CodeVerifyParams params,
  );
  external String? get createdSessionId;
}

@JS()
extension type _ClerkError(JSObject _) implements JSObject {
  external JSArray<_ClerkErrorDetail>? get errors;
  external String? get message;
}

@JS()
extension type _ClerkErrorDetail(JSObject _) implements JSObject {
  external String? get message;
  external String? get longMessage;
}

@JS()
extension type _SignInCreateParams._(JSObject _) implements JSObject {
  external factory _SignInCreateParams({
    required String identifier,
    required String strategy,
  });
}

@JS()
extension type _SignUpCreateParams._(JSObject _) implements JSObject {
  external factory _SignUpCreateParams({
    String? emailAddress,
    String? phoneNumber,
  });
}

@JS()
extension type _VerificationPrepareParams._(JSObject _) implements JSObject {
  external factory _VerificationPrepareParams({required String strategy});
}

@JS()
extension type _CodeAttemptParams._(JSObject _) implements JSObject {
  external factory _CodeAttemptParams({
    required String strategy,
    required String code,
  });
}

@JS()
extension type _CodeVerifyParams._(JSObject _) implements JSObject {
  external factory _CodeVerifyParams({required String code});
}

@JS()
extension type _OAuthRedirectParams._(JSObject _) implements JSObject {
  external factory _OAuthRedirectParams({
    required String strategy,
    required String redirectUrl,
    required String redirectUrlComplete,
  });
}

@JS()
extension type _SetActiveParams._(JSObject _) implements JSObject {
  external factory _SetActiveParams({required String session});
}

@JS()
extension type _TokenOptions._(JSObject _) implements JSObject {
  external factory _TokenOptions({
    required String template,
    required bool skipCache,
  });
}

@JS()
extension type _RedirectCallbackOptions._(JSObject _) implements JSObject {
  external factory _RedirectCallbackOptions({
    required String signInFallbackRedirectUrl,
    required String signUpFallbackRedirectUrl,
    required String signInUrl,
    required String signUpUrl,
    required String firstFactorUrl,
    required String secondFactorUrl,
    required String resetPasswordUrl,
    required String continueSignUpUrl,
    required String verifyEmailAddressUrl,
    required String verifyPhoneNumberUrl,
  });
}
