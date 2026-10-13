import 'package:flutter/foundation.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../utils/route_calculator.dart';
import '../utils/route_waypoint.dart';

class RouteSegment {
  final List<Point> points;
  final double distanceKm;
  final bool isRealRoute;

  const RouteSegment({
    required this.points,
    required this.distanceKm,
    required this.isRealRoute,
  });
}

/// Результат успешного построения маршрута.
class RouteResult {
  /// Список сегментов пути для раздельной отрисовки (offroad vs onroad)
  final List<RouteSegment> segments;

  /// Оригинальный единый список точек для обратной совместимости
  final List<Point> points;

  /// Расстояние маршрута в километрах.
  final double distanceKm;

  /// Приблизительное время в пути (часы).
  final int durationHours;

  /// `true` — данные получены от Yandex Driving API.
  /// `false` — данные рассчитаны по прямым линиям (Haversine fallback).
  final bool isRealRoute;

  const RouteResult({
    required this.segments,
    required this.points,
    required this.distanceKm,
    required this.durationHours,
    required this.isRealRoute,
  });
}

/// Сетевой сервис построения маршрутов через **Yandex MapKit Driving API**.
///
/// Аналог Kotlin `DirectionsService.kt`, но вместо Retrofit + Google Directions
/// использует встроенный `YandexDriving` из SDK — тот же API-ключ, настроенный
/// в `MainApplication.kt`, работает для роутинга тоже.
///
/// При ошибке автоматически переключается на **Haversine-fallback** (прямые линии).
abstract final class YandexDirectionsService {
  /// Запросить маршрут через все точки [waypoints].
  ///
  /// Строит маршрут по сегментам (от точки к точке).
  /// Для каждого сегмента пытается построить: Автомобильный -> Пешеходный -> Прямая линия.
  /// Это позволяет иметь "смешанный" маршрут, где только часть пути пешком.
  static Future<RouteResult> getRoute(List<RouteWaypoint> waypoints) async {
    if (waypoints.length < 2) {
      return _fallbackHaversine(
        waypoints.isEmpty
            ? [
                RouteWaypoint(
                  latitude: 0,
                  longitude: 0,
                  name: '',
                  color: RouteWaypoint.colorStart,
                ),
                RouteWaypoint(
                  latitude: 0,
                  longitude: 0,
                  name: '',
                  color: RouteWaypoint.colorEnd,
                ),
              ]
            : waypoints,
      );
    }

    final allPoints = <Point>[];
    final segments = <RouteSegment>[];
    double totalDistanceKm = 0.0;
    double totalDurationSeconds = 0.0;
    bool allReal = true;

    for (int i = 0; i < waypoints.length - 1; i++) {
      final start = waypoints[i];
      final end = waypoints[i + 1];

      // 1. Пытаемся построить автомобильный маршрут
      var segment = await _tryDriving(start, end);

      // 2. Если не вышло — пробуем пешеходный
      segment ??= await _tryPedestrian(start, end);

      // 3. Если и это не вышло (например пропал интернет) — соединяем напрямую
      segment ??= _getHaversineSegment(start, end);

      allReal = allReal && segment.isRealRoute;

      segments.add(
        RouteSegment(
          points: segment.points,
          distanceKm: segment.distanceKm,
          isRealRoute: segment.isRealRoute,
        ),
      );

      // Добавляем точки сегмента
      if (i > 0 && segment.points.isNotEmpty && allPoints.isNotEmpty) {
        allPoints.addAll(segment.points.skip(1));
      } else {
        allPoints.addAll(segment.points);
      }

      totalDistanceKm += segment.distanceKm;
      totalDurationSeconds += segment.durationSeconds;
    }

    final durationHours = (totalDurationSeconds / 3600).ceil();

    return RouteResult(
      segments: segments,
      points: allPoints,
      distanceKm: totalDistanceKm,
      durationHours: durationHours,
      isRealRoute: allReal,
    );
  }

  static Future<_SegmentData?> _tryDriving(
    RouteWaypoint start,
    RouteWaypoint end,
  ) async {
    try {
      final (session, futureResult) = await YandexDriving.requestRoutes(
        points: [
          RequestPoint(
            point: Point(latitude: start.latitude, longitude: start.longitude),
            requestPointType: RequestPointType.wayPoint,
          ),
          RequestPoint(
            point: Point(latitude: end.latitude, longitude: end.longitude),
            requestPointType: RequestPointType.wayPoint,
          ),
        ],
        drivingOptions: const DrivingOptions(routesCount: 1),
      );

      final sessionResult = await futureResult;
      session.close();

      if (sessionResult.error != null) {
        debugPrint(
          '[YandexDirectionsService] Driving API Error: ${sessionResult.error}',
        );
        return null;
      }
      if (sessionResult.routes == null || sessionResult.routes!.isEmpty) {
        debugPrint('[YandexDirectionsService] No driving routes returned');
        return null;
      }

      final route = sessionResult.routes!.first;
      return _SegmentData(
        points: route.geometry.points,
        distanceKm: (route.metadata.weight.distance.value ?? 0.0) / 1000.0,
        durationSeconds: route.metadata.weight.timeWithTraffic.value ?? 0.0,
        isRealRoute: true,
      );
    } catch (e) {
      debugPrint('[YandexDirectionsService] Driving Exception: $e');
      return null;
    }
  }

  static Future<_SegmentData?> _tryPedestrian(
    RouteWaypoint start,
    RouteWaypoint end,
  ) async {
    try {
      final (session, futureResult) = await YandexPedestrian.requestRoutes(
        points: [
          RequestPoint(
            point: Point(latitude: start.latitude, longitude: start.longitude),
            requestPointType: RequestPointType.wayPoint,
          ),
          RequestPoint(
            point: Point(latitude: end.latitude, longitude: end.longitude),
            requestPointType: RequestPointType.wayPoint,
          ),
        ],
        timeOptions: const TimeOptions(),
        fitnessOptions: const FitnessOptions(
          avoidSteep: false,
          avoidStairs: false,
        ),
      );

      final sessionResult = await futureResult;
      session.close();

      if (sessionResult.error != null) {
        debugPrint(
          '[YandexDirectionsService] Pedestrian API Error: ${sessionResult.error}',
        );
        return null;
      }
      if (sessionResult.routes == null || sessionResult.routes!.isEmpty) {
        debugPrint('[YandexDirectionsService] No pedestrian routes returned');
        return null;
      }

      final route = sessionResult.routes!.first;
      return _SegmentData(
        points: route.geometry.points,
        distanceKm:
            (route.metadata.weight.walkingDistance.value ?? 0.0) / 1000.0,
        durationSeconds: route.metadata.weight.time.value ?? 0.0,
        isRealRoute: true,
      );
    } catch (e) {
      return null;
    }
  }

  static _SegmentData _getHaversineSegment(
    RouteWaypoint start,
    RouteWaypoint end,
  ) {
    final distanceKm = RouteCalculator.calculateRouteDistance([start, end]);
    final durationHours = RouteCalculator.calculateRouteDuration(distanceKm);
    return _SegmentData(
      points: [
        Point(latitude: start.latitude, longitude: start.longitude),
        Point(latitude: end.latitude, longitude: end.longitude),
      ],
      distanceKm: distanceKm,
      durationSeconds: durationHours * 3600.0,
      isRealRoute: false,
    );
  }

  // в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
  // FULL FALLBACK — Haversine для случая, когда точек < 2
  // в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
  static RouteResult _fallbackHaversine(List<RouteWaypoint> waypoints) {
    final points = waypoints
        .map((w) => Point(latitude: w.latitude, longitude: w.longitude))
        .toList();
    final distanceKm = RouteCalculator.calculateRouteDistance(waypoints);
    final durationHours = RouteCalculator.calculateRouteDuration(distanceKm);

    return RouteResult(
      segments: [
        RouteSegment(
          points: points,
          distanceKm: distanceKm,
          isRealRoute: false,
        ),
      ],
      points: points,
      distanceKm: distanceKm,
      durationHours: durationHours,
      isRealRoute: false,
    );
  }
}

class _SegmentData {
  final List<Point> points;
  final double distanceKm;
  final double durationSeconds;
  final bool isRealRoute;

  _SegmentData({
    required this.points,
    required this.distanceKm,
    required this.durationSeconds,
    required this.isRealRoute,
  });
}


