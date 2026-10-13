import 'package:explora_partners_app/services/auth_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/partner_models.dart';
import '../repository/firestore_repository.dart';
import '../theme/app_colors.dart';
import '../utils/firebase_auth_module.dart';

/// Экран аутентификации Explora Partners.
///
/// Единственный начальный экран — красивая форма входа/регистрации по email.
/// Телефонный hero-экран удалён; email-авторизация — первый и единственный шаг.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  // 0 — Вход, 1 — Регистрация
  int _tabIndex = 0;
  bool _isLoading = false;

  // Регистрация: шаг 1 — данные, шаг 2 — тип аккаунта, шаг 3 — роль
  int _registerStep = 1;
  bool? _isGuideAccount;
  PartnerRole? _selectedRole;
  int _vehicleCapacity = 5;

  // Видимость пароля
  bool _passwordVisible = false;

  // Контроллеры полей
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  bool get _isLogin => _tabIndex == 0;

  void _switchTab(int index) {
    setState(() {
      _tabIndex = index;
      _registerStep = 1;
      _isGuideAccount = null;
      _selectedRole = null;
      _vehicleCapacity = 5;
    });
  }

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
      default:
        return 10;
    }
  }

  // ── Логика ──────────────────────────────────────────────────────────────────

  void _onLoginTap() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showError('Введите email и пароль');
      return;
    }
    setState(() => _isLoading = true);
    final result = await FirebaseAuthModule.signInWithEmail(
      email: email,
      password: password,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!result.success) _showError(result.errorMessage ?? 'Ошибка входа');
  }

  void _onGoogleSignIn() async {
    setState(() => _isLoading = true);
    final result = await FirebaseAuthModule.signInWithGoogle();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!result.success) {
      _showError(result.errorMessage ?? 'Ошибка входа через Google');
    } else if (result.user != null) {
      _checkAndCreatePartnerProfile(result.user!.uid, result.user!.displayName);
    }
  }

  void _onAppleSignIn() async {
    setState(() => _isLoading = true);
    final result = await FirebaseAuthModule.signInWithApple();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!result.success) {
      _showError(result.errorMessage ?? 'Ошибка входа через Apple');
    } else if (result.user != null) {
      _checkAndCreatePartnerProfile(result.user!.uid, result.user!.displayName);
    }
  }

  Future<void> _checkAndCreatePartnerProfile(
    String uid,
    String? displayName,
  ) async {
    final existing = await FirestoreRepository.instance.getPartner(uid);
    if (existing != null) return;
    if (!mounted) return;
    _showRolePickerSheet(uid, displayName);
  }

  void _showRolePickerSheet(String uid, String? displayName) {
    bool? pickedIsGuide;
    PartnerRole? pickedRole;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState2) {
          final names = (displayName ?? '').split(' ');
          final firstName = names.isNotEmpty ? names.first : '';
          final lastName = names.length > 1 ? names.sublist(1).join(' ') : '';

          Future<void> save() async {
            if (pickedRole == null) return;
            final isDriver =
                pickedRole == PartnerRole.suvDriver ||
                pickedRole == PartnerRole.busDriver ||
                pickedRole == PartnerRole.minibusDriver ||
                pickedRole == PartnerRole.minivanDriver;
            final profile = PartnerProfile(
              id: uid,
              firstName: firstName,
              lastName: lastName,
              email: '',
              role: pickedRole!,
              vehicleCapacity: isDriver ? 4 : 0,
              vehicleType: pickedRole!.vehicleTypeCode,
            );
            await FirestoreRepository.instance.savePartner(profile);
            await AuthService.instance.refreshProfile();
            if (ctx.mounted) Navigator.of(ctx).pop();
          }

          Widget _typeCard(bool isGuide, String title, String subtitle, IconData icon) {
            final isSelected = pickedIsGuide == isGuide;
            return GestureDetector(
              onTap: () => setState2(() {
                pickedIsGuide = isGuide;
                pickedRole = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF6FBF4F).withAlpha(30) : const Color(0xFF2C2C2E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF6FBF4F) : Colors.white12,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF6FBF4F) : Colors.white12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: isSelected ? const Color(0xFF0B1209) : Colors.white54, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(color: isSelected ? const Color(0xFF6FBF4F) : Colors.white, fontSize: 16, fontWeight: FontWeight.bold, decoration: TextDecoration.none)),
                          const SizedBox(height: 4),
                          Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13, decoration: TextDecoration.none)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return Container(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    pickedIsGuide == null ? 'Выберите тип аккаунта' : 'Выберите роль',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Роль нельзя будет изменить самостоятельно',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white54,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (pickedIsGuide == null) ...[
                    _typeCard(true, 'Я Гид', 'Пешие экскурсии, эко-тропы, города', LucideIcons.mapPin),
                    _typeCard(false, 'Я Водитель', 'Трансфер, экспедиции, туры', LucideIcons.car),
                  ] else ...[
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: PartnerRole.values.where((r) {
                          if (pickedIsGuide!) {
                            return r == PartnerRole.guide || r == PartnerRole.cityGuide;
                          } else {
                            return r != PartnerRole.guide && r != PartnerRole.cityGuide;
                          }
                        }).map((role) {
                          final isSelected = pickedRole == role;
                          return GestureDetector(
                            onTap: () => setState2(() => pickedRole = role),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF6FBF4F).withAlpha(30)
                                    : const Color(0xFF2C2C2E),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF6FBF4F)
                                      : Colors.white12,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _roleLabel(role),
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: isSelected
                                            ? const Color(0xFF6FBF4F)
                                            : Colors.white,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      CupertinoIcons.checkmark_circle_fill,
                                      color: Color(0xFF6FBF4F),
                                      size: 20,
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: pickedRole == null
                              ? Colors.white24
                              : const Color(0xFF6FBF4F),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        onPressed: pickedRole == null ? null : save,
                        child: const Text(
                          'Продолжить',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: GestureDetector(
                        onTap: () => setState2(() => pickedIsGuide = null),
                        child: const Text(
                          '← Назад к типу аккаунта',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _roleLabel(PartnerRole role) {
    switch (role) {
      case PartnerRole.suvDriver:
        return 'Водитель SUV';
      case PartnerRole.busDriver:
        return 'Водитель автобуса';
      case PartnerRole.minibusDriver:
        return 'Водитель минибуса';
      case PartnerRole.minivanDriver:
        return 'Водитель минивэна';
      case PartnerRole.guide:
        return 'Гид';
      case PartnerRole.cityGuide:
        return 'Городской гид';
    }
  }

  void _onNextStepTap() {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      _showError('Заполните все поля');
      return;
    }
    if (password.length < 6) {
      _showError('Пароль должен содержать не менее 6 символов');
      return;
    }
    setState(() => _registerStep = 2);
  }

  void _onRegisterTap() async {
    if (_selectedRole == null) {
      _showError('Выберите роль');
      return;
    }
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() => _isLoading = true);

    final result = await FirebaseAuthModule.registerWithEmail(
      email: email,
      password: password,
      displayName: '$firstName $lastName',
    );

    if (!result.success) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(result.errorMessage ?? 'Ошибка регистрации');
      }
      return;
    }

    try {
      final uid = result.user!.uid;
      final profile = PartnerProfile(
        id: uid,
        firstName: firstName,
        lastName: lastName,
        email: email,
        role: _selectedRole!,
        vehicleCapacity: _selectedRoleIsDriver ? _vehicleCapacity : 0,
        vehicleType: _selectedRole!.vehicleTypeCode,
      );
      await FirestoreRepository.instance.savePartner(profile);
      await AuthService.instance.refreshProfile();
    } catch (e) {
      debugPrint('[AuthScreen] Ошибка сохранения профиля: $e');
      if (mounted) {
        _showError(
          'Аккаунт создан, но профиль не сохранился: $e\n'
          'Попробуйте отредактировать профиль в настройках.',
        );
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CupertinoColors.systemRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Фон: топо-карта ──
          Positioned.fill(
            child: Image.asset('assets/images/topo_bg.png', fit: BoxFit.cover),
          ),
          // ── Градиент поверх фона ──
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0.60),
                    AppColors.background.withValues(alpha: 0.97),
                  ],
                ),
              ),
            ),
          ),
          // ── Контент ──
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: _buildBody(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),

        // ── Логотип + заголовок ──
        Center(
          child: Column(
            children: [
              // EP badge
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  LucideIcons.mountain,
                  color: Color(0xFF0B1209),
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Explora Partners',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isLogin
                    ? 'Войдите в рабочий кабинет'
                    : (_registerStep == 1
                          ? 'Создайте аккаунт партнёра'
                          : (_registerStep == 2
                              ? 'Шаг 2 из 3 — Выберите тип аккаунта'
                              : 'Шаг 3 из 3 — Выберите роль')),
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // ── Табы Вход / Регистрация ──
        _buildTabSwitcher(),
        const SizedBox(height: 24),

        // ── Форма ──
        if (_isLogin) ..._buildLoginForm(),
        if (!_isLogin && _registerStep == 1) ..._buildRegStep1(),
        if (!_isLogin && _registerStep == 2) ..._buildRegStep2(),
        if (!_isLogin && _registerStep == 3) ..._buildRegStep3(),

        const SizedBox(height: 28),

        // ── Разделитель + соцсети (только для входа) ──
        if (_isLogin) ..._buildSocialLogin(context),

        const SizedBox(height: 24),

        // ── Правовой текст ──
        const Center(
          child: Text(
            'Продолжая, вы принимаете правила работы партнёров '
            'Explora и политику обработки геоданных.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Таб-переключатель ────────────────────────────────────────────────────────

  Widget _buildTabSwitcher() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _tab(label: 'Вход', index: 0),
          _tab(label: 'Регистрация', index: 1),
        ],
      ),
    );
  }

  Widget _tab({required String label, required int index}) {
    final selected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchTab(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? const Color(0xFF0B1209) : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ── Форма входа ──────────────────────────────────────────────────────────────

  List<Widget> _buildLoginForm() {
    return [
      _inputField(
        controller: _emailController,
        placeholder: 'Email',
        icon: LucideIcons.mail,
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: 12),
      _inputField(
        controller: _passwordController,
        placeholder: 'Пароль',
        icon: LucideIcons.lock,
        isSecret: true,
      ),
      const SizedBox(height: 24),
      _primaryButton(
        label: 'Войти',
        onPressed: _isLoading ? null : _onLoginTap,
        isLoading: _isLoading,
      ),
    ];
  }

  // ── Регистрация: шаг 1 ───────────────────────────────────────────────────────

  List<Widget> _buildRegStep1() {
    return [
      Row(
        children: [
          Expanded(
            child: _inputField(
              controller: _firstNameController,
              placeholder: 'Имя',
              icon: LucideIcons.user,
              keyboardType: TextInputType.name,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _inputField(
              controller: _lastNameController,
              placeholder: 'Фамилия',
              icon: LucideIcons.user,
              keyboardType: TextInputType.name,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _inputField(
        controller: _emailController,
        placeholder: 'Email',
        icon: LucideIcons.mail,
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: 12),
      _inputField(
        controller: _passwordController,
        placeholder: 'Придумайте пароль (минимум 6 символов)',
        icon: LucideIcons.lock,
        isSecret: true,
      ),
      const SizedBox(height: 24),
      _primaryButton(label: 'Далее →', onPressed: _onNextStepTap),
    ];
  }

  // ── Регистрация: шаг 2 — Тип аккаунта ────────────────────────────────────────

  List<Widget> _buildRegStep2() {
    return [
      _accountTypeCard(
        isGuide: true,
        title: 'Я Гид',
        subtitle: 'Пешие экскурсии, эко-тропы, города',
        icon: LucideIcons.mapPin,
      ),
      const SizedBox(height: 12),
      _accountTypeCard(
        isGuide: false,
        title: 'Я Водитель',
        subtitle: 'Трансфер, экспедиции, туры',
        icon: LucideIcons.car,
      ),
      const SizedBox(height: 20),
      _primaryButton(
        label: 'Далее →',
        onPressed: _isGuideAccount == null
            ? null
            : () {
                setState(() {
                  _registerStep = 3;
                  if (_isGuideAccount! && _selectedRoleIsDriver) {
                    _selectedRole = null;
                  }
                  if (!_isGuideAccount! && !_selectedRoleIsDriver && _selectedRole != null) {
                    _selectedRole = null;
                  }
                });
              },
      ),
      const SizedBox(height: 12),
      Center(
        child: GestureDetector(
          onTap: () => setState(() => _registerStep = 1),
          child: const Text(
            '← Назад к данным',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _accountTypeCard({
    required bool isGuide,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _isGuideAccount == isGuide;
    return GestureDetector(
      onTap: () => setState(() => _isGuideAccount = isGuide),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? const Color(0xFF0B1209) : AppColors.textSecondary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? AppColors.accentBright : AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                LucideIcons.checkCircle2,
                color: AppColors.accent,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  // ── Регистрация: шаг 3 — Роль ────────────────────────────────────────────────

  List<Widget> _buildRegStep3() {
    return [
      ..._roleOptions(),
      if (_selectedRole == PartnerRole.suvDriver) ...[
        const SizedBox(height: 14),
        _fixedCapacityCard(
          title: 'Вместимость: 4 места',
          description: '1 водитель + 3 пассажира\n(или 1 водитель + 1 гид + 2 пассажира)',
        ),
      ] else if (_selectedRole == PartnerRole.minivanDriver) ...[
        const SizedBox(height: 14),
        _fixedCapacityCard(
          title: 'Вместимость: 7 мест',
          description: '1 водитель + 1 гид + 5 пассажиров',
        ),
      ] else if (_selectedRole == PartnerRole.minibusDriver ||
          _selectedRole == PartnerRole.busDriver) ...[
        const SizedBox(height: 14),
        _seatsStepperCard(
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
      const SizedBox(height: 20),
      _primaryButton(
        label: 'Создать аккаунт',
        onPressed: (_isLoading || _selectedRole == null) ? null : _onRegisterTap,
        isLoading: _isLoading,
      ),
      const SizedBox(height: 12),
      Center(
        child: GestureDetector(
          onTap: () => setState(() => _registerStep = 2),
          child: const Text(
            '← Назад к типу аккаунта',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ];
  }

  // ── Соцсети (вход) ───────────────────────────────────────────────────────────

  List<Widget> _buildSocialLogin(BuildContext context) {
    return [
      Row(
        children: [
          Expanded(child: Divider(color: AppColors.border)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'или войдите через',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
          ),
          Expanded(child: Divider(color: AppColors.border)),
        ],
      ),
      const SizedBox(height: 14),
      _socialButton(
        label: 'Войти через Google',
        icon: const _GoogleLogoWidget(),
        onPressed: _isLoading ? null : _onGoogleSignIn,
      ),
      if (Theme.of(context).platform == TargetPlatform.iOS) ...[
        const SizedBox(height: 10),
        _socialButton(
          label: 'Войти через Apple',
          icon: Icon(LucideIcons.apple, color: Colors.white, size: 20),
          onPressed: _isLoading ? null : _onAppleSignIn,
          darkBackground: true,
        ),
      ],
    ];
  }

  // ── Карточки ролей ───────────────────────────────────────────────────────────

  List<Widget> _roleOptions() {
    final roles = [
      if (_isGuideAccount == true) ...[
        (PartnerRole.guide, 'Гид', 'Пешие эко-тропы', LucideIcons.personStanding),
        (PartnerRole.cityGuide, 'Городской гид', 'Обзорные экскурсии', LucideIcons.building2),
      ] else if (_isGuideAccount == false) ...[
        (PartnerRole.suvDriver, 'Водитель внедорожника', 'Экспедиции & оффроад', LucideIcons.car),
        (PartnerRole.busDriver, 'Водитель автобуса', 'Крупные тур. группы', LucideIcons.bus),
        (PartnerRole.minibusDriver, 'Водитель микроавтобуса', 'Группы до 15 чел.', LucideIcons.truck),
        (PartnerRole.minivanDriver, 'Водитель минивена', 'Комфорт до 7 мест', LucideIcons.car),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.accent.withValues(alpha: 0.12)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? AppColors.accent : AppColors.border,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.accent : AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? const Color(0xFF0B1209) : AppColors.textSecondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isSelected ? AppColors.accentBright : AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    LucideIcons.checkCircle2,
                    color: AppColors.accent,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  // ── Вспомогательные виджеты ─────────────────────────────────────────────────

  Widget _inputField({
    required TextEditingController controller,
    required String placeholder,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool isSecret = false,
  }) {
    final isPasswordField = isSecret;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(icon, size: 18, color: AppColors.textTertiary),
          const SizedBox(width: 12),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              padding: const EdgeInsets.symmetric(vertical: 16),
              placeholder: placeholder,
              placeholderStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 15),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
              decoration: null,
              keyboardType: isSecret ? TextInputType.visiblePassword : keyboardType,
              obscureText: isPasswordField && !_passwordVisible,
              textInputAction: isSecret ? TextInputAction.done : TextInputAction.next,
            ),
          ),
          if (isPasswordField)
            GestureDetector(
              onTap: () => setState(() => _passwordVisible = !_passwordVisible),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(
                  _passwordVisible ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ),
            )
          else
            const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _fixedCapacityCard({required String title, required String description}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.car, color: AppColors.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(LucideIcons.lock, color: AppColors.textTertiary, size: 16),
        ],
      ),
    );
  }

  Widget _seatsStepperCard({
    required int seats,
    required int maxSeats,
    required VoidCallback? onDecrement,
    required VoidCallback? onIncrement,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Количество мест в автомобиле',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stepperBtn(icon: LucideIcons.minus, onTap: onDecrement),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$seats',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      '${seats - 1} пасс. + 1 водительское',
                      style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              _stepperBtn(icon: LucideIcons.plus, onTap: onIncrement),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepperBtn({required IconData icon, required VoidCallback? onTap}) {
    final active = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active ? AppColors.accent : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: active ? const Color(0xFF0B1209) : AppColors.textTertiary,
          size: 18,
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: onPressed == null ? AppColors.surfaceHigh : AppColors.accent,
          foregroundColor: onPressed == null ? AppColors.textTertiary : const Color(0xFF0B1209),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        onPressed: onPressed,
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF0B1209),
                ),
              )
            : Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
      ),
    );
  }

  Widget _socialButton({
    required String label,
    required Widget icon,
    required VoidCallback? onPressed,
    bool darkBackground = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: darkBackground ? Colors.black : AppColors.surface,
          side: BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          foregroundColor: darkBackground ? Colors.white : AppColors.textPrimary,
        ),
        onPressed: onPressed,
        icon: icon,
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }
}

// ── Google 'G' logo ───────────────────────────────────────────────────────────

class _GoogleLogoWidget extends StatelessWidget {
  const _GoogleLogoWidget();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(20, 20), painter: _GoogleLogoPainter());
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final colors = [
      const Color(0xFF4285F4),
      const Color(0xFFEA4335),
      const Color(0xFFFBBC04),
      const Color(0xFF34A853),
    ];

    for (var i = 0; i < 4; i++) {
      final paint = Paint()..color = colors[i];
      final startAngle = (i * 90 - 45) * 3.14159265358979323846 / 180;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        1.5707963267948966,
        true,
        paint,
      );
    }

    canvas.drawCircle(center, radius * 0.65, Paint()..color = Colors.white);

    final barPaint = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx,
        center.dy - radius * 0.2,
        radius * 0.9,
        radius * 0.38,
      ),
      barPaint,
    );

    canvas.drawCircle(center, radius * 0.4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
