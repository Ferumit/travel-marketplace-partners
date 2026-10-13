import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/trip_providers.dart';
import '../models/partner_models.dart';
import '../services/location_permission_service.dart';
import '../repository/firestore_repository.dart';
import '../models/booking_models.dart';
import '../navigation/main_tab_scaffold.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/work/guide_gallery_section.dart';
import '../widgets/work/assigned_trips_section.dart';
import '../widgets/work/available_orders_section.dart';
import '../models/offline_action.dart';
import '../services/sync_manager.dart';
import '../services/foreground_location_service.dart';
import '../widgets/work/metrics_grid.dart';
import '../widgets/work/work_banners.dart';
import '../widgets/work/active_order_section.dart';
import '../widgets/work/work_widgets.dart';
import 'vehicle_inspection_screen.dart';

class WorkScreen extends ConsumerStatefulWidget {
  const WorkScreen({super.key});

  @override
  ConsumerState<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends ConsumerState<WorkScreen> {
  // bool _isOnline = false; // Removed taxi-style toggle
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? CupertinoColors.systemRed : CupertinoColors.systemGreen,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  /*
  double _dist(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * 3.141592653589793 / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.asin(math.sqrt(a < 1 ? a : 1));
  }
  */

  Future<void> _markReady(ActiveTrip trip, Booking? booking, bool isDriver) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        if (mounted) {
          await LocationPermissionService.requestAll(context);
          perm = await Geolocator.checkPermission();
        }
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        _snack('Нет разрешения на геолокацию', isError: true);
        setState(() => _isLoading = false);
        return;
      }

      // Fire-and-forget update with a timeout for UI feedback
      FirestoreRepository.instance
          .setPartnerReady(trip.id, isDriver: isDriver)
          .timeout(const Duration(seconds: 3))
          .catchError((e) {
        if (e is TimeoutException || e.toString().contains('Timeout')) {
          _snack('Сохранено локально. Запрос будет отправлен при появлении сети.', isError: false);
        } else {
          debugPrint('Error in setPartnerReady: $e');
        }
      });

      // Try to re-read quickly to see if we can auto-start
      try {
        final latestTrip = await FirestoreRepository.instance
            .getTripById(trip.id)
            .timeout(const Duration(seconds: 2));

        if (latestTrip != null) {
          final hasGuide = latestTrip.guideId != null;
          final driverOk = isDriver ? true : latestTrip.driverReady;
          final guideOk = !hasGuide || (!isDriver ? true : latestTrip.guideReady);
          final companionsReady = latestTrip.companions.isEmpty || latestTrip.companions.every((c) => c.ready);

          if (driverOk && guideOk && latestTrip.clientReady && companionsReady) {
            SyncManager.instance.enqueueAction(OfflineAction(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              type: 'startTrip',
              payload: {'tripId': trip.id, 'bookingId': trip.bookingId},
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ));
            _snack('🚗 Все готовы! Маршрут начат.', isError: false);
            setState(() => _isLoading = false);
            return;
          }
        }
      } catch (_) {
        // Timeout fetching latest trip, just show optimistic success
      }

      _snack('✅ Готовность отмечена! Ожидаем остальных.', isError: false);
    } catch (e) {
      _snack('Ошибка: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finishTrip(ActiveTrip trip, {required bool isDriver}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      SyncManager.instance.enqueueAction(OfflineAction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'finishTrip',
        payload: {'tripId': trip.id, 'isDriver': isDriver},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
      if (mounted) {
        _snack('📨 Запрос отправлен — ожидаем подтверждения клиента', isError: false);
      }
    } catch (e) {
      if (mounted) _snack('Ошибка запроса завершения: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uid = ref.watch(authUserProvider).value;

    ref.listen<AsyncValue<ActiveTrip?>>(activeTripProvider, (prev, next) {
      final trip = next.value;
      if (trip?.status == TripStatus.inProgress) {
        ForegroundLocationService.instance.startTracking();
      } else if (trip == null || trip.status == TripStatus.completed) {
        ForegroundLocationService.instance.stopTracking();
      }
    });

    return Scaffold(
      backgroundColor: isDark ? CupertinoColors.black : const Color(0xFFF2F2F7),
      body: uid == null
          ? const Center(child: Text('Не авторизован'))
          : Consumer(
              builder: (context, ref, child) {
                final profileAsync = ref.watch(profileProvider);
                
                return profileAsync.when(
                  data: (profile) {
                    final isDriver = profile?.role.isDriver ?? false;
                    // checkInDue covers both "never verified" and "10-day check-in expired".
                    final needsFaceControl = profile == null || profile.checkInDue;

                    return CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverAppBar(
                      expandedHeight: 56,
                      toolbarHeight: 56,
                      backgroundColor: isDark ? CupertinoColors.black.withValues(alpha: 0.8) : const Color(0xFFF2F2F7).withValues(alpha: 0.8),
                      elevation: 0,
                      pinned: true,
                      leading: IconButton(
                        icon: Icon(LucideIcons.arrowLeft, color: Theme.of(context).textTheme.bodyLarge?.color),
                        onPressed: () => context.pop(),
                      ),
                      title: Text(
                        'Рабочий стол',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      centerTitle: true,
                      actions: [
                        GestureDetector(
                          onTap: () {
                            context.pop();
                            MainTabScaffold.goToTab(2);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              color: const Color(0xFF00E5FF).withValues(alpha: 0.12),
                              border: Border.all(
                                color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.wifi_tethering_rounded, color: Color(0xFF00E5FF), size: 14),
                                SizedBox(width: 5),
                                Text(
                                  'MESH',
                                  style: TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),

                            // ── Metrics Grid ───────────────────────────
                            // ── Online Toggle ─────────────────────────────
                            if (profile != null)
                              _OnlineToggleCard(isDark: isDark, profile: profile, uid: uid),
                            const SizedBox(height: 16),
                            MetricsGrid(isDark: isDark, profile: profile),
                            const SizedBox(height: 24),

                            // ── Face Control Reminder ────────────────────
                            if (needsFaceControl)
                              FaceControlReminder(
                                isDark: isDark,
                                role: profile?.role ?? PartnerRole.guide,
                              ),
                            if (needsFaceControl) const SizedBox(height: 16),

                            // ── Price per km (driver only) ────────────────
                            if (profile?.role.isDriver == true) ...[
                              _PricePerKmField(
                                isDark: isDark,
                                uid: uid,
                                currentPrice: profile?.pricePerKm,
                              ),
                              const SizedBox(height: 16),
                            ],

                            // ── Document Status Banner (driver only) ───────
                             DocumentStatusBanner(isDark: isDark, profile: profile),
                             const SizedBox(height: 16),

                             // ── Inspection / Certification Section ──────────────────
                             if (profile?.role.isDriver == true)
                               _InspectionSection(isDark: isDark, profile: profile),
                             if (profile?.role.isGuide == true) ...[
                               _GuideCertificateSection(isDark: isDark, profile: profile),
                               const SizedBox(height: 16),
                               GuideGallerySection(isDark: isDark, profile: profile),
                             ],
                             const SizedBox(height: 16),

                            // ── История button (full width) ───────────────
                            SizedBox(
                              width: double.infinity,
                              child: CupertinoButton(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                color: isDark
                                    ? CupertinoColors.darkBackgroundGray
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      CupertinoIcons.clock_fill,
                                      color: Color(0xFF6FBF4F),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'История поездок',
                                      style: TextStyle(
                                        color: Theme.of(context).textTheme.bodyLarge?.color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                onPressed: () => context.push('/history'),
                              ),
                            ),
                            const SizedBox(height: 32),


                            // ── Active Order / Available Orders / Locked ──
                            if (!needsFaceControl)
                              Consumer(
                                builder: (context, ref, child) {
                                  final activeTripAsync = ref.watch(activeTripProvider);
                                  
                                  return activeTripAsync.when(
                                    data: (activeTrip) {
                                      if (activeTrip != null) {
                                        return FutureBuilder<Booking?>(
                                          future: FirestoreRepository.instance.getBookingById(activeTrip.bookingId),
                                          builder: (context, bookingSnap) {
                                            return ActiveOrderSection(
                                              isDark: isDark,
                                              trip: activeTrip,
                                              booking: bookingSnap.data,
                                              isDriver: isDriver,
                                              isLoading: _isLoading,
                                              onMarkReady: _markReady,
                                              onFinishTrip: _finishTrip,
                                            );
                                          },
                                        );
                                      }

                                      if (profile.role.isDriver) {
                                        return Column(
                                          children: [
                                            AssignedTripsSection(
                                              isDark: isDark,
                                              uid: uid,
                                              isDriver: true,
                                            ),
                                            const SizedBox(height: 24),
                                            AvailableOrdersSection(
                                              isDark: isDark,
                                              uid: uid,
                                              driverName: '${profile.firstName} ${profile.lastName}'.trim(),
                                            ),
                                          ],
                                        );
                                      }

                                      if (profile.role.isGuide) {
                                        return Column(
                                          children: [
                                            AssignedTripsSection(
                                              isDark: isDark,
                                              uid: uid,
                                              isDriver: false,
                                            ),
                                            const SizedBox(height: 24),
                                            PlaceholderCard(
                                              isDark: isDark,
                                              icon: CupertinoIcons.tray_fill,
                                              text: 'Нет активных заказов. Новые предложения появятся в разделе «Маршрут».',
                                            ),
                                          ],
                                        );
                                      }

                                      return PlaceholderCard(
                                        isDark: isDark,
                                        icon: CupertinoIcons.tray_fill,
                                        text: 'Нет активных заказов. Новые предложения появятся в разделе «Маршрут».',
                                      );
                                    },
                                    loading: () => const Center(child: CupertinoActivityIndicator()),
                                    error: (e, st) => Center(child: Text('Ошибка загрузки поездок: $e')),
                                  );
                                },
                              )
                            else
                              PlaceholderCard(
                                isDark: isDark,
                                icon: CupertinoIcons.lock_fill,
                                text: 'Пройдите check-in, чтобы видеть заказы',
                              ),
                            const SizedBox(height: 32),

                            // Monthly Analytics — live from Firestore
                            const SizedBox(height: 8),
                            StreamBuilder<Map<String, dynamic>>(
                              stream: FirestoreRepository.instance.streamMonthlyStats(
                                uid,
                                isDriver: profile?.role.isDriver ?? true,
                              ),
                              builder: (context, statsSnap) {
                                final stats = statsSnap.data ?? {
                                  'count': 0,
                                  'avgEarnings': 0.0,
                                  'totalEarnings': 0.0,
                                };
                                final count = stats['count'] as int? ?? 0;
                                final avg = stats['avgEarnings'] as double? ?? 0.0;
                                final total = stats['totalEarnings'] as double? ?? 0.0;

                                final now = DateTime.now();
                                final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
                                final daysDone = now.day;
                                final progress = daysDone / daysInMonth;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Статистика за месяц',
                                          style: TextStyle(
                                            color: Theme.of(context).textTheme.bodyLarge?.color,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          '$daysDone / $daysInMonth д.',
                                          style: const TextStyle(
                                            color: CupertinoColors.systemGrey,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // Month progress bar
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 4,
                                        backgroundColor: isDark ? Colors.white12 : Colors.black12,
                                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6FBF4F)),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? CupertinoColors.darkBackgroundGray
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: CupertinoListSection.insetGrouped(
                                        backgroundColor: Colors.transparent,
                                        margin: EdgeInsets.zero,
                                        children: [
                                          CupertinoListTile(
                                            title: Text(
                                              'Заказы выполнено',
                                              style: TextStyle(
                                                color: Theme.of(context).textTheme.bodyLarge?.color,
                                              ),
                                            ),
                                            additionalInfo: statsSnap.connectionState == ConnectionState.waiting
                                                ? const CupertinoActivityIndicator()
                                                : Text(
                                                    '$count',
                                                    style: TextStyle(
                                                      color: Theme.of(context).textTheme.bodyLarge?.color,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                          ),
                                          CupertinoListTile(
                                            title: Text(
                                              'Средний чек',
                                              style: TextStyle(
                                                color: Theme.of(context).textTheme.bodyLarge?.color,
                                              ),
                                            ),
                                            additionalInfo: statsSnap.connectionState == ConnectionState.waiting
                                                ? const CupertinoActivityIndicator()
                                                : Text(
                                                    count == 0 ? '—' : '${_formatCurrency(avg)} ₸',
                                                    style: TextStyle(
                                                      color: Theme.of(context).textTheme.bodyLarge?.color,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                          ),
                                          CupertinoListTile(
                                            title: Text(
                                              'Итого за месяц',
                                              style: TextStyle(
                                                color: Theme.of(context).textTheme.bodyLarge?.color,
                                              ),
                                            ),
                                            additionalInfo: statsSnap.connectionState == ConnectionState.waiting
                                                ? const CupertinoActivityIndicator()
                                                : Text(
                                                    count == 0 ? '—' : '${_formatCurrency(total)} ₸',
                                                    style: const TextStyle(
                                                      color: Color(0xFF6FBF4F),
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CupertinoActivityIndicator()),
              error: (e, st) => Center(child: Text('Ошибка загрузки профиля: $e')),
            );
          },
        ),
      ); // end Scaffold
  }

  /// Formats a double as a currency string with space thousands separator.
  String _formatCurrency(double value) {
    final intVal = value.toInt();
    return intVal.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]} ',
    );
  }
}

class _BalanceLimitField extends StatefulWidget {
  final bool isDark;
  const _BalanceLimitField({required this.isDark});

  @override
  State<_BalanceLimitField> createState() => _BalanceLimitFieldState();
}

class _BalanceLimitFieldState extends State<_BalanceLimitField> {
  final _ctrl = TextEditingController(text: '10,000');

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Лимит баланса:',
          style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 13),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: CupertinoTextField(
            controller: _ctrl,
            placeholder: '0',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.isDark ? Colors.white : Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            decoration: BoxDecoration(
              color: widget.isDark ? Colors.black26 : Colors.white54,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          ),
        ),
        const SizedBox(width: 4),
        const Text('₸', style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 13)),
      ],
    );
  }
}

class _PricePerKmField extends StatefulWidget {
  final bool isDark;
  final String uid;
  final double? currentPrice;

  const _PricePerKmField({
    required this.isDark,
    required this.uid,
    required this.currentPrice,
  });

  @override
  State<_PricePerKmField> createState() => _PricePerKmFieldState();
}

class _PricePerKmFieldState extends State<_PricePerKmField> {
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.currentPrice != null && widget.currentPrice! > 0
          ? widget.currentPrice!.toStringAsFixed(0)
          : '',
    );
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _save();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() {
    final val = double.tryParse(_ctrl.text.trim());
    if (val != null) {
      FirestoreRepository.instance.updatePartner(widget.uid, {'pricePerKm': val});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Цена за 1 км:',
          style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 13),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: CupertinoTextField(
            controller: _ctrl,
            focusNode: _focus,
            placeholder: '0',
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            onSubmitted: (_) => _save(),
            style: TextStyle(
              color: widget.isDark ? Colors.white : Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            decoration: BoxDecoration(
              color: widget.isDark ? Colors.black26 : Colors.white54,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          ),
        ),
        const SizedBox(width: 4),
        const Text('₸', style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 13)),
      ],
    );
  }
}

class _GuideCertificateSection extends StatelessWidget {
  final bool isDark;
  final PartnerProfile? profile;

  const _GuideCertificateSection({required this.isDark, this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile == null) return const SizedBox.shrink();
    
    final uploaded = profile!.guideCertificateUrl != null;
    final verified = profile!.guideCertificateVerified;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (verified) {
      statusText = 'Подтверждено ✓';
      statusColor = CupertinoColors.systemGreen;
      statusIcon = CupertinoIcons.checkmark_seal_fill;
    } else if (uploaded) {
      statusText = 'На рассмотрении';
      statusColor = CupertinoColors.systemOrange;
      statusIcon = CupertinoIcons.clock_fill;
    } else {
      statusText = 'Добавьте Сертификат гида';
      statusColor = CupertinoColors.systemRed;
      statusIcon = CupertinoIcons.exclamationmark_circle_fill;
    }

    return GestureDetector(
      onTap: () => context.push('/guide-documents'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.25),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(CupertinoIcons.doc_plaintext, color: Color(0xFF6FBF4F), size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Сертификат гида',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, color: statusColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(CupertinoIcons.chevron_right, color: CupertinoColors.systemGrey3, size: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectionSection extends StatelessWidget {
  final bool isDark;
  final PartnerProfile? profile;

  const _InspectionSection({required this.isDark, this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile == null) return const SizedBox.shrink();
    
    final isVerified = profile!.vehicleInspectionVerified;
    final statusText = isVerified ? 'Подтверждено ✓' : 'Требуется проверка';
    final statusColor = isVerified ? CupertinoColors.systemGreen : CupertinoColors.systemRed;
    final statusIcon = isVerified ? CupertinoIcons.checkmark_seal_fill : CupertinoIcons.exclamationmark_circle_fill;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (_) => VehicleInspectionScreen(profile: profile),
          fullscreenDialog: true,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.25),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(CupertinoIcons.camera_viewfinder, color: Color(0xFF6FBF4F), size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Фотоконтроль',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, color: statusColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(CupertinoIcons.chevron_right, color: CupertinoColors.systemGrey3, size: 14),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
class _OnlineToggleCard extends StatelessWidget {
  final bool isDark;
  final PartnerProfile profile;
  final String uid;

  const _OnlineToggleCard({required this.isDark, required this.profile, required this.uid});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: profile.isOnline ? const Color(0xFF6FBF4F).withValues(alpha: 0.4) : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05))),
        boxShadow: [
          BoxShadow(
            color: profile.isOnline ? const Color(0xFF6FBF4F).withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: profile.isOnline ? const Color(0xFF6FBF4F).withValues(alpha: 0.15) : CupertinoColors.systemGrey.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  profile.isOnline ? CupertinoIcons.bolt_fill : CupertinoIcons.bolt_slash_fill,
                  color: profile.isOnline ? const Color(0xFF6FBF4F) : CupertinoColors.systemGrey,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.isOnline ? 'На линии' : 'Оффлайн',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: profile.isOnline ? const Color(0xFF6FBF4F) : (isDark ? Colors.white : Colors.black),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile.isOnline ? 'Вы получаете заказы' : 'Заказы не поступают',
                    style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
                  ),
                ],
              ),
            ],
          ),
          CupertinoSwitch(
            value: profile.isOnline,
            activeColor: const Color(0xFF6FBF4F),
            onChanged: (val) {
              FirestoreRepository.instance.updatePartner(uid, {'isOnline': val});
            },
          ),
        ],
      ),
    );
  }
}
