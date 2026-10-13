import 'dart:ui' show Color;

/// Точка маршрута (Dart-порт Kotlin `data class RouteWaypoint`).
///
/// Хранит координаты, отображаемое имя и цвет маркера на карте.
/// Ограничения:
///   вЂў Максимум **10** точек на маршрут
///   вЂў Минимум **2** точки для построения маршрута
class RouteWaypoint {
  final double latitude;
  final double longitude;
  final String name;

  /// Цвет маркера на карте.
  ///
  /// Логика по умолчанию:
  ///   вЂў Точка 1 (start)  в†’ зелёный
  ///   вЂў Точка N (end)    в†’ красный
  ///   • Промежуточные    → синий (0xFF6650A4 — Material primary)
  final Color color;

  const RouteWaypoint({
    required this.latitude,
    required this.longitude,
    required this.name,
    required this.color,
  });

  /// Цветовая палитра маркеров.
  static const Color colorStart = Color(0xFF43A047); // green
  static const Color colorEnd = Color(0xFFE53935); // red
  static const Color colorMid = Color(0xFF1565C0); // deep blue

  /// Создать точку с автоматическим именем и цветом по позиции в маршруте.
  ///
  /// [index] — 0-based индекс в списке.
  /// [total] — текущее общее количество точек (после добавления этой).
  factory RouteWaypoint.fromIndex(
    double latitude,
    double longitude,
    int index,
    int total,
  ) {
    final Color color;
    if (index == 0) {
      color = colorStart;
    } else if (index == total - 1) {
      color = colorEnd;
    } else {
      color = colorMid;
    }

    return RouteWaypoint(
      latitude: latitude,
      longitude: longitude,
      name: index == 0
          ? 'Старт'
          : (index == total - 1 ? 'Финиш' : 'Точка $index'),
      color: color,
    );
  }

  /// Пересоздаёт точку с обновлённым цветом (для пересчёта при изменении списка).
  RouteWaypoint withColor(Color newColor) => RouteWaypoint(
    latitude: latitude,
    longitude: longitude,
    name: name,
    color: newColor,
  );

  @override
  String toString() => 'RouteWaypoint($name: $latitude, $longitude)';
}


