import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/partner_models.dart';
import '../repository/firestore_repository.dart';
import '../services/auth_service.dart';
import '../services/firebase_storage_service.dart';
import '../utils/support_helper.dart';
import '../services/payout_service.dart';
import '../models/guide_specializations.dart';

// ===========================================================================
// ProfileScreen
// ===========================================================================

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uid = AuthService.instance.currentUser?.uid;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            transitionBetweenRoutes: false,
            largeTitle: Text(
              'Профиль',
              style: TextStyle(
                color: Theme.of(context).textTheme.displayLarge?.color,
              ),
            ),
            backgroundColor: Colors.transparent,
            border: null,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: uid == null
                  ? const Center(child: Text('Не авторизован'))
                  : StreamBuilder<PartnerProfile?>(
                      stream: FirestoreRepository.instance.streamPartner(uid),
                      builder: (context, snapshot) {
                        final profile = snapshot.data;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Карточка профиля ──────────────────────────
                            _ProfileHeader(
                              profile: profile,
                              isDark: isDark,
                              uid: uid,
                            ),
                            const SizedBox(height: 16),
                            _MetricsSection(profile: profile, isDark: isDark),
                            const SizedBox(height: 24),

                            // ── Финансы и Выплаты ────────────────────────
                            _sectionLabel('ФИНАНСЫ И ВЫПЛАТЫ'),
                            const SizedBox(height: 10),
                            _WalletSection(profile: profile, isDark: isDark, uid: uid),
                            const SizedBox(height: 24),

                            // ── Профиль / Гараж (только водитель) ─────────
                            _SettingsCard(
                              isDark: isDark,
                              items: [
                                _SettingsRow(
                                  icon: CupertinoIcons.person_fill,
                                  iconColor: Theme.of(context).primaryColor,
                                  title: 'Редактировать профиль',
                                  onTap: () => Navigator.of(context).push(
                                    CupertinoPageRoute(
                                      builder: (_) => EditProfileScreen(
                                        profile: profile,
                                        uid: uid,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // ── Настройки ─────────────────────────────────
                            _SettingsCard(
                              isDark: isDark,
                              items: [
                                _SettingsRow(
                                  icon: CupertinoIcons.bell_fill,
                                  iconColor: CupertinoColors.systemYellow,
                                  title: 'Уведомления',
                                  trailing: CupertinoSwitch(
                                    value: true,
                                    activeTrackColor: const Color(0xFF6FBF4F),
                                    onChanged: (_) {},
                                  ),
                                ),
                                _SettingsRow(
                                  icon: CupertinoIcons.globe,
                                  iconColor: Theme.of(context).primaryColor,
                                  title: 'Язык приложения',
                                  trailingText: 'Русский',
                                  onTap: () {},
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // ── Поддержка ─────────────────────────────────
                            _SettingsCard(
                              isDark: isDark,
                              items: [
                                _SettingsRow(
                                  icon: CupertinoIcons.headphones,
                                  iconColor: CupertinoColors.systemGreen,
                                  title: 'Служба поддержки',
                                  onTap: () {
                                    showCupertinoModalPopup(
                                      context: context,
                                      builder: (context) => CupertinoActionSheet(
                                        title: const Text('Служба поддержки'),
                                        message: const Text('Выберите удобный способ связи'),
                                        actions: [
                                          CupertinoActionSheetAction(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              SupportHelper.openTelegram();
                                            },
                                            child: const Text('Написать в Telegram', style: TextStyle(color: Color(0xFF6FBF4F))),
                                          ),
                                          CupertinoActionSheetAction(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              SupportHelper.openWhatsApp();
                                            },
                                            child: const Text('Написать в WhatsApp', style: TextStyle(color: CupertinoColors.systemGreen)),
                                          ),
                                        ],
                                        cancelButton: CupertinoActionSheetAction(
                                          isDefaultAction: true,
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('Отмена'),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // ── Выход ─────────────────────────────────────
                             SizedBox(
                               width: double.infinity,
                               child: CupertinoButton(
                                 padding: const EdgeInsets.symmetric(
                                   vertical: 14,
                                 ),
                                 child: const Text(
                                   'Выйти из аккаунта',
                                   style: TextStyle(
                                     color: CupertinoColors.systemRed,
                                     fontWeight: FontWeight.w600,
                                   ),
                                 ),
                                 onPressed: () {
                                   showCupertinoDialog(
                                     context: context,
                                     builder: (context) => CupertinoAlertDialog(
                                       title: const Text('Выход'),
                                       content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
                                       actions: [
                                         CupertinoDialogAction(
                                           child: const Text('Отмена'),
                                           onPressed: () => Navigator.pop(context),
                                         ),
                                         CupertinoDialogAction(
                                           isDestructiveAction: true,
                                           onPressed: () async {
                                             await AuthService.instance.signOut();
                                             if (context.mounted) {
                                               context.go('/auth');
                                             }
                                           },
                                           child: const Text('Выйти'),
                                         ),
                                       ],
                                     ),
                                   );
                                 },
                               ),
                             ),
                             const SizedBox(height: 16),
                             // ── Удалить аккаунт ───────────────────────────
                             SizedBox(
                               width: double.infinity,
                               child: CupertinoButton(
                                 padding: const EdgeInsets.symmetric(
                                   vertical: 14,
                                 ),
                                 child: const Text(
                                   'Удалить аккаунт',
                                   style: TextStyle(
                                     color: CupertinoColors.systemRed,
                                     fontWeight: FontWeight.w600,
                                   ),
                                 ),
                                 onPressed: () {
                                   showCupertinoDialog(
                                     context: context,
                                     builder: (context) => CupertinoAlertDialog(
                                       title: const Text('Удаление аккаунта'),
                                       content: const Text('Это действие необратимо. Ваш профиль и аккаунт будут навсегда удалены. Продолжить?'),
                                       actions: [
                                         CupertinoDialogAction(
                                           child: const Text('Отмена'),
                                           onPressed: () => Navigator.pop(context),
                                         ),
                                         CupertinoDialogAction(
                                           isDestructiveAction: true,
                                           onPressed: () async {
                                             Navigator.pop(context); // close dialog
                                             await AuthService.instance.deleteAccount(context);
                                             if (context.mounted && AuthService.instance.currentUser == null) {
                                               context.go('/auth');
                                             }
                                           },
                                           child: const Text('Удалить'),
                                         ),
                                       ],
                                     ),
                                   );
                                 },
                               ),
                             ),
                             const SizedBox(height: 24),
                             const Center(
                               child: Text(
                                 'Версия 1.0.10',
                                 style: TextStyle(
                                   color: CupertinoColors.systemGrey,
                                   fontSize: 12,
                                 ),
                               ),
                             ),
                             const SizedBox(height: 40),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 2),
    child: Text(
      text,
      style: const TextStyle(
        color: CupertinoColors.systemGrey,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
  );
}

// ===========================================================================
// _WalletSection
// ===========================================================================

class _WalletSection extends StatefulWidget {
  final PartnerProfile? profile;
  final bool isDark;
  final String uid;

  const _WalletSection({
    required this.profile,
    required this.isDark,
    required this.uid,
  });

  @override
  State<_WalletSection> createState() => _WalletSectionState();
}

class _WalletSectionState extends State<_WalletSection> {
  bool _isWithdrawing = false;

  void _showAddCardDialog() {
    final cardCtrl = TextEditingController(text: widget.profile?.savedCard ?? '');
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Карта для выплат'),
        content: Column(
          children: [
            const SizedBox(height: 10),
            const Text(
              'Введите номер карты, на которую будут поступать деньги от поездок.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            CupertinoTextField(
              controller: cardCtrl,
              keyboardType: TextInputType.number,
              placeholder: '0000 0000 0000 0000',
              maxLength: 16,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Отмена'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Сохранить'),
            onPressed: () async {
              final val = cardCtrl.text.replaceAll(' ', '');
              if (val.length < 12) return;
              try {
                await FirestoreRepository.instance.updatePartner(widget.uid, {
                  'savedCard': val,
                });
                if (mounted) Navigator.pop(context);
              } catch (e) {
                if (mounted) {
                  showCupertinoDialog(
                    context: context,
                    builder: (ctx) => CupertinoAlertDialog(
                      title: const Text('Ошибка'),
                      content: Text('Не удалось сохранить карту: $e'),
                      actions: [
                        CupertinoDialogAction(
                          child: const Text('ОК'),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _withdraw() async {
    if (widget.profile == null || widget.profile!.balance <= 0) return;
    if (widget.profile!.savedCard == null || widget.profile!.savedCard!.isEmpty) {
      _showAddCardDialog();
      return;
    }

    setState(() => _isWithdrawing = true);
    try {
      final success = await PayoutService.requestPayout(
        partnerId: widget.uid,
        amount: widget.profile!.balance,
        cardPan: widget.profile!.savedCard!,
      );
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: Text(success ? 'Успешно' : 'Не удалось'),
            content: Text(success
                ? 'Средства отправлены на вашу карту.'
                : 'Выплата не прошла. Проверьте карту и баланс, или попробуйте позже.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('ОК'),
                onPressed: () => Navigator.pop(ctx),
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Ошибка'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                child: const Text('ОК'),
                onPressed: () => Navigator.pop(ctx),
              )
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isWithdrawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.profile == null) return const SizedBox.shrink();

    final balance = widget.profile!.balance;
    final card = widget.profile!.savedCard;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Баланс',
                style: TextStyle(
                  color: CupertinoColors.systemGrey,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (card != null && card.length >= 4)
                GestureDetector(
                  onTap: _showAddCardDialog,
                  child: Text(
                    'Карта *${card.substring(card.length - 4)}',
                    style: const TextStyle(
                      color: Color(0xFF6FBF4F),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: _showAddCardDialog,
                  child: const Text(
                    'Добавить карту',
                    style: TextStyle(
                      color: CupertinoColors.systemRed,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${balance.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]} ')} ₸',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: balance > 0 && card != null ? const Color(0xFF34C759) : CupertinoColors.systemGrey4,
              borderRadius: BorderRadius.circular(10),
              onPressed: balance > 0 ? _withdraw : null,
              child: _isWithdrawing
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                      'Вывести средства',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// _ProfileHeader with photo upload
// ===========================================================================

class _ProfileHeader extends StatefulWidget {
  final PartnerProfile? profile;
  final bool isDark;
  final String uid;

  const _ProfileHeader({
    required this.profile,
    required this.isDark,
    required this.uid,
  });

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  bool _isUploading = false;

  Future<void> _uploadPhoto() async {
    if (_isUploading) return;
    setState(() => _isUploading = true);
    try {
      final url = await FirebaseStorageService.instance.pickCameraAndUpload(
        storagePath: 'partner_avatars/${widget.uid}.jpg',
      );
      if (url != null && mounted) {
        await FirestoreRepository.instance.updatePartner(widget.uid, {
          'photoUrl': url,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка загрузки фото: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    // Fix: use fullName for display, with fallback
    final displayName = profile != null
        ? (profile.firstName.isNotEmpty || profile.lastName.isNotEmpty
              ? '${profile.firstName} ${profile.lastName}'.trim()
              : profile.email)
        : '...';
    final roleLabel = profile?.role.displayName ?? '';
    final rating = profile != null ? profile.rating.toStringAsFixed(1) : '—';
    final isVerified = profile?.isVerified ?? false;
    final photoUrl = profile?.photoUrl;

    return Container(
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color(0xFF1C1C1E)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Row(
        children: [
          // ── Avatar with camera overlay ──────────────────────────────
          GestureDetector(
            onTap: _uploadPhoto,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor: CupertinoColors.systemGrey5,
                  backgroundImage: photoUrl != null
                      ? NetworkImage(photoUrl)
                      : null,
                  child: _isUploading
                      ? const CupertinoActivityIndicator()
                      : (photoUrl == null
                            ? const Icon(
                                CupertinoIcons.person_crop_circle,
                                size: 48,
                                color: CupertinoColors.systemGrey,
                              )
                            : null),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6FBF4F),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isDark ? const Color(0xFF1C1C1E) : Colors.white,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      CupertinoIcons.camera_fill,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
],
            ),
          ),
          const SizedBox(width: 16),

          // ── Name & role ────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isVerified) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        CupertinoIcons.checkmark_seal_fill,
                        color: Color(0xFF6FBF4F),
                        size: 18,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  roleLabel.isNotEmpty ? '$roleLabel • ★ $rating' : '...',
                  style: const TextStyle(
                    color: Color(0xFF6FBF4F),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// EditProfileScreen
// ===========================================================================

class EditProfileScreen extends StatefulWidget {
  final PartnerProfile? profile;
  final String uid;
  const EditProfileScreen({
    super.key,
    required this.profile,
    required this.uid,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _bioCtrl;
  // Driver-specific
  late final TextEditingController _vehicleModelCtrl;
  late final TextEditingController _pricePerKmCtrl;
  late final TextEditingController _vehicleCapacityCtrl;
  // Guide-specific
  late final TextEditingController _pricePerDayCtrl;
  late final TextEditingController _experienceCtrl;
  late final TextEditingController _tourAreasCtrl;
  late final TextEditingController _maxGroupSizeCtrl;
  late Set<String> _selectedSpecializations;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _selectedSpecializations = {...?p?.specializations};
    _firstNameCtrl = TextEditingController(text: p?.firstName ?? '');
    _lastNameCtrl = TextEditingController(text: p?.lastName ?? '');
    _bioCtrl = TextEditingController(text: p?.bio ?? '');
    _vehicleModelCtrl = TextEditingController(text: p?.vehicleModel ?? '');
    _pricePerKmCtrl = TextEditingController(
      text: p != null && p.pricePerKm > 0
          ? p.pricePerKm.toStringAsFixed(0)
          : '',
    );
    _vehicleCapacityCtrl = TextEditingController(
      text: p != null && p.vehicleCapacity > 0
          ? p.vehicleCapacity.toString()
          : '',
    );
    _pricePerDayCtrl = TextEditingController(
      text: p != null && p.pricePerDay > 0
          ? p.pricePerDay.toStringAsFixed(0)
          : '',
    );
    _experienceCtrl = TextEditingController(
      text: p != null && p.experience > 0 ? p.experience.toString() : '',
    );
    _tourAreasCtrl = TextEditingController(
      text: p?.tourAreas.join(', ') ?? '',
    );
    _maxGroupSizeCtrl = TextEditingController(
      text: p != null && p.maxGroupSize > 0 ? p.maxGroupSize.toString() : '',
    );
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _bioCtrl.dispose();
    _vehicleModelCtrl.dispose();
    _pricePerKmCtrl.dispose();
    _vehicleCapacityCtrl.dispose();
    _pricePerDayCtrl.dispose();
    _experienceCtrl.dispose();
    _tourAreasCtrl.dispose();
    _maxGroupSizeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final firstName = _firstNameCtrl.text.trim();
    if (firstName.isEmpty) {
      _snack('Введите имя', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final updates = <String, dynamic>{
        'firstName': firstName,
        'lastName': _lastNameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
      };

      final isDriver = widget.profile?.role.isDriver == true;
      if (isDriver) {
        // Backfill vehicleType for partners who registered before it was
        // wired up at signup — it should never be blank for a driver.
        if (widget.profile != null && widget.profile!.vehicleType.isEmpty) {
          updates['vehicleType'] = widget.profile!.role.vehicleTypeCode;
        }
        updates['vehicleModel'] = _vehicleModelCtrl.text.trim();
        final km = double.tryParse(_pricePerKmCtrl.text.trim());
        if (km != null) updates['pricePerKm'] = km;
        final cap = int.tryParse(_vehicleCapacityCtrl.text.trim());
        if (cap != null) updates['vehicleCapacity'] = cap;
      } else {
        final day = double.tryParse(_pricePerDayCtrl.text.trim());
        if (day != null) updates['pricePerDay'] = day;
        final exp = int.tryParse(_experienceCtrl.text.trim());
        if (exp != null) updates['experience'] = exp;
        
        updates['tourAreas'] = _tourAreasCtrl.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

        final maxG = int.tryParse(_maxGroupSizeCtrl.text.trim());
        if (maxG != null) updates['maxGroupSize'] = maxG;

        updates['specializations'] = _selectedSpecializations.toList();
      }

      await FirestoreRepository.instance.updatePartner(widget.uid, updates);
      _snack('✅ Профиль сохранён', isError: false);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack('Ошибка: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError
            ? Colors.red.shade600
            : const Color(0xFF6FBF4F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final labelColor = isDark
        ? CupertinoColors.systemGrey
        : const Color(0xFF8E8E93);
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final isDriver = widget.profile?.role.isDriver == true;

    return Scaffold(
      backgroundColor: bg,
      appBar:
          CupertinoNavigationBar(
                transitionBetweenRoutes: false,
                backgroundColor: isDark
                    ? const Color(0xFF1C1C1E).withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.9),
                middle: Text(
                  'Редактировать профиль',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: _isSaving
                    ? const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: CupertinoActivityIndicator(),
                      )
                    : CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _save,
                        child: const Text(
                          'Сохранить',
                          style: TextStyle(
                            color: Color(0xFF6FBF4F),
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
              )
              as PreferredSizeWidget,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          // ── Основная информация ───────────────────────────────────
          _section(label: 'ОСНОВНАЯ ИНФОРМАЦИЯ'),
          _formCard(
            isDark: isDark,
            cardBg: cardBg,
            children: [
              _inputTile(
                label: 'Имя',
                controller: _firstNameCtrl,
                labelColor: labelColor,
                textColor: textColor,
                placeholder: 'Введите имя',
              ),
              _divider(isDark),
              _inputTile(
                label: 'Фамилия',
                controller: _lastNameCtrl,
                labelColor: labelColor,
                textColor: textColor,
                placeholder: 'Введите фамилию',
              ),
              _divider(isDark),
              _inputTile(
                label: 'О себе',
                controller: _bioCtrl,
                labelColor: labelColor,
                textColor: textColor,
                placeholder: 'Кратко о себе...',
                maxLines: 3,
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── Специфика роли ────────────────────────────────────────
          if (isDriver) ...[ 
            _section(label: 'ДОКУМЕНТЫ ВОДИТЕЛЯ'),
            _DriverDocumentsSection(
              uid: widget.uid,
              profile: widget.profile,
              isDark: isDark,
              cardBg: cardBg,
            ),
          ] else if (widget.profile?.role.isGuide == true) ...[
            _section(label: 'ДАННЫЕ ГИДА'),
            _formCard(
              isDark: isDark,
              cardBg: cardBg,
              children: [
                _inputTile(
                  label: 'Опыт работы (лет)',
                  controller: _experienceCtrl,
                  labelColor: labelColor,
                  textColor: textColor,
                  placeholder: '3',
                  keyboardType: TextInputType.number,
                ),
                _divider(isDark),
                _inputTile(
                  label: 'Цена за день (₸)',
                  controller: _pricePerDayCtrl,
                  labelColor: labelColor,
                  textColor: textColor,
                  placeholder: '15000',
                  keyboardType: TextInputType.number,
                ),
                _divider(isDark),
                _inputTile(
                  label: 'Макс. размер группы',
                  controller: _maxGroupSizeCtrl,
                  labelColor: labelColor,
                  textColor: textColor,
                  placeholder: '10',
                  keyboardType: TextInputType.number,
                ),
                _divider(isDark),
                _inputTile(
                  label: 'Регионы (через запятую)',
                  controller: _tourAreasCtrl,
                  labelColor: labelColor,
                  textColor: textColor,
                  placeholder: 'Алматы, Медео',
                ),
              ],
            ),
            const SizedBox(height: 20),
            _section(label: 'СПЕЦИАЛИЗАЦИИ'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                'Выберите всё, что относится к вам — это покажется в вашем '
                'профиле для туристов.',
                style: TextStyle(color: labelColor, fontSize: 13),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kGuideSpecializations.map((spec) {
                final selected = _selectedSpecializations.contains(spec);
                return FilterChip(
                  label: Text(spec),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _selectedSpecializations.add(spec);
                    } else {
                      _selectedSpecializations.remove(spec);
                    }
                  }),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? const Color(0xFF0B1209) : textColor,
                  ),
                  backgroundColor: cardBg,
                  selectedColor: const Color(0xFF6FBF4F),
                  side: BorderSide(
                    color: selected
                        ? const Color(0xFF6FBF4F)
                        : (isDark ? Colors.white24 : Colors.black12),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 36),

          // ── Save button ───────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              color: const Color(0xFF6FBF4F),
              borderRadius: BorderRadius.circular(14),
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                      'Сохранить изменения',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({required String label}) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      label,
      style: const TextStyle(
        color: CupertinoColors.systemGrey,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _formCard({
    required bool isDark,
    required Color cardBg,
    required List<Widget> children,
  }) => Container(
    decoration: BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _divider(bool isDark) => Divider(
    height: 1,
    indent: 16,
    color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
  );

  Widget _inputTile({
    required String label,
    required TextEditingController controller,
    required Color labelColor,
    required Color textColor,
    String placeholder = '',
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          CupertinoTextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            placeholder: placeholder,
            placeholderStyle: TextStyle(
              color: labelColor.withValues(alpha: 0.6),
              fontSize: 16,
            ),
            style: TextStyle(color: textColor, fontSize: 16),
            decoration: null,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// _DriverDocumentsSection — full document upload widget
// ===========================================================================

class _DriverDocumentsSection extends StatefulWidget {
  final String uid;
  final PartnerProfile? profile;
  final bool isDark;
  final Color cardBg;

  const _DriverDocumentsSection({
    required this.uid,
    required this.profile,
    required this.isDark,
    required this.cardBg,
  });

  @override
  State<_DriverDocumentsSection> createState() => _DriverDocumentsSectionState();
}

class _DriverDocumentsSectionState extends State<_DriverDocumentsSection> {
  // Local upload state per doc key
  final Map<String, bool> _uploading = {};

  bool _isUploading(String key) => _uploading[key] == true;

  Future<void> _uploadDoc(String fieldKey, String storageSubPath) async {
    setState(() => _uploading[fieldKey] = true);
    try {
      final svc = FirebaseStorageService.instance;
      final url = await svc.pickCameraAndUpload(
        storagePath: 'driver_docs/${widget.uid}/$storageSubPath.jpg',
      );
      if (url != null && mounted) {
        final updates = <String, dynamic>{fieldKey: url};
        // Track upload date for driver license renewal
        if (fieldKey == 'driverLicenseFrontUrl') {
          updates['driverLicenseUpdatedAt'] = DateTime.now().toIso8601String();
        }

        // ВРЕМЕННО: Автоматически подтверждаем документ при загрузке
        if (fieldKey.startsWith('driverLicense')) {
          updates['driverLicenseVerified'] = true;
        } else if (fieldKey.startsWith('techPassport')) {
          updates['techPassportVerified'] = true;
        } else if (fieldKey.startsWith('faceControl')) {
          updates['faceControlVerified'] = true;
          updates['lastCheckInAt'] = DateTime.now().toIso8601String();
        }

        await FirestoreRepository.instance.updatePartner(widget.uid, updates);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('✅ Документ загружен'),
              backgroundColor: const Color(0xFF6FBF4F),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading[fieldKey] = false);
    }
  }

  /// Returns how many days ago the driver license was last uploaded. null = never.
  int? _licenseAgeDays() {
    final dt = widget.profile?.driverLicenseUpdatedAt;
    if (dt == null) return null;
    return DateTime.now().difference(dt).inDays;
  }

  /// Returns how many days ago check-in was last done. null = never.
  int? _checkInAgeDays() {
    final dt = widget.profile?.lastCheckInAt;
    if (dt == null) return null;
    return DateTime.now().difference(dt).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final ageDays = _licenseAgeDays();
    final licenseExpired = ageDays != null && ageDays >= 10;
    final licenseWarning = ageDays != null && ageDays >= 7 && !licenseExpired;
    final checkInAgeDays = _checkInAgeDays();
    final checkInExpired = checkInAgeDays == null || checkInAgeDays >= 10;
    final checkInWarning = checkInAgeDays != null && checkInAgeDays >= 7 && !checkInExpired;

    return Column(
      children: [
        // ── Водительское удостоверение ──────────────────────────────
        _docGroupCard(
          title: 'Водительское удостоверение',
          subtitle: ageDays == null
              ? 'Требуется обновление каждые 10 дней'
              : licenseExpired
                  ? '⚠️ Просрочено — обновите права!'
                  : licenseWarning
                      ? '⚠️ Обновите через ${10 - ageDays} дн.'
                      : 'Загружены $ageDays дн. назад',
          subtitleColor: ageDays == null
              ? CupertinoColors.systemGrey
              : licenseExpired
                  ? CupertinoColors.systemRed
                  : licenseWarning
                      ? CupertinoColors.systemOrange
                      : CupertinoColors.systemGreen,
          icon: CupertinoIcons.creditcard_fill,
          iconColor: const Color(0xFF6FBF4F),
          children: [
            _docTile(
              label: 'Лицевая сторона',
              fieldKey: 'driverLicenseFrontUrl',
              storagePath: 'license_front',
              currentUrl: p?.driverLicenseFrontUrl,
            ),
            _tileDivider(),
            _docTile(
              label: 'Обратная сторона',
              fieldKey: 'driverLicenseBackUrl',
              storagePath: 'license_back',
              currentUrl: p?.driverLicenseBackUrl,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Технический паспорт ─────────────────────────────────────
        _docGroupCard(
          title: 'Технический паспорт авто',
          subtitle: 'Обе стороны документа',
          subtitleColor: CupertinoColors.systemGrey,
          icon: CupertinoIcons.car_fill,
          iconColor: CupertinoColors.systemOrange,
          children: [
            _docTile(
              label: 'Лицевая сторона',
              fieldKey: 'techPassportFrontUrl',
              storagePath: 'tech_passport_front',
              currentUrl: p?.techPassportFrontUrl,
            ),
            _tileDivider(),
            _docTile(
              label: 'Обратная сторона',
              fieldKey: 'techPassportBackUrl',
              storagePath: 'tech_passport_back',
              currentUrl: p?.techPassportBackUrl,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Check-in ─────────────────────────────────────────────────
        _docGroupCard(
          title: 'Check-in',
          subtitle: checkInAgeDays == null
              ? 'Требуется каждые 10 дней'
              : checkInExpired
                  ? '⚠️ Срок истёк — пройдите check-in заново'
                  : checkInWarning
                      ? '⚠️ Обновите через ${10 - checkInAgeDays} дн.'
                      : 'Пройден $checkInAgeDays дн. назад',
          subtitleColor: checkInAgeDays == null
              ? CupertinoColors.systemGrey
              : checkInExpired
                  ? CupertinoColors.systemRed
                  : checkInWarning
                      ? CupertinoColors.systemOrange
                      : CupertinoColors.systemGreen,
          icon: CupertinoIcons.person_crop_circle_badge_checkmark,
          iconColor: CupertinoColors.systemGreen,
          children: [
            _docTile(
              label: 'Фото лица',
              fieldKey: 'faceControlUrl',
              storagePath: 'face_control',
              currentUrl: p?.faceControlUrl,
            ),
          ],
        ),
      ],
    );
  }

  Widget _docGroupCard({
    required String title,
    required String subtitle,
    required Color subtitleColor,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: widget.cardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: widget.isDark ? Colors.white : const Color(0xFF1C1C1E),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: widget.isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _docTile({
    required String label,
    required String fieldKey,
    required String storagePath,
    String? currentUrl,
  }) {
    final isUploading = _isUploading(fieldKey);
    final uploaded = currentUrl != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Photo preview / placeholder
          GestureDetector(
            onTap: uploaded ? () => _showImagePreview(currentUrl) : null,
            child: Container(
              width: 56,
              height: 44,
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: uploaded
                      ? CupertinoColors.systemGreen.withValues(alpha: 0.5)
                      : (widget.isDark ? Colors.white10 : Colors.black12),
                  width: 1.5,
                ),
                image: uploaded
                    ? DecorationImage(
                        image: NetworkImage(currentUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: uploaded
                  ? null
                  : Icon(
                      CupertinoIcons.photo,
                      color: widget.isDark ? Colors.white38 : Colors.black26,
                      size: 20,
                    ),
            ),
          ),
          const SizedBox(width: 12),

          // Label + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: widget.isDark ? Colors.white : const Color(0xFF1C1C1E),
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  uploaded ? '✓ Загружено' : 'Не загружено',
                  style: TextStyle(
                    color: uploaded
                        ? CupertinoColors.systemGreen
                        : CupertinoColors.systemGrey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Upload button
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: isUploading
                ? null
                : () => _uploadDoc(fieldKey, storagePath),
            child: isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CupertinoActivityIndicator(),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6FBF4F).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      uploaded ? 'Обновить' : 'Загрузить',
                      style: const TextStyle(
                        color: Color(0xFF6FBF4F),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tileDivider() => Divider(
    height: 1,
    indent: 84,
    color: widget.isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
  );

  void _showImagePreview(String url) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        color: Colors.black,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                    child: const Icon(CupertinoIcons.xmark_circle_fill,
                        color: Colors.white, size: 32),
                  ),
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : const Center(child: CupertinoActivityIndicator(color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



// ===========================================================================
// Shared widgets
// ===========================================================================

class _SettingsCard extends StatelessWidget {
  final bool isDark;
  final List<Widget> items;
  const _SettingsCard({required this.isDark, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Column(
        children:
            items.expand((item) => [item, const Divider(height: 1)]).toList()
              ..removeLast(),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? trailingText;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.trailingText,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyLarge?.color,
          fontSize: 15,
        ),
      ),
      trailing:
          trailing ??
          (trailingText != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      trailingText!,
                      style: const TextStyle(
                        color: CupertinoColors.systemGrey,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      CupertinoIcons.chevron_right,
                      color: CupertinoColors.systemGrey,
                      size: 16,
                    ),
                  ],
                )
              : onTap != null
              ? const Icon(
                  CupertinoIcons.chevron_right,
                  color: CupertinoColors.systemGrey,
                  size: 16,
                )
              : null),
      onTap: onTap,
    );
  }
}

class _MetricsSection extends StatelessWidget {
  final PartnerProfile? profile;
  final bool isDark;

  const _MetricsSection({required this.profile, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (profile == null) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: _MetricItem(
            label: 'Рейти��г',
            value: profile!.rating.toStringAsFixed(1),
            icon: CupertinoIcons.star_fill,
            iconColor: CupertinoColors.systemYellow,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricItem(
            label: 'Уровень',
            value: profile!.level,
            icon: CupertinoIcons.graph_square_fill,
            iconColor: const Color(0xFF6FBF4F),
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricItem(
            label: 'Приоритет',
            value: '+${profile!.priority}',
            icon: CupertinoIcons.shield_fill,
            iconColor: CupertinoColors.systemGreen,
            isDark: isDark,
          ),
        ),
      ],
    );
  }
}

class _MetricItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final bool isDark;

  const _MetricItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: CupertinoColors.systemGrey,
            ),
          ),
        ],
      ),
    );
  }
}
