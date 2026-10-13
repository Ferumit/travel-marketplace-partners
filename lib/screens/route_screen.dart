import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../services/location_permission_service.dart';

import 'package:geolocator/geolocator.dart';
import '../models/booking_models.dart';
import '../models/partner_models.dart';
import '../navigation/main_tab_scaffold.dart';
import '../repository/firestore_repository.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../utils/user_marker_painter.dart';
import '../widgets/navigation_overlay.dart';

class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key});

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  YandexMapController? _mapController;

  // Live GPS tracking
  Position? _myPosition;
  Position? _lastBroadcastPosition;
  DateTime? _lastBroadcastTime;
  StreamSubscription<Position>? _locationSub;
  String? _listeningTripId;
  bool _alreadyFit = false;
  bool _hasCenteredOnStart = false; // one-time center on open

  // Cached car marker icon bytes
  Uint8List? _carIconBytes;
  Uint8List? _guideIconBytes;
  Uint8List? _clientIconBytes;

  double _currentSpeedKmh = 0.0;
  TurnInstruction? _nextTurn;

  // ── Троттлинг, чтобы карта не тормозила ──
  // GPS-стрим (distanceFilter:0) шлёт события очень часто. Полный setState и
  // moveCamera на каждом тике перегружают UI и заставляют камеру «залипать»
  // на иконке. Поэтому ограничиваем частоту перерисовки и движения камеры.
  DateTime? _lastUiUpdate;
  DateTime? _lastCameraMove;
  static const _uiThrottle = Duration(milliseconds: 700);
  static const _cameraThrottle = Duration(milliseconds: 1100);

  @override
  void initState() {
    super.initState();
    _initCarIcon();
    _initGuideIcon();
    _initClientIcon();
    _requestAndStartIdle();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }

  // ─────────────────────────────── GPS ───────────────────────────────────────

  /// Request permissions and start idle location stream (no broadcast).
  Future<void> _requestAndStartIdle() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      // Permission will be requested by LocationPermissionService.
      // We will just not start the idle stream until next time.
      return;
    }
    _startContinuousLocation(null);
  }

  void _startContinuousLocation(ActiveTrip? trip, {bool isDriver = true}) {
    final tripId = trip?.id;
    if (_locationSub != null && _listeningTripId == tripId) return;

    _locationSub?.cancel();
    _listeningTripId = tripId;

    // В режиме поездки показываем уведомление с включённым wake-lock.
    // В режиме ожидания — без wake-lock (батарея важнее).
    final locationSettings = tripId != null
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 5,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Explora Partners — Маршрут активен',
              notificationText: 'Ваше местоположение передаётся участникам поездки',
              enableWakeLock: true,
              notificationIcon: AndroidResource(
                name: 'launcher_icon',
                defType: 'mipmap',
              ),
            ),
          )
        : AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 5,
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

    _locationSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (pos) {
        if (!mounted) return;

        // 1. Данные обновляем всегда (дёшево, без перерисовки).
        _myPosition = pos;
        _currentSpeedKmh = pos.speed < 0 ? 0.0 : pos.speed * 3.6;

        // 2. Передача координат участникам — со своим троттлингом.
        if (tripId != null) {
          _checkAndBroadcast(tripId, pos, isDriver: isDriver);
        }

        final now = DateTime.now();

        // 3. Перерисовка UI (маркер, спидометр) — не чаще _uiThrottle.
        if (_lastUiUpdate == null ||
            now.difference(_lastUiUpdate!) >= _uiThrottle) {
          _lastUiUpdate = now;
          if (tripId != null && trip != null) {
            _calculateNextTurn(pos.latitude, pos.longitude, trip);
          }
          setState(() {});
        }

        // 4. Разовое центрирование при первом фиксе в режиме ожидания.
        if (tripId == null && !_hasCenteredOnStart && _mapController != null) {
          _hasCenteredOnStart = true;
          _lastCameraMove = now;
          _mapController!.moveCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target:
                    Point(latitude: pos.latitude, longitude: pos.longitude),
                zoom: 15,
              ),
            ),
            animation: const MapAnimation(
                type: MapAnimationType.smooth, duration: 1.5),
          );
        }

        // 5. Следование камеры в активной поездке — не чаще _cameraThrottle,
        //    чтобы анимации не накладывались и карта не «залипала».
        if (tripId != null &&
            _mapController != null &&
            (_lastCameraMove == null ||
                now.difference(_lastCameraMove!) >= _cameraThrottle)) {
          _lastCameraMove = now;
          final cameraHeading = _getRouteHeading(trip);
          _mapController!.moveCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target:
                    Point(latitude: pos.latitude, longitude: pos.longitude),
                zoom: 17,
                azimuth: cameraHeading,
                tilt: 50,
              ),
            ),
            animation: const MapAnimation(
                type: MapAnimationType.smooth, duration: 1.0),
          );
        }
      },
      onError: (_) {}, // ignore PermissionDeniedException
      cancelOnError: false,
    );
  }

  void _checkAndBroadcast(String tripId, Position pos, {bool isDriver = true}) {
    final now = DateTime.now();
    bool shouldBroadcast = false;

    if (_lastBroadcastPosition == null || _lastBroadcastTime == null) {
      shouldBroadcast = true;
    } else {
      final dist = _dist(
          _lastBroadcastPosition!.latitude,
          _lastBroadcastPosition!.longitude,
          pos.latitude,
          pos.longitude);
      final timeDiff = now.difference(_lastBroadcastTime!).inSeconds;

      // Throttle broadcast to every 10 meters or 15 seconds
      if (dist >= 10 || timeDiff >= 15) {
        shouldBroadcast = true;
      }
    }

    if (shouldBroadcast) {
      _lastBroadcastPosition = pos;
      _lastBroadcastTime = now;
      if (isDriver) {
        FirestoreRepository.instance.updateDriverLocation(
          tripId,
          pos.latitude,
          pos.longitude,
        );
      } else {
        FirestoreRepository.instance.updateGuideLocation(
          tripId,
          pos.latitude,
          pos.longitude,
        );
      }
    }
  }

  void _stopContinuousLocation() {
    _locationSub?.cancel();
    _locationSub = null;
    _listeningTripId = null;
    _myPosition = null;
  }

  // ──────────────────────────────── Geometry ─────────────────────────────────

  double _dist(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * 3.141592653589793 / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.asin(math.sqrt(a < 1 ? a : 1));
  }

  int _closestIdx(List<(double, double)> geo) {
    if (_myPosition == null || geo.isEmpty) return 0;
    int best = 0;
    double bestD = double.infinity;
    for (int i = 0; i < geo.length; i++) {
      final d = _dist(
          _myPosition!.latitude, _myPosition!.longitude, geo[i].$1, geo[i].$2);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  double _calculateBearing(double lat1, double lng1, double lat2, double lng2) {
    final dLon = (lng2 - lng1) * math.pi / 180.0;
    final y = math.sin(dLon) * math.cos(lat2 * math.pi / 180.0);
    final x = math.cos(lat1 * math.pi / 180.0) * math.sin(lat2 * math.pi / 180.0) -
        math.sin(lat1 * math.pi / 180.0) * math.cos(lat2 * math.pi / 180.0) * math.cos(dLon);
    var brng = math.atan2(y, x);
    brng = brng * 180.0 / math.pi;
    return (brng + 360.0) % 360.0;
  }

  double _getRouteHeading(ActiveTrip? trip) {
    if (_myPosition == null) return 0.0;
    if (trip == null || trip.routeGeometry.isEmpty || trip.status != TripStatus.inProgress) {
      return _myPosition!.heading;
    }
    
    final geo = trip.routeGeometry;
    final closest = _closestIdx(geo);
    
    // Look ahead a few points to find the direction of the route for a smoother heading
    int nextIdx = closest + 1;
    if (nextIdx < geo.length) {
      // If points are very close, look slightly further ahead (e.g., up to 3 points) to avoid jitter
      int lookAhead = nextIdx;
      while (lookAhead < geo.length && lookAhead < closest + 3) {
        if (_dist(_myPosition!.latitude, _myPosition!.longitude, geo[lookAhead].$1, geo[lookAhead].$2) > 5.0) {
          nextIdx = lookAhead;
          break;
        }
        lookAhead++;
      }
      
      final nextPoint = geo[nextIdx];
      return _calculateBearing(
        _myPosition!.latitude, 
        _myPosition!.longitude, 
        nextPoint.$1, 
        nextPoint.$2
      );
    }
    return _myPosition!.heading;
  }

  void _calculateNextTurn(double currentLat, double currentLng, ActiveTrip trip) {
    if (trip.routeGeometry.isEmpty || trip.status != TripStatus.inProgress) {
      if (_nextTurn != null && mounted) setState(() => _nextTurn = null);
      return;
    }

    final route = trip.routeGeometry;
    int closestIdx = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < route.length; i++) {
      final dist = _dist(currentLat, currentLng, route[i].$1, route[i].$2);
      if (dist < minDistance) {
        minDistance = dist;
        closestIdx = i;
      }
    }

    TurnInstruction? newInstruction;
    for (int i = closestIdx + 1; i < route.length - 1; i++) {
        final p1 = route[i - 1];
        final p2 = route[i];
        final p3 = route[i + 1];

        final bearing1 = _calculateBearing(p1.$1, p1.$2, p2.$1, p2.$2);
        final bearing2 = _calculateBearing(p2.$1, p2.$2, p3.$1, p3.$2);
        var angle = bearing2 - bearing1;
        if (angle > 180) angle -= 360;
        if (angle < -180) angle += 360;

        if (angle.abs() > 25.0) {
            final distToTurn = _dist(currentLat, currentLng, p2.$1, p2.$2);
            TurnDirection dir = TurnDirection.straight;
            if (angle > 70) { dir = TurnDirection.right; }
            else if (angle < -70) { dir = TurnDirection.left; }
            else if (angle > 25) { dir = TurnDirection.slightRight; }
            else if (angle < -25) { dir = TurnDirection.slightLeft; }

            newInstruction = TurnInstruction(dir, distToTurn);
            break;
        }
    }

    if (newInstruction == null) {
        final dest = route.last;
        final d = _dist(currentLat, currentLng, dest.$1, dest.$2);
        newInstruction = TurnInstruction(TurnDirection.destination, d);
    }

    if (mounted) setState(() => _nextTurn = newInstruction);
  }

  // ──────────────────────────────── Actions ──────────────────────────────────

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? CupertinoColors.systemRed : const Color(0xFF6FBF4F),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ──────────────────────────────── Map objects ──────────────────────────────

  Future<void> _initCarIcon() async {
    final data = await UserMarkerPainter.driver();
    if (data != null && mounted) setState(() => _carIconBytes = data);
  }

  Future<void> _initGuideIcon() async {
    final data = await UserMarkerPainter.guide();
    if (data != null && mounted) setState(() => _guideIconBytes = data);
  }

  Future<void> _initClientIcon() async {
    final data = await UserMarkerPainter.client();
    if (data != null && mounted) setState(() => _clientIconBytes = data);
  }


  /// Car arrow marker drawn with Canvas — rotated to heading.
  PlacemarkMapObject? _buildCarMarker(ActiveTrip? trip) {
    if (_carIconBytes == null || _myPosition == null) return null;
    final heading = _getRouteHeading(trip);
    return PlacemarkMapObject(
      mapId: const MapObjectId('my_pos'),
      zIndex: 105,
      point: Point(
        latitude: _myPosition!.latitude,
        longitude: _myPosition!.longitude,
      ),
      direction: heading,
      icon: PlacemarkIcon.single(
        PlacemarkIconStyle(
          image: BitmapDescriptor.fromBytes(_carIconBytes!),
          scale: 1.0, // Standard size badge
          rotationType: RotationType.rotate,
        ),
      ),
    );
  }

  List<MapObject> _buildMapObjects(ActiveTrip trip, bool isDriver) {
    final objects = <MapObject>[];
    final geo = trip.routeGeometry;

    // Only show the route polyline if the trip has actually been accepted ('waiting' or 'in_progress' or 'completed')
    if (geo.isNotEmpty && trip.status != TripStatus.scheduled) {
      final closestIdx =
          trip.status == TripStatus.inProgress ? _closestIdx(geo) : 0;

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

    for (var i = 0; i < trip.waypoints.length; i++) {
      final wp = trip.waypoints[i];
      // Only draw waypoints if trip is not completed and the point hasn't been passed (or we are in active trip)
      // Actually, Yandex maps allows simple CircleMapObject for waypoints to be less obtrusive
      objects.add(
        CircleMapObject(
          mapId: MapObjectId('wp_$i'),
          circle: Circle(
            center: Point(latitude: wp.latitude, longitude: wp.longitude),
            radius: 8, // small 8-meter dot
          ),
          fillColor: CupertinoColors.systemGrey,
          strokeColor: Colors.white,
          strokeWidth: 2,
          zIndex: 50, // Keep below user markers
        ),
      );
    }

    // ── Participant Markers ──────────────────────────────────────────
    
    // 1. Client
    if (trip.clientLocation != null && _clientIconBytes != null) {
      objects.add(
        PlacemarkMapObject(
          mapId: const MapObjectId('client_pos'),
          zIndex: 110,
          point: Point(latitude: trip.clientLocation!.$1, longitude: trip.clientLocation!.$2),
          icon: PlacemarkIcon.single(
            PlacemarkIconStyle(
              image: BitmapDescriptor.fromBytes(_clientIconBytes!),
              scale: 1.2, // Larger Yandex-style badge
            ),
          ),
        ),
      );
    }

    // 2. Driver
    if (isDriver) {
      // Current user is driver → show "Me" (blue car)
      if (_myPosition != null) {
        final marker = _buildCarMarker(trip);
        if (marker != null) objects.add(marker);
      }
    } else {
      // Current user is NOT driver → show driver from Firestore
      if (trip.driverLocation != null && _carIconBytes != null) {
        objects.add(
          PlacemarkMapObject(
            mapId: const MapObjectId('driver_pos'),
            zIndex: 105,
            point: Point(latitude: trip.driverLocation!.$1, longitude: trip.driverLocation!.$2),
            icon: PlacemarkIcon.single(
              PlacemarkIconStyle(
                image: BitmapDescriptor.fromBytes(_carIconBytes!),
                scale: 1.0,
              ),
            ),
          ),
        );
      }
    }

    // 3. Guide
    if (!isDriver) {
      // Current user is guide → show "Me" (using guide icon)
      if (_myPosition != null && _guideIconBytes != null) {
        objects.add(
          PlacemarkMapObject(
            mapId: const MapObjectId('my_pos_guide'),
            zIndex: 105,
            point: Point(latitude: _myPosition!.latitude, longitude: _myPosition!.longitude),
            icon: PlacemarkIcon.single(
              PlacemarkIconStyle(
                image: BitmapDescriptor.fromBytes(_guideIconBytes!),
                scale: 1.2,
              ),
            ),
          ),
        );
      }
    } else {
      // Current user is driver → show guide from Firestore
      if (trip.guideLocation != null && _guideIconBytes != null) {
        objects.add(
          PlacemarkMapObject(
            mapId: const MapObjectId('guide_pos'),
            zIndex: 100,
            point: Point(latitude: trip.guideLocation!.$1, longitude: trip.guideLocation!.$2),
            icon: PlacemarkIcon.single(
              PlacemarkIconStyle(
                image: BitmapDescriptor.fromBytes(_guideIconBytes!),
                scale: 1.2,
              ),
            ),
          ),
        );
      }
    }

    return objects;
  }

  List<MapObject> _buildIdleMapObjects() {
    final marker = _buildCarMarker(null);
    if (marker == null) return [];
    return [marker];
  }

  // ──────────────────────────── Route fit ────────────────────────────────────

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
            CameraPosition(target: points.first, zoom: 14)),
        animation:
            const MapAnimation(type: MapAnimationType.smooth, duration: 1.5),
      );
    } else {
      double minLat = points.map((p) => p.latitude).reduce(math.min);
      double maxLat = points.map((p) => p.latitude).reduce(math.max);
      double minLng = points.map((p) => p.longitude).reduce(math.min);
      double maxLng = points.map((p) => p.longitude).reduce(math.max);

      await _mapController!.moveCamera(
        CameraUpdate.newGeometry(
          Geometry.fromBoundingBox(
            BoundingBox(
              southWest:
                  Point(latitude: minLat - 0.005, longitude: minLng - 0.005),
              northEast:
                  Point(latitude: maxLat + 0.005, longitude: maxLng + 0.005),
            ),
          ),
        ),
        animation:
            const MapAnimation(type: MapAnimationType.smooth, duration: 1.5),
      );
    }
  }

  void _centerOnMe() async {
    if (_mapController == null) return;
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
      locationSettings:
          const LocationSettings(accuracy: LocationAccuracy.high),
    );
    setState(() => _myPosition = pos);
    _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
            target: Point(latitude: pos.latitude, longitude: pos.longitude),
            zoom: 15),
      ),
      animation:
          const MapAnimation(type: MapAnimationType.smooth, duration: 1.0),
    );
    // Ensure idle stream is running
    _startContinuousLocation(null);
  }

  void _zoomIn() => _mapController?.moveCamera(CameraUpdate.zoomIn(),
      animation: const MapAnimation(type: MapAnimationType.linear, duration: 0.1));
  void _zoomOut() => _mapController?.moveCamera(CameraUpdate.zoomOut(),
      animation: const MapAnimation(type: MapAnimationType.linear, duration: 0.1));

  // ──────────────────────────────── Build ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uid = AuthService.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: uid == null
          ? const Center(child: Text('Не авторизован'))
          : StreamBuilder<PartnerProfile?>(
              stream: FirestoreRepository.instance.streamPartner(uid),
              builder: (context, profileSnap) {
                final profile = profileSnap.data;
                final isDriver = profile?.role.isDriver ?? false;

                // Единая подписка на активные поездки для карты и оверлеев
                // (раньше было две — это удваивало слушатели и ребилды).
                return StreamBuilder<List<ActiveTrip>>(
                  stream: FirestoreRepository.instance
                      .streamActiveTripsByPartner(uid),
                  builder: (context, snapshot) {
                    final trips = snapshot.data ?? const <ActiveTrip>[];
                    final trip = trips.isNotEmpty ? trips.first : null;

                    // GPS-логика по статусу поездки (вызывается один раз).
                    if (trip != null) {
                      if (trip.status == TripStatus.inProgress) {
                        _startContinuousLocation(trip, isDriver: isDriver);
                      } else if (trip.status == TripStatus.waiting) {
                        _startContinuousLocation(null, isDriver: isDriver);
                      } else if (_locationSub != null &&
                          trip.status == TripStatus.completed) {
                        _stopContinuousLocation();
                      }
                    }
                    // В режиме ожидания (без поездки) поток уже запущен в initState.

                    return Stack(
                      children: [
                        // ── Map ────────────────────────────────────────
                        Positioned.fill(
                          child: YandexMap(
                            mode2DEnabled: !isDriver,
                            nightModeEnabled: isDark,
                            mapObjects: trip != null
                                ? _buildMapObjects(trip, isDriver)
                                : _buildIdleMapObjects(),
                            onMapCreated: (controller) {
                              _mapController = controller;
                              if (trip != null) {
                                _fitRoute(trip);
                              }
                              if (trip == null &&
                                  _myPosition != null &&
                                  !_hasCenteredOnStart) {
                                _hasCenteredOnStart = true;
                                controller.moveCamera(
                                  CameraUpdate.newCameraPosition(
                                    CameraPosition(
                                      target: Point(
                                        latitude: _myPosition!.latitude,
                                        longitude: _myPosition!.longitude,
                                      ),
                                      zoom: 15,
                                    ),
                                  ),
                                  animation: const MapAnimation(
                                      type: MapAnimationType.smooth,
                                      duration: 1.5),
                                );
                              }
                            },
                          ),
                        ),

                        // ── State-aware Overlays ────────────────────────
                        if (trip == null)
                          _IdleOverlay(
                            onCenter: _centerOnMe,
                            onZoomIn: _zoomIn,
                            onZoomOut: _zoomOut,
                          )
                        else
                          _NavigatorOverlay(
                            trip: trip,
                            speedKmh: _currentSpeedKmh,
                            nextTurn: _nextTurn,
                            onCenter: _centerOnMe,
                            onZoomIn: _zoomIn,
                            onZoomOut: _zoomOut,
                          ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}

// ===========================================================================
// Yandex Pro Style Components
// ===========================================================================


// Idle overlay — no search, no bolt, only zoom + center
class _IdleOverlay extends StatelessWidget {
  final VoidCallback onCenter;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _IdleOverlay({
    required this.onCenter,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Right Controls: zoom + center
        Positioned(
          right: 16,
          bottom: 180,
          child: Column(
            children: [
              _FloatingActionButton(
                  icon: CupertinoIcons.add, onTap: onZoomIn),
              const SizedBox(height: 8),
              _FloatingActionButton(
                  icon: CupertinoIcons.minus, onTap: onZoomOut),
              const SizedBox(height: 16),
              _FloatingActionButton(
                icon: CupertinoIcons.location_fill,
                iconColor: AppColors.accent,
                onTap: onCenter,
              ),
            ],
          ),
        ),

        // Bottom handle
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 24,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavigatorOverlay extends StatelessWidget {
  final ActiveTrip trip;
  final VoidCallback onCenter;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final double speedKmh;
  final TurnInstruction? nextTurn;

  const _NavigatorOverlay({
    required this.trip,
    required this.onCenter,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.speedKmh,
    this.nextTurn,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Navigation Turn Guide & Speedometer (Only in progress)
        if (trip.status == TripStatus.inProgress)
          NavigationOverlay(
            speedKmh: speedKmh,
            nextTurn: nextTurn,
          ),

        // ── Нижняя панель waypoints ───────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _WaypointsPanel(trip: trip),
        ),

        // Right Controls
        Positioned(
          right: 16,
          bottom: 220,
          child: Column(
            children: [
              _FloatingActionButton(
                  icon: CupertinoIcons.add, onTap: onZoomIn),
              const SizedBox(height: 8),
              _FloatingActionButton(
                  icon: CupertinoIcons.minus, onTap: onZoomOut),
              const SizedBox(height: 16),
              _FloatingActionButton(
                icon: CupertinoIcons.chat_bubble_text_fill,
                onTap: () => MainTabScaffold.goToTab(2),
              ),
              const SizedBox(height: 12),
              _FloatingActionButton(
                icon: CupertinoIcons.location_fill,
                iconColor: AppColors.accent,
                onTap: onCenter,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FloatingActionButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final VoidCallback onTap;

  const _FloatingActionButton({
    required this.icon,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Icon(
          icon,
          color: iconColor ?? AppColors.textPrimary,
          size: 24,
        ),
      ),
    );
  }
}

// ===========================================================================
// Draggable waypoints bottom panel
// ===========================================================================

/// Нижняя драгаемая панель со списком точек маршрута (как на дизайн-префабе).
class _WaypointsPanel extends StatefulWidget {
  final ActiveTrip trip;
  const _WaypointsPanel({required this.trip});

  @override
  State<_WaypointsPanel> createState() => _WaypointsPanelState();
}

class _WaypointsPanelState extends State<_WaypointsPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final waypoints = trip.waypoints;
    final done = trip.currentWaypointIndex.clamp(0, waypoints.length);
    final inProgress = trip.status == TripStatus.inProgress;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    // Заголовок маршрута — возьмём из customName / последней точки / заготовка
    final routeTitle = trip.customName?.isNotEmpty == true
        ? trip.customName!
        : waypoints.isNotEmpty
            ? waypoints.last.address
            : 'Текущая экспедиция';

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        constraints: BoxConstraints(
          maxHeight: _expanded ? 340 : 90,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle + заголовок ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              routeTitle,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              waypoints.isEmpty
                                  ? 'Точки маршрута не определены'
                                  : '$done / ${waypoints.length} точек',
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: inProgress
                              ? AppColors.accent.withValues(alpha: 0.15)
                              : AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: inProgress
                                ? AppColors.accent.withValues(alpha: 0.5)
                                : AppColors.border,
                          ),
                        ),
                        child: Text(
                          inProgress ? 'В пути' : 'Ожидание',
                          style: TextStyle(
                            color: inProgress
                                ? AppColors.accentBright
                                : AppColors.textTertiary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Список waypoints (only when expanded) ──
            if (_expanded && waypoints.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 16),
                  itemCount: waypoints.length,
                  itemBuilder: (_, i) {
                    final wp = waypoints[i];
                    final isPast = i < done;
                    final isCurrent = i == done;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          // Иконка статуса
                          SizedBox(
                            width: 28,
                            child: isPast
                                ? const Icon(
                                    CupertinoIcons.checkmark_circle_fill,
                                    color: AppColors.accent,
                                    size: 20,
                                  )
                                : isCurrent
                                    ? Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          color: AppColors.warning,
                                          shape: BoxShape.circle,
                                        ),
                                      )
                                    : Container(
                                        width: 14,
                                        height: 14,
                                        margin: const EdgeInsets.only(left: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppColors.border,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              wp.address.isEmpty
                                  ? 'Точка ${i + 1}'
                                  : wp.address,
                              style: TextStyle(
                                color: isCurrent
                                    ? AppColors.textPrimary
                                    : isPast
                                        ? AppColors.textTertiary
                                        : AppColors.textSecondary,
                                fontSize: 14,
                                fontWeight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              )
            else if (_expanded)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Точки маршрута появятся после подтверждения маршрута',
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                  ),
                ),
              )
            else
              SizedBox(height: bottomPad),
          ],
        ),
      ),
    );
  }
}
