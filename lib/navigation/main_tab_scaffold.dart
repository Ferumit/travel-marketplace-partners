import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../screens/group_screen.dart';
import '../screens/mesh_screen.dart';
import '../screens/overview_screen.dart';
import '../screens/route_screen.dart';
import '../services/location_permission_service.dart';
import '../theme/app_colors.dart';

/// Главный каркас с нижней навигацией Explora Partners.
///
/// Вкладки: Обзор · Маршрут · SOS (центральная кнопка) · Связь · Группа.
/// SOS — это действие (активация маяка), а не отдельный экран.
class MainTabScaffold extends StatefulWidget {
  const MainTabScaffold({super.key});

  /// Запрос на переключение вкладки из любого экрана.
  /// Индексы: 0 — Обзор, 1 — Маршрут, 2 — Связь, 3 — Группа.
  static final ValueNotifier<int> tabRequest = ValueNotifier<int>(0);

  /// Переключить активную вкладку программно.
  static void goToTab(int index) => tabRequest.value = index;

  @override
  State<MainTabScaffold> createState() => _MainTabScaffoldState();
}

class _MainTabScaffoldState extends State<MainTabScaffold> {
  int _currentIndex = 0;

  static const _screens = <Widget>[
    OverviewScreen(),
    RouteScreen(),
    MeshScreen(),
    GroupScreen(),
  ];

  @override
  void initState() {
    super.initState();
    MainTabScaffold.tabRequest.addListener(_onTabRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        LocationPermissionService.requestAll(context);
      }
    });
  }

  @override
  void dispose() {
    MainTabScaffold.tabRequest.removeListener(_onTabRequest);
    super.dispose();
  }

  void _onTabRequest() {
    final index = MainTabScaffold.tabRequest.value;
    if (mounted && index >= 0 && index < _screens.length) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _ExpeditionNavBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        onSos: () => context.push('/sos'),
      ),
    );
  }
}

class _ExpeditionNavBar extends StatelessWidget {
  const _ExpeditionNavBar({
    required this.currentIndex,
    required this.onTap,
    required this.onSos,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onSos;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.backgroundElevated,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset, top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NavItem(
            icon: LucideIcons.layoutGrid,
            label: 'Обзор',
            selected: currentIndex == 0,
            onTap: () => onTap(0),
          ),
          _NavItem(
            icon: LucideIcons.map,
            label: 'Маршрут',
            selected: currentIndex == 1,
            onTap: () => onTap(1),
          ),
          _SosNavButton(onTap: onSos),
          _NavItem(
            icon: LucideIcons.radio,
            label: 'Связь',
            selected: currentIndex == 2,
            onTap: () => onTap(2),
          ),
          _NavItem(
            icon: LucideIcons.users,
            label: 'Группа',
            selected: currentIndex == 3,
            onTap: () => onTap(3),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.textTertiary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SosNavButton extends StatelessWidget {
  const _SosNavButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.danger.withValues(alpha: 0.45),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Icon(LucideIcons.shield, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 5),
            const Text(
              'SOS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
