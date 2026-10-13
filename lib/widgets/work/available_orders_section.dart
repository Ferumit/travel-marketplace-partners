import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/booking_models.dart';
import '../../repository/firestore_repository.dart';
import '../../utils/route_calculator.dart';
import 'work_widgets.dart'; // For InfoBadge and PlaceholderCard

class AvailableOrdersSection extends StatefulWidget {
  final bool isDark;
  final String uid;
  final String driverName;

  const AvailableOrdersSection({
    super.key,
    required this.isDark,
    required this.uid,
    required this.driverName,
  });

  @override
  State<AvailableOrdersSection> createState() => _AvailableOrdersSectionState();
}

class _AvailableOrdersSectionState extends State<AvailableOrdersSection> {
  String? _acceptingId;
  // Пропущенные заказы скрываются только у этого партнёра на время сессии —
  // лента общая для всех водителей/гидов, поэтому "пропустить" не должно
  // убирать заказ у остальных.
  final Set<String> _dismissedIds = {};
  Position? _lastPosition;

  @override
  void initState() {
    super.initState();
    _loadLastPosition();
  }

  Future<void> _loadLastPosition() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (mounted && pos != null) setState(() => _lastPosition = pos);
    } catch (_) {
      // Нет разрешения / недоступно — карточки просто не покажут расстояние до подачи.
    }
  }

  Future<void> _acceptOrder(ActiveTrip trip) async {
    if (_acceptingId != null) return;
    setState(() => _acceptingId = trip.id);
    try {
      await FirestoreRepository.instance.claimAvailableOrder(
        trip.id,
        trip.bookingId,
        widget.uid,
        widget.driverName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Заказ принят! Детали появятся выше.'),
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

  Future<void> _counterOffer(Booking booking) async {
    final ctrl = TextEditingController(
      text: booking.totalPrice > 0 ? booking.totalPrice.toStringAsFixed(0) : '',
    );
    final price = await showCupertinoDialog<double>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Своя цена'),
        content: Column(
          children: [
            const SizedBox(height: 10),
            Text('Пассажир предложил ${booking.totalPrice.toStringAsFixed(0)} ₸. Укажите свою цену:',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              placeholder: 'Цена в тенге',
              autofocus: true,
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Отмена'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Отправить'),
            onPressed: () {
              final val = double.tryParse(ctrl.text.trim());
              Navigator.pop(ctx, val);
            },
          ),
        ],
      ),
    );
    if (price == null || price <= 0 || !mounted) return;

    try {
      await FirestoreRepository.instance.proposeCounterOffer(
        booking.id,
        price: price,
        proposedBy: widget.uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Предложение отправлено пассажиру'),
            backgroundColor: Color(0xFF6FBF4F),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось отправить предложение: $e')),
        );
      }
    }
  }

  Future<void> _withdrawCounterOffer(Booking booking) async {
    try {
      await FirestoreRepository.instance.withdrawCounterOffer(booking.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось отменить предложение: $e')),
        );
      }
    }
  }

  void _dismiss(String tripId) => setState(() => _dismissedIds.add(tripId));

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActiveTrip>>(
      stream: FirestoreRepository.instance.streamAvailableOrders(),
      builder: (context, snap) {
        final orders = (snap.data ?? [])
            .where((t) => !_dismissedIds.contains(t.id))
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Доступные заказы',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: widget.isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(width: 8),
                if (orders.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6FBF4F),
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

            if (snap.connectionState == ConnectionState.waiting)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CupertinoActivityIndicator(),
              ))
            else if (orders.isEmpty)
              PlaceholderCard(
                isDark: widget.isDark,
                icon: CupertinoIcons.tray_fill,
                text: 'Нет доступных заказов. Обновления придут автоматически.',
              )
            else
              ...orders.map((trip) => _OrderCard(
                key: ValueKey(trip.id),
                trip: trip,
                isDark: widget.isDark,
                myUid: widget.uid,
                lastPosition: _lastPosition,
                isAccepting: _acceptingId == trip.id,
                onAccept: _acceptingId == null ? () => _acceptOrder(trip) : null,
                onCounterOffer: _counterOffer,
                onWithdrawCounterOffer: _withdrawCounterOffer,
                onDismiss: () => _dismiss(trip.id),
              )),
          ],
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final ActiveTrip trip;
  final bool isDark;
  final String myUid;
  final Position? lastPosition;
  final bool isAccepting;
  final VoidCallback? onAccept;
  final void Function(Booking booking) onCounterOffer;
  final void Function(Booking booking) onWithdrawCounterOffer;
  final VoidCallback onDismiss;

  const _OrderCard({
    super.key,
    required this.trip,
    required this.isDark,
    required this.myUid,
    required this.lastPosition,
    required this.isAccepting,
    required this.onCounterOffer,
    required this.onWithdrawCounterOffer,
    required this.onDismiss,
    this.onAccept,
  });

  double? get _tripDistanceKm {
    if (trip.waypoints.length < 2) return null;
    double total = 0;
    for (var i = 0; i < trip.waypoints.length - 1; i++) {
      total += RouteCalculator.calculateDistance(
        trip.waypoints[i].latitude,
        trip.waypoints[i].longitude,
        trip.waypoints[i + 1].latitude,
        trip.waypoints[i + 1].longitude,
      );
    }
    return total;
  }

  double? get _pickupDistanceKm {
    final pos = lastPosition;
    if (pos == null || trip.waypoints.isEmpty) return null;
    final first = trip.waypoints.first;
    return RouteCalculator.calculateDistance(
      pos.latitude, pos.longitude, first.latitude, first.longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = trip.customName?.isNotEmpty == true ? trip.customName! : 'Маршрут';
    final dateRaw = trip.createdAt;
    String dateLabel = dateRaw;
    try {
      final dt = DateTime.parse(dateRaw);
      dateLabel = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StreamBuilder<Booking?>(
        stream: FirestoreRepository.instance.streamBookingById(trip.bookingId),
        builder: (context, bookingSnap) {
          final booking = bookingSnap.data;
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF6FBF4F).withValues(alpha: 0.2),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6FBF4F).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        CupertinoIcons.map_fill,
                        color: Color(0xFF6FBF4F),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '📅 $dateLabel',
                            style: const TextStyle(
                              color: CupertinoColors.systemGrey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (booking != null && booking.totalPrice > 0)
                      Text(
                        '${booking.totalPrice.toStringAsFixed(0)} ₸',
                        style: const TextStyle(
                          color: Color(0xFF6FBF4F),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // Mini route summary — точка А → точка Б
                if (trip.waypoints.isNotEmpty) ...[
                  _RouteSummary(waypoints: trip.waypoints, isDark: isDark),
                  const SizedBox(height: 10),
                ],

                // Info row: distances, rating
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    InfoBadge(
                      icon: CupertinoIcons.location_solid,
                      label: '${trip.waypoints.length} точки',
                      isDark: isDark,
                    ),
                    if (_pickupDistanceKm != null)
                      InfoBadge(
                        icon: CupertinoIcons.arrow_right_arrow_left,
                        label: 'До подачи ${_pickupDistanceKm!.toStringAsFixed(1)} км',
                        isDark: isDark,
                      ),
                    if (_tripDistanceKm != null)
                      InfoBadge(
                        icon: CupertinoIcons.speedometer,
                        label: '${_tripDistanceKm!.toStringAsFixed(0)} км в пути',
                        isDark: isDark,
                      ),
                    if (booking?.passengerRating != null)
                      InfoBadge(
                        icon: CupertinoIcons.star_fill,
                        label: booking!.passengerRating!.toStringAsFixed(1),
                        isDark: isDark,
                        color: CupertinoColors.systemYellow,
                      ),
                    InfoBadge(
                      icon: CupertinoIcons.circle_fill,
                      label: trip.status == TripStatus.scheduled ? 'Новый' : trip.status.value,
                      isDark: isDark,
                      color: CupertinoColors.systemGreen,
                    ),
                  ],
                ),

                if (booking?.comments != null && booking!.comments!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(CupertinoIcons.text_bubble, size: 14, color: CupertinoColors.systemGrey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            booking.comments!,
                            style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 13, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                _actions(context, booking),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _actions(BuildContext context, Booking? booking) {
    // Партнёр уже отправил встречное предложение по этому заказу — ждём ответа пассажира.
    if (booking != null &&
        booking.status == BookingStatus.counterOffered &&
        booking.counterOfferBy == myUid) {
      return Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: BoxDecoration(
                color: CupertinoColors.systemOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Предложено ${booking.counterOfferPrice?.toStringAsFixed(0)} ₸ — ждём ответ',
                style: const TextStyle(color: CupertinoColors.systemOrange, fontSize: 13, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            color: CupertinoColors.systemGrey5,
            borderRadius: BorderRadius.circular(12),
            onPressed: () => onWithdrawCounterOffer(booking),
            child: const Text('Отменить', style: TextStyle(fontSize: 13, color: CupertinoColors.black)),
          ),
        ],
      );
    }

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 14),
            color: const Color(0xFF6FBF4F),
            borderRadius: BorderRadius.circular(12),
            onPressed: onAccept,
            child: isAccepting
                ? const CupertinoActivityIndicator(color: Colors.white)
                : Text(
                    booking != null && booking.totalPrice > 0
                        ? 'Принять за ${booking.totalPrice.toStringAsFixed(0)} ₸'
                        : 'Принять заказ',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                onPressed: booking == null ? null : () => onCounterOffer(booking),
                child: Text(
                  'Своя цена',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 12),
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                onPressed: onDismiss,
                child: Text(
                  'Пропустить',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Компактная сводка маршрута "точка А → точка Б" вместо полноценной карты —
/// живая карта на каждой карточке в прокручиваемой ленте была бы слишком
/// дорогой (много одновременных инстансов Yandex MapKit).
class _RouteSummary extends StatelessWidget {
  final List<MeetingPoint> waypoints;
  final bool isDark;

  const _RouteSummary({required this.waypoints, required this.isDark});

  String _label(MeetingPoint wp) {
    if (wp.address.isNotEmpty) return wp.address;
    return '${wp.latitude.toStringAsFixed(3)}, ${wp.longitude.toStringAsFixed(3)}';
  }

  @override
  Widget build(BuildContext context) {
    final from = _label(waypoints.first);
    final to = _label(waypoints.last);
    final color = isDark ? Colors.white70 : Colors.black87;
    return Row(
      children: [
        Expanded(
          child: Text(from, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(CupertinoIcons.arrow_right, size: 14, color: CupertinoColors.systemGrey),
        ),
        Expanded(
          child: Text(to, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
