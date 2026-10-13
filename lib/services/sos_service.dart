import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/offline_models.dart';
import '../models/sos_signal.dart';

/// Relay-only SOS-сервис для партнёрского приложения.
///
/// Партнёры **не отправляют** SOS напрямую, но при получении SOS от клиента
/// по BLE Mesh форвардят данные в Firebase Firestore (`sos_signals`).
///
/// Исправленные баги (идентичны explora_app):
/// - BUG-1: только одна подписка на сеть, не две
/// - BUG-2: тот же детерминированный UUID v5 для signalId (совместим с отправителем)
/// - BUG-4: нет мутации Map из toJson()
/// - BUG-5: не relay собственный сигнал
/// - BUG-6: защита _isFlushing от параллельного запуска
class SosService {
  SosService._();
  static final SosService instance = SosService._();

  static const _prefKey = 'partner_sos_pending_queue';

  bool _initialized = false;
  // BUG-6 fix: защита от параллельного запуска flush
  bool _isFlushing = false;

  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  final _firestore = FirebaseFirestore.instance;

  /// Инициализировать: подписаться на изменения сети для автосброса очереди.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final results = await Connectivity().checkConnectivity();
    _isOnline = _hasInternet(results);

    // BUG-1 fix: только одна подписка
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = _hasInternet(results);
      if (online && !_isOnline) {
        _flushPendingQueue();
      }
      _isOnline = online;
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
    _initialized = false;
  }

  static bool _hasInternet(List<ConnectivityResult> r) =>
      r.any((c) => c != ConnectivityResult.none);

  // ─── Публичный API ────────────────────────────────────────────────────────

  /// BUG-2 fix: тот же детерминированный алгоритм что в explora_app SosService.
  /// Округление до минуты: один SOS за минуту от одного user = один документ.
  static String deriveSignalId(String userId, DateTime ts) {
    final minuteTs = (ts.millisecondsSinceEpoch ~/ 60000) * 60000;
    // ignore: deprecated_member_use
    return const Uuid().v5(Uuid.NAMESPACE_URL, '$userId-$minuteTs');
  }

  /// Вызывается при получении SOS от клиента по BLE Mesh.
  Future<void> relayReceivedSos({
    required OfflineMessage msg,
    required String relayUserId,
  }) async {
    if (msg.beaconActive != true) return;
    // BUG-5 fix: не relay собственный сигнал (два устройства под одним аккаунтом)
    if (msg.userId == relayUserId) return;

    // BUG-2 fix: детерминированный signalId = совместим с отправителем
    final signalId = deriveSignalId(msg.userId, msg.timestamp);

    final signal = SosSignal(
      signalId: signalId,
      senderId: msg.userId,
      senderName: msg.userName,
      tripId: msg.tripId.isNotEmpty ? msg.tripId : null,
      lat: msg.lat,
      lng: msg.lng,
      sentAt: msg.timestamp,
      uploadedAt: DateTime.now(),
      uploadedBy: relayUserId,
      isRelay: true,
      status: 'active',
    );

    debugPrint('[SosService Partner] 📡 Relay SOS от ${msg.userName} | signalId=$signalId');

    if (_isOnline) {
      await _uploadToFirestore(signal);
    } else {
      await _enqueue(signal);
    }
  }

  // ─── Внутренняя логика ────────────────────────────────────────────────────

  Future<void> _uploadToFirestore(SosSignal signal) async {
    try {
      await _firestore
          .collection('sos_signals')
          .doc(signal.signalId)
          .set(signal.toJson());
      debugPrint('[SosService Partner] ✅ Relay ${signal.signalId} записан в Firestore');
    } catch (e, stack) {
      // Документ уже существует — другой relay или сам отправитель записал раньше.
      debugPrint('[SosService Partner] ⚠️ Relay не удался (дубль или ошибка): $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerSosService._uploadToFirestore', fatal: false);
    }
  }

  Future<void> _enqueue(SosSignal signal) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefKey) ?? [];
      // BUG-4 fix: создаём новый Map, не мутируем toJson()
      final json = <String, dynamic>{...signal.toJson()};
      json['sentAt'] = signal.sentAt.millisecondsSinceEpoch;
      json['uploadedAt'] = signal.uploadedAt.millisecondsSinceEpoch;
      raw.add(jsonEncode(json));
      await prefs.setStringList(_prefKey, raw);
      debugPrint('[SosService Partner] 💾 В очереди ${raw.length} relay-сигналов');
    } catch (e, stack) {
      debugPrint('[SosService Partner] ❌ Ошибка enqueue: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerSosService._enqueue', fatal: false);
    }
  }

  Future<void> _flushPendingQueue() async {
    // BUG-6 fix: защита от параллельного запуска
    if (_isFlushing) return;
    _isFlushing = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefKey);
      if (raw == null || raw.isEmpty) return;

      debugPrint('[SosService Partner] 🔄 Сброс ${raw.length} relay-сигналов...');
      final remaining = <String>[];

      for (final item in raw) {
        try {
          final json = Map<String, dynamic>.from(jsonDecode(item) as Map);
          // Восстанавливаем Timestamp из ms
          final sentAtMs = json['sentAt'];
          final uploadedAtMs = json['uploadedAt'];
          if (sentAtMs is int) {
            json['sentAt'] = Timestamp.fromDate(
                DateTime.fromMillisecondsSinceEpoch(sentAtMs));
          }
          if (uploadedAtMs is int) {
            json['uploadedAt'] = Timestamp.fromDate(
                DateTime.fromMillisecondsSinceEpoch(uploadedAtMs));
          }
          final signal = SosSignal.fromJson(json);
          await _uploadToFirestore(signal);
        } catch (e, stack) {
          debugPrint('[SosService Partner] ❌ Ошибка при сбросе: $e');
          FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerSosService._flushPendingQueue item', fatal: false);
          remaining.add(item);
        }
      }

      if (remaining.isEmpty) {
        await prefs.remove(_prefKey);
        debugPrint('[SosService Partner] ✅ Очередь полностью сброшена');
      } else {
        await prefs.setStringList(_prefKey, remaining);
        debugPrint('[SosService Partner] ⚠️ Осталось ${remaining.length} в очереди');
      }
    } catch (e, stack) {
      debugPrint('[SosService Partner] ❌ Ошибка flushPendingQueue: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerSosService._flushPendingQueue', fatal: false);
    } finally {
      _isFlushing = false;
    }
  }
}
