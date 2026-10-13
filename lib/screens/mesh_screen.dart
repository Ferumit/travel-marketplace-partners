import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/offline_models.dart';
import '../services/mesh_service.dart';
import '../theme/app_colors.dart';

/// Offline MESH screen for the partner app.
/// Shows nearby peers (clients, other partners) and allows text messaging
/// without internet via Bridgefy BLE mesh.
class MeshScreen extends StatefulWidget {
  const MeshScreen({super.key});

  @override
  State<MeshScreen> createState() => _MeshScreenState();
}

class _MeshScreenState extends State<MeshScreen>
    with SingleTickerProviderStateMixin {
  final _mesh = MeshService.instance;
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  StreamSubscription<MeshEvent>? _eventSub;
  StreamSubscription<OfflinePeer>? _peerSub;

  bool _meshActive = false;
  List<OfflinePeer> _peers = [];
  List<MeshTextMessage> _messages = [];
  bool _isSending = false;
  Position? _myPosition;
  StreamSubscription<Position>? _posSub;

  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _meshActive = _mesh.isStarted && _mesh.isBluetoothActive;
    _messages = List.from(_mesh.textHistory);
    _peers = List.from(_mesh.nearbyPeers);

    _eventSub = _mesh.events.listen(_onEvent);
    _peerSub = _mesh.peerEvents.listen((_) {
      if (mounted) setState(() => _peers = List.from(_mesh.nearbyPeers));
    });

    // Start Bridgefy BLE if not already running
    if (!_mesh.isStarted) {
      final user = FirebaseAuth.instance.currentUser;
      MeshService.instance.start(
        roomId:   AppConfig.meshRoomId,
        userId:   user?.uid ?? '',
        userName: user?.displayName ?? 'Партнёр',
        apiKey:   AppConfig.bridgefyApiKey,
      );
    }

    _posSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 20,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Explora Partners — MESH',
          notificationText: 'Офлайн-сеть активна',
          enableWakeLock: false,
          notificationIcon: AndroidResource(
            name: 'launcher_icon',
            defType: 'mipmap',
          ),
        ),
      ),
    ).listen(
      (p) { if (mounted) setState(() => _myPosition = p); },
      onError: (_) {}, // ignore PermissionDeniedException
      cancelOnError: false,
    );
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _peerSub?.cancel();
    _posSub?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onEvent(MeshEvent event) {
    if (!mounted) return;
    if (event is MeshBtStatusEvent) {
      setState(() => _meshActive = event.active);
    } else if (event is MeshTextHistoryUpdatedEvent) {
      setState(() => _messages = List.from(event.history));
    } else if (event is MeshSosReceivedEvent) {
      _showSosAlert(event);
    }
  }

  void _showSosAlert(MeshSosReceivedEvent event) {
    showCupertinoDialog(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('🆘 SOS СИГНАЛ!'),
        content: Text(
          '${event.userName} отправил(а) SOS сигнал!\n'
          '${event.lat != null ? 'Координаты: ${event.lat!.toStringAsFixed(4)}°N, ${event.lng!.toStringAsFixed(4)}°E' : 'Координаты неизвестны'}',
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Принято'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    _msgCtrl.clear();
    await _mesh.sendTextMessage(text);
    setState(() => _isSending = false);
  }

  String _distanceLabel(OfflinePeer peer) {
    if (!peer.hasLocation || _myPosition == null) return '';
    final d = MeshService.distanceMeters(
      _myPosition!.latitude, _myPosition!.longitude,
      peer.lat!, peer.lng!,
    );
    return MeshService.formatDistance(d);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    return CupertinoPageScaffold(
      backgroundColor: AppColors.background,
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.backgroundElevated,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
        leading: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // EP logo badge
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'EP',
                  style: TextStyle(
                    color: Color(0xFF0B1209),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        middle: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.radio,
                  size: 14,
                  color: _meshActive ? AppColors.accent : CupertinoColors.systemGrey,
                ),
                const SizedBox(width: 5),
                const Text(
                  'Mesh-связь',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            const Text(
              'Оффлайн-сеть · без сотовой связи',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        trailing: _meshActive && _peers.isNotEmpty
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${_peers.length} онлайн',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentBright,
                      ),
                    ),
                  ],
                ),
              )
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Column(
            children: [
              // ── Канал-строка ──────────────────────────────────────────────
              if (_meshActive)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.07),
                    border: const Border(
                      bottom: BorderSide(color: AppColors.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7, height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Канал «Explora MESH» · радиус ${AppConfig.meshRadiusKm} км',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.accentBright,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              // ── Tab bar ────────────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: CupertinoColors.separator.resolveFrom(context))),
                ),
                child: Row(
                  children: [
                    _buildTab(0, LucideIcons.messageSquare, 'Чат'),
                    _buildTab(1, LucideIcons.users, 'Рядом'),
                  ],
                ),
              ),
              Expanded(
                child: _tabCtrl.index == 0
                    ? _buildChatTab(isDark)
                    : _buildPeersTab(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(int index, IconData icon, String label) {
    final selected = _tabCtrl.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabCtrl.index = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: selected ? AppColors.accent : CupertinoColors.systemGrey),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.accent : CupertinoColors.systemGrey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatTab(bool isDark) {
    return Column(
      children: [
        if (!_meshActive)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: CupertinoColors.systemOrange.withValues(alpha: 0.12),
            child: const Text(
              '⚠️ MESH не активен — сообщения не отправляются',
              style: TextStyle(color: CupertinoColors.systemOrange, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.messageSquare, color: AppColors.accent, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        'Нет сообщений',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: isDark ? CupertinoColors.white : CupertinoColors.black,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Все сообщения передаются\nбез интернета через MESH',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: CupertinoColors.systemGrey,
                          fontSize: 12,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _buildBubble(_messages[i], isDark),
                ),
        ),
        _buildInput(isDark),
      ],
    );
  }

  Widget _buildBubble(MeshTextMessage msg, bool isDark) {
    final isMine = msg.isMine;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            CircleAvatar(
              radius: 13,
              backgroundColor: AppColors.accent.withValues(alpha: 0.15),
              child: Text(
                msg.senderName.isNotEmpty ? msg.senderName[0].toUpperCase() : '?',
                style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMine
                    ? AppColors.accent.withValues(alpha: 0.18)
                    : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMine ? 16 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 16),
                ),
                border: Border.all(
                  color: isMine
                      ? AppColors.accent.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.04),
                ),
              ),
              child: Column(
                crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMine)
                    Text(msg.senderName, style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
                  if (!isMine) const SizedBox(height: 2),
                  Text(msg.text, style: TextStyle(fontSize: 14, color: isDark ? CupertinoColors.white : CupertinoColors.black, decoration: TextDecoration.none)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isMine) ...[
                        const Icon(LucideIcons.radio, size: 8, color: CupertinoColors.systemGrey),
                        const SizedBox(width: 3),
                        const Text('ретранслировано  ', style: TextStyle(fontSize: 9, color: CupertinoColors.systemGrey, decoration: TextDecoration.none)),
                      ],
                      Text(
                        '${msg.receivedAt.hour.toString().padLeft(2, '0')}:${msg.receivedAt.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 9, color: CupertinoColors.systemGrey, decoration: TextDecoration.none),
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

  Widget _buildInput(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemGroupedBackground.resolveFrom(context),
        border: Border(top: BorderSide(color: CupertinoColors.separator.resolveFrom(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: CupertinoTextField(
              controller: _msgCtrl,
              enabled: _meshActive,
              placeholder: _meshActive ? 'Сообщение MESH...' : 'MESH не активен',
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: CupertinoColors.separator.resolveFrom(context).withValues(alpha: 0.5)),
              ),
              onSubmitted: (_) => _sendMessage(),
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _meshActive ? _sendMessage : null,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _meshActive ? AppColors.accent : CupertinoColors.systemGrey4.resolveFrom(context),
              ),
              child: _isSending
                  ? const Padding(padding: EdgeInsets.all(10), child: CupertinoActivityIndicator())
                  : const Icon(LucideIcons.send, color: Colors.black, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeersTab(bool isDark) {
    if (_peers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.radar, color: AppColors.accent, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Поиск участников...',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Сканируем Bluetooth для поиска\nближайших устройств',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CupertinoColors.systemGrey,
                fontSize: 12,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      );
    }

    return CupertinoScrollbar(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _peers.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _buildPeerCard(_peers[i], isDark),
      ),
    );
  }

  Widget _buildPeerCard(OfflinePeer peer, bool isDark) {
    final name = peer.userName ?? 'Участник';
    final dist = _distanceLabel(peer);
    final isSos = peer.sosBroadcasting;
    final isRecent = DateTime.now().difference(peer.lastSeen).inSeconds < 30;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isSos
            ? CupertinoColors.systemRed.withValues(alpha: 0.08)
            : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSos
              ? CupertinoColors.systemRed.withValues(alpha: 0.3)
              : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSos
                  ? CupertinoColors.systemRed.withValues(alpha: 0.15)
                  : AppColors.accent.withValues(alpha: 0.1),
            ),
            child: Center(
              child: isSos
                  ? const Icon(LucideIcons.alertTriangle, color: CupertinoColors.systemRed, size: 18)
                  : Text(name[0].toUpperCase(), style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 17)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, decoration: TextDecoration.none, color: isSos ? CupertinoColors.systemRed : null),
                    ),
                    if (isSos) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: CupertinoColors.systemRed, borderRadius: BorderRadius.circular(5)),
                        child: const Text('SOS', style: TextStyle(color: CupertinoColors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(LucideIcons.radio, size: 10, color: isRecent ? AppColors.accent : CupertinoColors.systemGrey),
                    const SizedBox(width: 4),
                    Text(
                      'MESH${dist.isNotEmpty ? '  •  $dist' : ''}',
                      style: TextStyle(fontSize: 11, color: isRecent ? AppColors.accent : CupertinoColors.systemGrey, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRecent ? (isSos ? CupertinoColors.systemRed : CupertinoColors.systemGreen) : CupertinoColors.systemGrey,
            ),
          ),
        ],
      ),
    );
  }
}
