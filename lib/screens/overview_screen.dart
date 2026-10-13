import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/booking_models.dart';
import '../models/partner_models.dart';
import '../navigation/main_tab_scaffold.dart';
import '../repository/firestore_repository.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/expedition_widgets.dart';

/// База — главный обзорный экран партнёра (таб «Обзор»).
///
/// Данные берутся из проверенных стримов:
///  • [FirestoreRepository.streamPartner] — профиль партнёра
///  • [FirestoreRepository.streamAllTripsByPartner] — активные поездки
///  • [FirestoreRepository.getBookingById] — детали брони
///
/// Телеметрия, которой пока нет в бэкенде (скорость, высота, погода, заряд
/// участников), показывается как аккуратные плейсхолдеры и НЕ подменяется
/// выдуманными данными.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  Stream<List<ActiveTrip>>? _tripsStream;
  final String? _uid = AuthService.instance.currentUser?.uid;

  // Кэш future брони, чтобы он НЕ пересоздавался на каждом ребилде стрима
  // (иначе FutureBuilder мерцает и сбрасывает позицию скролла).
  String? _bookingFutureId;
  Future<Booking?>? _bookingFuture;

  @override
  void initState() {
    super.initState();
    if (_uid != null) {
      _tripsStream = FirestoreRepository.instance.streamAllTripsByPartner(_uid);
    }
  }

  /// Возвращает закэшированный future брони для [bookingId]; пересоздаёт его
  /// только если идентификатор изменился.
  Future<Booking?> _bookingFutureFor(String bookingId) {
    if (_bookingFutureId != bookingId || _bookingFuture == null) {
      _bookingFutureId = bookingId;
      _bookingFuture =
          FirestoreRepository.instance.getBookingById(bookingId);
    }
    return _bookingFuture!;
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(
        body: Center(
          child: Text('Не авторизован',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<PartnerProfile?>(
          stream: FirestoreRepository.instance.streamPartner(_uid),
          builder: (context, profileSnap) {
            final profile = profileSnap.data;
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(child: _header(context, profile)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: GestureDetector(
                      onTap: () => context.push('/work'),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(LucideIcons.briefcase, color: AppColors.accentBright, size: 20),
                            const SizedBox(width: 10),
                            const Text(
                              'Рабочий стол',
                              style: TextStyle(
                                color: AppColors.accentBright,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (profile?.role.isGuide == true)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: _GuideStatusCard(profile: profile),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: StreamBuilder<List<ActiveTrip>>(
                      stream: _tripsStream,
                      builder: (context, tripSnap) {
                        final trips = tripSnap.data ?? const [];
                        final activeTrip = trips
                            .where((t) =>
                                (t.driverId == _uid ? t.driverAccepted : true) &&
                                (t.guideId == _uid ? t.guideAccepted : true))
                            .firstOrNull;

                        if (activeTrip == null) {
                          return _noTripState(context, profile);
                        }

                        return FutureBuilder<Booking?>(
                          future: _bookingFutureFor(activeTrip.bookingId),
                          builder: (context, bookingSnap) {
                            return _activeContent(
                              context,
                              trip: activeTrip,
                              booking: bookingSnap.data,
                              profile: profile,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header(BuildContext context, PartnerProfile? profile) {
    final firstName =
        profile?.firstName.isNotEmpty == true ? profile!.firstName : 'партнёр';
    final initials = _initials(profile);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'EP',
                  style: TextStyle(
                    color: Color(0xFF0B1209),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Explora',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const Spacer(),
              _circleButton(
                icon: LucideIcons.user,
                onTap: () => context.push('/profile'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Добрый день, $firstName',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'База',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.accentMuted,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
                  image: profile?.photoUrl != null
                      ? DecorationImage(
                          image: NetworkImage(profile!.photoUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: profile?.photoUrl == null
                    ? Text(
                        initials,
                        style: const TextStyle(
                          color: AppColors.accentBright,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Active trip content ─────────────────────────────────────────────────

  Widget _activeContent(
    BuildContext context, {
    required ActiveTrip trip,
    required Booking? booking,
    required PartnerProfile? profile,
  }) {
    final title = trip.customName?.isNotEmpty == true
        ? trip.customName!
        : (booking?.routeTitle.isNotEmpty == true
            ? booking!.routeTitle
            : 'Текущая экспедиция');

    final waypoints = trip.waypoints.isNotEmpty
        ? trip.waypoints
        : (booking?.waypoints ?? const <MeetingPoint>[]);
    final totalPoints = waypoints.length;
    final donePoints = trip.currentWaypointIndex.clamp(0, totalPoints);
    final progress = totalPoints > 0 ? donePoints / totalPoints : 0.0;
    final nextPoint = totalPoints > donePoints ? waypoints[donePoints] : null;

    final dayInfo = _dayInfo(booking);
    final inProgress = trip.status == TripStatus.inProgress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Активная поездка ──
        ExpeditionCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusPill(
                    label: inProgress ? 'АКТИВНАЯ ПОЕЗДКА' : 'ОЖИДАНИЕ',
                    color: inProgress ? AppColors.accent : AppColors.warning,
                  ),
                  const Spacer(),
                  Text(
                    _tripCode(booking, trip),
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (dayInfo != null) dayInfo,
                  if (nextPoint != null && nextPoint.address.isNotEmpty)
                    'до точки «${nextPoint.address}»',
                ].join(' · '),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Точка $donePoints из $totalPoints',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(progress * 100).round()}%',
                    style: const TextStyle(
                      color: AppColors.accentBright,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: AppColors.surfaceHigh,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.accent),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        const SizedBox(height: 14),

        // ── Карточка внимания (если есть неготовые участники) ──
        if (_attentionCompanion(trip) case final attn?) ...[
          _attentionCard(context, attn),
          const SizedBox(height: 14),
        ],

        // ── Группа (реальные данные из companions) ──
        _groupCard(context, trip),
        const SizedBox(height: 14),

        // ── Быстрые действия ──
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: LucideIcons.map,
                label: 'Маршрут',
                onTap: () => MainTabScaffold.goToTab(1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionTile(
                icon: LucideIcons.radio,
                label: 'Связь',
                onTap: () => MainTabScaffold.goToTab(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionTile(
                icon: LucideIcons.clock,
                label: 'История',
                onTap: () => context.push('/history'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── No active trip ────────────────────────────────────────────────────────

  Widget _noTripState(BuildContext context, PartnerProfile? profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
                  LucideIcons.compass,
                  color: AppColors.accentBright,
                  size: 32,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Нет активной экспедиции',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Новые заказы и предложения появятся в разделе «Маршрут». Включите «На линии», чтобы получать заказы.',
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
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: LucideIcons.map,
                label: 'Маршрут',
                onTap: () => MainTabScaffold.goToTab(1),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Group card ──────────────────────────────────────────────────────────

  Widget _groupCard(BuildContext context, ActiveTrip trip) {
    final companions = trip.companions;
    final total = companions.length + 1; // +ведущий партнёр
    final readyCount = companions.where((c) => c.ready).length;

    return ExpeditionCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.users,
                  color: AppColors.accentBright, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Группа',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => MainTabScaffold.goToTab(3),
                child: const Text(
                  'Все участники',
                  style: TextStyle(
                    color: AppColors.accentBright,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: -8,
                  children: [
                    for (final c in companions.take(5))
                      _miniAvatar(_initialsFromName(c.displayName)),
                    if (companions.length > 5)
                      _miniAvatar('+${companions.length - 5}', highlight: true),
                    if (companions.isEmpty)
                      const Text(
                        'Участники появятся после подтверждения брони',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              if (companions.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$readyCount/$total',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'готовы',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Attention card ───────────────────────────────────────────────────

  /// Возвращает первого участника с [ready == false], или null.
  CompanionInfo? _attentionCompanion(ActiveTrip trip) {
    return trip.companions.where((c) => !c.ready).firstOrNull;
  }

  Widget _attentionCard(BuildContext context, CompanionInfo companion) {
    return GestureDetector(
      onTap: () => MainTabScaffold.goToTab(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(LucideIcons.alertTriangle, color: AppColors.danger, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${companion.displayName.isEmpty ? 'Участник' : companion.displayName}: Требует внимания',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Не прошёл Face Control · Нажмите для просмотра',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, color: AppColors.danger, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Small helpers / widgets ────────────────────────────────────────────

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 20),
      ),
    );
  }

  Widget _miniAvatar(String text, {bool highlight = false}) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: highlight ? AppColors.accent : AppColors.surfaceHigh,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.background, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: highlight ? const Color(0xFF0B1209) : AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _initials(PartnerProfile? p) {
    if (p == null) return '—';
    final f = p.firstName.isNotEmpty ? p.firstName[0] : '';
    final l = p.lastName.isNotEmpty ? p.lastName[0] : '';
    final res = '$f$l'.toUpperCase();
    return res.isEmpty ? '—' : res;
  }

  String _initialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  String _tripCode(Booking? booking, ActiveTrip trip) {
    final src = (booking?.id.isNotEmpty == true ? booking!.id : trip.id);
    if (src.isEmpty) return 'EXP';
    final tail = src.length >= 4 ? src.substring(src.length - 4) : src;
    return 'EXP-${tail.toUpperCase()}';
  }

  /// «День X из Y» по датам брони, либо null если данных нет.
  String? _dayInfo(Booking? booking) {
    if (booking == null) return null;
    final start = DateTime.tryParse(booking.startDate);
    final end = DateTime.tryParse(booking.endDate);
    if (start == null || end == null) return null;
    final totalDays = end.difference(start).inDays + 1;
    if (totalDays <= 0) return null;
    final dayIndex =
        (DateTime.now().difference(start).inDays + 1).clamp(1, totalDays);
    return 'День $dayIndex из $totalDays';
  }

  String _etaValue(ActiveTrip trip) {
    final eta = trip.estimatedArrivalTime;
    if (eta == null || eta.isEmpty) return '—';
    final mins = int.tryParse(eta);
    if (mins != null) return '$mins';
    return eta;
  }

  String _etaUnit(ActiveTrip trip) {
    final eta = trip.estimatedArrivalTime;
    if (eta == null || eta.isEmpty) return '';
    return int.tryParse(eta) != null ? 'мин' : '';
  }
}

// ── Reusable tiles ──────────────────────────────────────────────────────────

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ExpeditionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 18),
          const SizedBox(height: 14),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ExpeditionCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.accentBright, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Guide Status Card ───────────────────────────────────────────────────

class _GuideStatusCard extends StatelessWidget {
  final PartnerProfile? profile;

  const _GuideStatusCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile == null) return const SizedBox.shrink();

    final isVerified = profile!.guideCertificateVerified;
    final regions = profile!.tourAreas.isNotEmpty
        ? profile!.tourAreas.join(', ')
        : 'Районы не указаны';

    return ExpeditionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.mapPin,
                color: AppColors.accentBright,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Статус Гида',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (isVerified)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'ВЕРИФИЦИРОВАН',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'НЕ ПОДТВЕРЖДЕН',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Регионы',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      regions,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Макс. группа',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile!.maxGroupSize > 0 ? profile!.maxGroupSize : 15} чел.',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
