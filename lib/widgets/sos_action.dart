import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/mesh_service.dart';
import '../theme/app_colors.dart';

/// Показывает подтверждение и активирует SOS-маяк через MESH.
///
/// Сохраняет существующую бэкенд-логику: запускает MESH (если не запущен)
/// и вызывает [MeshService.activateBeacon], который ретранслирует сигнал
/// в Firebase при наличии интернета.
Future<void> showSosSheet(BuildContext context) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _SosSheet(),
  );

  if (confirmed != true) return;

  final mesh = MeshService.instance;
  if (!mesh.isStarted) {
    final user = FirebaseAuth.instance.currentUser;
    await mesh.start(
      roomId: 'explora-mesh',
      userId: user?.uid ?? '',
      userName: user?.displayName ?? 'Партнёр',
      apiKey: 'YOUR_BRIDGEFY_API_KEY',
    );
  }
  await mesh.activateBeacon();

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(
          'SOS-маяк активирован. Сигнал передаётся группе.',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _SosSheet extends StatelessWidget {
  const _SosSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.dangerSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.shieldAlert, color: AppColors.danger, size: 34),
            ),
            const SizedBox(height: 16),
            const Text(
              'Отправить сигнал SOS?',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Сигнал тревоги будет передан всем участникам колонны '
              'через MESH-сеть и продублирован в центр при наличии связи.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.45),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Отправить SOS'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Отмена',
                  style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
