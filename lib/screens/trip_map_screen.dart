import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../models/offline_action.dart';
import '../services/sync_manager.dart';
import '../models/booking_models.dart';
import '../models/partner_models.dart';
import '../repository/firestore_repository.dart';
import '../services/location_permission_service.dart';
import '../services/yandex_directions_service.dart';
import '../utils/route_waypoint.dart';
import '../utils/user_marker_painter.dart';

/// Navigator-style full-screen trip map for partners (drivers & guides).
///
/// – Shows the full route polyline + waypoints
/// – Camera follows the partner's live GPS position when in_progress
/// – "Travelled" segment highlighted in green
/// – GPS broadcast every 20 m → Firestore `driverLocation`
/// – Bottom draggable panel with stage indicator, trip details,
///   "I'm here (≤100 m)" button (waiting) and "Finish Trip" (in_progress)
class TripMapScreen extends StatefulWidget {
  final String tripId;
  final PartnerRole? role;

  const TripMapScreen({super.key, required this.tripId, this.role});

  @override
  State<TripMapScreen> createState() => _TripMapScreenState();
}

class _TripMapScreenState extends State<TripMapScreen> {
  YandexMapController? _mapController;
  bool _isMapCreated = false;
  bool _alreadyFit = false;

  bool _isMarkingReady = false;
  bool _isCompleting = false;

  List<RouteSegment>? _dynamicRouteSegments;
  List<Point> _flattenedDynamicPoints = [];

  // Live GPS tracking
  Position? _myPosition;
  StreamSubscription<Position>? _locationSub;

  bool get _isDriver => widget.role?.isDriver ?? true;

  // Cached role marker icons (generated once)
  Uint8List? _driverIconBytes;
  Uint8List? _guideIconBytes;
  Uint8List? _clientIconBytes;

  // Stage metadata (mirrors the client app)
  static const List<TripStatus> _stages = [TripStatus.scheduled, TripStatus.waiting, TripStatus.inProgress, TripStatus.completed];
  static const Map<TripStatus, String> _stageLabels = {
    TripStatus.scheduled: 'Запланировано',
    TripStatus.waiting: 'Сбор группы',
    TripStatus.inProgress: 'В пути',
    TripStatus.completed: 'Завершён',
  };

  @override
  void initState() {
    super.initState();
    _startListeningLocation();
    _initMarkers();
  }

  Future<void> _initMarkers() async {
    final d = await UserMarkerPainter.driver();
    final g = await UserMarkerPainter.guide();
    final c = await UserMarkerPainter.client();
    if (mounted) {
      setState(() {
        _driverIconBytes = d;
        _guideIconBytes  = g;
        _clientIconBytes = c;
      });
    }
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }

  // ─────────────────────────────── GPS ─────────────────────────────────────

  /// AndroidSettings с foreground-уведомлением для режима ожидания (idle).
  /// Показывает уведомление в шторке чтобы Android не убил процесс.
  static final _idleLocationSettings = AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationTitle: 'Explora Partners',
      notificationText: 'Определение местоположения активно',
      enableWakeLock: false,
      notificationIcon: AndroidResource(
        name: 'launcher_icon',
        defType: 'mipmap',
      ),
    ),
  );

  /// AndroidSettings с foreground-уведомлением для активной поездки.
  /// Wake-lock включён — GPS не должен прерываться при выключенном экране.
  static final _tripLocationSettings = AndroidSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 20,
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationTitle: 'Explora Partners — Маршрут активен',
      notificationText: 'Ваше местоположение передаётся участникам поездки',
      enableWakeLock: true,
      notificationIcon: AndroidResource(
        name: 'launcher_icon',
        defType: 'mipmap',
      ),
    ),
  );

  void _startListeningLocation() {
    _locationSub =
        Geolocator.getPositionStream(
          locationSettings: _idleLocationSettings,
        ).listen(
          (pos) { if (mounted) setState(() => _myPosition = pos); },
          onError: (_) {},
          cancelOnError: false,
        );
  }

  void _startBroadcast(String tripId) {
    // If already listening, reuse; the same _locationSub sends to Firestore too.
    // We replace the listener so it also writes to Firestore.
    _locationSub?.cancel();
    _locationSub =
        Geolocator.getPositionStream(
          locationSettings: _tripLocationSettings,
        ).listen(
          (pos) {
          if (mounted) setState(() => _myPosition = pos);
          if (_isDriver) {
            SyncManager.instance.enqueueAction(OfflineAction(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              type: 'updateDriverLocation',
              payload: {'tripId': tripId, 'lat': pos.latitude, 'lng': pos.longitude},
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ));
          } else {
            SyncManager.instance.enqueueAction(OfflineAction(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              type: 'updateGuideLocation',
              payload: {'tripId': tripId, 'lat': pos.latitude, 'lng': pos.longitude},
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ));
          }
          // Camera follows
          _mapController?.moveCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: Point(latitude: pos.latitude, longitude: pos.longitude),
                zoom: 16,
              ),
            ),
            animation: const MapAnimation(
              type: MapAnimationType.smooth,
              duration: 1.0,
            ),
          );
        },
          onError: (_) {},
          cancelOnError: false,
        );
  }

  void _stopBroadcast() {
    _locationSub?.cancel();
    _locationSub = null;
    _myPosition = null;
  }

  // ──────────────────────────────── Geometry ───────────────────────────────

  double _dist(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  // Find the index of the closest geometry point to the current position
  int _closestIdx(List<Point> geo) {
    if (_myPosition == null || geo.isEmpty) return 0;
    int best = 0;
    double bestD = double.infinity;
    for (int i = 0; i < geo.length; i++) {
      final d = _dist(
        _myPosition!.latitude,
        _myPosition!.longitude,
        geo[i].latitude,
        geo[i].longitude,
      );
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  // ────────────────────────────── Map Objects ───────────────────────────────

  List<MapObject> _buildMapObjects(ActiveTrip trip) {
    final objects = <MapObject>[];

    if (_dynamicRouteSegments != null && _dynamicRouteSegments!.isNotEmpty) {
      final closestIdx = trip.status == TripStatus.inProgress ? _closestIdx(_flattenedDynamicPoints) : 0;

      for (var i = 0; i < _dynamicRouteSegments!.length; i++) {
        final segment = _dynamicRouteSegments![i];
        objects.add(
          PolylineMapObject(
            mapId: MapObjectId('route_segment_$i'),
            polyline: Polyline(points: segment.points),
            strokeColor: segment.isRealRoute
                ? const Color(0xFF6FBF4F)
                : const Color(0xFFFF6F00),
            strokeWidth: segment.isRealRoute ? 5.0 : 4.0,
            outlineColor: segment.isRealRoute
                ? Colors.white
                : const Color(0x44FF6F00),
            outlineWidth: segment.isRealRoute ? 1.5 : 2.0,
            dashLength: segment.isRealRoute ? 0.0 : 10.0,
            gapLength: segment.isRealRoute ? 0.0 : 6.0,
          ),
        );
      }

      if (closestIdx > 0 && trip.status == TripStatus.inProgress) {
        objects.add(
          PolylineMapObject(
            mapId: const MapObjectId('route_done'),
            polyline: Polyline(
              points: _flattenedDynamicPoints.take(closestIdx + 1).toList(),
            ),
            strokeColor: CupertinoColors.systemGreen,
            strokeWidth: 6,
            outlineColor: Colors.white,
            outlineWidth: 1.5,
          ),
        );
      }
    } else if (trip.routeGeometry.isNotEmpty) {
      final geo = trip.routeGeometry;
      final closestIdx = trip.status == TripStatus.inProgress 
          ? _closestIdx(geo.map((p) => Point(latitude: p.$1, longitude: p.$2)).toList()) 
          : 0;

      if (closestIdx < geo.length - 1) {
        objects.add(
          PolylineMapObject(
            mapId: const MapObjectId('route_ahead'),
            polyline: Polyline(
              points: geo
                  .skip(closestIdx)
                  .map((p) => Point(latitude: p.$1, longitude: p.$2))
                  .toList(),
            ),
            strokeColor: const Color(0xFF6FBF4F),
            strokeWidth: 5,
            outlineColor: Colors.white,
            outlineWidth: 1.5,
          ),
        );
      }

      if (closestIdx > 0 && trip.status == TripStatus.inProgress) {
        objects.add(
          PolylineMapObject(
            mapId: const MapObjectId('route_done'),
            polyline: Polyline(
              points: geo
                  .take(closestIdx + 1)
                  .map((p) => Point(latitude: p.$1, longitude: p.$2))
                  .toList(),
            ),
            strokeColor: CupertinoColors.systemGreen,
            strokeWidth: 5,
            outlineColor: Colors.white,
            outlineWidth: 1.5,
          ),
        );
      }
    }

    // Waypoint markers
    for (var i = 0; i < trip.waypoints.length; i++) {
      final wp = trip.waypoints[i];
      objects.add(
        PlacemarkMapObject(
          mapId: MapObjectId('wp_$i'),
          point: Point(latitude: wp.latitude, longitude: wp.longitude),
          icon: PlacemarkIcon.single(
            PlacemarkIconStyle(
              image: BitmapDescriptor.fromAssetImage(
                'packages/yandex_mapkit/lib/assets/place.png',
              ),
              scale: 2.0,
            ),
          ),
          text: PlacemarkText(
            text: wp.address.isNotEmpty ? wp.address : 'Точка ${i + 1}',
            style: const PlacemarkTextStyle(
              color: Color(0xFF1A1A1A),
              size: 11,
              placement: TextStylePlacement.bottom,
              offset: 4,
            ),
          ),
        ),
      );
    }

    if (!_isDriver && trip.driverLocation != null) {
      objects.add(
        PlacemarkMapObject(
          mapId: const MapObjectId('driver_location'),
          point: Point(
            latitude: trip.driverLocation!.$1,
            longitude: trip.driverLocation!.$2,
          ),
          icon: _driverIconBytes != null
              ? PlacemarkIcon.single(PlacemarkIconStyle(
                  image: BitmapDescriptor.fromBytes(_driverIconBytes!),
                  scale: 1.0,
                  rotationType: RotationType.noRotation,
                ))
              : PlacemarkIcon.single(PlacemarkIconStyle(
                  image: BitmapDescriptor.fromAssetImage(
                    'packages/yandex_mapkit/lib/assets/user.png',
                  ),
                  scale: 1.5,
                )),
        ),
      );
    }

    if (_isDriver && trip.guideLocation != null) {
      objects.add(
        PlacemarkMapObject(
          mapId: const MapObjectId('guide_location'),
          point: Point(
            latitude: trip.guideLocation!.$1,
            longitude: trip.guideLocation!.$2,
          ),
          icon: _guideIconBytes != null
              ? PlacemarkIcon.single(PlacemarkIconStyle(
                  image: BitmapDescriptor.fromBytes(_guideIconBytes!),
                  scale: 1.0,
                  rotationType: RotationType.noRotation,
                ))
              : PlacemarkIcon.single(PlacemarkIconStyle(
                  image: BitmapDescriptor.fromAssetImage(
                    'packages/yandex_mapkit/lib/assets/user.png',
                  ),
                  scale: 1.5,
                )),
        ),
      );
    }

    if (trip.clientLocation != null) {
      objects.add(
        PlacemarkMapObject(
          mapId: const MapObjectId('client_location'),
          point: Point(
            latitude: trip.clientLocation!.$1,
            longitude: trip.clientLocation!.$2,
          ),
          icon: _clientIconBytes != null
              ? PlacemarkIcon.single(PlacemarkIconStyle(
                  image: BitmapDescriptor.fromBytes(_clientIconBytes!),
                  scale: 1.0,
                  rotationType: RotationType.noRotation,
                ))
              : PlacemarkIcon.single(PlacemarkIconStyle(
                  image: BitmapDescriptor.fromAssetImage(
                    'packages/yandex_mapkit/lib/assets/route_start.png',
                  ),
                  scale: 1.2,
                )),
        ),
      );
    }

    // My live position — bright orange dot
    if (_myPosition != null) {
      objects.add(
        PlacemarkMapObject(
          mapId: const MapObjectId('my_pos'),
          point: Point(
            latitude: _myPosition!.latitude,
            longitude: _myPosition!.longitude,
          ),
          icon: PlacemarkIcon.single(
            PlacemarkIconStyle(
              image: BitmapDescriptor.fromAssetImage(
                'packages/yandex_mapkit/lib/assets/place.png',
              ),
              scale: 2.2,
            ),
          ),
        ),
      );
    }

    return objects;
  }

  Future<void> _fetchDynamicRoute(ActiveTrip trip) async {
    if (_dynamicRouteSegments != null || trip.waypoints.isEmpty) return;

    final routeWaypoints = trip.waypoints.map((pt) {
      return RouteWaypoint(
        latitude: pt.latitude,
        longitude: pt.longitude,
        name: pt.address,
        color: RouteWaypoint.colorMid,
      );
    }).toList();

    if (routeWaypoints.isNotEmpty) {
      routeWaypoints.first = routeWaypoints.first.withColor(RouteWaypoint.colorStart);
      routeWaypoints.last = routeWaypoints.last.withColor(RouteWaypoint.colorEnd);
    }

    final result = await YandexDirectionsService.getRoute(routeWaypoints);
    if (!mounted) return;

    setState(() {
      _dynamicRouteSegments = result.segments;
      _flattenedDynamicPoints = result.points;
    });
  }

  void _fitRoute(ActiveTrip trip) async {
    if (_mapController == null || _alreadyFit) return;
    if (trip.routeGeometry.isEmpty && trip.waypoints.isEmpty) return;
    _alreadyFit = true;

    final points = trip.routeGeometry.isNotEmpty
        ? trip.routeGeometry
              .map((p) => Point(latitude: p.$1, longitude: p.$2))
              .toList()
        : trip.waypoints
              .map((w) => Point(latitude: w.latitude, longitude: w.longitude))
              .toList();

    if (points.length == 1) {
      await _mapController!.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: points.first, zoom: 14),
        ),
        animation: const MapAnimation(
          type: MapAnimationType.smooth,
          duration: 1.5,
        ),
      );
    } else {
      // Fit all points
      double minLat = points.map((p) => p.latitude).reduce(math.min);
      double maxLat = points.map((p) => p.latitude).reduce(math.max);
      double minLng = points.map((p) => p.longitude).reduce(math.min);
      double maxLng = points.map((p) => p.longitude).reduce(math.max);

      await _mapController!.moveCamera(
        CameraUpdate.newGeometry(
          Geometry.fromBoundingBox(
            BoundingBox(
              southWest: Point(
                latitude: minLat - 0.005,
                longitude: minLng - 0.005,
              ),
              northEast: Point(
                latitude: maxLat + 0.005,
                longitude: maxLng + 0.005,
              ),
            ),
          ),
        ),
        animation: const MapAnimation(
          type: MapAnimationType.smooth,
          duration: 1.5,
        ),
      );
    }
  }

  // ─────────────────────────────── Actions ─────────────────────────────────

  Future<void> _markReady(ActiveTrip trip, Booking? booking) async {
    if (_isMarkingReady) return;
    setState(() => _isMarkingReady = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        if (mounted) {
          await LocationPermissionService.requestAll(context);
          perm = await Geolocator.checkPermission();
        }
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        _snack('Нет разрешения на геолокацию', isError: true);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );

      final wp = booking?.waypoints.firstOrNull;
      if (wp != null) {
        // ignore: unused_local_variable
        final d = _dist(pos.latitude, pos.longitude, wp.latitude, wp.longitude);
        /*
        if (d > 100) {
          _snack(
            'Вы в ${d.toStringAsFixed(0)} м от точки сбора. Нужно ≤ 100 м.',
            isError: true,
          );
          return;
        }
        */
      }

      SyncManager.instance.enqueueAction(OfflineAction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'setPartnerReady',
        payload: {'tripId': trip.id, 'isDriver': _isDriver},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      // ACTUAL re-read the trip from Firestore to prevent race conditions
      // when both participants press "Я на месте" at the same time.
      final latestTrip = await FirestoreRepository.instance.getTripById(trip.id);
      if (latestTrip == null) return;

      // Guard: if trip already transitioned (e.g. another participant fired startTrip
      // between our setPartnerReady() and this re-read), bail out — no-op.
      if (latestTrip.status != TripStatus.waiting) return;

      // Optimistic: check if all ready to auto-start
      // final hasGuide = booking?.guideId != null;
      final driverOk = _isDriver ? true : latestTrip.driverReady;
      final guideOk = true; // !hasGuide || (!_isDriver ? true : latestTrip.guideReady);
      final clientOk = latestTrip.clientReady;

      if (driverOk && guideOk && clientOk) {
        SyncManager.instance.enqueueAction(OfflineAction(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: 'startTrip',
          payload: {'tripId': trip.id, 'bookingId': trip.bookingId},
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));
        _snack('🚗 Все готовы! Маршрут начат.', isError: false);
      } else {
        _snack('✅ Готовность отмечена! Ожидаем остальных.', isError: false);
      }
    } catch (e) {
      _snack('Ошибка: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isMarkingReady = false);
    }
  }

  // Returns true if [index] is the final return-to-start waypoint appended by startTrip().
  bool _isReturnWaypoint(ActiveTrip trip, int index) {
    final wps = trip.waypoints;
    if (wps.length < 2) return false;
    if (index != wps.length - 1) return false;
    final first = wps.first;
    final last  = wps.last;
    return (first.latitude == last.latitude && first.longitude == last.longitude) ||
        (first.address == last.address && first.address.isNotEmpty);
  }

  // True once the driver/guide has checked in at ALL waypoints (incl. return).
  bool _allWaypointsDone(ActiveTrip trip) {
    final idx = trip.currentWaypointIndex;
    return idx >= trip.waypoints.length;
  }

  // ignore: unused_element
  Widget _buildPartnerWaypointCard(ActiveTrip trip) {
    final wps        = trip.waypoints;
    final idx        = trip.currentWaypointIndex;
    final total      = wps.length;
    final role       = _isDriver ? 'driver' : 'guide';

    if (idx >= total) {
      // All waypoints done — return a soft "all done" banner.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoColors.systemGreen.withAlpha(30),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CupertinoColors.systemGreen.withAlpha(80)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.checkmark_circle_fill,
                color: CupertinoColors.systemGreen, size: 18),
            SizedBox(width: 8),
            Text('Все точки пройдены!',
                style: TextStyle(
                    color: CupertinoColors.systemGreen,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ],
        ),
      );
    }

    final isReturn     = _isReturnWaypoint(trip, idx);
    final Map<String, bool> wpCheckIns = idx < trip.waypoints.length
        ? trip.waypoints[idx].checkIns
        : {};
    final alreadyIn    = wpCheckIns[role] == true;
    final pointLabel   = isReturn
        ? '🏁 ФИНИШ — ВОЗВРАТ НА СТАРТ'
        : 'ТОЧКА ${idx + 1} ИЗ $total';
    final accentColor  = isReturn
        ? CupertinoColors.systemGreen
        : const Color(0xFF6FBF4F);

    if (alreadyIn) {
      final checkedIn = wpCheckIns.values.where((v) => v).length;
      final need = 2 + (trip.partnerId != null ? 1 : 0) + trip.companions.length;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accentColor.withAlpha(25),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(pointLabel,
                style: TextStyle(
                    color: accentColor, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Ждём остальных: $checkedIn / $need',
                style: const TextStyle(color: Colors.white60, fontSize: 13)),
          ],
        ),
      );
    } else {
      return Column(
        children: [
          if (isReturn)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGreen.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CupertinoColors.systemGreen.withAlpha(70)),
              ),
              child: const Row(
                children: [
                  Icon(CupertinoIcons.flag_fill,
                      color: CupertinoColors.systemGreen, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Последний отрезок — возвращайтесь на точку старта!',
                      style: TextStyle(
                          color: CupertinoColors.systemGreen,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accentColor.withAlpha(80)),
            ),
            child: Column(
              children: [
                Text(pointLabel,
                    style: TextStyle(
                        color: accentColor, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    color: accentColor,
                    borderRadius: BorderRadius.circular(12),
                    onPressed: () {
                      SyncManager.instance.enqueueAction(OfflineAction(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        type: 'checkInAtWaypoint',
                        payload: {'tripId': trip.id, 'idx': idx, 'role': role},
                        timestamp: DateTime.now().millisecondsSinceEpoch,
                      ));
                    },
                    child: Text(
                      isReturn ? '🏁 Я вернулся на старт' : 'Я на месте',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
  }

  Future<void> _finishTrip(ActiveTrip trip) async {
    if (_isCompleting) return;
    // Step 1: request client confirmation (no local dialog needed —
    // the client will see a prompt in their app)
    setState(() => _isCompleting = true);
    try {
      SyncManager.instance.enqueueAction(OfflineAction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'finishTrip',
        payload: {'tripId': trip.id, 'isDriver': _isDriver},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
      if (mounted) {
        _snack(
          '📨 Запрос отправлен — ожидаем подтверждения клиента',
          isError: false,
        );
      }
    } catch (e) {
      _snack('Ошибка запроса завершения: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  void _centerOnMe() {
    if (_myPosition == null || _mapController == null) return;
    _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: Point(
            latitude: _myPosition!.latitude,
            longitude: _myPosition!.longitude,
          ),
          zoom: 16,
        ),
      ),
      animation: const MapAnimation(
        type: MapAnimationType.smooth,
        duration: 0.8,
      ),
    );
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError
            ? Colors.red.shade600
            : const Color(0xFF6FBF4F),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ───────────────────────────── Stage UI ──────────────────────────────────

  Widget _buildStageIndicator(TripStatus currentStatus) {
    final currentIdx = _stages.indexOf(currentStatus).clamp(0, 3);
    return Row(
      children: List.generate(_stages.length, (i) {
        final isDone = i < currentIdx;
        final isActive = i == currentIdx;
        final label = _stageLabels[_stages[i]] ?? '';
        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  if (i > 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isDone || isActive
                            ? const Color(0xFF6FBF4F)
                            : Colors.white24,
                      ),
                    ),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone || isActive
                          ? const Color(0xFF6FBF4F)
                          : Colors.white24,
                    ),
                    child: Center(
                      child: isDone
                          ? const Icon(
                              CupertinoIcons.check_mark,
                              size: 12,
                              color: Colors.white,
                            )
                          : isActive
                          ? Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                  ),
                  if (i < _stages.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isDone
                            ? const Color(0xFF6FBF4F)
                            : Colors.white24,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive || isDone
                      ? const Color(0xFF6FBF4F)
                      : Colors.white38,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }),
    );
  }

  bool _amIReady(ActiveTrip trip) =>
      _isDriver ? trip.driverReady : trip.guideReady;

  // ─────────────────────────────── Build ───────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<ActiveTrip?>(
        stream: FirestoreRepository.instance.streamTripById(widget.tripId),
        builder: (context, tripSnap) {
          final trip = tripSnap.data;

          if (trip == null) {
            if (tripSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CupertinoActivityIndicator());
            }
            return const Center(
              child: Text(
                'Маршрут не найден',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          // Manage GPS broadcast based on status
          if (_dynamicRouteSegments == null && trip.waypoints.isNotEmpty) {
            _fetchDynamicRoute(trip);
          }

          if (trip.status == TripStatus.inProgress) {
            if (_locationSub == null) _startBroadcast(trip.id);
          } else {
            if (_locationSub != null && trip.status == TripStatus.completed) {
              _stopBroadcast();
            }
          }

          // Fit camera on first load
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_isMapCreated && !_alreadyFit) _fitRoute(trip);
          });

          return FutureBuilder<Booking?>(
            future: FirestoreRepository.instance.getBookingById(trip.bookingId),
            builder: (context, bookingSnap) {
              final booking = bookingSnap.data;
              final routeTitle =
                  booking?.routeTitle ?? trip.customName ?? 'Маршрут';

              return Stack(
                children: [
                  // ── Full-screen map ──────────────────────────────────
                  YandexMap(
                    mapObjects: _buildMapObjects(trip),
                    nightModeEnabled: true,
                    onMapCreated: (c) async {
                      _mapController = c;
                      _isMapCreated = true;
                      await c.toggleUserLayer(visible: true);
                      _fitRoute(trip);
                    },
                  ),

                  // ── Back button ──────────────────────────────────────
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 16,
                    child: CircleAvatar(
                      backgroundColor: Colors.black87,
                      child: IconButton(
                        icon: const Icon(
                          CupertinoIcons.arrow_left,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),

                  // ── Center-on-me button ──────────────────────────────
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    right: 16,
                    child: CircleAvatar(
                      backgroundColor: Colors.black87,
                      child: IconButton(
                        icon: const Icon(
                          CupertinoIcons.location_fill,
                          color: Color(0xFF6FBF4F),
                          size: 20,
                        ),
                        onPressed: _centerOnMe,
                      ),
                    ),
                  ),

                  // ── GPS live indicator (in_progress) ─────────────────
                  if (trip.status == TripStatus.inProgress)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 64,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.location_fill,
                              size: 12,
                              color: CupertinoColors.systemGreen,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'GPS Live',
                              style: TextStyle(
                                color: CupertinoColors.systemGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ── Draggable bottom panel ───────────────────────────
                  DraggableScrollableSheet(
                    initialChildSize: 0.38,
                    minChildSize: 0.14,
                    maxChildSize: 0.75,
                    builder: (ctx, scrollCtrl) {
                      return Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: SingleChildScrollView(
                          controller: scrollCtrl,
                          padding: EdgeInsets.only(
                            left: 20,
                            right: 20,
                            top: 12,
                            bottom: MediaQuery.of(context).padding.bottom + 24,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Drag handle
                              Center(
                                child: Container(
                                  width: 36,
                                  height: 4,
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),

                              // Stage indicator
                              _buildStageIndicator(trip.status),
                              const SizedBox(height: 20),

                              // Route title
                              Text(
                                routeTitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),

                              // Meeting point
                              if (booking?.waypoints.isNotEmpty == true) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(
                                      CupertinoIcons.map_pin,
                                      size: 13,
                                      color: Colors.white54,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Старт: ${booking!.waypoints.first.address}',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 13,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],

                              // Booking details
                              if (booking != null) ...[
                                const SizedBox(height: 12),
                                _buildInfoRow(
                                  CupertinoIcons.person_2_fill,
                                  '${booking.participants} участников',
                                ),
                                if (booking.startDate.isNotEmpty)
                                  _buildInfoRow(
                                    CupertinoIcons.calendar,
                                    booking.startDate.split('T').first,
                                  ),
                                _buildInfoRow(
                                  CupertinoIcons.money_dollar_circle,
                                  '${booking.totalPrice.toStringAsFixed(0)} ₸',
                                ),
                              ],

                              const SizedBox(height: 20),

                              // ── Waiting: arrival button ──────────────
                              if (trip.status == TripStatus.waiting) ...[
                                // Readiness status
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.darkBackgroundGray,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Готовность: '
                                    '${trip.driverReady ? "✅" : "⏳"} Водитель   '
                                    '${trip.clientReady ? "✅" : "⏳"} Клиент',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: _amIReady(trip)
                                      ? (trip.clientReady 
                                          ? CupertinoButton(
                                              padding: const EdgeInsets.symmetric(vertical: 14),
                                              color: CupertinoColors.systemGreen,
                                              borderRadius: BorderRadius.circular(14),
                                              onPressed: _isMarkingReady ? null : () async {
                                                setState(() => _isMarkingReady = true);
                                                try {
                                                  SyncManager.instance.enqueueAction(OfflineAction(
                                                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                                                    type: 'startTrip',
                                                    payload: {'tripId': trip.id, 'bookingId': booking?.id ?? trip.bookingId},
                                                    timestamp: DateTime.now().millisecondsSinceEpoch,
                                                  ));
                                                } catch (e) {
                                                  _snack('Ошибка: $e', isError: true);
                                                } finally {
                                                  if (mounted) setState(() => _isMarkingReady = false);
                                                }
                                              },
                                              child: _isMarkingReady
                                                  ? const CupertinoActivityIndicator(color: Colors.white)
                                                  : const Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Icon(CupertinoIcons.play_fill, color: Colors.white, size: 18),
                                                        SizedBox(width: 8),
                                                        Text('Начать поездку', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                                                      ],
                                                    ),
                                            )
                                          : Container(
                                              padding: const EdgeInsets.symmetric(
                                                vertical: 14,
                                              ),
                                              decoration: BoxDecoration(
                                                color: CupertinoColors.systemGreen
                                                    .withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(
                                                  14,
                                                ),
                                              ),
                                              child: const Center(
                                                child: Text(
                                                  '✅ Вы отметили прибытие',
                                                  style: TextStyle(
                                                    color:
                                                        CupertinoColors.systemGreen,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ),
                                            ))
                                      : CupertinoButton(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          color: CupertinoColors.systemOrange,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          onPressed: _isMarkingReady
                                              ? null
                                              : () => _markReady(trip, booking),
                                          child: _isMarkingReady
                                              ? const CupertinoActivityIndicator(
                                                  color: Colors.white,
                                                )
                                              : const Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      CupertinoIcons
                                                          .location_fill,
                                                      color: Colors.white,
                                                      size: 18,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      'Я на месте (≤ 100 м)',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                        ),
                                ),
                              ],

                              // ── In progress: finish or pending-completion ─
                              if (trip.status == TripStatus.inProgress) ...[
                                if (trip.completionRequested)
                                  // Banner: waiting for client
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: CupertinoColors.systemOrange
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: CupertinoColors.systemOrange
                                            .withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          CupertinoIcons.hourglass,
                                          color: CupertinoColors.systemOrange,
                                          size: 18,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Ожидаем подтверждения клиента…',
                                          style: TextStyle(
                                            color: CupertinoColors.systemOrange,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  SizedBox(
                                    width: double.infinity,
                                    child: CupertinoButton(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      color: _allWaypointsDone(trip) ? CupertinoColors.systemRed : CupertinoColors.systemGrey,
                                      borderRadius: BorderRadius.circular(14),
                                      onPressed: (_isCompleting || !_allWaypointsDone(trip))
                                          ? null
                                          : () => _finishTrip(trip),
                                      child: _isCompleting
                                          ? const CupertinoActivityIndicator(
                                              color: Colors.white,
                                            )
                                          : const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  CupertinoIcons
                                                      .checkmark_circle_fill,
                                                  color: Colors.white,
                                                  size: 18,
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Запросить завершение',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                              ],

                              // ── Chat button ──────────────────────────
                              if (trip.status != TripStatus.completed) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: CupertinoButton(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    color: const Color(0xFF2C2C2E),
                                    borderRadius: BorderRadius.circular(14),
                                    onPressed: () {
                                      context.push(
                                        '/messenger',
                                        extra: {
                                          'tripId': trip.id,
                                          'title': routeTitle,
                                        },
                                      );
                                    },
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          CupertinoIcons.chat_bubble_text,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Перейти в чат',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white38),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
