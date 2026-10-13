import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'vehicle_inspection_screen.dart';
import '../models/partner_models.dart';
import '../models/vehicle_inspection.dart';
import '../repository/firestore_repository.dart';
import '../services/auth_service.dart';
import '../services/firebase_storage_service.dart';
import '../theme/app_colors.dart';

import 'guide_documents_screen.dart';

class GarageScreen extends StatelessWidget {
  const GarageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uid = AuthService.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Не авторизован')));
    }

    return StreamBuilder<PartnerProfile?>(
      stream: FirestoreRepository.instance.streamPartner(uid),
      builder: (context, profileSnap) {
        if (profileSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CupertinoActivityIndicator()),
          );
        }

        final profile = profileSnap.data;
        if (profile != null && profile.role.isGuide) {
          return const GuideDocumentsScreen();
        }

        // ── Интерфейс для Водителей (Гараж) ──────────────────────────────────
        return Scaffold(
          backgroundColor: AppColors.background,
          body: CustomScrollView(
            slivers: [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            largeTitle: Text(
              'Гараж',
              style: TextStyle(
                color: Theme.of(context).textTheme.displayLarge?.color,
              ),
            ),
            backgroundColor: Colors.transparent,
            border: null,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              child: uid == null
                  ? const Center(child: Text('Не авторизован'))
                  : StreamBuilder<PartnerProfile?>(
                      stream: FirestoreRepository.instance.streamPartner(uid),
                      builder: (context, profileSnap) {
                        if (profileSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(48),
                            child: Center(child: CupertinoActivityIndicator()),
                          );
                        }
                        final profile = profileSnap.data;
                        final isDriver = profile?.role.isDriver ?? false;
                        // First run: vehicle not yet added
                        final hasVehicle = profile?.vehicleModel.isNotEmpty == true;

                        return StreamBuilder<VehicleInspection?>(
                          stream: FirestoreRepository.instance
                              .streamTodayInspection(uid),
                          builder: (context, inspSnap) {
                            final todayInsp = inspSnap.data;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Car Info Card or First Run CTA ─────────
                                if (isDriver) ...[
                                  if (hasVehicle)
                                    _CarInfoCard(
                                      isDark: isDark,
                                      profile: profile,
                                      uid: uid,
                                    )
                                  else
                                    _AddVehicleCta(
                                      isDark: isDark,
                                      uid: uid,
                                    ),
                                  const SizedBox(height: 24),
                                ],

                                // ── Document onboarding (always for drivers) ─
                                if (isDriver) ...[
                                  _GarageOnboardingSection(
                                    isDark: isDark,
                                    uid: uid,
                                    profile: profile,
                                  ),
                                  const SizedBox(height: 24),
                                ],

                                // ── Inspection row ───────────────────────
                                _InspectionSection(
                                  isDark: isDark,
                                  inspection: todayInsp,
                                  profile: profile,
                                  isDriver: isDriver,
                                ),

                                // ── Stats row (drivers) ──────────────────
                                if (isDriver) ...[
                                  const SizedBox(height: 24),
                                  _StatsRow(isDark: isDark, profile: profile, uid: uid),
                                ],
                                ],
                              );
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ===========================================================================
// Inspection status section
// ===========================================================================

class _InspectionSection extends StatelessWidget {
  final bool isDark;
  final VehicleInspection? inspection;
  final PartnerProfile? profile;
  final bool isDriver;

  const _InspectionSection({
    required this.isDark,
    required this.inspection,
    required this.profile,
    required this.isDriver,
  });

  @override
  Widget build(BuildContext context) {
    if (!isDriver) return const SizedBox.shrink();

    final insp = inspection;
    final isVerifiedOverride = profile?.vehicleInspectionVerified ?? false;
    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (isVerifiedOverride) {
      statusText = 'Подтверждено ✓';
      statusColor = CupertinoColors.systemGreen;
      statusIcon = CupertinoIcons.checkmark_seal_fill;
    } else if (insp == null) {
      statusText = 'Требуется';
      statusColor = CupertinoColors.systemRed;
      statusIcon = CupertinoIcons.exclamationmark_circle_fill;
    } else {
      switch (insp.status) {
        case InspectionStatus.approved:
          statusText = 'Одобрен ✓';
          statusColor = CupertinoColors.systemGreen;
          statusIcon = CupertinoIcons.checkmark_seal_fill;
        case InspectionStatus.rejected:
          statusText = 'Отклонён';
          statusColor = CupertinoColors.systemRed;
          statusIcon = CupertinoIcons.xmark_circle_fill;
        case InspectionStatus.pending:
          statusText = 'На рассмотрении';
          statusColor = CupertinoColors.systemOrange;
          statusIcon = CupertinoIcons.clock_fill;
      }
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => VehicleInspectionScreen(profile: profile),
            fullscreenDialog: true,
          ),
        );
      },
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(CupertinoIcons.camera_viewfinder,
                    color: const Color(0xFF6FBF4F), size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Проверка кузова',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(CupertinoIcons.chevron_right,
                        color: CupertinoColors.systemGrey3, size: 14),
                  ],
                ),
              ],
            ),
            if (insp?.status == InspectionStatus.rejected &&
                insp?.rejectionReason != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '💬 ${insp!.rejectionReason}',
                  style: const TextStyle(
                      color: CupertinoColors.systemRed, fontSize: 12),
                ),
              ),
            ],
            if (insp?.hasDamage == true && insp?.status != InspectionStatus.rejected) ...[
              const SizedBox(height: 8),
              const Text(
                '⚠️ Обнаружены повреждения кузова',
                style: TextStyle(
                    color: CupertinoColors.systemOrange, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
// ===========================================================================
// Add Vehicle CTA (first-run when vehicleModel is empty)
// ===========================================================================

class _AddVehicleCta extends StatelessWidget {
  final bool isDark;
  final String uid;

  const _AddVehicleCta({required this.isDark, required this.uid});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showCupertinoModalPopup(
        context: context,
        builder: (_) => _AddVehicleSheet(isDark: isDark, uid: uid),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
          color: CupertinoColors.systemGreen.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: CupertinoColors.systemGreen.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            const Icon(
              CupertinoIcons.car_fill,
              color: CupertinoColors.systemGreen,
              size: 42,
            ),
            const SizedBox(height: 12),
            const Text(
              'Добавить автомобиль',
              style: TextStyle(
                color: CupertinoColors.systemGreen,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Нажмите чтобы добавить данные вашего транспортного средства',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CupertinoColors.systemGrey,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Add Vehicle Sheet
// ===========================================================================

class _AddVehicleSheet extends StatefulWidget {
  final bool isDark;
  final String uid;

  const _AddVehicleSheet({required this.isDark, required this.uid});

  @override
  State<_AddVehicleSheet> createState() => _AddVehicleSheetState();
}

class _AddVehicleSheetState extends State<_AddVehicleSheet> {
  final _modelCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _modelCtrl.dispose();
    _plateCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_modelCtrl.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await FirestoreRepository.instance.updatePartner(widget.uid, {
        'vehicleModel': _modelCtrl.text.trim(),
        'vehiclePlate': _plateCtrl.text.trim(),
        'vehicleAdded': true,
      });
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Данные автомобиля',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none,
                color: widget.isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
            ),
            const SizedBox(height: 16),
            CupertinoTextField(
              controller: _modelCtrl,
              placeholder: 'Марка и модель (напр. Toyota Land Cruiser)',
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(12),
              ),
              style: TextStyle(color: widget.isDark ? Colors.white : Colors.black),
            ),
            const SizedBox(height: 12),
            CupertinoTextField(
              controller: _plateCtrl,
              placeholder: 'Гос. номер (напр. 123 ABC 01)',
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(12),
              ),
              style: TextStyle(color: widget.isDark ? Colors.white : Colors.black),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: CupertinoColors.systemGreen,
                borderRadius: BorderRadius.circular(12),
                padding: const EdgeInsets.symmetric(vertical: 14),
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text(
                        'Добавить автомобиль',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Document onboarding section
// ===========================================================================

class _GarageOnboardingSection extends StatelessWidget {
  final bool isDark;
  final String uid;
  final PartnerProfile? profile;

  const _GarageOnboardingSection({
    required this.isDark,
    required this.uid,
    this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final docs = [
      _DocTileData(
        label: 'Права (лицевая)',
        fieldKey: 'driverLicenseFrontUrl',
        storageFolder: 'driver_licenses',
        currentUrl: profile?.driverLicenseFrontUrl,
        verified: profile?.driverLicenseVerified ?? false,
        icon: CupertinoIcons.creditcard_fill,
      ),
      _DocTileData(
        label: 'Права (обратная)',
        fieldKey: 'driverLicenseBackUrl',
        storageFolder: 'driver_licenses',
        currentUrl: profile?.driverLicenseBackUrl,
        verified: profile?.driverLicenseVerified ?? false,
        icon: CupertinoIcons.creditcard_fill,
      ),
      _DocTileData(
        label: 'Тех. паспорт (лицевая)',
        fieldKey: 'techPassportFrontUrl',
        storageFolder: 'tech_passports',
        currentUrl: profile?.techPassportFrontUrl,
        verified: profile?.techPassportVerified ?? false,
        icon: CupertinoIcons.doc_fill,
      ),
      _DocTileData(
        label: 'Тех. паспорт (обратная)',
        fieldKey: 'techPassportBackUrl',
        storageFolder: 'tech_passports',
        currentUrl: profile?.techPassportBackUrl,
        verified: profile?.techPassportVerified ?? false,
        icon: CupertinoIcons.doc_fill,
      ),
      _DocTileData(
        label: 'Check-in',
        fieldKey: 'faceControlUrl',
        storageFolder: 'face_control',
        currentUrl: profile?.faceControlUrl,
        verified: profile?.faceControlVerified ?? false,
        icon: CupertinoIcons.person_crop_circle_fill,
        isSelfie: true,
      ),
    ];

    final allUploaded = docs.every((d) => d.currentUrl != null);
    final allVerified = docs.every((d) => d.verified);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Документы',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: allVerified
                    ? CupertinoColors.systemGreen
                    : allUploaded
                        ? CupertinoColors.systemOrange
                        : CupertinoColors.systemRed,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                allVerified
                    ? '✓ Подтверждено'
                    : allUploaded
                        ? 'На проверке'
                        : 'Требуется',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
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
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07),
                      indent: 16,
                      endIndent: 16,
                    ),
                  _DocUploadTile(
                    data: doc,
                    isDark: isDark,
                    uid: uid,
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _DocTileData {
  final String label;
  final String fieldKey;
  final String storageFolder;
  final String? currentUrl;
  final bool verified;
  final IconData icon;
  final bool isSelfie;

  const _DocTileData({
    required this.label,
    required this.fieldKey,
    required this.storageFolder,
    required this.currentUrl,
    required this.verified,
    required this.icon,
    this.isSelfie = false,
  });
}

class _DocUploadTile extends StatefulWidget {
  final _DocTileData data;
  final bool isDark;
  final String uid;

  const _DocUploadTile({
    required this.data,
    required this.isDark,
    required this.uid,
  });

  @override
  State<_DocUploadTile> createState() => _DocUploadTileState();
}

class _DocUploadTileState extends State<_DocUploadTile> {
  bool _isUploading = false;

  Future<void> _pick() async {
    if (_isUploading) return;
    final picker = ImagePicker();
    final XFile? xfile = await picker.pickImage(
      source: widget.data.isSelfie ? ImageSource.camera : ImageSource.camera,
      imageQuality: 85,
    );
    if (xfile == null || !mounted) return;

    // Cache messenger before async gap
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isUploading = true);
    try {
      final file = File(xfile.path);
      final url = await FirebaseStorageService.instance.uploadFile(
        file: file,
        path: '${widget.data.storageFolder}/${widget.uid}_${widget.data.fieldKey}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      if (url == null) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Не удалось загрузить ${widget.data.label.toLowerCase()}. Попробуйте ещё раз.'),
              backgroundColor: CupertinoColors.systemRed,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      final updates = <String, dynamic>{
        widget.data.fieldKey: url,
      };

      // ВРЕМЕННО: Автоматически подтверждаем документ при загрузке
      if (widget.data.fieldKey.startsWith('driverLicense')) {
        updates['driverLicenseVerified'] = true;
      } else if (widget.data.fieldKey.startsWith('techPassport')) {
        updates['techPassportVerified'] = true;
      } else if (widget.data.fieldKey.startsWith('faceControl')) {
        updates['faceControlVerified'] = true;
        updates['lastCheckInAt'] = DateTime.now().toIso8601String();
      }

      await FirestoreRepository.instance.updatePartner(widget.uid, updates);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('${widget.data.label} загружено ✓'),
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
            backgroundColor: CupertinoColors.systemRed,
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
    final uploaded = widget.data.currentUrl != null;
    final verified = widget.data.verified;

    Color statusColor;
    String statusText;
    IconData statusIcon;
    if (verified) {
      statusColor = CupertinoColors.systemGreen;
      statusText = 'Подтверждено';
      statusIcon = CupertinoIcons.checkmark_seal_fill;
    } else if (uploaded) {
      statusColor = CupertinoColors.systemOrange;
      statusText = 'На проверке';
      statusIcon = CupertinoIcons.clock_fill;
    } else {
      statusColor = CupertinoColors.systemRed;
      statusText = 'Не загружено';
      statusIcon = CupertinoIcons.exclamationmark_circle_fill;
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
              child: Icon(widget.data.icon, color: statusColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.data.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: widget.isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
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
              const Icon(
                CupertinoIcons.arrow_2_circlepath,
                color: CupertinoColors.systemGrey,
                size: 18,
              )
            else
              const Icon(
                CupertinoIcons.camera_fill,
                color: CupertinoColors.systemGrey,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}


class _StatsRow extends StatelessWidget {
  final bool isDark;
  final PartnerProfile? profile;
  final String uid;

  const _StatsRow({required this.isDark, this.profile, required this.uid});

  void _showToggleSheet(BuildContext context, String title, String fieldKey, bool currentValue) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        bool tempValue = currentValue;
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return Container(
              height: 250,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'У меня есть в наличии',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        CupertinoSwitch(
                          value: tempValue,
                          activeTrackColor: const Color(0xFF6FBF4F),
                          onChanged: (val) {
                            setStateSB(() => tempValue = val);
                          },
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        color: const Color(0xFF6FBF4F),
                        borderRadius: BorderRadius.circular(12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: const Text(
                          'Сохранить',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          FirestoreRepository.instance.updatePartner(uid, {fieldKey: tempValue});
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasStarlink = profile?.hasStarlink ?? false;
    final hasRentalGear = profile?.hasRentalGear ?? false;

    // Tuple structure: Icon, Value text, Label, Color, onTap handler
    final items = [
      (
        CupertinoIcons.wifi,
        hasStarlink ? 'Есть' : 'Нет',
        'Наличие Starlink',
        hasStarlink ? CupertinoColors.systemGreen : CupertinoColors.systemGrey,
        () => _showToggleSheet(context, 'Наличие Starlink', 'hasStarlink', hasStarlink),
      ),
      (
        CupertinoIcons.money_rubl_circle_fill,
        '${profile?.pricePerKm.toInt() ?? 0} ₸',
        'Цена/км',
        const Color(0xFF6FBF4F),
        // Just empty tap for Price, as it's edited on Work Screen
        () {},
      ),
      (
        CupertinoIcons.bag_fill,
        hasRentalGear ? 'Доступно' : 'Нет',
        'Снаряжение',
        hasRentalGear ? CupertinoColors.systemOrange : CupertinoColors.systemGrey,
        () => _showToggleSheet(context, 'Снаряжение в аренду', 'hasRentalGear', hasRentalGear),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: items.map((item) {
          return Expanded(
            child: GestureDetector(
              onTap: item.$5,
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: [
                  Icon(item.$1, color: item.$4, size: 22),
                  const SizedBox(height: 6),
                  Text(
                    item.$2,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: item.$2 == 'Нет' ? CupertinoColors.systemGrey : (isDark ? Colors.white : Colors.black),
                    ),
                  ),
                  Text(
                    item.$3,
                    style: const TextStyle(
                      color: CupertinoColors.systemGrey,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ===========================================================================
// Car info card with profile photo upload
// ===========================================================================

class _CarInfoCard extends StatefulWidget {
  final bool isDark;
  final PartnerProfile? profile;
  final String uid;

  const _CarInfoCard({
    required this.isDark,
    required this.profile,
    required this.uid,
  });

  @override
  State<_CarInfoCard> createState() => _CarInfoCardState();
}

class _CarInfoCardState extends State<_CarInfoCard> {
  bool _uploading = false;

  Future<void> _pickAndUploadCarPhoto() async {
    if (_uploading) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      final url = await FirebaseStorageService.instance.pickCameraAndUpload(
        storagePath: 'car_photos/${widget.uid}/main.jpg',
      );
      if (url != null && mounted) {
        await FirestoreRepository.instance
            .updatePartner(widget.uid, {'carPhotoUrl': url});
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Фото автомобиля обновлено'),
            backgroundColor: Color(0xFF6FBF4F),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final isDark = widget.isDark;

    final model = profile?.vehicleModel.isNotEmpty == true
        ? profile!.vehicleModel
        : 'Автомобиль';
    final plate = profile?.vehiclePlate.isNotEmpty == true
        ? profile!.vehiclePlate
        : '— — —';
    final type = profile?.vehicleType.isNotEmpty == true
        ? profile!.vehicleType.toUpperCase()
        : '—';
    final seats = profile?.vehicleCapacity ?? 0;
    final pricePerKm = profile?.pricePerKm ?? 0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Car banner
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            child: Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF0D1117), const Color(0xFF1C1C2E)]
                      : [const Color(0xFFE8F0FE), const Color(0xFFF0F4FF)],
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      CupertinoIcons.car_detailed,
                      size: 80,
                      color: const Color(0xFF6FBF4F).withValues(alpha: 0.15),
                    ),
                  ),
                  // Camera button
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: _pickAndUploadCarPhoto,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: Color(0xFF6FBF4F),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x44147EFB),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: _uploading
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: CupertinoActivityIndicator(
                                    color: Colors.white),
                              )
                            : const Icon(CupertinoIcons.camera_fill,
                                color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + plate
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            model,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            profile?.role.displayName ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Plate badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Colors.black87, width: 2),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2)),
                        ],
                      ),
                      child: Text(
                        plate,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.08)),
                const SizedBox(height: 12),
                // Stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _infoItem(context, 'Мест', '$seats',
                        CupertinoIcons.person_2_fill),
                    _infoItem(
                        context,
                        'Тип',
                        type.isNotEmpty ? type : '—',
                        CupertinoIcons.square_grid_2x2_fill),
                    _infoItem(context, 'Цена/км', '${ pricePerKm.toInt()} ₸',
                        CupertinoIcons.money_rubl_circle_fill),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoItem(
      BuildContext context, String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF6FBF4F)),
        const SizedBox(height: 6),
        Text(value,
            style:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        Text(
          label,
          style: const TextStyle(
              color: CupertinoColors.systemGrey,
              fontSize: 10,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
