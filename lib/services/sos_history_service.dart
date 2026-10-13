import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Одна запись в истории полученных SOS-сигналов.
class SosHistoryEntry {
  final String userId;
  final String userName;
  final double? lat;
  final double? lng;
  final DateTime receivedAt;
  final bool isFromMyTrip;

  const SosHistoryEntry({
    required this.userId,
    required this.userName,
    this.lat,
    this.lng,
    required this.receivedAt,
    required this.isFromMyTrip,
  });

  Map<String, dynamic> toJson() => {
        'userId':       userId,
        'userName':     userName,
        'lat':          lat,
        'lng':          lng,
        'receivedAt':   receivedAt.millisecondsSinceEpoch,
        'isFromMyTrip': isFromMyTrip,
      };

  factory SosHistoryEntry.fromJson(Map<String, dynamic> j) => SosHistoryEntry(
        userId:       j['userId']  as String,
        userName:     j['userName'] as String,
        lat:          (j['lat']  as num?)?.toDouble(),
        lng:          (j['lng']  as num?)?.toDouble(),
        receivedAt:   DateTime.fromMillisecondsSinceEpoch(j['receivedAt'] as int),
        isFromMyTrip: j['isFromMyTrip'] as bool? ?? false,
      );
}

/// Хранилище истории полученных SOS-сигналов.
///
/// Персистентное (SharedPreferences) — история не теряется при перезапуске.
/// Хранит последние [maxEntries] записей.
class SosHistoryService {
  SosHistoryService._();
  static final SosHistoryService instance = SosHistoryService._();

  static const _prefKey    = 'sos_history_v1';
  static const _maxEntries = 100;

  final List<SosHistoryEntry> _entries = [];
  final _ctrl = StreamController<List<SosHistoryEntry>>.broadcast();
  bool _initialized = false;

  List<SosHistoryEntry> get entries => List.unmodifiable(_entries);
  Stream<List<SosHistoryEntry>> get stream => _ctrl.stream;

  /// Загружает историю из SharedPreferences при старте.
  /// Повторные вызовы безопасны — загрузка выполнится только один раз.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefKey) ?? [];
      _entries.clear();
      for (final item in raw) {
        try {
          _entries.add(SosHistoryEntry.fromJson(
            Map<String, dynamic>.from(jsonDecode(item) as Map),
          ));
        } catch (_) {}
      }
      _ctrl.add(List.unmodifiable(_entries));
    } catch (e) {
      debugPrint('[SosHistoryService] ❌ init error: $e');
    }
  }

  /// Добавляет новую запись и сохраняет в SharedPreferences.
  Future<void> add(SosHistoryEntry entry) async {
    // Дедупликация: не добавлять тот же userId + время (±60 сек)
    final isDup = _entries.any((e) =>
        e.userId == entry.userId &&
        e.receivedAt.difference(entry.receivedAt).abs().inSeconds < 60);
    if (isDup) return;

    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) _entries.removeLast();
    _ctrl.add(List.unmodifiable(_entries));
    await _persist();
    debugPrint('[SosHistoryService] ✅ SOS от ${entry.userName} добавлен в историю');
  }

  Future<void> clear() async {
    _entries.clear();
    _ctrl.add(const []);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey); // удаляем ключ целиком, а не сохраняем [].
    } catch (e) {
      debugPrint('[SosHistoryService] ❌ clear error: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = _entries.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_prefKey, raw);
    } catch (e) {
      debugPrint('[SosHistoryService] ❌ persist error: $e');
    }
  }
}
