import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../repository/firestore_repository.dart';
import '../utils/firebase_auth_module.dart';

/// Синглтон-сервис авторизации для Explora Partners.
///
/// Слушает [FirebaseAuth.authStateChanges] и уведомляет GoRouter
/// при любом изменении состояния сессии.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// Текущий пользователь из Firebase Auth.
  FirebaseUserModel? _currentUser;
  FirebaseUserModel? get currentUser => _currentUser;

  /// `true` если пользователь авторизован.
  bool get isSignedIn => _currentUser != null;

  /// `true` пока идёт асинхронная проверка профиля.
  /// Роутер должен игнорировать [hasPartnerProfile] пока это `true`.
  bool _isProfileLoading = true;
  bool get isProfileLoading => _isProfileLoading;

  /// `true` если у авторизованного пользователя есть PartnerProfile в Firestore.
  bool _hasPartnerProfile = false;
  bool get hasPartnerProfile => _hasPartnerProfile;

  /// Загружает начальное состояние и подписывается на изменения Firebase Auth.
  /// Вызывать один раз в `main()`.
  Future<void> init() async {
    // Синхронизируем начальное состояние
    _currentUser = FirebaseAuthModule.currentUser;

    // Слушаем все последующие изменения сессии
    FirebaseAuth.instance.authStateChanges().listen((firebaseUser) async {
      _isProfileLoading = true;
      // Immediately notify so router sees the loading state before redirect
      notifyListeners();

      if (firebaseUser != null) {
        _currentUser = FirebaseUserModel(
          uid: firebaseUser.uid,
          email: firebaseUser.email,
          displayName: firebaseUser.displayName,
          photoUrl: firebaseUser.photoURL,
          emailVerified: firebaseUser.emailVerified,
        );
        // Check if partner profile exists
        final profile =
            await FirestoreRepository.instance.getPartner(firebaseUser.uid);
        _hasPartnerProfile = profile != null;
        
        // Fetch and update FCM token
        if (_hasPartnerProfile) {
          try {
            await FirebaseMessaging.instance.requestPermission();
            final token = await FirebaseMessaging.instance.getToken();
            if (token != null && token != profile!.fcmToken) {
              await FirestoreRepository.instance.updatePartner(
                firebaseUser.uid,
                {'fcmToken': token},
              );
              debugPrint('[AuthService] Updated FCM token for partner');
            }
          } catch (e) {
            debugPrint('[AuthService] Failed to get FCM token: $e');
          }
        }
      } else {
        _currentUser = null;
        _hasPartnerProfile = false;
      }

      _isProfileLoading = false;
      debugPrint(
        '[AuthService] State ready: isSignedIn=$isSignedIn, hasProfile=$_hasPartnerProfile, uid=${_currentUser?.uid}',
      );
      notifyListeners();
    });

    notifyListeners();
  }

  /// Полный выход из Firebase Auth.
  Future<void> signOut() async {
    await FirebaseAuthModule.signOut();
    // notifyListeners() вызовется автоматически через authStateChanges listener
  }

  /// Удаление аккаунта и профиля из Firestore.
  Future<void> deleteAccount(BuildContext context) async {
    final uid = _currentUser?.uid;
    if (uid != null) {
      await FirestoreRepository.instance.deletePartner(uid);
    }
    final result = await FirebaseAuthModule.deleteAccount();
    if (!result.success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Ошибка удаления аккаунта'),
          backgroundColor: CupertinoColors.systemRed,
        ),
      );
    }
  }

  /// Перепроверяет наличие PartnerProfile в Firestore и обновляет роутер.
  /// Вызывать после сохранения профиля.
  Future<void> refreshProfile() async {
    final uid = _currentUser?.uid;
    if (uid == null) return;
    final profile = await FirestoreRepository.instance.getPartner(uid);
    _hasPartnerProfile = profile != null;
    notifyListeners();
  }
}
