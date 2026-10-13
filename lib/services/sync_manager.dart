import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/offline_action.dart';
import '../repository/firestore_repository.dart';

class SyncManager {
  SyncManager._();
  static final SyncManager instance = SyncManager._();

  static const String _boxName = 'offline_actions_box';
  late Box _box;
  StreamSubscription? _connectivitySub;
  bool _isSyncing = false;
  // Set when enqueueAction() arrives while a sync is already in flight, so
  // that action isn't stranded waiting for the next real connectivity
  // change — we just run another pass right after the current one finishes.
  bool _rerunRequested = false;

  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);

    // Listen to network changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = !results.contains(ConnectivityResult.none);
      if (hasConnection) {
        _syncPendingActions();
      }
    });

    // Initial sync attempt
    _syncPendingActions();
  }

  Future<void> enqueueAction(OfflineAction action) async {
    debugPrint('[SyncManager] Enqueuing action: ${action.type}');
    await _box.put(action.id, action.toMap());
    
    // Try to sync immediately
    _syncPendingActions();
  }

  Future<void> _syncPendingActions() async {
    if (_isSyncing) {
      // A new action arrived (or connectivity changed) while a pass was
      // already running — don't drop it, just ask for another pass once
      // this one is done.
      _rerunRequested = true;
      return;
    }
    final results = await Connectivity().checkConnectivity();
    if (results.contains(ConnectivityResult.none)) return;

    if (_box.isEmpty) return;

    _isSyncing = true;
    try {
      final keys = _box.keys.toList();
      for (final key in keys) {
        final raw = _box.get(key);
        if (raw == null) continue;

        // Each item is isolated: a single malformed/unparseable entry must
        // not abort the whole pass and block every action queued behind it.
        try {
          final action = OfflineAction.fromMap(raw as Map);
          final success = await _processAction(action);
          if (success) {
            await _box.delete(key);
            debugPrint('[SyncManager] Successfully synced action: ${action.id}');
          }
        } catch (e) {
          debugPrint('[SyncManager] Dropping unparseable queued action ($key): $e');
          await _box.delete(key);
        }
      }
    } catch (e) {
      debugPrint('[SyncManager] Sync failed: $e');
    } finally {
      _isSyncing = false;
      if (_rerunRequested) {
        _rerunRequested = false;
        unawaited(_syncPendingActions());
      }
    }
  }

  Future<bool> _processAction(OfflineAction action) async {
    try {
      switch (action.type) {
        case 'startTrip':
          await FirestoreRepository.instance.startTrip(
            action.payload['tripId'],
            action.payload['bookingId'],
          );
          return true;
        case 'finishTrip':
          await FirestoreRepository.instance.requestTripCompletion(
            action.payload['tripId'],
            isDriver: action.payload['isDriver'],
          );
          return true;
        case 'checkInAtWaypoint':
          await FirestoreRepository.instance.checkInAtWaypoint(
            action.payload['tripId'],
            action.payload['idx'],
            action.payload['role'],
          );
          return true;
        case 'setPartnerReady':
          await FirestoreRepository.instance.setPartnerReady(
            action.payload['tripId'],
            isDriver: action.payload['isDriver'],
          );
          return true;
        case 'updateDriverLocation':
          await FirestoreRepository.instance.updateDriverLocation(
            action.payload['tripId'],
            action.payload['lat'],
            action.payload['lng'],
          );
          return true;
        case 'updateGuideLocation':
          await FirestoreRepository.instance.updateGuideLocation(
            action.payload['tripId'],
            action.payload['lat'],
            action.payload['lng'],
          );
          return true;
        default:
          debugPrint('[SyncManager] Unknown action type: ${action.type}');
          return true; // Return true to delete it from queue to avoid infinite loop
      }
    } catch (e) {
      debugPrint('[SyncManager] Error processing action ${action.id}: $e');
      return false; // Will retry later
    }
  }

  void dispose() {
    _connectivitySub?.cancel();
  }
}
