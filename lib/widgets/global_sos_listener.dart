import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/mesh_service.dart';
import '../services/sos_history_service.dart';

/// Оборачивает дерево партнёрского приложения.
///
/// Запускает MESH-сервис и показывает SOS-баннер поверх ЛЮБОГО экрана.
/// Использует [Stack] + [setState] вместо [OverlayEntry]:
/// виджет уже выше [Navigator] в [MaterialApp.builder] — наложение гарантировано.
class GlobalSosListener extends StatefulWidget {
  final Widget child;
  const GlobalSosListener({super.key, required this.child});

  @override
  State<GlobalSosListener> createState() => _GlobalSosListenerState();
}

class _GlobalSosListenerState extends State<GlobalSosListener> {
  StreamSubscription<MeshEvent>? _meshSub;
  final List<_SosBannerData> _pendingBanners = [];

  @override
  void initState() {
    super.initState();
    _meshSub = MeshService.instance.events.listen(_onMeshEvent);
    _ensureMeshStarted();
    SosHistoryService.instance.init();
  }

  void _ensureMeshStarted() {
    if (MeshService.instance.isStarted) return;
    final user = FirebaseAuth.instance.currentUser;
    MeshService.instance.start(
      roomId:   'explora-mesh',
      userId:   user?.uid ?? '',
      userName: user?.displayName ?? 'Партнёр',
      apiKey:   'YOUR_BRIDGEFY_API_KEY',
    );
  }

  @override
  void dispose() {
    _meshSub?.cancel();
    super.dispose();
  }

  void _onMeshEvent(MeshEvent event) {
    if (event is! MeshSosReceivedEvent) return;

    final entry = SosHistoryEntry(
      userId:       event.userId,
      userName:     event.userName,
      lat:          event.lat,
      lng:          event.lng,
      receivedAt:   DateTime.now(),
      isFromMyTrip: event.isFromMyTrip,
    );

    SosHistoryService.instance.add(entry);
    MeshService.instance.dismissSosAlert();

    if (mounted) {
      setState(() => _pendingBanners.add(_SosBannerData(entry: entry)));
    }
  }

  void _onCloseBanner() {
    if (mounted) {
      setState(() {
        if (_pendingBanners.isNotEmpty) _pendingBanners.removeAt(0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_pendingBanners.isNotEmpty)
          Positioned(
            top: 0, left: 0, right: 0,
            child: _SosBanner(
              data:    _pendingBanners.first,
              onClose: _onCloseBanner,
            ),
          ),
      ],
    );
  }
}

// ─── Данные баннера ──────────────────────────────────────────────────────────

class _SosBannerData {
  final SosHistoryEntry entry;
  _SosBannerData({required this.entry});
}

// ─── Сам баннер ──────────────────────────────────────────────────────────────

class _SosBanner extends StatefulWidget {
  final _SosBannerData data;
  final VoidCallback onClose;
  const _SosBanner({required this.data, required this.onClose});

  @override
  State<_SosBanner> createState() => _SosBannerState();
}

class _SosBannerState extends State<_SosBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _copyCoords() async {
    final entry = widget.data.entry;
    if (entry.lat == null || entry.lng == null) return;
    final coords =
        '${entry.lat!.toStringAsFixed(6)}, ${entry.lng!.toStringAsFixed(6)}';
    await Clipboard.setData(ClipboardData(text: coords));
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('📍 Скопировано: $coords'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry  = widget.data.entry;
    final hasGps = entry.lat != null && entry.lng != null;
    final time   = DateFormat('HH:mm:ss').format(entry.receivedAt);

    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB71C1C), Color(0xFF7B0000)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.6),
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок
                  Row(
                    children: [
                      ScaleTransition(
                        scale: _pulseAnim,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Text('🆘',
                              style: TextStyle(fontSize: 22)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'SOS СИГНАЛ!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      // Без tooltip — нет Overlay-предка выше MaterialApp.builder
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),

                  const Divider(color: Colors.white24, height: 20),

                  // Имя + бейдж
                  Row(
                    children: [
                      const Icon(Icons.person, color: Colors.white70, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          entry.isFromMyTrip ? 'Мой маршрут' : 'MESH',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Координаты
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.white70, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        hasGps
                            ? '${entry.lat!.toStringAsFixed(5)}°N, '
                              '${entry.lng!.toStringAsFixed(5)}°E'
                            : 'Координаты недоступны',
                        style: TextStyle(
                          color: hasGps ? Colors.white : Colors.white54,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Время
                  Row(
                    children: [
                      const Icon(Icons.access_time,
                          color: Colors.white70, size: 18),
                      const SizedBox(width: 6),
                      Text(time,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Кнопки
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Принято'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      if (hasGps) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _copyCoords,
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            label: const Text('Координаты'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFFB71C1C),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
