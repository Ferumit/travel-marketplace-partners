import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../models/booking_models.dart';
import '../../repository/firestore_repository.dart';
import 'work_widgets.dart'; // We will create this for InfoBadge

class AssignedTripsSection extends StatefulWidget {
  final bool isDark;
  final String uid;
  final bool isDriver;

  const AssignedTripsSection({
    super.key,
    required this.isDark,
    required this.uid,
    required this.isDriver,
  });

  @override
  State<AssignedTripsSection> createState() => _AssignedTripsSectionState();
}

class _AssignedTripsSectionState extends State<AssignedTripsSection> {
  String? _acceptingId;
  String? _decliningId;

  Future<void> _acceptOrder(ActiveTrip trip) async {
    if (_acceptingId != null || _decliningId != null) return;
    setState(() => _acceptingId = trip.id);
    try {
      if (widget.isDriver) {
        await FirestoreRepository.instance.acceptTrip(trip.id, trip.bookingId);
      } else {
        await FirestoreRepository.instance.acceptTripGuide(trip.id, trip.bookingId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Заказ принят! Вы можете начать поездку.'),
            backgroundColor: Color(0xFF6FBF4F),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка принятия заказа: $e'),
            backgroundColor: CupertinoColors.systemRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _acceptingId = null);
    }
  }

  Future<void> _declineOrder(ActiveTrip trip) async {
    if (_acceptingId != null || _decliningId != null) return;
    
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Отказаться от заказа?'),
        content: const Text('Заказ будет передан другим водителям.'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Отказаться'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _decliningId = trip.id);
    try {
      if (widget.isDriver) {
        await FirestoreRepository.instance.declineTrip(trip.id, trip.bookingId, widget.uid);
      } else {
        await FirestoreRepository.instance.declineGuide(trip.id, trip.bookingId, widget.uid);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Вы отказались от заказа.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка отказа от заказа: $e'),
            backgroundColor: CupertinoColors.systemRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _decliningId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = widget.isDriver 
        ? FirestoreRepository.instance.streamAssignedTrips(widget.uid)
        : FirestoreRepository.instance.streamAssignedGuideTrips(widget.uid);

    return StreamBuilder<List<ActiveTrip>>(
      stream: stream,
      builder: (context, snap) {
        final orders = snap.data ?? [];
        if (orders.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Назначенные мне',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: widget.isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemOrange,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${orders.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...orders.map((trip) {
              final isAccepting = _acceptingId == trip.id;
              final isDeclining = _decliningId == trip.id;
              final isBusy = isAccepting || isDeclining;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: widget.isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: CupertinoColors.systemOrange.withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: CupertinoColors.systemOrange.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemOrange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              CupertinoIcons.star_fill,
                              color: CupertinoColors.systemOrange,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              trip.customName?.isNotEmpty == true ? trip.customName! : 'Маршрут',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: widget.isDark ? Colors.white : Colors.black,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          InfoBadge(
                            icon: CupertinoIcons.location_solid,
                            label: '${trip.waypoints.length} точки',
                            isDark: widget.isDark,
                            color: CupertinoColors.systemOrange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              color: CupertinoColors.systemRed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              onPressed: isBusy ? null : () => _declineOrder(trip),
                              child: isDeclining
                                  ? const CupertinoActivityIndicator()
                                  : const Text(
                                      'Отказаться',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: CupertinoColors.systemRed,
                                        fontSize: 14,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              color: const Color(0xFF6FBF4F),
                              borderRadius: BorderRadius.circular(12),
                              onPressed: isBusy ? null : () => _acceptOrder(trip),
                              child: isAccepting
                                  ? const CupertinoActivityIndicator(color: Colors.white)
                                  : const Text(
                                      'Подтвердить',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
