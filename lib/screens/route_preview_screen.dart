import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';

import '../models/booking_models.dart';
import '../repository/firestore_repository.dart';
import '../services/yandex_directions_service.dart';
import '../utils/route_waypoint.dart';
import '../utils/user_marker_painter.dart';

class RoutePreviewScreen extends StatefulWidget {
  final ActiveTrip trip;
  final Booking booking;

  const RoutePreviewScreen({
    super.key,
    required this.trip,
    required this.booking,
  });

  @override
  State<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends State<RoutePreviewScreen> {
  YandexMapController? _mapController;
  bool _isAccepting = false;
  bool _isLoadingRoute = true;

  /// Dynamic road-snapped route points from Yandex Directions API
  List<Point> _dynamicPoints = [];

  /// Driver's current device position for the marker
  (double, double)? _myLocation;

  /// Rendered driver marker bytes
  Uint8List? _markerBytes;

  @override
  void initState() {
    super.initState();
    _renderMarker();
    _loadCurrentPosition();
    _fetchDynamicRoute();
  }

  Future<void> _renderMarker() async {
    final bytes = await UserMarkerPainter.driver();
    if (mounted && bytes != null) {
      setState(() => _markerBytes = bytes);
    }
  }

  Future<void> _loadCurrentPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() => _myLocation = (pos.latitude, pos.longitude));
      }
    } catch (_) {}
  }

  Future<void> _fetchDynamicRoute() async {
    final waypoints = widget.trip.waypoints;
    if (waypoints.length < 2) {
      if (mounted) setState(() => _isLoadingRoute = false);
      return;
    }
    try {
      final routeWaypoints = waypoints.map((wp) => RouteWaypoint(
        latitude: wp.latitude,
        longitude: wp.longitude,
        name: wp.address,
        color: const Color(0xFF6FBF4F),
      )).toList();
      final result = await YandexDirectionsService.getRoute(routeWaypoints);
      if (mounted) {
        // Convert segments: each segment list of Points -> list of RouteWaypoint-like Points
        setState(() {
          _dynamicPoints = result.points;
          _isLoadingRoute = false;
        });
        _fitRoute();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  void _onMapCreated(YandexMapController controller) {
    _mapController = controller;
    if (!_isLoadingRoute) _fitRoute();
  }

  void _fitRoute() {
    if (_mapController == null) return;
    final waypoints = widget.trip.waypoints;
    if (waypoints.isEmpty) return;

    double minLat = waypoints.first.latitude;
    double maxLat = waypoints.first.latitude;
    double minLng = waypoints.first.longitude;
    double maxLng = waypoints.first.longitude;

    for (var wp in waypoints) {
      if (wp.latitude < minLat) minLat = wp.latitude;
      if (wp.latitude > maxLat) maxLat = wp.latitude;
      if (wp.longitude < minLng) minLng = wp.longitude;
      if (wp.longitude > maxLng) maxLng = wp.longitude;
    }

    // Also expand to include driver location if available
    if (_myLocation != null) {
      final (lat, lng) = _myLocation!;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    _mapController!.moveCamera(
      CameraUpdate.newGeometry(
        Geometry.fromBoundingBox(
          BoundingBox(
            southWest: Point(latitude: minLat - 0.005, longitude: minLng - 0.005),
            northEast: Point(latitude: maxLat + 0.005, longitude: maxLng + 0.005),
          ),
        ),
      ),
      animation: const MapAnimation(type: MapAnimationType.smooth, duration: 1.0),
    );
  }

  Future<void> _acceptTrip() async {
    setState(() => _isAccepting = true);
    try {
      await FirestoreRepository.instance.acceptTrip(widget.trip.id, widget.booking.id);
      if (mounted) {
        context.pop(); // Go back to WorkScreen
      }
    } catch (e) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Ошибка'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  List<MapObject> _buildMapObjects() {
    final objects = <MapObject>[];

    // 1. Dynamic road-snapped polyline
    if (_dynamicPoints.length >= 2) {
      objects.add(
        PolylineMapObject(
          mapId: const MapObjectId('dynamic_route'),
          polyline: Polyline(points: _dynamicPoints),
          strokeColor: const Color(0xFF6FBF4F),
          strokeWidth: 5,
          outlineColor: Colors.white,
          outlineWidth: 1.5,
          zIndex: 10,
        ),
      );
    }

    // Fallback: straight lines between waypoints if no dynamic route
    if (_dynamicPoints.isEmpty && !_isLoadingRoute && widget.trip.waypoints.length >= 2) {
      objects.add(
        PolylineMapObject(
          mapId: const MapObjectId('fallback_route'),
          polyline: Polyline(
            points: widget.trip.waypoints
                .map((wp) => Point(latitude: wp.latitude, longitude: wp.longitude))
                .toList(),
          ),
          strokeColor: const Color(0xFF6FBF4F).withValues(alpha: 0.6),
          strokeWidth: 4,
          dashLength: 8,
          gapLength: 4,
          zIndex: 10,
        ),
      );
    }

    // 2. Waypoint circles
    for (var i = 0; i < widget.trip.waypoints.length; i++) {
      final wp = widget.trip.waypoints[i];
      objects.add(
        CircleMapObject(
          mapId: MapObjectId('wp_$i'),
          circle: Circle(
            center: Point(latitude: wp.latitude, longitude: wp.longitude),
            radius: 10,
          ),
          fillColor: i == 0
              ? CupertinoColors.systemGreen
              : i == widget.trip.waypoints.length - 1
                  ? CupertinoColors.systemRed
                  : CupertinoColors.systemBlue,
          strokeColor: Colors.white,
          strokeWidth: 2.5,
          zIndex: 50,
        ),
      );
    }

    // 3. Driver (partner) marker
    if (_myLocation != null && _markerBytes != null) {
      final (lat, lng) = _myLocation!;
      objects.add(
        PlacemarkMapObject(
          mapId: const MapObjectId('driver_marker'),
          point: Point(latitude: lat, longitude: lng),
          icon: PlacemarkIcon.single(
            PlacemarkIconStyle(
              image: BitmapDescriptor.fromBytes(_markerBytes!),
              scale: 1.2,
              zIndex: 100,
            ),
          ),
        ),
      );
    }

    return objects;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Map
          YandexMap(
            mode2DEnabled: true,
            nightModeEnabled: isDark,
            logoAlignment: const MapAlignment(
              horizontal: HorizontalAlignment.left,
              vertical: VerticalAlignment.top,
            ),
            mapObjects: _buildMapObjects(),
            onMapCreated: _onMapCreated,
          ),

          // Loading indicator for dynamic route
          if (_isLoadingRoute)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoActivityIndicator(),
                      SizedBox(width: 10),
                      Text('Строим маршрут…', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),

          // 2. Back Button (Top Left)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  CupertinoIcons.back,
                  color: isDark ? Colors.white : Colors.black,
                  size: 24,
                ),
              ),
            ),
          ),

          // 3. Bottom actions panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).padding.bottom + 24,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.booking.routeTitle.isNotEmpty
                        ? widget.booking.routeTitle
                        : (widget.trip.customName != null && widget.trip.customName!.isNotEmpty
                            ? widget.trip.customName!
                            : 'Новый маршрут'),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(LucideIcons.users, color: CupertinoColors.systemGrey, size: 18),
                      const SizedBox(width: 8),
                      Text('Группа: ${widget.booking.participants} туристов', style: const TextStyle(fontSize: 15, color: CupertinoColors.systemGrey)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(LucideIcons.calendar, color: CupertinoColors.systemGrey, size: 18),
                      const SizedBox(width: 8),
                      Text('Дата: ${widget.booking.startDate.split('T').first}', style: const TextStyle(fontSize: 15, color: CupertinoColors.systemGrey)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(LucideIcons.mapPin, color: CupertinoColors.systemGrey, size: 18),
                      const SizedBox(width: 8),
                      Text('${widget.trip.waypoints.length} точек маршрута', style: const TextStyle(fontSize: 15, color: CupertinoColors.systemGrey)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Вы получите',
                            style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.booking.totalPrice.toStringAsFixed(0)} ₸',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Точек',
                            style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.trip.waypoints.length}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          color: isDark ? CupertinoColors.darkBackgroundGray : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(16),
                          onPressed: () => context.pop(),
                          child: Text(
                            'Отклонить',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          color: Theme.of(context).primaryColor,
                          borderRadius: BorderRadius.circular(16),
                          onPressed: _isAccepting ? null : _acceptTrip,
                          child: _isAccepting
                              ? const CupertinoActivityIndicator(color: Colors.white)
                              : const Text(
                                  'Принять заказ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
