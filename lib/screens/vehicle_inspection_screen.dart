import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/partner_models.dart';
import '../models/vehicle_inspection.dart';
import '../repository/firestore_repository.dart';
import '../services/auth_service.dart';
import '../services/firebase_storage_service.dart';

// ===========================================================================
// Vehicle Inspection Screen — Yandex Pro style + Firebase integration
// ===========================================================================

class VehicleInspectionScreen extends StatefulWidget {
  final PartnerProfile? profile;
  const VehicleInspectionScreen({super.key, this.profile});

  @override
  State<VehicleInspectionScreen> createState() =>
      _VehicleInspectionScreenState();
}

class _VehicleInspectionScreenState extends State<VehicleInspectionScreen> {
  final _picker = ImagePicker();

  // State machine
  bool _loading = true;
  bool _hasActiveTrip = false;
  VehicleInspection? _todayReport; // already submitted today
  bool _submitting = false;
  StreamSubscription<VehicleInspection?>? _reportSub;

  // Inspection data — 5 классических ракурсов кузова + 5 доп. кадров по
  // инструкции (см. аудит: госномер, фары, салон, багажник).
  int _currentIdx = 0;
  final _sides = <String, _SideData>{
    'front': _SideData('Спереди', CupertinoIcons.arrow_up_circle_fill,
        hint: 'Встаньте на 2–3 метра перед машиной, в кадре — весь борт целиком.',
        useCarDiagram: true, checks: _bodyChecks()),
    'right': _SideData('Справа', CupertinoIcons.arrow_right_circle_fill,
        hint: 'Правый борт целиком, от переднего до заднего колеса.',
        useCarDiagram: true, checks: _bodyChecks()),
    'back': _SideData('Сзади', CupertinoIcons.arrow_down_circle_fill,
        hint: 'Задний борт целиком, включая бампер.',
        useCarDiagram: true, checks: _bodyChecks()),
    'left': _SideData('Слева', CupertinoIcons.arrow_left_circle_fill,
        hint: 'Левый борт целиком, от переднего до заднего колеса.',
        useCarDiagram: true, checks: _bodyChecks()),
    'roof': _SideData('Крыша', CupertinoIcons.sun_max_fill,
        hint: 'Крыша и багажник (если есть) сверху или с капота.',
        useCarDiagram: true, checks: _bodyChecks()),
    'plate': _SideData('Госномер', CupertinoIcons.rectangle_fill,
        hint: 'Крупным планом, чтобы номер читался чётко.'),
    'headlights': _SideData('Фары', CupertinoIcons.lightbulb_fill,
        hint: 'Обе фары спереди, видно состояние стёкол.'),
    'interiorFront': _SideData('Салон спереди', CupertinoIcons.square_grid_2x2_fill,
        hint: 'Передние сиденья и приборная панель.'),
    'interiorRear': _SideData('Салон и задние сиденья', CupertinoIcons.rectangle_stack_fill,
        hint: 'Задний ряд сидений целиком.'),
    'trunk': _SideData('Багажник', CupertinoIcons.cube_box_fill,
        hint: 'Багажник открыт, видно свободное место.'),
  };

  static Map<String, bool> _bodyChecks() => {
        'Вмятины / царапины': false,
        'Трещины стёкол': false,
        'Повреждение зеркал': false,
        'Повреждение бампера': false,
        'Следы жидкостей': false,
      };

  List<String> get _sideKeys => _sides.keys.toList();
  String get _currentKey => _sideKeys[_currentIdx];
  _SideData get _current => _sides[_currentKey]!;

  bool get _allPhotoDone => _sides.values.every((d) => d.photo != null);
  double get _progress =>
      _sides.values.where((d) => d.photo != null).length / _sides.length;

  @override
  void initState() {
    super.initState();
    _checkPrerequisites();
  }

  @override
  void dispose() {
    _reportSub?.cancel();
    super.dispose();
  }

  Future<void> _checkPrerequisites() async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    final hasTrip = await FirestoreRepository.instance.hasActiveTrip(uid);
    if (hasTrip) {
      setState(() {
        _hasActiveTrip = true;
        _loading = false;
      });
      return;
    }

    // Subscribe to today's report stream
    _reportSub = FirestoreRepository.instance.streamTodayInspection(uid).listen((report) {
      if (mounted) setState(() => _todayReport = report);
    });

    setState(() => _loading = false);
  }

  Future<void> _takePhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 60,
      maxWidth: 1200,
    );
    if (picked != null && mounted) {
      setState(() => _current.photo = File(picked.path));
    }
  }

  void _next() {
    if (_currentIdx < _sideKeys.length - 1) {
      setState(() => _currentIdx++);
    } else {
      _submit();
    }
  }

  void _prev() {
    if (_currentIdx > 0) setState(() => _currentIdx--);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      final uid = AuthService.instance.currentUser?.uid;
      if (uid == null) throw Exception('Не авторизован');

      final profile = widget.profile;
      final today = _todayDateString();

      // 1. Upload all photos to Firebase Storage in parallel
      _snack('⬆️ Загрузка фотографий...', isError: false);

      final uploadFutures = <String, Future<String?>> {};
      for (final entry in _sides.entries) {
        if (entry.value.photo == null) continue;
        uploadFutures[entry.key] =
            FirebaseStorageService.instance.uploadInspectionPhoto(
          file: entry.value.photo!,
          driverId: uid,
          date: today,
          side: entry.key,
        );
      }

      final photoUrls = <String, String>{};
      for (final entry in uploadFutures.entries) {
        final url = await entry.value;
        if (url != null) photoUrls[entry.key] = url;
      }

      // 2. Build inspection model
      final sidesData = <String, SideInspection>{};
      for (final entry in _sides.entries) {
        sidesData[entry.key] = SideInspection(
          photoUrl: photoUrls[entry.key],
          damageFlags: Map<String, bool>.from(entry.value.checks),
        );
      }

      final inspection = VehicleInspection(
        id: '',
        driverId: uid,
        driverName: profile?.fullName ?? 'Неизвестно',
        vehicleModel: profile?.vehicleModel ?? '',
        vehiclePlate: profile?.vehiclePlate ?? '',
        date: today,
        // Реальный статус всегда выставляется сервером/модератором при
        // сохранении (см. FirestoreRepository.submitInspection) — здесь
        // указываем pending, чтобы локальный объект не расходился с тем,
        // что на самом деле попадёт в Firestore.
        status: InspectionStatus.pending,
        sides: sidesData,
        submittedAt: DateTime.now(),
      );

      // 3. Submit to Firestore
      await FirestoreRepository.instance.submitInspection(inspection);

      if (mounted) {
        _snack('✅ Отчёт отправлен на проверку', isError: false);
        // The StreamBuilder will update _todayReport automatically
      }
    } catch (e) {
      if (mounted) {
        _snack('Ошибка отправки: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? CupertinoColors.systemRed : const Color(0xFF6FBF4F),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  static String _todayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    if (_loading) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CupertinoActivityIndicator()),
      );
    }

    // BLOCK: driver is on active route
    if (_hasActiveTrip) {
      return _buildBlockedScreen(isDark, cardBg);
    }

    // READONLY: report already submitted today
    if (_todayReport != null) {
      return _buildReportStatusScreen(isDark, cardBg, _todayReport!);
    }

    // INSPECTION FORM
    return _buildInspectionForm(isDark, bg, cardBg);
  }

  // ── Blocked Screen ──────────────────────────────────────────────────────────

  Widget _buildBlockedScreen(bool isDark, Color cardBg) {
    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      body: SafeArea(
        child: Column(
          children: [
            _buildMinimalHeader('Фотоконтроль'),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemOrange.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.car_detailed,
                          color: CupertinoColors.systemOrange,
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Маршрут в процессе',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Фотоконтроль недоступен во время активного маршрута.\n\nВернитесь после завершения поездки.',
                        style: TextStyle(
                          fontSize: 15,
                          color: CupertinoColors.systemGrey,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: CupertinoButton(
                          color: const Color(0xFF6FBF4F),
                          borderRadius: BorderRadius.circular(14),
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Понятно',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Report Status Screen (already submitted today) ──────────────────────────

  Widget _buildReportStatusScreen(
      bool isDark, Color cardBg, VehicleInspection report) {
    final statusColor = switch (report.status) {
      InspectionStatus.approved => CupertinoColors.systemGreen,
      InspectionStatus.rejected => CupertinoColors.systemRed,
      InspectionStatus.pending => CupertinoColors.systemOrange,
    };
    final bg = isDark ? Colors.black : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildMinimalHeader('Фотоконтроль'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Status card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                report.status.emoji,
                                style: const TextStyle(fontSize: 36),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            report.status.label,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Отчёт за ${report.date}',
                            style: const TextStyle(
                              color: CupertinoColors.systemGrey,
                              fontSize: 14,
                            ),
                          ),
                          if (report.status == InspectionStatus.rejected &&
                              report.rejectionReason != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: CupertinoColors.systemRed
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '💬 ${report.rejectionReason}',
                                style: const TextStyle(
                                  color: CupertinoColors.systemRed,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                          if (report.hasDamage) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: CupertinoColors.systemOrange
                                    .withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                '⚠️ Зафиксированы повреждения',
                                style: TextStyle(
                                  color: CupertinoColors.systemOrange,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Photo grid
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ФОТОГРАФИИ',
                            style: TextStyle(
                              color: CupertinoColors.systemGrey,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            children: report.sides.entries.map((e) {
                              final sideLabel = _sides[e.key]?.label ?? e.key;
                              final url = e.value.photoUrl;
                              final dmg = e.value.hasDamage;
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: url != null
                                        ? Image.network(url, fit: BoxFit.cover)
                                        : Container(
                                            color: isDark
                                                ? Colors.white12
                                                : Colors.black12,
                                            child: const Icon(
                                                CupertinoIcons.photo,
                                                color: CupertinoColors
                                                    .systemGrey),
                                          ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: const BorderRadius.vertical(
                                            bottom: Radius.circular(10)),
                                      ),
                                      child: Text(
                                        sideLabel,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  if (dmg)
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: CupertinoColors.systemRed,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          CupertinoIcons.exclamationmark,
                                          color: Colors.white,
                                          size: 10,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: CupertinoButton(
                        color: const Color(0xFF6FBF4F),
                        borderRadius: BorderRadius.circular(14),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Готово',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Main Inspection Form ────────────────────────────────────────────────────

  Widget _buildInspectionForm(bool isDark, Color bg, Color cardBg) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark, cardBg),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGuideCard(isDark, cardBg),
                    const SizedBox(height: 20),
                    _buildPhotoSection(isDark, cardBg),
                    if (_current.checks.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildChecklist(isDark, cardBg),
                    ],
                    const SizedBox(height: 24),
                    _buildNavButtons(isDark),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMinimalHeader(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
            child: const Icon(CupertinoIcons.xmark,
                color: CupertinoColors.systemGrey),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color cardBg) {
    return Container(
      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.pop(context),
                child: const Icon(CupertinoIcons.xmark,
                    color: CupertinoColors.systemGrey),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Фотоконтроль',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${(_progress * 100).toInt()}%',
                style: const TextStyle(
                  color: Color(0xFF6FBF4F),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress,
              backgroundColor: isDark ? Colors.white12 : Colors.black12,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF6FBF4F)),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _sideKeys.map((key) {
                final data = _sides[key]!;
                final isActive = key == _currentKey;
                final isDone = data.photo != null;
                return GestureDetector(
                  onTap: () => setState(
                      () => _currentIdx = _sideKeys.indexOf(key)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF6FBF4F)
                          : isDone
                              ? const Color(0xFF6FBF4F)
                                  .withValues(alpha: 0.1)
                              : (isDark
                                  ? Colors.white12
                                  : Colors.black.withValues(alpha: 0.06)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isDone && !isActive
                              ? CupertinoIcons.checkmark_circle_fill
                              : data.icon,
                          size: 14,
                          color: isActive
                              ? Colors.white
                              : isDone
                                  ? const Color(0xFF6FBF4F)
                                  : CupertinoColors.systemGrey,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          data.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? Colors.white
                                : isDone
                                    ? const Color(0xFF6FBF4F)
                                    : CupertinoColors.systemGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideCard(bool isDark, Color cardBg) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            _current.label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          if (_current.useCarDiagram) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: CustomPaint(
                painter: _CarTopViewPainter(activeSideKey: _currentKey),
                child: const SizedBox.expand(),
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF6FBF4F).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(_current.icon, color: const Color(0xFF6FBF4F), size: 30),
            ),
          ],
          if (_current.hint.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              _current.hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.black54,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotoSection(bool isDark, Color cardBg) {
    final photo = _current.photo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ФОТО',
          style: TextStyle(
            color: CupertinoColors.systemGrey,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _takePhoto,
          child: Container(
            height: 180,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: photo != null
                    ? const Color(0xFF6FBF4F)
                    : (isDark ? Colors.white12 : Colors.black12),
                width: photo != null ? 2 : 1,
              ),
            ),
            clipBehavior: Clip.hardEdge,
            child: photo != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(photo, fit: BoxFit.cover),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFF6FBF4F),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(CupertinoIcons.checkmark,
                              color: Colors.white, size: 14),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(CupertinoIcons.camera,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('Переснять',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.camera_fill,
                        size: 36,
                        color: isDark ? Colors.white30 : Colors.black26,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Нажмите для фото',
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black38,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _current.label,
                        style: const TextStyle(
                          color: CupertinoColors.systemGrey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildChecklist(bool isDark, Color cardBg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ПРОВЕРИТЬ НАЛИЧИЕ',
          style: TextStyle(
            color: CupertinoColors.systemGrey,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: _current.checks.keys.map((key) {
              final isLast = key == _current.checks.keys.last;
              return Column(
                children: [
                  CupertinoListTile(
                    leading: Icon(
                      _current.checks[key]!
                          ? CupertinoIcons.exclamationmark_triangle_fill
                          : CupertinoIcons.checkmark_circle,
                      color: _current.checks[key]!
                          ? CupertinoColors.systemRed
                          : CupertinoColors.systemGrey,
                      size: 20,
                    ),
                    title: Text(
                      key,
                      style: TextStyle(
                        color: _current.checks[key]!
                            ? CupertinoColors.systemRed
                            : (isDark ? Colors.white : Colors.black),
                        fontSize: 15,
                      ),
                    ),
                    trailing: CupertinoSwitch(
                      value: _current.checks[key]!,
                      activeTrackColor: CupertinoColors.systemRed,
                      onChanged: (v) =>
                          setState(() => _current.checks[key] = v),
                    ),
                  ),
                  if (!isLast)
                    Divider(
                      height: 0.5,
                      indent: 52,
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildNavButtons(bool isDark) {
    final isLast = _currentIdx == _sideKeys.length - 1;
    return Row(
      children: [
        if (_currentIdx > 0)
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _prev,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  side: BorderSide(
                      color: isDark ? Colors.white24 : Colors.black26),
                ),
                child: const Text('← Назад'),
              ),
            ),
          ),
        if (_currentIdx > 0) const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 52,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              color: isLast && _allPhotoDone
                  ? CupertinoColors.systemGreen
                  : const Color(0xFF6FBF4F),
              borderRadius: BorderRadius.circular(14),
              onPressed: _submitting
                  ? null
                  : (isLast || _current.photo != null ? _next : null),
              child: _submitting
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : Text(
                      isLast
                          ? (_allPhotoDone
                              ? 'Отправить отчёт ✓'
                              : 'Пропустить')
                          : 'Далее →',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Side data holder
// ===========================================================================

class _SideData {
  final String label;
  final IconData icon;
  final String hint;
  final bool useCarDiagram;
  File? photo;
  final Map<String, bool> checks;

  _SideData(
    this.label,
    this.icon, {
    this.hint = '',
    this.useCarDiagram = false,
    Map<String, bool>? checks,
  }) : checks = checks ?? {};
}

// ===========================================================================
// Custom car top-view diagram painter
// ===========================================================================

class _CarTopViewPainter extends CustomPainter {
  final String activeSideKey;
  _CarTopViewPainter({required this.activeSideKey});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const carW = 60.0;
    const carH = 110.0;
    final activeColor = const Color(0xFF6FBF4F);
    final inactiveColor = const Color(0xFF555555);
    final bodyColor = const Color(0xFF2C2C2E);
    final glassPaint = Paint()
      ..color = const Color(0xFF3A3A5C)
      ..style = PaintingStyle.fill;

    // Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: carW, height: carH),
        const Radius.circular(14),
      ),
      Paint()..color = bodyColor,
    );
    // Front glass
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy - 28), width: 44, height: 20),
        const Radius.circular(6),
      ),
      glassPaint,
    );
    // Rear glass
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy + 28), width: 44, height: 18),
        const Radius.circular(6),
      ),
      glassPaint,
    );
    // Wheels
    final wheelPaint = Paint()..color = const Color(0xFF404040);
    for (final pos in [
      Offset(cx - carW / 2 - 6, cy - 30),
      Offset(cx + carW / 2 + 6, cy - 30),
      Offset(cx - carW / 2 - 6, cy + 30),
      Offset(cx + carW / 2 + 6, cy + 30),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: pos, width: 12, height: 22),
          const Radius.circular(3),
        ),
        wheelPaint,
      );
    }

    // Direction arrows
    final sideArrows = {
      'front': Offset(cx, cy - carH / 2 - 20),
      'back': Offset(cx, cy + carH / 2 + 20),
      'left': Offset(cx - carW / 2 - 26, cy),
      'right': Offset(cx + carW / 2 + 26, cy),
    };
    sideArrows.forEach((key, tip) {
      final paint = Paint()
        ..color =
            (key == activeSideKey ? activeColor : inactiveColor.withValues(alpha: 0.4))
        ..style = PaintingStyle.fill;
      _drawArrow(canvas, tip, key, paint);
    });

    // Roof dot
    if (activeSideKey == 'roof') {
      canvas.drawCircle(Offset(cx, cy), 10, Paint()..color = activeColor);
    }
  }

  void _drawArrow(Canvas canvas, Offset tip, String side, Paint paint) {
    const r = 10.0;
    final path = Path();
    switch (side) {
      case 'front':
        path.moveTo(tip.dx, tip.dy - r);
        path.lineTo(tip.dx - r, tip.dy + r);
        path.lineTo(tip.dx + r, tip.dy + r);
        break;
      case 'back':
        path.moveTo(tip.dx, tip.dy + r);
        path.lineTo(tip.dx - r, tip.dy - r);
        path.lineTo(tip.dx + r, tip.dy - r);
        break;
      case 'left':
        path.moveTo(tip.dx - r, tip.dy);
        path.lineTo(tip.dx + r, tip.dy - r);
        path.lineTo(tip.dx + r, tip.dy + r);
        break;
      case 'right':
        path.moveTo(tip.dx + r, tip.dy);
        path.lineTo(tip.dx - r, tip.dy - r);
        path.lineTo(tip.dx - r, tip.dy + r);
        break;
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CarTopViewPainter old) =>
      old.activeSideKey != activeSideKey;
}
