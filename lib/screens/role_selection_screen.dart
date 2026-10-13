import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/partner_models.dart';
import '../repository/firestore_repository.dart';
import '../services/auth_service.dart';

/// Экран выбора роли — открывается для пользователей входящих через Google/Apple
/// у которых ещё нет PartnerProfile.
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool? _isGuideAccount;
  PartnerRole? _selectedRole;
  int _vehicleCapacity = 5;
  bool _isSaving = false;

  bool get _selectedRoleIsDriver =>
      _selectedRole == PartnerRole.suvDriver ||
      _selectedRole == PartnerRole.busDriver ||
      _selectedRole == PartnerRole.minibusDriver ||
      _selectedRole == PartnerRole.minivanDriver;

  int _defaultSeatsFor(PartnerRole role) {
    switch (role) {
      case PartnerRole.busDriver:
        return 30;
      case PartnerRole.minibusDriver:
        return 15;
      case PartnerRole.suvDriver:
        return 4;
      case PartnerRole.minivanDriver:
        return 7;
      default:
        return 5;
    }
  }

  int _maxSeatsFor(PartnerRole? role) {
    switch (role) {
      case PartnerRole.busDriver:
        return 30;
      case PartnerRole.minibusDriver:
        return 15;
      case PartnerRole.suvDriver:
      case PartnerRole.minivanDriver:
        return 7;
      default:
        return 10;
    }
  }

  Future<void> _save() async {
    if (_selectedRole == null || _isSaving) return;
    setState(() => _isSaving = true);

    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isSaving = false);
      return;
    }

    final capacity = _selectedRoleIsDriver ? _defaultSeatsFor(_selectedRole!) : 0;

    final profile = PartnerProfile(
      id: uid,
      firstName:
          AuthService.instance.currentUser?.displayName?.split(' ').first ?? '',
      lastName: '',
      email: AuthService.instance.currentUser?.email ?? '',
      role: _selectedRole!,
      vehicleCapacity: capacity,
      vehicleType: _selectedRole!.vehicleTypeCode,
    );

    await FirestoreRepository.instance.savePartner(profile);
    await AuthService.instance.refreshProfile();
  }

  List<Widget> _roleOptions(bool isDark) {
    final roles = [
      if (_isGuideAccount == true) ...[
        (PartnerRole.guide, 'Гид', 'Пешие эко-тропы',
            CupertinoIcons.person_crop_circle_badge_exclam),
        (PartnerRole.cityGuide, 'Городской гид', 'Обзорные экскурсии',
            CupertinoIcons.building_2_fill),
      ] else if (_isGuideAccount == false) ...[
        (PartnerRole.suvDriver, 'Водитель внедорожника', 'Экспедиции & оффроад',
            CupertinoIcons.car_fill),
        (PartnerRole.busDriver, 'Водитель автобуса', 'Крупные тур. группы',
            CupertinoIcons.bus),
        (PartnerRole.minibusDriver, 'Водитель микроавтобуса', 'Группы до 15 чел.',
            CupertinoIcons.tram_fill),
        (PartnerRole.minivanDriver, 'Водитель минивена', 'Комфорт до 7 мест',
            CupertinoIcons.car_detailed),
      ]
    ];

    return roles.map((entry) {
      final (role, title, subtitle, icon) = entry;
      final isSelected = _selectedRole == role;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GestureDetector(
          onTap: () => setState(() {
            _selectedRole = role;
            _vehicleCapacity = _defaultSeatsFor(role);
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF6FBF4F).withAlpha(30)
                  : (isDark ? CupertinoColors.darkBackgroundGray : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: isSelected
                  ? Border.all(color: const Color(0xFF6FBF4F), width: 1.5)
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF6FBF4F)
                        : (isDark
                              ? CupertinoColors.systemGrey5
                              : CupertinoColors.systemGrey6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon,
                      color: isSelected
                          ? Colors.white
                          : CupertinoColors.systemGrey,
                      size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          )),
                      Text(subtitle,
                          style: const TextStyle(
                              color: CupertinoColors.systemGrey, fontSize: 13)),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(CupertinoIcons.checkmark_circle_fill,
                      color: Color(0xFF6FBF4F)),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _typeCard({
    required bool isGuide,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
  }) {
    final isSelected = _isGuideAccount == isGuide;
    return GestureDetector(
      onTap: () => setState(() {
        _isGuideAccount = isGuide;
        _selectedRole = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6FBF4F).withAlpha(30)
              : (isDark ? CupertinoColors.darkBackgroundGray : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: isSelected
              ? Border.all(color: const Color(0xFF6FBF4F), width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF6FBF4F)
                    : (isDark ? CupertinoColors.systemGrey5 : CupertinoColors.systemGrey6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: isSelected ? Colors.white : CupertinoColors.systemGrey, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      )),
                  Text(subtitle,
                      style: const TextStyle(
                          color: CupertinoColors.systemGrey, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fixedCapacityCard({
    required bool isDark,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? CupertinoColors.darkBackgroundGray : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6FBF4F).withAlpha(60)),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.car_fill,
              color: Color(0xFF6FBF4F), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    )),
                const SizedBox(height: 2),
                Text(description,
                    style: const TextStyle(
                        color: CupertinoColors.systemGrey, fontSize: 12)),
              ],
            ),
          ),
          const Icon(CupertinoIcons.lock_fill,
              color: CupertinoColors.systemGrey, size: 16),
        ],
      ),
    );
  }

  Widget _seatsStepperCard({
    required bool isDark,
    required int seats,
    required int maxSeats,
    required VoidCallback? onDecrement,
    required VoidCallback? onIncrement,
  }) {
    final passengers = seats - 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? CupertinoColors.darkBackgroundGray : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6FBF4F).withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Количество мест в автомобиле',
              style: TextStyle(
                  color: CupertinoColors.systemGrey,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                onTap: onDecrement,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: onDecrement != null
                        ? const Color(0xFF6FBF4F)
                        : CupertinoColors.systemGrey5,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(CupertinoIcons.minus,
                      color: onDecrement != null
                          ? Colors.white
                          : CupertinoColors.systemGrey,
                      size: 18),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    Text('$seats',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : Colors.black)),
                    Text('$passengers пассажирских + 1 водительское',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: CupertinoColors.systemGrey, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: onIncrement,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: onIncrement != null
                        ? const Color(0xFF6FBF4F)
                        : CupertinoColors.systemGrey5,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(CupertinoIcons.plus,
                      color: onIncrement != null
                          ? Colors.white
                          : CupertinoColors.systemGrey,
                      size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      body: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(_isGuideAccount == null ? 'Тип аккаунта' : 'Выберите роль',
                style: TextStyle(
                    color: Theme.of(context).textTheme.displayLarge?.color)),
            backgroundColor: Colors.transparent,
            border: null,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_isGuideAccount == null ? 'Шаг 1 из 2' : 'Шаг 2 из 2',
                      style: const TextStyle(
                          color: Color(0xFF6FBF4F),
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                      _isGuideAccount == null
                          ? 'Выберите тип вашего профиля партнёра'
                          : 'Роль определяет ваши возможности в приложении',
                      style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black45,
                          fontSize: 13)),
                  const SizedBox(height: 20),

                  if (_isGuideAccount == null) ...[
                    _typeCard(
                      isGuide: true,
                      title: 'Я Гид',
                      subtitle: 'Пешие экскурсии, эко-тропы, города',
                      icon: CupertinoIcons.person_crop_circle_badge_exclam,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _typeCard(
                      isGuide: false,
                      title: 'Я Водитель',
                      subtitle: 'Трансфер, экспедиции, туры',
                      icon: CupertinoIcons.car_fill,
                      isDark: isDark,
                    ),
                  ] else ...[
                    ..._roleOptions(isDark),

                    // ── Seat capacity ──────────────────────────────────────────
                    if (_selectedRole == PartnerRole.suvDriver) ...[
                      const SizedBox(height: 16),
                      _fixedCapacityCard(
                        isDark: isDark,
                        title: 'Вместимость: 4 места',
                        description:
                            '1 водитель + 3 пассажира\n(или 1 водитель + 1 гид + 2 пассажира)',
                      ),
                    ] else if (_selectedRole == PartnerRole.minivanDriver) ...[
                      const SizedBox(height: 16),
                      _fixedCapacityCard(
                        isDark: isDark,
                        title: 'Вместимость: 7 мест',
                        description: '1 водитель + 1 гид + 5 пассажиров',
                      ),
                    ] else if (_selectedRole == PartnerRole.minibusDriver ||
                        _selectedRole == PartnerRole.busDriver) ...[
                      const SizedBox(height: 16),
                      _seatsStepperCard(
                        isDark: isDark,
                        seats: _vehicleCapacity,
                        maxSeats: _maxSeatsFor(_selectedRole),
                        onDecrement: _vehicleCapacity > 2
                            ? () => setState(() => _vehicleCapacity--)
                            : null,
                        onIncrement: _vehicleCapacity < _maxSeatsFor(_selectedRole)
                            ? () => setState(() => _vehicleCapacity++)
                            : null,
                      ),
                    ],

                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: _isSaving
                          ? const Center(child: CupertinoActivityIndicator())
                          : CupertinoButton(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              color: _selectedRole == null
                                  ? CupertinoColors.systemGrey4
                                  : const Color(0xFF6FBF4F),
                              borderRadius: BorderRadius.circular(14),
                              onPressed: _selectedRole == null ? null : _save,
                              child: const Text('Создать аккаунт',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 17)),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _isGuideAccount = null;
                          _selectedRole = null;
                        }),
                        child: Text(
                          '← Назад',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black54,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
