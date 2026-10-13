import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/partner_models.dart';
import '../repository/firestore_repository.dart';
import '../services/auth_service.dart';
import '../services/firebase_storage_service.dart';
import '../theme/app_colors.dart';

// ══════════════════════════════════════════════════════════════════════════════
// GuideDocumentsScreen — экран верификации документов гида
// ══════════════════════════════════════════════════════════════════════════════

class GuideDocumentsScreen extends StatelessWidget {
  const GuideDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            largeTitle: const Text(
              'Документы',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.transparent,
            border: null,
          ),
          if (uid == null)
            const SliverToBoxAdapter(
              child: Center(child: Text('Не авторизован')),
            )
          else
            SliverToBoxAdapter(
              child: StreamBuilder<PartnerProfile?>(
                stream: FirestoreRepository.instance.streamPartner(uid),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CupertinoActivityIndicator()),
                    );
                  }
                  final profile = snap.data;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Прогресс-бар ───────────────────────────────────
                        _VerificationProgress(profile: profile),
                        const SizedBox(height: 24),

                        // ── Удостоверение личности ─────────────────────────
                        _DocSection(
                          title: 'Удостоверение личности',
                          subtitle: 'Лицевая и обратная сторона УЛ или паспорта',
                          icon: LucideIcons.creditCard,
                          sectionVerified: profile?.guideIdVerified ?? false,
                          docs: [
                            _DocTileConfig(
                              label: 'УЛ (лицевая сторона)',
                              fieldKey: 'guideIdFrontUrl',
                              storageFolder: 'guide_id',
                              currentUrl: profile?.guideIdFrontUrl,
                              verified: profile?.guideIdVerified ?? false,
                              icon: LucideIcons.creditCard,
                            ),
                            _DocTileConfig(
                              label: 'УЛ (обратная сторона)',
                              fieldKey: 'guideIdBackUrl',
                              storageFolder: 'guide_id',
                              currentUrl: profile?.guideIdBackUrl,
                              verified: profile?.guideIdVerified ?? false,
                              icon: LucideIcons.creditCard,
                            ),
                          ],
                          uid: uid,
                        ),
                        const SizedBox(height: 20),

                        // ── Сертификат гида ────────────────────────────────
                        _DocSection(
                          title: 'Сертификат / Лицензия гида',
                          subtitle: 'Действующий сертификат туристического гида',
                          icon: LucideIcons.award,
                          sectionVerified: profile?.guideCertificateVerified ?? false,
                          docs: [
                            _DocTileConfig(
                              label: 'Сертификат гида',
                              fieldKey: 'guideCertificateUrl',
                              storageFolder: 'guide_certificates',
                              currentUrl: profile?.guideCertificateUrl,
                              verified: profile?.guideCertificateVerified ?? false,
                              icon: LucideIcons.award,
                            ),
                          ],
                          uid: uid,
                        ),
                        const SizedBox(height: 20),

                        // ── Check-in ────────────────────────────────────────
                        _DocSection(
                          title: 'Check-in',
                          subtitle: 'Подтверждение личности раз в 10 дней',
                          icon: LucideIcons.scanFace,
                          sectionVerified: profile?.guideFaceControlVerified ?? false,
                          docs: [
                            _DocTileConfig(
                              label: 'Фото лица',
                              fieldKey: 'guideFaceControlUrl',
                              storageFolder: 'guide_face_control',
                              currentUrl: profile?.guideFaceControlUrl,
                              verified: profile?.guideFaceControlVerified ?? false,
                              icon: LucideIcons.userCheck,
                              isSelfie: true,
                            ),
                          ],
                          uid: uid,
                        ),
                        const SizedBox(height: 32),

                        // ── Инфо-блок ──────────────────────────────────────
                        _InfoBlock(),
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

// ══════════════════════════════════════════════════════════════════════════════
// _VerificationProgress
// ══════════════════════════════════════════════════════════════════════════════

class _VerificationProgress extends StatelessWidget {
  final PartnerProfile? profile;

  const _VerificationProgress({this.profile});

  @override
  Widget build(BuildContext context) {
    final idOk = (profile?.guideIdFrontUrl != null &&
        profile?.guideIdBackUrl != null);
    final certOk = profile?.guideCertificateUrl != null;
    final faceOk = profile?.guideFaceControlUrl != null;

    final idVerified = profile?.guideIdVerified ?? false;
    final certVerified = profile?.guideCertificateVerified ?? false;
    final faceVerified = profile?.guideFaceControlVerified ?? false;

    final uploaded = [idOk, certOk, faceOk].where((b) => b).length;
    final verified = [idVerified, certVerified, faceVerified].where((b) => b).length;
    final total = 3;

    final allVerified = verified == total;
    final allUploaded = uploaded == total;

    Color statusColor;
    String statusText;
    IconData statusIcon;
    if (allVerified) {
      statusColor = CupertinoColors.systemGreen;
      statusText = 'Все документы подтверждены';
      statusIcon = LucideIcons.checkCircle2;
    } else if (allUploaded) {
      statusColor = CupertinoColors.systemOrange;
      statusText = 'Документы на проверке';
      statusIcon = LucideIcons.clock;
    } else {
      statusColor = AppColors.danger;
      statusText = 'Требуется загрузить документы';
      statusIcon = LucideIcons.alertCircle;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$verified / $total',
                style: TextStyle(
                  color: statusColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: verified / total,
              minHeight: 6,
              backgroundColor: statusColor.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ProgressDot(label: 'УЛ', done: idOk, verified: idVerified),
              const SizedBox(width: 16),
              _ProgressDot(label: 'Сертификат', done: certOk, verified: certVerified),
              const SizedBox(width: 16),
              _ProgressDot(label: 'Face Control', done: faceOk, verified: faceVerified),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressDot extends StatelessWidget {
  final String label;
  final bool done;
  final bool verified;

  const _ProgressDot({
    required this.label,
    required this.done,
    required this.verified,
  });

  @override
  Widget build(BuildContext context) {
    final color = verified
        ? CupertinoColors.systemGreen
        : done
            ? CupertinoColors.systemOrange
            : AppColors.textTertiary;
    final icon = verified
        ? LucideIcons.checkCircle2
        : done
            ? LucideIcons.clock
            : LucideIcons.circle;

    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _DocSection — секция документов с заголовком и списком тайлов
// ══════════════════════════════════════════════════════════════════════════════

class _DocSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool sectionVerified;
  final List<_DocTileConfig> docs;
  final String uid;

  const _DocSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.sectionVerified,
    required this.docs,
    required this.uid,
  });

  @override
  Widget build(BuildContext context) {
    final allUploaded = docs.every((d) => d.currentUrl != null);

    Color badge;
    String badgeText;
    if (sectionVerified) {
      badge = CupertinoColors.systemGreen;
      badgeText = '✓ Подтверждено';
    } else if (allUploaded) {
      badge = CupertinoColors.systemOrange;
      badgeText = 'На проверке';
    } else {
      badge = AppColors.danger;
      badgeText = 'Требуется';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.accent, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badge.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: badge.withValues(alpha: 0.35)),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  color: badge,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Upload tiles
        Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: docs.asMap().entries.map((entry) {
              final i = entry.key;
              final doc = entry.value;
              return Column(
                children: [
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: AppColors.border,
                      indent: 16,
                      endIndent: 16,
                    ),
                  _DocUploadTile(config: doc, uid: uid),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _DocTileConfig — конфиг одного тайла документа
// ══════════════════════════════════════════════════════════════════════════════

class _DocTileConfig {
  final String label;
  final String fieldKey;
  final String storageFolder;
  final String? currentUrl;
  final bool verified;
  final IconData icon;
  final bool isSelfie;

  const _DocTileConfig({
    required this.label,
    required this.fieldKey,
    required this.storageFolder,
    required this.currentUrl,
    required this.verified,
    required this.icon,
    this.isSelfie = false,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// _DocUploadTile
// ══════════════════════════════════════════════════════════════════════════════

class _DocUploadTile extends StatefulWidget {
  final _DocTileConfig config;
  final String uid;

  const _DocUploadTile({required this.config, required this.uid});

  @override
  State<_DocUploadTile> createState() => _DocUploadTileState();
}

class _DocUploadTileState extends State<_DocUploadTile> {
  bool _isUploading = false;

  Future<void> _pick() async {
    if (_isUploading) return;
    final picker = ImagePicker();
    final XFile? xfile = await picker.pickImage(
      source: widget.config.isSelfie ? ImageSource.camera : ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (xfile == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isUploading = true);

    try {
      final file = File(xfile.path);
      final url = await FirebaseStorageService.instance.uploadFile(
        file: file,
        path:
            '${widget.config.storageFolder}/${widget.uid}_${widget.config.fieldKey}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      if (url == null) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Не удалось загрузить ${widget.config.label.toLowerCase()}. Попробуйте ещё раз.'),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final updates = <String, dynamic>{widget.config.fieldKey: url};

      // Авто-верификация (временно)
      if (widget.config.fieldKey.startsWith('guideId')) {
        updates['guideIdVerified'] = true;
      } else if (widget.config.fieldKey == 'guideCertificateUrl') {
        updates['guideCertificateVerified'] = true;
      } else if (widget.config.fieldKey == 'guideFaceControlUrl') {
        updates['guideFaceControlVerified'] = true;
        updates['guideLastCheckInAt'] = DateTime.now().toIso8601String();
      }

      await FirestoreRepository.instance.updatePartner(widget.uid, updates);

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('${widget.config.label} загружено ✓'),
            backgroundColor: CupertinoColors.systemGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploaded = widget.config.currentUrl != null;
    final verified = widget.config.verified;

    Color statusColor;
    String statusText;
    IconData statusIcon;
    if (verified) {
      statusColor = CupertinoColors.systemGreen;
      statusText = 'Подтверждено';
      statusIcon = LucideIcons.checkCircle2;
    } else if (uploaded) {
      statusColor = CupertinoColors.systemOrange;
      statusText = 'На проверке';
      statusIcon = LucideIcons.clock;
    } else {
      statusColor = AppColors.danger;
      statusText = 'Не загружено';
      statusIcon = LucideIcons.alertCircle;
    }

    return InkWell(
      onTap: _isUploading ? null : _pick,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(widget.config.icon, color: statusColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.config.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 11),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_isUploading)
              const CupertinoActivityIndicator(radius: 10)
            else if (uploaded)
              Icon(LucideIcons.refreshCw, color: AppColors.textTertiary, size: 18)
            else
              Icon(
                widget.config.isSelfie ? LucideIcons.camera : LucideIcons.upload,
                color: AppColors.textTertiary,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _InfoBlock
// ══════════════════════════════════════════════════════════════════════════════

class _InfoBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.info, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Информация о верификации',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow('🪪', 'Удостоверение личности рассматривается 1–2 рабочих дня'),
          const SizedBox(height: 6),
          _infoRow('📋', 'Сертификат гида: подтверждаем подлинность документа'),
          const SizedBox(height: 6),
          _infoRow('📸', 'Face Control обновляется еженедельно для безопасности'),
          const SizedBox(height: 6),
          _infoRow('✅', 'После подтверждения вы получите уведомление'),
        ],
      ),
    );
  }

  Widget _infoRow(String emoji, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
