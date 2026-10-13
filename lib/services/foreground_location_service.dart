import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

class LocationTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _positionStream;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[LocationTaskHandler] Foreground service started');
    // We can't access usual Firebase plugins unless we initialize Firebase again in this isolate
    // But geolocator can work independently. We will track location and optionally sync to Firebase.
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[LocationTaskHandler] Firebase already initialized or failed: $e');
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      debugPrint('[LocationTaskHandler] Location updated: ${position.latitude}, ${position.longitude}');
      FlutterForegroundTask.updateService(
        notificationTitle: 'Маршрут активен',
        notificationText: 'Текущая скорость: ${(position.speed * 3.6).toStringAsFixed(1)} км/ч',
      );
      
      // We can send location updates back to main isolate
      FlutterForegroundTask.sendDataToMain({
        'lat': position.latitude,
        'lng': position.longitude,
        'speed': position.speed,
        'timestamp': position.timestamp.millisecondsSinceEpoch,
      });
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Called periodically based on interval, not used for location stream
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isForceDestroy) async {
    debugPrint('[LocationTaskHandler] Foreground service stopped');
    await _positionStream?.cancel();
  }
}

class ForegroundLocationService {
  ForegroundLocationService._();
  static final ForegroundLocationService instance = ForegroundLocationService._();

  Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'location_tracking',
        channelName: 'Location Tracking',
        channelDescription: 'Уведомление для отслеживания маршрута в фоне',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.DEFAULT,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> startTracking() async {
    if (await FlutterForegroundTask.isRunningService) return;

    final hasPermissions = await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    if (hasPermissions) {
      await FlutterForegroundTask.startService(
        notificationTitle: 'Маршрут активен',
        notificationText: 'Ваша геопозиция передается пассажирам',
        callback: startCallback,
      );
    }
  }

  Future<void> stopTracking() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
