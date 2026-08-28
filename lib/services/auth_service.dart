import 'dart:async';

enum OAuthProvider { google, apple }

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class AuthService {
  bool get signedIn;
  String? get displayName;
  Stream<bool> get signedInChanges;
  Future<void> initialize();
  Future<void> signInDemo();
  Future<void> signOut();
  Future<void> deleteAccount();
  Future<String?> fetchConvexToken();
  Future<void> startEmailSignIn(String email);
  Future<bool> verifyEmailCode(String code);
  Future<void> startPhoneSignIn(String phoneNumber);
  Future<bool> verifyPhoneCode(String code);
  bool get supportsEmailSignIn;
  bool get supportsPhoneSignIn;
  bool get supportsAppleSignIn;
  bool get supportsGoogleSignIn;
  Future<void> signInWithOAuth(OAuthProvider provider);
}

class FakeAuthService implements AuthService {
  FakeAuthService({
    this.supportsEmailSignIn = true,
    this.supportsPhoneSignIn = true,
    this.supportsAppleSignIn = true,
    this.supportsGoogleSignIn = true,
  });

  final StreamController<bool> _signedInController =
      StreamController<bool>.broadcast();

  @override
  final bool supportsEmailSignIn;

  @override
  final bool supportsPhoneSignIn;

  @override
  final bool supportsAppleSignIn;

  @override
  final bool supportsGoogleSignIn;

  bool _signedIn = false;
  int deleteAccountCalls = 0;
  Object? deleteAccountError;

  @override
  bool get signedIn => _signedIn;

  @override
  String? get displayName => null;

  @override
  Stream<bool> get signedInChanges => _signedInController.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> signInDemo() async {
    _signedIn = true;
    _signedInController.add(true);
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _signedInController.add(false);
  }

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalls++;
    final error = deleteAccountError;
    if (error != null) throw error;
    _signedIn = false;
    _signedInController.add(false);
  }

  @override
  Future<String?> fetchConvexToken() => Future<String?>.value(null);

  @override
  Future<void> startEmailSignIn(String email) async {}

  @override
  Future<bool> verifyEmailCode(String code) async {
    if (code != '424242') return false;
    await signInDemo();
    return true;
  }

  @override
  Future<void> startPhoneSignIn(String phoneNumber) async {}

  @override
  Future<bool> verifyPhoneCode(String code) async {
    if (code != '424242') return false;
    await signInDemo();
    return true;
  }

  @override
  Future<void> signInWithOAuth(OAuthProvider provider) => signInDemo();
}
