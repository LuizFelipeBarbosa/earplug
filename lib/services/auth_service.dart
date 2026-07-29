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
  Future<String?> fetchConvexToken();
  Future<void> startEmailSignIn(String email);
  Future<bool> verifyEmailCode(String code);
  Future<void> signInWithOAuth(OAuthProvider provider);
}

class FakeAuthService implements AuthService {
  final StreamController<bool> _signedInController =
      StreamController<bool>.broadcast();

  bool _signedIn = false;

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
  Future<void> signInWithOAuth(OAuthProvider provider) => signInDemo();
}
