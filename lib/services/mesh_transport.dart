import 'dart:async';
import 'dart:convert';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:bridgefy/bridgefy.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:crypto/crypto.dart';

import '../models/offline_models.dart';

/// Bridgefy BLE transport for the MESH offline module.
///
/// Design:
/// - Singleton with explicit [reset] for session reuse.
/// - [start] awaits the async [bridgefyDidStart] callback via Completer.
/// - [broadcast] only fires when SDK is truly started.
class MeshTransport with BridgefyDelegate {
  MeshTransport._();
  static final MeshTransport instance = MeshTransport._();

  final _bridgefy = Bridgefy();

  final _msgCtrl     = StreamController<OfflineMessage>.broadcast();
  final _errorCtrl   = StreamController<String?>.broadcast();
  final _peerConnCtrl = StreamController<String>.broadcast();

  bool _started = false;
  String _roomId = '';
  String _userId = '';

  // Message dedup — BLE mesh retransmits packets via multiple paths
  final Set<String> _seenIds = {};
  static const _maxSeenIds = 200;

  // Completer resolves once bridgefyDidStart fires (or fails).
  Completer<bool>? _startCompleter;

  bool get isStarted => _started;

  Stream<OfflineMessage> get incomingMessages => _msgCtrl.stream;
  Stream<String?>        get btError          => _errorCtrl.stream;
  /// Fires with peerUserId each time a BLE peer connects.
  Stream<String>         get peerConnected    => _peerConnCtrl.stream;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Resets state so the transport can be cleanly restarted.
  void reset() {
    _started = false;
    _roomId = '';
    _userId = '';
    _startCompleter = null;
  }

  Future<bool> start({
    required String roomId,
    required String userId,
    required String userName,
    required String apiKey,
  }) async {
    if (_started) return true;

    _roomId = roomId;
    _userId = userId;

    final ok = await _requestPermissions();
    if (!ok) {
      const err = 'Bluetooth: необходимо разрешение';
      debugPrint('[MeshTransport] $err');
      _errorCtrl.add(err);
      return false;
    }

    try {
      final masked = '${apiKey.substring(0, 4)}...${apiKey.substring(apiKey.length - 4)}';
      debugPrint('[MeshTransport] Инициализация (key: $masked)');
      await _bridgefy.initialize(
        apiKey: apiKey,
        delegate: this,
        verboseLogging: false,
      );
    } catch (e) {
      final errStr = e.toString();
      // Bridgefy clears old session when key changes — retry once after cleanup
      if (errStr.contains('sessionError') || errStr.contains('not equal to the previous session')) {
        debugPrint('[MeshTransport] ⚠️ Смена ключа, повтор инициализации...');
        await Future.delayed(const Duration(milliseconds: 800));
        try {
          await _bridgefy.initialize(
            apiKey: apiKey,
            delegate: this,
            verboseLogging: false,
          );
        } catch (e2, stack2) {
          debugPrint('[MeshTransport] initialize retry error: $e2');
          FirebaseCrashlytics.instance.recordError(e2, stack2, reason: 'PartnerMeshTransport.initialize retry', fatal: false);
          _errorCtrl.add('mesh: init failed - $e2');
          return false;
        }
      } else {
        debugPrint('[MeshTransport] initialize error: $e');
        FirebaseCrashlytics.instance.recordError(e, StackTrace.current, reason: 'PartnerMeshTransport.initialize', fatal: false);
        _errorCtrl.add('mesh: init failed - $e');
        return false;
      }
    }

    _startCompleter = Completer<bool>();
    try {
      final uuid = _toUUID(userId);
      debugPrint('[MeshTransport] запуск UUID: $uuid (origin: $userId)');
      await _bridgefy.start(
        userId: uuid,
        propagationProfile: BridgefyPropagationProfile.standard,
      );
    } catch (e) {
      final errStr = e.toString();
      // После hot restart нативный Bridgefy ещё запущен — это успех
      if (errStr.toLowerCase().contains('already started')) {
        debugPrint('[MeshTransport] ✅ Bridgefy уже запущен (hot restart) — считаем успехом');
        _started = true;
        if (!(_startCompleter?.isCompleted ?? true)) {
          _startCompleter!.complete(true);
        }
        return true;
      }
      debugPrint('[MeshTransport] start error: $e');
      FirebaseCrashlytics.instance.recordError(e, StackTrace.current, reason: 'PartnerMeshTransport.start', fatal: false);
      _errorCtrl.add('mesh: start failed - $e');
      _startCompleter?.complete(false);
      return false;
    }

    final startedOk = await _startCompleter!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('[MeshTransport] ⏱ старт завершился по таймауту');
        return _started;
      },
    );

    return startedOk;
  }

  Future<void> stop() async {
    if (!_started) return;
    try {
      await _bridgefy.stop();
    } catch (_) {}
  }

  /// Broadcasts JSON payload to all connected mesh peers.
  Future<void> broadcast(Map<String, dynamic> payload) async {
    if (!_started) {
      debugPrint('[MeshTransport] broadcast abort — SDK not started');
      return;
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    try {
      await _bridgefy.send(
        data: bytes,
        transmissionMode: BridgefyTransmissionMode(
          type: BridgefyTransmissionModeType.broadcast,
          uuid: _toUUID(_roomId),
        ),
      );
    } catch (e, stack) {
      debugPrint('[MeshTransport] broadcast error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerMeshTransport.broadcast', fatal: false);
    }
  }

  void dispose() {
    _msgCtrl.close();
    _errorCtrl.close();
  }

  // ── Bridgefy SDK callbacks ────────────────────────────────────────────────

  @override
  void bridgefyDidStart({required String currentUserID}) {
    _started = true;
    _errorCtrl.add(null);
    debugPrint('[MeshTransport] ✅ MESH запущен — пользователь: $currentUserID');
    if (!(_startCompleter?.isCompleted ?? true)) {
      _startCompleter!.complete(true);
    }
  }

  @override
  void bridgefyDidFailToStart({required BridgefyError error}) {
    final msg = error.message ?? 'Неизвестная ошибка запуска';

    // ► "already started" — нативный Bridgefy ещё работает после hot restart.
    if (msg.toLowerCase().contains('already started') ||
        msg.toLowerCase().contains('alreadystarted')) {
      debugPrint('[MeshTransport] ✅ Bridgefy уже запущен (hot restart callback) — считаем успехом');
      _started = true;
      _errorCtrl.add(null);
      if (!(_startCompleter?.isCompleted ?? true)) {
        _startCompleter!.complete(true);
      }
      return;
    }

    _started = false;
    _errorCtrl.add(msg);
    debugPrint('[MeshTransport] ❌ Ошибка запуска: $msg');
    if (!(_startCompleter?.isCompleted ?? true)) {
      _startCompleter!.complete(false);
    }
  }

  @override
  void bridgefyDidStop() {
    _started = false;
    debugPrint('[MeshTransport] остановлен');
  }

  @override
  void bridgefyDidFailToStop({required BridgefyError error}) {
    debugPrint('[MeshTransport] ошибка остановки: ${error.message}');
  }

  @override
  void bridgefyDidDestroySession() {}

  @override
  void bridgefyDidFailToDestroySession() {}

  @override
  void bridgefyDidConnect({required String userID}) {
    debugPrint('[MeshTransport] 🔗 подключен пир: $userID');
    if (!_peerConnCtrl.isClosed) _peerConnCtrl.add(userID);
  }

  @override
  void bridgefyDidDisconnect({required String userID}) {
    debugPrint('[MeshTransport] 🔌 отключен пир: $userID');
  }

  @override
  void bridgefyDidEstablishSecureConnection({required String userID}) {
    debugPrint('[MeshTransport] 🔒 защищённое соединение: $userID');
  }

  @override
  void bridgefyDidFailToEstablishSecureConnection(
      {required String userID, required BridgefyError error}) {
    debugPrint('[MeshTransport] 🔓 ошибка защищённого соединения с $userID: ${error.message}');
  }

  @override
  void bridgefyDidSendMessage({required String messageID}) {}

  @override
  void bridgefyDidFailSendingMessage(
      {required String messageID, BridgefyError? error}) {
    debugPrint('[MeshTransport] 📤 ошибка отправки $messageID: ${error?.message}');
  }

  @override
  void bridgefyDidReceiveData({
    required Uint8List data,
    required String messageId,
    required BridgefyTransmissionMode transmissionMode,
  }) {
    try {
      final raw = utf8.decode(data);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final msgType = json['type'] as String? ?? '';

      // SOS-beacon пропускаем всегда — достигает ВСЕХ пользователей MESH.
      // Остальные типы фильтруются по roomId как прежде.
      final isBeacon = msgType == 'beacon';
      if (!isBeacon) {
        if (json['roomId'] != _roomId) {
          if (json['tripId'] != _roomId) return;
        }
      }

      // Игнорируем эхо собственных сообщений
      if (json['userId'] == _userId) return;

      // Dedup: BLE mesh передаёт пакеты по нескольким маршрутам
      final seenKey = '${json['userId']}_${json['ts']}_${json['type']}_${json['chunkIndex'] ?? 0}';
      if (_seenIds.contains(seenKey)) return;
      _seenIds.add(seenKey);
      if (_seenIds.length > _maxSeenIds) _seenIds.remove(_seenIds.first);

      final ts = json['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch;
      // Для beacon сохраняем оригинальный tripId (от отправителя), для остальных — наш roomId
      final msgTripId = isBeacon
          ? (json['tripId'] as String? ?? '')
          : _roomId;
      final msg = OfflineMessage.fromJson(
        {...json, 'ts': ts, 'tripId': msgTripId},
        currentUserId: _userId,
        overrideId: 'mesh_${messageId}_$ts',
      );
      _msgCtrl.add(msg);
    } catch (e, stack) {
      debugPrint('[MeshTransport] parse error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerMeshTransport.bridgefyDidReceiveData', fatal: false);
    }
  }

  @override
  void bridgefyDidSendDataProgress({
    required String messageID,
    required int position,
    required int of,
  }) {}

  // ── Permissions ───────────────────────────────────────────────────────────

  Future<bool> _requestPermissions() async {
    final results = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ].request();

    // Location should be requested by LocationPermissionService, we just check here.
    // On Android 12+ Bridgefy doesn't strictly need Location, but we check for completeness.
    final locOk     = await Permission.locationWhenInUse.isGranted || await Permission.locationAlways.isGranted;
    final scanOk    = results[Permission.bluetoothScan]?.isGranted    == true;
    final connectOk = results[Permission.bluetoothConnect]?.isGranted == true;
    final legacyOk  = results[Permission.bluetooth]?.isGranted        == true;

    debugPrint('[MeshTransport] perms: loc=$locOk scan=$scanOk connect=$connectOk legacy=$legacyOk');
    return locOk && (scanOk && connectOk || legacyOk);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Deterministic UUID from MD5 hash of input string.
  String _toUUID(String input) {
    if (input.isEmpty) return '00000000-0000-0000-0000-000000000000';
    final bytes = md5.convert(utf8.encode(input)).bytes;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20, 32)}';
  }
}
