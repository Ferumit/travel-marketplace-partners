import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../navigation/main_tab_scaffold.dart';
import '../screens/auth_screen.dart';
import '../screens/garage_screen.dart';
import '../screens/messenger_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/role_selection_screen.dart';
import '../screens/route_screen.dart';
import '../screens/trip_history_screen.dart';
import '../screens/work_screen.dart';
import '../screens/face_control_screen.dart';
import '../screens/route_preview_screen.dart';
import '../screens/guide_certificate_screen.dart';
import '../screens/guide_documents_screen.dart';
import '../screens/sos_screen.dart';
import '../screens/mesh_screen.dart';
import '../models/booking_models.dart';
import '../models/partner_models.dart';
import '../services/auth_service.dart';

/// Единственный маршрутизатор приложения Explora Partners.
///
/// Использует [GoRouter] с guard-перенаправлениями на основе [AuthService].
/// Структура:
///   /auth              → AuthScreen        (только неавторизованные)
///   /                  → MainTabScaffold   (только авторизованные)
///   /profile           → ProfileScreen
///   /garage            → GarageScreen
///   /work              → WorkScreen
///   /route             → RouteScreen
///   /role-select       → RoleSelectionScreen
///   /messenger         → MessengerScreen   (чат по маршруту)
/// Global navigator key — used by GlobalSosListener to show dialogs
/// from outside the Navigator tree (e.g. from MaterialApp.router builder).
final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/auth',
  refreshListenable: AuthService.instance,
  redirect: (context, state) {
    final isSignedIn = AuthService.instance.isSignedIn;
    final isLoading = AuthService.instance.isProfileLoading;
    final hasProfile = AuthService.instance.hasPartnerProfile;
    final location = state.uri.path;

    // Не авторизован → всегда на /auth
    if (!isSignedIn) {
      if (location != '/auth') return '/auth';
      return null;
    }

    // Профиль ещё грузится — ждём, роутер перезапустится сам через notifyListeners
    if (isLoading) return null;

    // Авторизован, но нет профиля → выбор роли
    if (!hasProfile && location != '/role-select') {
      return '/role-select';
    }

    // Авторизован с профилем — не пускаем на /auth или /role-select
    if (hasProfile && (location == '/auth' || location == '/role-select')) {
      return '/';
    }

    return null;
  },
  routes: [
    GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
    GoRoute(path: '/', builder: (context, state) => const MainTabScaffold()),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(path: '/garage', builder: (context, state) => const GarageScreen()),
    GoRoute(path: '/work', builder: (context, state) => const WorkScreen()),
    GoRoute(path: '/route', builder: (context, state) => const RouteScreen()),
    GoRoute(path: '/history', builder: (context, state) => const TripHistoryScreen()),
    GoRoute(
      path: '/role-select',
      builder: (context, state) => const RoleSelectionScreen(),
    ),
    GoRoute(
      path: '/messenger',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final tripId = extra['tripId'] as String? ?? '';
        final title = extra['title'] as String? ?? 'Чат';
        return MessengerScreen(tripId: tripId, title: title);
      },
    ),
    GoRoute(
      path: '/face-control',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final role = extra['role'] as PartnerRole? ?? PartnerRole.guide;
        final isWeekly = extra['isWeekly'] as bool? ?? false;
        return FaceControlScreen(role: role, isWeeklyVerification: isWeekly);
      },
    ),
    GoRoute(
      path: '/guide-documents',
      builder: (context, state) => const GuideDocumentsScreen(),
    ),
    GoRoute(
      path: '/sos',
      builder: (context, state) => const SosScreen(),
    ),
    GoRoute(
      path: '/route-preview',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final trip = extra['trip'] as ActiveTrip;
        final booking = extra['booking'] as Booking;
        return RoutePreviewScreen(trip: trip, booking: booking);
      },
    ),
    GoRoute(
      path: '/guide-certificate',
      builder: (context, state) {
        final profile = state.extra as PartnerProfile?;
        return GuideCertificateScreen(profile: profile);
      },
    ),
    GoRoute(path: '/mesh', builder: (context, state) => const MeshScreen()),
  ],
);
