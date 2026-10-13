import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервис запроса разрешений на геолокацию (foreground + background).
///
/// Реализует требования Google Play:
/// 1. Prominent Disclosure — объяснительный диалог ДО запроса разрешений.
/// 2. Foreground location — стандартный системный диалог Android.
/// 3. Background location — отдельный шаг с доп. объяснением (требование Google Play).
///
/// Диалог показывается **один раз** при первом запуске после входа.
/// Повторный запрос производится только если разрешения всё ещё не выданы.
abstract final class LocationPermissionService {
  static const _prefKey = 'location_permission_disclosure_shown';

  /// Запрашивает все необходимые разрешения геолокации.
  ///
  /// [context] — BuildContext для показа диалогов.
  /// Безопасно вызывать повторно: если разрешения уже выданы — ничего не делает.
  static Future<void> requestAll(BuildContext context) async {
    // 1. Проверяем, включена ли служба GPS
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return; // Нет смысла запрашивать без GPS

    // 2. Проверяем текущее состояние разрешений
    final currentPerm = await Geolocator.checkPermission();
    final bgPerm = await Permission.locationAlways.status;

    // Если уже всё выдано — ничего не делаем
    if ((currentPerm == LocationPermission.always ||
            currentPerm == LocationPermission.whileInUse) &&
        bgPerm.isGranted) {
      return;
    }

    // 3. Проверяем, показывали ли уже Prominent Disclosure
    final prefs = await SharedPreferences.getInstance();
    final disclosed = prefs.getBool(_prefKey) ?? false;

    if (!context.mounted) return;

    // 4. Показываем Prominent Disclosure (один раз или если разрешения не выданы)
    if (!disclosed || currentPerm == LocationPermission.denied) {
      final agreed = await _showProminentDisclosure(context);
      if (!agreed) return; // Пользователь отказался
      await prefs.setBool(_prefKey, true);
    }

    if (!context.mounted) return;

    // 5. Запрашиваем Foreground-разрешение (FINE + COARSE)
    if (currentPerm == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }

    if (!context.mounted) return;

    // 6. Проверяем результат foreground
    final afterFg = await Geolocator.checkPermission();
    if (afterFg == LocationPermission.deniedForever ||
        afterFg == LocationPermission.denied) {
      return; // Пользователь отказал — не давим
    }

    if (!context.mounted) return;

    // 6.5. На Android 13+ обязательно запрашиваем разрешение на уведомления,
    // иначе Foreground Service будет работать без уведомления в шторке.
    final notifStatus = await Permission.notification.status;
    if (!notifStatus.isGranted) {
      await Permission.notification.request();
    }

    if (!context.mounted) return;

    // 7. Запрашиваем Background-разрешение отдельным шагом
    final bgStatus = await Permission.locationAlways.status;
    if (!bgStatus.isGranted) {
      if (!context.mounted) return;
      final agreedBg = await _showBackgroundDisclosure(context);
      if (!agreedBg) return;

      if (!context.mounted) return;
      // На Android 11+ система сама откроет настройки или покажет диалог
      await Permission.locationAlways.request();
    }
  }

  // ── Диалоги ───────────────────────────────────────────────────────────────

  /// Prominent Disclosure — объяснение зачем нужна геолокация.
  static Future<bool> _showProminentDisclosure(BuildContext context) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Доступ к геолокации'),
        content: const Text(
          'Приложение Explora Partners собирает данные о местоположении для '
          'обеспечения работы следующих функций:\n'
          '• Отслеживание вашего маршрута во время поездки\n'
          '• Трансляция вашей геопозиции клиентам в реальном времени\n'
          '• Работа функции экстренного SOS\n'
          '• MESH-сеть для офлайн-связи\n\n'
          'Данные собираются даже когда приложение закрыто или '
          'не используется (в фоновом режиме), чтобы поездка '
          'не прерывалась при блокировке экрана.',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Не сейчас'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Объяснение перед запросом фонового доступа (Background location).
  static Future<bool> _showBackgroundDisclosure(BuildContext context) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Геолокация в фоне'),
        content: const Text(
          'Приложение Explora Partners собирает данные о местоположении '
          'в фоновом режиме (опция «Всегда» в настройках).\n\n'
          'Это позволяет:\n'
          '• Продолжать трансляцию вашего маршрута клиентам\n'
          '• Работать SOS-сигналу при заблокированном экране\n\n'
          'Данные собираются даже когда приложение закрыто или не используется. '
          'На следующем экране выберите «Всегда разрешать».',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Пропустить'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Разрешить'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
