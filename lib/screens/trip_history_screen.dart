import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/booking_models.dart';
import '../repository/firestore_repository.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/review_sheet.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  Stream<List<ActiveTrip>>? _tripsStream;
  final String? _uid = AuthService.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    if (_uid != null) {
      _tripsStream = FirestoreRepository.instance.streamCompletedTripsByPartner(_uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? CupertinoColors.black : const Color(0xFFF2F2F7),
      body: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            largeTitle: Text(
              'История',
              style: TextStyle(
                color: Theme.of(context).textTheme.displayLarge?.color,
              ),
            ),
            backgroundColor: Colors.transparent,
            border: null,
          ),
          if (_uid == null)
            const SliverFillRemaining(
              child: Center(child: Text('Не авторизован')),
            )
          else
            SliverToBoxAdapter(
              child: StreamBuilder<List<ActiveTrip>>(
                stream: _tripsStream,
                builder: (context, tripsSnap) {
                  if (tripsSnap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CupertinoActivityIndicator()),
                    );
                  }

                  final trips = tripsSnap.data ?? [];

                  if (trips.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHigh.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: AppColors.textSecondary.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.accentMuted,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.accent.withValues(alpha: 0.2),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                CupertinoIcons.time,
                                color: AppColors.accentBright,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Нет выполненных заказов',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Ваши завершённые экспедиции и маршруты будут отображаться здесь.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            '${trips.length} заказов выполнено',
                            style: const TextStyle(
                              color: CupertinoColors.systemGrey,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        ...trips.map((trip) => _HistoryCard(
                          trip: trip,
                          isDark: isDark,
                        )),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatefulWidget {
  final ActiveTrip trip;
  final bool isDark;

  const _HistoryCard({required this.trip, required this.isDark});

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  late Future<Booking?> _bookingFuture;
  String _clientName = 'Клиент';

  @override
  void initState() {
    super.initState();
    _bookingFuture = FirestoreRepository.instance.getBookingById(widget.trip.bookingId);
    _bookingFuture.then((booking) {
      if (booking != null && mounted) {
        _fetchClientName(booking.userId);
      }
    });
  }

  Future<void> _fetchClientName(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (doc.exists && mounted) {
        final data = doc.data();
        if (data != null && data['displayName'] != null) {
          setState(() {
            _clientName = data['displayName'] as String;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching client name: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final isDark = widget.isDark;
    
    final name = trip.customName?.isNotEmpty == true ? trip.customName! : 'Маршрут';
    String dateLabel = trip.createdAt;
    try {
      final dt = DateTime.parse(trip.createdAt);
      final months = [
        '', 'янв', 'фев', 'мар', 'апр', 'май', 'июн',
        'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
      ];
      dateLabel = '${dt.day} ${months[dt.month]} ${dt.year}';
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FutureBuilder<Booking?>(
        future: _bookingFuture,
        builder: (context, bookingSnap) {
          final booking = bookingSnap.data;

          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status icon
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        CupertinoIcons.checkmark_seal_fill,
                        color: CupertinoColors.systemGreen,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Route info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateLabel,
                            style: const TextStyle(
                              color: CupertinoColors.systemGrey,
                              fontSize: 13,
                            ),
                          ),
                          if (trip.waypoints.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${trip.waypoints.length} точки маршрута',
                              style: const TextStyle(
                                color: CupertinoColors.systemGrey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Price
                    if (booking != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${booking.totalPrice.toStringAsFixed(0)} ₸',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: CupertinoColors.systemGreen,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${booking.participants} чел.',
                            style: const TextStyle(
                              color: CupertinoColors.systemGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      )
                    else if (bookingSnap.connectionState == ConnectionState.waiting)
                      const CupertinoActivityIndicator(radius: 10),
                  ],
                ),
                if (booking != null) ...[
                  const SizedBox(height: 16),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    onPressed: () => showReviewSheet(
                      context: context,
                      bookingId: booking.id,
                      targetId: booking.userId, // userId is the client ID in Booking model
                      targetName: _clientName, // Fetched client name
                      targetRole: 'client',
                    ),
                    child: Text(
                      'Оценить клиента',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );

        },
      ),
    );
  }
}