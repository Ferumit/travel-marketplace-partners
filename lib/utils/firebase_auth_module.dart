import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Модели
// ─────────────────────────────────────────────────────────────────────────────

/// Упрощённая модель пользователя, независимая от Firebase SDK.
class FirebaseUserModel {
  final String uid;
  final String? email;
  final String? phoneNumber;
  final String? displayName;
  final String? photoUrl;
  final bool emailVerified;

  const FirebaseUserModel({
    required this.uid,
    this.email,
    this.phoneNumber,
    this.displayName,
    this.photoUrl,
    this.emailVerified = false,
  });

  factory FirebaseUserModel._fromFirebase(User user) => FirebaseUserModel(
    uid: user.uid,
    email: user.email,
    phoneNumber: user.phoneNumber,
    displayName: user.displayName,
    photoUrl: user.photoURL,
    emailVerified: user.emailVerified,
  );

  @override
  String toString() =>
      'FirebaseUserModel(uid: $uid, email: $email, emailVerified: $emailVerified)';
}

/// Результат операции авторизации — всегда возвращается, никогда не бросает.
class AuthResult {
  final bool success;
  final FirebaseUserModel? user;
  final String? errorMessage;

  const AuthResult._({required this.success, this.user, this.errorMessage});

  factory AuthResult.ok(FirebaseUserModel user) =>
      AuthResult._(success: true, user: user);

  factory AuthResult.fail(String message) =>
      AuthResult._(success: false, errorMessage: message);
}

// ─────────────────────────────────────────────────────────────────────────────
// Модуль
// ─────────────────────────────────────────────────────────────────────────────

/// Отказоустойчивый модуль Firebase Authentication.
///
/// Email/Password — регистрация и вход.
/// Все методы оборачивают [FirebaseAuthException] в [AuthResult.fail]
/// с понятным текстом на русском языке.
abstract final class FirebaseAuthModule {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Текущий пользователь ──────────────────────────────────────────────────

  static FirebaseUserModel? get currentUser {
    final u = _auth.currentUser;
    return u == null ? null : FirebaseUserModel._fromFirebase(u);
  }

  static Stream<FirebaseUserModel?> get authStateChanges => _auth
      .authStateChanges()
      .map((u) => u == null ? null : FirebaseUserModel._fromFirebase(u));

  // ── Регистрация ───────────────────────────────────────────────────────────

  static Future<AuthResult> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        return AuthResult.fail('Не удалось создать пользователя');
      }
      if (displayName != null && displayName.trim().isNotEmpty) {
        await user.updateDisplayName(displayName.trim());
        await user.reload();
      }
      debugPrint('[FirebaseAuthModule] Registered: ${user.uid}');
      return AuthResult.ok(FirebaseUserModel._fromFirebase(_auth.currentUser!));
    } on FirebaseAuthException catch (e) {
      debugPrint(
        '[FirebaseAuthModule] Register error: ${e.code} — ${e.message}',
      );
      return AuthResult.fail(_mapError(e.code));
    } catch (e, stack) {
      debugPrint('[FirebaseAuthModule] Unknown register error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerFirebaseAuthModule.registerWithEmail', fatal: false);
      return AuthResult.fail('Произошла непредвиденная ошибка');
    }
  }

  // ── Вход ──────────────────────────────────────────────────────────────────

  static Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        return AuthResult.fail('Не удалось выполнить вход');
      }
      debugPrint('[FirebaseAuthModule] Signed in: ${user.uid}');
      return AuthResult.ok(FirebaseUserModel._fromFirebase(user));
    } on FirebaseAuthException catch (e) {
      debugPrint(
        '[FirebaseAuthModule] Sign-in error: ${e.code} — ${e.message}',
      );
      return AuthResult.fail(_mapError(e.code));
    } catch (e, stack) {
      debugPrint('[FirebaseAuthModule] Unknown sign-in error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerFirebaseAuthModule.signInWithEmail', fatal: false);
      return AuthResult.fail('Произошла непредвиденная ошибка');
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  static Future<AuthResult> signInWithGoogle() async {
    try {
      // serverClientId is the Web OAuth 2.0 client ID from google-services.json
      // Required by google_sign_in v6.x on Android to obtain an idToken
      final googleSignIn = GoogleSignIn(
        scopes: ['email'],
        serverClientId: '000000000000-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com',
      );
      await googleSignIn.signOut(); // Force account picker
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        return AuthResult.fail('Вход через Google отменён');
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred = await _auth.signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) return AuthResult.fail('Не удалось выполнить вход через Google');
      debugPrint('[FirebaseAuthModule] Google sign-in: ${user.uid}');
      return AuthResult.ok(FirebaseUserModel._fromFirebase(user));
    } on FirebaseAuthException catch (e) {
      return AuthResult.fail(_mapError(e.code));
    } catch (e, stack) {
      debugPrint('[FirebaseAuthModule] Google sign-in error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerFirebaseAuthModule.signInWithGoogle', fatal: false);
      return AuthResult.fail('Ошибка входа через Google');
    }
  }

  // ── Apple Sign-In ────────────────────────────────────────────────────────

  static Future<AuthResult> signInWithApple() async {
    try {
      if (!Platform.isIOS && !Platform.isMacOS) {
        return AuthResult.fail('Вход через Apple доступен только на iOS/macOS');
      }
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      final userCred = await _auth.signInWithCredential(oauthCredential);
      final user = userCred.user;
      if (user == null) return AuthResult.fail('Не удалось выполнить вход через Apple');

      // Update display name if provided (only on first sign-in)
      if (appleCredential.givenName != null) {
        final name = '${appleCredential.givenName} ${appleCredential.familyName ?? ''}'.trim();
        if (name.isNotEmpty) await user.updateDisplayName(name);
      }

      debugPrint('[FirebaseAuthModule] Apple sign-in: ${user.uid}');
      return AuthResult.ok(FirebaseUserModel._fromFirebase(_auth.currentUser!));
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return AuthResult.fail('Вход через Apple отменён');
      }
      return AuthResult.fail('Ошибка Apple Sign-In: ${e.message}');
    } on FirebaseAuthException catch (e) {
      return AuthResult.fail(_mapError(e.code));
    } catch (e, stack) {
      debugPrint('[FirebaseAuthModule] Apple sign-in error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerFirebaseAuthModule.signInWithApple', fatal: false);
      return AuthResult.fail('Ошибка входа через Apple');
    }
  }

  // ── Выход ──────────────────────────────────────────────────────────────────

  static Future<void> signOut() async {
    try {
      await _auth.signOut();
      debugPrint('[FirebaseAuthModule] Signed out');
    } catch (e, stack) {
      debugPrint('[FirebaseAuthModule] Error during sign out: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerFirebaseAuthModule.signOut', fatal: false);
    }
  }

  // ── Удаление аккаунта ───────────────────────────────────────────────────

  static Future<AuthResult> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return AuthResult.fail('Пользователь не найден');
      await user.delete();
      debugPrint('[FirebaseAuthModule] Account deleted');
      return AuthResult.ok(const FirebaseUserModel(uid: ''));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return AuthResult.fail('В целях безопасности необходимо выйти из аккаунта и войти снова перед удалением.');
      }
      return AuthResult.fail(_mapError(e.code));
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerFirebaseAuthModule.deleteAccount', fatal: false);
      return AuthResult.fail('Непредвиденная ошибка при удалении аккаунта');
    }
  }

  // ── Сброс пароля ──────────────────────────────────────────────────────────

  static Future<AuthResult> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      debugPrint('[FirebaseAuthModule] Password reset sent to $email');
      return AuthResult.ok(
        const FirebaseUserModel(uid: '', emailVerified: false),
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult.fail(_mapError(e.code));
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerFirebaseAuthModule.sendPasswordReset', fatal: false);
      return AuthResult.fail('Ошибка отправки письма');
    }
  }

  // ── Маппинг ошибок ────────────────────────────────────────────────────────

  static String _mapError(String code) => switch (code) {
    'invalid-email' => 'Некорректный email адрес',
    'user-not-found' => 'Пользователь не найден',
    'wrong-password' || 'invalid-credential' => 'Неверный email или пароль',
    'email-already-in-use' => 'Этот email уже зарегистрирован',
    'weak-password' => 'Пароль должен содержать не менее 6 символов',
    'user-disabled' => 'Аккаунт заблокирован',
    'too-many-requests' => 'Слишком много попыток — попробуйте позже',
    'network-request-failed' => 'Нет подключения к интернету',
    'operation-not-allowed' =>
      'Данный способ входа не поддерживается в Firebase',
    'requires-recent-login' => 'Для этого действия нужно войти заново',
    _ => 'Ошибка авторизации ($code)',
  };
}
