import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../models/offline_models.dart';
import 'mesh_transport.dart';
import 'sos_service.dart';

/// MESH offline service for the partner app.
///
/// Partners can send/receive text messages and SOS beacons over BLE mesh.
/// No PTT voice recording (partners use online Firestore chat).
/// Partners always receive client SOS alerts.
class MeshService {
  MeshService._();
  static final MeshService instance = MeshService._();

  final _auth = FirebaseAuth.instance;
  final _bt   = MeshTransport.instance;

  // ── Session state ─────────────────────────────────────────────────────────
  bool _started = false;
  String _roomId  = '';
  String _userId   = '';
  String _userName = '';

  bool _btActive = false;
  String? _btErrorMessage;

  bool get isStarted         => _started;
  bool get isBluetoothActive => _btActive;
  String? get btErrorMessage => _btErrorMessage;
  String get currentUserId   => _userId;

  // ── Presence heartbeat ────────────────────────────────────────────────────
  Timer? _presenceTimer;
  static const _presenceInterval = Duration(seconds: 10);

  // ── Beacon ────────────────────────────────────────────────────────────────
  bool _beaconActive = false;
  Timer? _beaconTimer;
  static const _beaconInterval = Duration(minutes: 2); // Limit SOS to 1 per 2 min
  bool get isBeaconActive => _beaconActive;

  // ── Text chat history ─────────────────────────────────────────────────────
  final List<MeshTextMessage> _textHistory = [];
  List<MeshTextMessage> get textHistory => List.unmodifiable(_textHistory);
  static const _maxTextHistory = 100;

  // ── Peer tracking ─────────────────────────────────────────────────────────
  final Map<String, OfflinePeer> _peers = {};
  List<OfflinePeer> get nearbyPeers => List.unmodifiable(_peers.values);

  // ── Streams ───────────────────────────────────────────────────────────────
  final _eventCtrl = StreamController<MeshEvent>.broadcast();
  final _peerCtrl  = StreamController<OfflinePeer>.broadcast();

  Stream<MeshEvent>    get events     => _eventCtrl.stream;
  Stream<OfflinePeer>  get peerEvents => _peerCtrl.stream;

  StreamSubscription<OfflineMessage>? _btSub;
  StreamSubscription<String?>?        _btErrSub;
  StreamSubscription<String>?         _peerConnSub;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> start({
    required String roomId,
    required String userId,
    required String userName,
    required String apiKey,
  }) async {
    if (_started) return;

    _roomId   = roomId.isNotEmpty   ? roomId   : 'explora-mesh';
    _userId   = userId.isNotEmpty   ? userId   : (_auth.currentUser?.uid ?? 'anon');
    _userName = userName.isNotEmpty ? userName : (_auth.currentUser?.displayName ?? 'Партнёр');

    _started = true;
    debugPrint('[MeshService] запущен — комната: $_roomId  пользователь: $_userName');
    _startBluetooth(apiKey);
  }

  Future<void> _startBluetooth(String apiKey) async {
    _bt.reset();

    await _btErrSub?.cancel();
    _btErrSub = _bt.btError.listen((err) {
      _btErrorMessage = err;
      _eventCtrl.add(MeshBtStatusEvent(_btActive));
    });

    final ok = await _bt.start(
      roomId:   _roomId,
      userId:   _userId,
      userName: _userName,
      apiKey:   apiKey,
    );

    _btActive = ok;
    if (ok) {
      await _btSub?.cancel();
      _btSub = _bt.incomingMessages.listen(_onMessage);

      _presenceTimer?.cancel();
      await _sendPresencePing();
      _presenceTimer = Timer.periodic(_presenceInterval, (_) => _sendPresencePing());

      // При каждом BLE-подключении — немедленный presence ping
      await _peerConnSub?.cancel();
      _peerConnSub = _bt.peerConnected.listen((peerId) {
        debugPrint('[MeshService] 🔗 пир подключён: $peerId — шлём presence ping');
        _sendPresencePing();
      });

      debugPrint('[MeshService] ✅ MESH активен (партнёр)');
    } else {
      debugPrint('[MeshService] ❌ MESH недоступен: $_btErrorMessage');
    }
    _eventCtrl.add(MeshBtStatusEvent(_btActive));
  }

  Future<void> stop() async {
    if (!_started) return;

    await deactivateBeacon();
    _presenceTimer?.cancel();
    _presenceTimer = null;

    await _btSub?.cancel();
    await _btErrSub?.cancel();
    await _peerConnSub?.cancel();
    _btSub = null; _btErrSub = null; _peerConnSub = null;

    try { await _bt.stop(); } catch (_) {}
    _btActive = false;
    _peers.clear();
    _started = false;
    debugPrint('[MeshService] остановлен');
  }

  Future<void> _sendPresencePing() async {
    if (!_btActive) return;
    double? lat, lng;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 4));
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {}
    await _bt.broadcast({
      'type':     'presence',
      'roomId':   _roomId,
      'tripId':   _roomId,
      'userId':   _userId,
      'userName': _userName,
      'lat':      lat,
      'lng':      lng,
      'ts':       DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Text Chat ─────────────────────────────────────────────────────────────

  Future<void> sendTextMessage(String text) async {
    if (!_started || !_btActive || text.trim().isEmpty) return;

    final msgId = const Uuid().v4();
    final msg = MeshTextMessage(
      id:         msgId,
      senderId:   _userId,
      senderName: _userName,
      text:       text.trim(),
      receivedAt: DateTime.now(),
      isMine:     true,
    );

    _textHistory.insert(0, msg);
    if (_textHistory.length > _maxTextHistory) _textHistory.removeLast();
    _eventCtrl.add(MeshTextHistoryUpdatedEvent(List.unmodifiable(_textHistory)));

    await _bt.broadcast({
      'type':     'text',
      'roomId':   _roomId,
      'tripId':   _roomId,
      'userId':   _userId,
      'userName': _userName,
      'text':     text.trim(),
      'msgId':    msgId,
      'ts':       DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── SOS Beacon ────────────────────────────────────────────────────────────

  Future<void> activateBeacon() async {
    if (!_started || _beaconActive) return;
    _beaconActive = true;
    await _sendBeaconPing(active: true);
    _beaconTimer = Timer.periodic(_beaconInterval, (_) => _sendBeaconPing(active: true));
    _eventCtrl.add(MeshLocalBeaconEvent(true));
  }

  Future<void> deactivateBeacon() async {
    if (!_beaconActive) return;
    _beaconActive = false;
    _beaconTimer?.cancel();
    _beaconTimer = null;
    if (_started && _btActive) await _sendBeaconPing(active: false);
    _eventCtrl.add(MeshLocalBeaconEvent(false));
  }

  Future<void> _sendBeaconPing({required bool active}) async {
    if (!_btActive) return;
    double? lat, lng;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 5));
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {}

    await _bt.broadcast({
      'type':         'beacon',
      'roomId':       _roomId,
      'tripId':       _roomId,
      'userId':       _userId,
      'userName':     _userName,
      'beaconActive': active,
      'lat':          lat,
      'lng':          lng,
      'ts':           DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Incoming handler ──────────────────────────────────────────────────────

  void _onMessage(OfflineMessage msg) {
    _updatePeer(msg);
    switch (msg.type) {
      case OfflineMessageType.text:     _handleTextMessage(msg);
      case OfflineMessageType.beacon:   _handleBeacon(msg);
      case OfflineMessageType.presence: break;
      default: break;
    }
  }

  void _updatePeer(OfflineMessage msg) {
    final ex = _peers[msg.userId];
    final peer = ex?.copyWith(
      userName:        msg.userName,
      lastSeen:        msg.timestamp,
      lat:             msg.lat ?? ex.lat,
      lng:             msg.lng ?? ex.lng,
      hasLocation:     msg.lat != null || (ex.hasLocation),
      sosBroadcasting: msg.type == OfflineMessageType.beacon
          ? (msg.beaconActive ?? false) : ex.sosBroadcasting,
    ) ?? OfflinePeer(
      peerId:          msg.userId,
      userId:          msg.userId,
      userName:        msg.userName,
      lastSeen:        msg.timestamp,
      lat:             msg.lat,
      lng:             msg.lng,
      hasLocation:     msg.lat != null,
      sosBroadcasting: msg.type == OfflineMessageType.beacon && (msg.beaconActive ?? false),
    );
    _peers[msg.userId] = peer;
    _peerCtrl.add(peer);
  }

  void _handleTextMessage(OfflineMessage msg) {
    if (msg.text == null || msg.text!.isEmpty) return;
    final entry = MeshTextMessage(
      id:         msg.id,
      senderId:   msg.userId,
      senderName: msg.userName,
      text:       msg.text!,
      receivedAt: msg.timestamp,
      isMine:     false,
    );
    _textHistory.insert(0, entry);
    if (_textHistory.length > _maxTextHistory) _textHistory.removeLast();
    _eventCtrl.add(MeshTextReceivedEvent(entry));
    _eventCtrl.add(MeshTextHistoryUpdatedEvent(List.unmodifiable(_textHistory)));
  }

  void _handleBeacon(OfflineMessage msg) {
    final active = msg.beaconActive ?? false;
    if (active) {
      // Relay: передаём SOS-сигнал в Firebase если есть интернет
      SosService.instance.relayReceivedSos(
        msg: msg,
        relayUserId: _userId,
      );
      // Приоритет: если tripId отправителя == roomId партнёра — это наш маршрут
      final isFromMyTrip = msg.tripId.isNotEmpty && msg.tripId == _roomId;
      _eventCtrl.add(MeshSosReceivedEvent(
        userId: msg.userId,
        userName: msg.userName,
        lat: msg.lat,
        lng: msg.lng,
        isFromMyTrip: isFromMyTrip,
      ));
    } else {
      _eventCtrl.add(MeshSosClearedEvent(msg.userId));
    }
  }

  /// Заглушка — у партнёра нет аудио-оповещения, метод для совместимости с GlobalSosListener.
  Future<void> dismissSosAlert() async {}

  // ── Distance helpers ──────────────────────────────────────────────────────

  static double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1), dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double d) => d * pi / 180;

  double? distanceToPeer(String peerId, {double? myLat, double? myLng}) {
    final peer = _peers[peerId];
    if (peer == null || !peer.hasLocation || myLat == null || myLng == null) return null;
    return distanceMeters(myLat, myLng, peer.lat!, peer.lng!);
  }

  static String formatDistance(double m) =>
      m < 1000 ? '~${m.round()} м' : '~${(m / 1000).toStringAsFixed(1)} км';

  void dispose() {
    _btSub?.cancel(); _btErrSub?.cancel();
    _eventCtrl.close(); _peerCtrl.close();
    _bt.dispose();
  }
}

// ── MeshEvent hierarchy ───────────────────────────────────────────────────────

abstract class MeshEvent { const MeshEvent(); }

class MeshBtStatusEvent extends MeshEvent {
  final bool active;
  const MeshBtStatusEvent(this.active);
}

class MeshTextReceivedEvent extends MeshEvent {
  final MeshTextMessage message;
  const MeshTextReceivedEvent(this.message);
}

class MeshSosReceivedEvent extends MeshEvent {
  final String userId, userName;
  final double? lat, lng;
  /// true = SOS от клиента нашего маршрута (приоритетное уведомление).
  /// false = посторонний пользователь MESH — спокойное уведомление.
  final bool isFromMyTrip;
  const MeshSosReceivedEvent({
    required this.userId,
    required this.userName,
    this.lat,
    this.lng,
    this.isFromMyTrip = false,
  });
}

class MeshSosClearedEvent extends MeshEvent {
  final String userId;
  const MeshSosClearedEvent(this.userId);
}

class MeshLocalBeaconEvent extends MeshEvent {
  final bool active;
  const MeshLocalBeaconEvent(this.active);
}

class MeshTextHistoryUpdatedEvent extends MeshEvent {
  final List<MeshTextMessage> history;
  const MeshTextHistoryUpdatedEvent(this.history);
}
