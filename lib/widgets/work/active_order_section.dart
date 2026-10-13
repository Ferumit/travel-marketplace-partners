import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/booking_models.dart';
import '../../models/offline_action.dart';
import '../../services/auth_service.dart';
import '../../repository/firestore_repository.dart';
import '../../services/sync_manager.dart';


class ActiveOrderSection extends StatelessWidget {
  final bool isDark;
  final ActiveTrip trip;
  final Booking? booking;
  final bool isDriver;
  final bool isLoading;
  final Future<void> Function(ActiveTrip, Booking?, bool) onMarkReady;
  final Future<void> Function(ActiveTrip, {required bool isDriver}) onFinishTrip;

  const ActiveOrderSection({
    required this.isDark,
    required this.trip,
    this.booking,
    required this.isDriver,
    required this.isLoading,
    required this.onMarkReady,
    required this.onFinishTrip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Текущий заказ',
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: isDark ? CupertinoColors.darkBackgroundGray : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Trip Info Instead of Map Placeholder
              GestureDetector(
                onTap: () => _showParticipantsSheet(context),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.grey.shade100,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking?.routeTitle ?? trip.customName ?? 'Новый маршрут',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (booking?.participants != null && booking!.participants > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(CupertinoIcons.person_2_fill, size: 14, color: CupertinoColors.systemGrey),
                            const SizedBox(width: 8),
                            Text('Группа: ${booking!.participants} туристов', style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
                          ],
                        ),
                      ),
                    if (booking?.startDate != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(CupertinoIcons.calendar, size: 14, color: CupertinoColors.systemGrey),
                            const SizedBox(width: 8),
                            Text('Дата: ${booking!.startDate.split('T').first}', style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
                          ],
                        ),
                      ),
                    if (booking?.phoneNumber != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Icon(CupertinoIcons.phone_fill, size: 14, color: CupertinoColors.systemGrey),
                            const SizedBox(width: 8),
                            Text('Тел: ${booking!.phoneNumber}', style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(CupertinoIcons.map_pin_ellipse, size: 14, color: CupertinoColors.systemGrey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            booking?.waypoints.firstOrNull?.address ?? 'Адрес уточняется',
                            style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ), // Close GestureDetector
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _OrderInfo(
                          label: 'Вы получите',
                          value: booking != null
                              ? '${(isDriver ? (booking!.driverEarning ?? booking!.totalPrice) : (booking!.guideEarning ?? booking!.totalPrice)).toStringAsFixed(0)} ₸'
                              : '...',
                          color: Theme.of(context).primaryColor,
                          isDark: isDark,
                        ),
                        _OrderInfo(
                          label: 'Время в пути',
                          value: '25 мин',
                          color: Theme.of(context).primaryColor,
                          isDark: isDark,
                        ),
                      ],
                    ),
                    _buildCompanionsList(context),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (trip.status == TripStatus.scheduled) ...[
                          if (isDriver) ...[
                            // Driver: Decline + Accept (via RoutePreviewScreen)
                            Expanded(
                              flex: 1,
                              child: CupertinoButton(
                                color: CupertinoColors.systemRed.withValues(alpha: 0.1),
                                padding: EdgeInsets.zero,
                                borderRadius: BorderRadius.circular(12),
                                onPressed: () async {
                                  final confirmed = await showCupertinoDialog<bool>(
                                    context: context,
                                    builder: (context) => CupertinoAlertDialog(
                                      title: const Text('Отмена заказа'),
                                      content: const Text(
                                          'Вы уверены, что хотите полностью отменить этот заказ? Это действие отправит уведомление клиенту.'),
                                      actions: [
                                        CupertinoDialogAction(
                                          child: const Text('Нет'),
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                        ),
                                        CupertinoDialogAction(
                                          isDestructiveAction: true,
                                          child: const Text('Да, отменить'),
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirmed != true) return;

                                  final uid = AuthService.instance.currentUser?.uid;
                                  if (booking != null && uid != null) {
                                    FirestoreRepository.instance
                                        .cancelTrip(trip.id, booking!.id);
                                  }
                                },
                                child: const Text(
                                  'Отменить',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: CupertinoColors.systemRed),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 1,
                              child: CupertinoButton(
                                color: Theme.of(context).primaryColor,
                                padding: EdgeInsets.zero,
                                borderRadius: BorderRadius.circular(12),
                                onPressed: () {
                                  if (booking != null) {
                                    context.push('/route-preview', extra: {'trip': trip, 'booking': booking});
                                  }
                                },
                                child: const Text(
                                  'Принять',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ),
                          ] else ...[
                            // Guide: Decline + Accept (simpler — just mark guideReady flag)
                            Expanded(
                              flex: 1,
                              child: CupertinoButton(
                                color: CupertinoColors.systemRed.withValues(alpha: 0.1),
                                padding: EdgeInsets.zero,
                                borderRadius: BorderRadius.circular(12),
                                onPressed: () async {
                                  final confirmed = await showCupertinoDialog<bool>(
                                    context: context,
                                    builder: (context) => CupertinoAlertDialog(
                                      title: const Text('Отказаться'),
                                      content: const Text('Отказаться от этого маршрута? Ваше имя будет удалено из предложения.'),
                                      actions: [
                                        CupertinoDialogAction(
                                          child: const Text('Нет'),
                                          onPressed: () => Navigator.pop(context, false),
                                        ),
                                        CupertinoDialogAction(
                                          isDestructiveAction: true,
                                          child: const Text('Отказаться'),
                                          onPressed: () => Navigator.pop(context, true),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true) return;
                                  final uid = AuthService.instance.currentUser?.uid;
                                  if (uid != null && booking != null) {
                                    await FirestoreRepository.instance
                                        .declineGuide(trip.id, booking!.id, uid);
                                  }
                                },
                                child: const Text(
                                  'Отказаться',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: CupertinoColors.systemRed),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 1,
                              child: CupertinoButton(
                                color: Theme.of(context).primaryColor,
                                padding: EdgeInsets.zero,
                                borderRadius: BorderRadius.circular(12),
                                onPressed: () async {
                                  await FirestoreRepository.instance
                                      .acceptTripGuide(trip.id, trip.bookingId);
                                },
                                child: const Text(
                                  'Принять',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 12),
                        ] else if (trip.status == TripStatus.waiting) ...[
                          Expanded(
                            child: (isDriver ? trip.driverReady : trip.guideReady)
                                ? Container(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    decoration: BoxDecoration(
                                      color: CupertinoColors.systemGreen.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: Text('ОЖИДАНИЕ КЛИЕНТА',
                                          style: TextStyle(
                                              color: CupertinoColors.systemGreen,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13)),
                                    ),
                                  )
                                : CupertinoButton(
                                    color: CupertinoColors.systemOrange,
                                    padding: EdgeInsets.zero,
                                    borderRadius: BorderRadius.circular(12),
                                    onPressed: isLoading ? null : () => onMarkReady(trip, booking, isDriver),
                                    child: isLoading
                                        ? const CupertinoActivityIndicator(color: Colors.white)
                                        : const Text('Я НА МЕСТЕ',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                                fontSize: 14)),
                                  ),
                          ),
                          const SizedBox(width: 12),
                        ] else if (trip.status == TripStatus.inProgress) ...[
                          Expanded(
                            child: trip.completionRequested
                                ? Container(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    decoration: BoxDecoration(
                                      color: CupertinoColors.systemGreen.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: Text('ОЖИДАНИЕ КЛИЕНТА',
                                          style: TextStyle(
                                              color: CupertinoColors.systemGreen,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13)),
                                    ),
                                  )
                                : _buildWaypointButton(context),
                          ),
                          const SizedBox(width: 12),
                        ] else ...[
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                              decoration: BoxDecoration(
                                color: CupertinoColors.systemGreen.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Статус: ${trip.status}',
                                style: const TextStyle(
                                  color: CupertinoColors.systemGreen,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            child: Icon(CupertinoIcons.chat_bubble_2_fill, color: Theme.of(context).primaryColor),
                            onPressed: () => context.push(
                              '/messenger',
                              extra: {'tripId': trip.id, 'title': booking?.routeTitle ?? 'Чат'},
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompanionsList(BuildContext context) {
    if (trip.companions.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Пассажиры (${trip.companions.where((c) => c.ready).length}/${trip.companions.length} на месте)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        ...trip.companions.map((comp) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemGrey6,
              borderRadius: BorderRadius.circular(12),
            ),
            child: CupertinoListTile(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  image: comp.photoUrl != null && comp.photoUrl!.isNotEmpty
                      ? DecorationImage(image: NetworkImage(comp.photoUrl!), fit: BoxFit.cover)
                      : null,
                ),
                child: (comp.photoUrl == null || comp.photoUrl!.isEmpty)
                    ? Icon(CupertinoIcons.person_fill, color: Theme.of(context).primaryColor)
                    : null,
              ),
              title: Text(comp.displayName, style: TextStyle(color: isDark ? Colors.white : Colors.black)),
              trailing: CupertinoSwitch(
                value: comp.ready,
                activeTrackColor: const Color(0xFF6FBF4F),
                onChanged: isLoading ? null : (val) {
                  final newList = trip.companions.map((c) => c.uid == comp.uid ? c.copyWith(ready: val) : c).toList();
                  FirestoreRepository.instance.updateCompanions(trip.id, newList.map((e) => e.toJson()).toList());
                  
                  // Auto-start check
                  bool allCompsReady = newList.every((c) => c.ready);
                  bool driverOk = isDriver ? true : trip.driverReady;
                  bool guideOk = (trip.guideId == null) || (!isDriver ? true : trip.guideReady);
                  if (allCompsReady && driverOk && guideOk && trip.clientReady) {
                    SyncManager.instance.enqueueAction(OfflineAction(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      type: 'startTrip',
                      payload: {'tripId': trip.id, 'bookingId': trip.bookingId},
                      timestamp: DateTime.now().millisecondsSinceEpoch,
                    ));
                  }
                },
              ),
            ),
          );
        }),
      ],
    );
  }

  void _showParticipantsSheet(BuildContext context) {
    if (booking == null) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Участники маршрута',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                _buildParticipantRow(context, CupertinoIcons.car_detailed, 'Водитель', booking!.driverName ?? 'Не назначен'),
                if (trip.partnerId != null)
                  _buildParticipantRow(context, CupertinoIcons.person_crop_circle_fill, 'Гид', booking!.guideName ?? 'Не назначен'),
                _buildParticipantRow(context, CupertinoIcons.group_solid, 'Туристы', '${booking!.participants} чел.'),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: Theme.of(context).primaryColor,
                    borderRadius: BorderRadius.circular(12),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Понятно', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildParticipantRow(BuildContext context, IconData icon, String role, String name) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Theme.of(context).primaryColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role, style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
                const SizedBox(height: 2),
                Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaypointButton(BuildContext context) {
    final currentIndex = trip.currentWaypointIndex;
    final totalPoints = trip.waypoints.length;
    
    if (currentIndex >= totalPoints) {
       return CupertinoButton(
        color: CupertinoColors.systemGreen,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(12),
        onPressed: isLoading ? null : () => onFinishTrip(trip, isDriver: isDriver),
        child: isLoading
            ? const CupertinoActivityIndicator(color: Colors.white)
            : const Text('ЗАВЕРШИТЬ МАРШРУТ',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontSize: 14)),
      );
    }

    final String roleKey = isDriver ? 'driver' : 'guide';
    final Map<String, bool> wpCheckIns = currentIndex < trip.waypoints.length
        ? trip.waypoints[currentIndex].checkIns
        : {};
    final bool meCheckedIn = wpCheckIns[roleKey] == true;

    if (meCheckedIn) {
      int checkedInCount = wpCheckIns.values.where((v) => v).length;
      int totalRequired = 2 + (trip.partnerId != null ? 1 : 0) + trip.companions.length;

      return Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: CupertinoColors.systemOrange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text('ТОЧКА ${currentIndex + 1}/$totalPoints: ЖДЕМ $checkedInCount/$totalRequired',
              style: const TextStyle(
                  color: CupertinoColors.systemOrange,
                  fontWeight: FontWeight.w900,
                  fontSize: 11)),
        ),
      );
    } else {
      return CupertinoButton(
        color: const Color(0xFF6FBF4F),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(12),
        onPressed: isLoading ? null : () {
          FirestoreRepository.instance
              .checkInAtWaypoint(trip.id, currentIndex, roleKey)
              .timeout(const Duration(seconds: 3))
              .catchError((e) {
                if (!context.mounted) return;
                if (e is TimeoutException || e.toString().contains('Timeout')) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Отметка сохранена локально. Данные обновятся при появлении сети.'),
                    backgroundColor: CupertinoColors.systemGreen,
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              });
        },
        child: Text('ПОДТВЕРДИТЬ ТОЧКУ ${currentIndex + 1}/$totalPoints',
            style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontSize: 12)),
      );
    }
  }
}


class _OrderInfo extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _OrderInfo({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
