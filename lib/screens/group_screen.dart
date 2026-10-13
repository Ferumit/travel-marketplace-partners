import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/booking_models.dart';
import '../models/partner_models.dart';
import '../repository/firestore_repository.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/expedition_widgets.dart';

/// Экран «Группа» — состав колонны экспедиции.
///
/// Реальные данные:
///  • ведущий партнёр — [FirestoreRepository.streamPartner]
///  • участники (companions) — из активной поездки [ActiveTrip.companions]
///  • статус верификации — [PartnerProfile.isVerified] / [CompanionInfo.ready]
///
/// Телеметрия (сигнал, заряд, дистанция) пока не реализована в бэкенде и
/// показывается как нейтральный плейсхолдер, без выдуманных значений.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final String? _uid = AuthService.instance.currentUser?.uid;
  Stream<List<ActiveTrip>>? _tripsStream;

  @override
  void initState() {
    super.initState();
    if (_uid != null) {
      _tripsStream = FirestoreRepository.instance.streamAllTripsByPartner(_uid);
    }
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
            return StreamBuilder<List<ActiveTrip>>(
              stream: _tripsStream,
              builder: (context, tripSnap) {
                final trips = tripSnap.data ?? const [];
                final trip = trips
                    .where((t) => t.driverId == _uid ? t.driverAccepted : true)
                    .firstOrNull;
                final companions = trip?.companions ?? const <CompanionInfo>[];
                final memberCount =
                    companions.length + (profile != null ? 1 : 0);

                return CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _header(context, memberCount, trip),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        child: Column(
                          children: [
                            _selfCheckInCard(context, profile),
                            if (companions.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _groupReadinessCard(companions),
                            ],
                            const SizedBox(height: 16),
                            if (profile != null)
                              _MemberCard(
                                initials: _initials(
                                    profile.firstName, profile.lastName),
                                name: profile.fullName.trim().isEmpty
                                    ? 'Вы'
                                    : profile.fullName,
                                subtitle: _leadSubtitle(profile),
                                verified: profile.isVerified,
                                isLead: true,
                              ),
                            for (final c in companions) ...[
                              const SizedBox(height: 12),
                              _MemberCard(
                                initials: _initialsFromName(c.displayName),
                                name: c.displayName.isEmpty
                                    ? 'Участник'
                                    : c.displayName,
                                subtitle: 'Участник',
                                verified: c.ready,
                                isLead: false,
                                isAttention: !c.ready,
                              ),
                            ],
                            if (companions.isEmpty && profile != null) ...[
                              const SizedBox(height: 12),
                              _emptyMembers(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header(BuildContext context, int memberCount, ActiveTrip? trip) {
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
              GestureDetector(
                onTap: () => context.push('/profile'),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(LucideIcons.user,
                      color: AppColors.textPrimary, size: 20),
                ),
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
                    const Text(
                      'Группа',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(memberCount, trip),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Состав группы формируется при подтверждении брони'),
                  ),
                ),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.plus,
                      color: Color(0xFF0B1209), size: 22),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Собственный check-in партнёра ───────────────────────────────────────
  //
  // Раньше эта карточка одновременно показывала статистику готовности
  // СПУТНИКОВ («N подтверждено · M в ожидании») и кнопку «Сканировать»,
  // которая на деле открывала совсем другую функцию — селфи-проверку самого
  // партнёра. Разделено на два виджета, чтобы кнопка делала ровно то, что
  // написано рядом с ней (см. аудит, пункт 10).
  Widget _selfCheckInCard(BuildContext context, PartnerProfile? profile) {
    final due = profile?.checkInDue ?? true;

    return ExpeditionCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: due ? AppColors.warning.withValues(alpha: 0.14) : AppColors.accentMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(LucideIcons.scanFace,
                color: due ? AppColors.warning : AppColors.accentBright, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Check-in',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  due
                      ? 'Подтвердите личность фото — раз в 10 дней'
                      : 'Пройден, действует ещё несколько дней',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: const Color(0xFF0B1209),
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.radiusSm),
              ),
            ),
            onPressed: () => context.push(
              '/face-control',
              extra: {'role': profile?.role ?? PartnerRole.guide},
            ),
            child: Text(
              due ? 'Пройти check-in' : 'Повторить',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ── Готовность спутников ─────────────────────────────────────────────────
  //
  // Чисто информационная сводка — со сводки нельзя ничего "просканировать":
  // готовность (CompanionInfo.ready) выставляется на стороне клиентского
  // приложения, у водителя/гида здесь нет действия для её изменения.
  Widget _groupReadinessCard(List<CompanionInfo> companions) {
    final confirmed = companions.where((c) => c.ready).length;
    final pending = companions.length - confirmed;

    return ExpeditionCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            pending > 0 ? LucideIcons.clock : LucideIcons.userCheck,
            color: pending > 0 ? AppColors.warning : AppColors.accent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              pending > 0
                  ? 'Спутники: $confirmed подтвердили участие · $pending ещё не подтвердили'
                  : 'Все спутники ($confirmed) подтвердили участие',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyMembers() {
    return ExpeditionCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: const [
          Icon(LucideIcons.userPlus, color: AppColors.textTertiary, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Участники появятся после подтверждения брони клиентами.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  String _subtitle(int memberCount, ActiveTrip? trip) {
    final parts = <String>['$memberCount участников'];
    final code = _columnCode(trip);
    if (code != null) parts.add('колонна $code');
    return parts.join(' · ');
  }

  String? _columnCode(ActiveTrip? trip) {
    if (trip == null) return null;
    final src = trip.bookingId.isNotEmpty ? trip.bookingId : trip.id;
    if (src.isEmpty) return null;
    final tail = src.length >= 4 ? src.substring(src.length - 4) : src;
    return 'EXP-${tail.toUpperCase()}';
  }

  String _leadSubtitle(PartnerProfile p) {
    final role = p.role.displayName;
    if (p.role.isDriver && p.vehicleModel.isNotEmpty) {
      return '$role · ${p.vehicleModel}';
    }
    return role;
  }

  String _initials(String first, String last) {
    final f = first.isNotEmpty ? first[0] : '';
    final l = last.isNotEmpty ? last[0] : '';
    final res = '$f$l'.toUpperCase();
    return res.isEmpty ? '?' : res;
  }

  String _initialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

// ── Member card ──────────────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.initials,
    required this.name,
    required this.subtitle,
    required this.verified,
    required this.isLead,
    this.isAttention = false,
  });

  final String initials;
  final String name;
  final String subtitle;
  final bool verified;
  final bool isLead;
  final bool isAttention;

  @override
  Widget build(BuildContext context) {
    return ExpeditionCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar — красный для участников с флагом внимания
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isAttention
                  ? AppColors.danger.withValues(alpha: 0.12)
                  : isLead
                      ? AppColors.accentMuted
                      : AppColors.surfaceHigh,
              shape: BoxShape.circle,
              border: Border.all(
                color: isAttention
                    ? AppColors.danger.withValues(alpha: 0.4)
                    : isLead
                        ? AppColors.accent.withValues(alpha: 0.5)
                        : AppColors.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: TextStyle(
                color: isAttention
                    ? AppColors.danger
                    : isLead
                        ? AppColors.accentBright
                        : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Name + subtitle + status pill
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                if (isAttention)
                  const StatusPill(
                    label: 'Внимание',
                    color: AppColors.danger,
                    icon: LucideIcons.alertTriangle,
                  )
                else if (verified)
                  const StatusPill(
                    label: 'Верифицирован',
                    color: AppColors.accent,
                    icon: LucideIcons.shieldCheck,
                  )
                else
                  const StatusPill(
                    label: 'Ожидает подтверждения',
                    color: AppColors.warning,
                    icon: LucideIcons.clock,
                  ),
              ],
            ),
          ),
          // Telemetry placeholder (нет данных в бэкенде)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(
                LucideIcons.signal,
                color: isAttention
                    ? AppColors.danger.withValues(alpha: 0.5)
                    : AppColors.textTertiary,
                size: 16,
              ),
              const SizedBox(height: 14),
              Text(
                '—',
                style: TextStyle(
                  color: isAttention
                      ? AppColors.danger.withValues(alpha: 0.7)
                      : AppColors.textTertiary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
