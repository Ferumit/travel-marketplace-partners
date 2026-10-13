import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';

import '../models/partner_models.dart';
import '../repository/firestore_repository.dart';
import '../services/auth_service.dart';
import '../services/firebase_storage_service.dart';

/// Screen for Guide Certificate upload — mirroring VehicleInspectionScreen style
class GuideCertificateScreen extends StatefulWidget {
  final PartnerProfile? profile;
  const GuideCertificateScreen({super.key, this.profile});

  @override
  State<GuideCertificateScreen> createState() => _GuideCertificateScreenState();
}

class _GuideCertificateScreenState extends State<GuideCertificateScreen> {
  final _picker = ImagePicker();
  File? _certificatePhoto;
  bool _submitting = false;

  Future<void> _takePhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked != null && mounted) {
      setState(() => _certificatePhoto = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (_certificatePhoto == null || _submitting) return;
    setState(() => _submitting = true);

    try {
      final uid = AuthService.instance.currentUser?.uid;
      if (uid == null) throw Exception('Не авторизован');

      _snack('⬆️ Загрузка сертификата...', isError: false);

      // 1. Upload to Firebase Storage
      final url = await FirebaseStorageService.instance.uploadFile(
        file: _certificatePhoto!,
        path: 'guide_certificates/${uid}_cert_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      if (url == null) {
        if (mounted) _snack('Не удалось загрузить сертификат. Попробуйте ещё раз.', isError: true);
        return;
      }

      // 2. Update Partner Profile
      await FirestoreRepository.instance.updatePartner(uid, {
        'guideCertificateUrl': url,
        'guideCertificateVerified': true, // ВРЕМЕННО: Автоматически подтверждаем
      });

      if (mounted) {
        _snack('✅ Сертификат отправлен на проверку', isError: false);
        context.pop();
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
        backgroundColor: isError ? CupertinoColors.systemRed : const Color(0xFF6FBF4F),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      CupertinoIcons.doc_plaintext,
                      color: Color(0xFF6FBF4F),
                      size: 64,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Сертификат гида',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Пожалуйста, сфотографируйте ваш действующий сертификат или лицензию гида. Фото должно быть четким, а текст — читаемым.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 15),
                    ),
                    const SizedBox(height: 40),
                    
                    // Photo Placeholder / Preview
                    GestureDetector(
                      onTap: _takePhoto,
                      child: Container(
                        width: double.infinity,
                        height: 250,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: _certificatePhoto != null 
                                ? const Color(0xFF6FBF4F) 
                                : (isDark ? Colors.white12 : Colors.black12),
                            width: 2,
                          ),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: _certificatePhoto != null
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(_certificatePhoto!, fit: BoxFit.cover),
                                  Container(color: Colors.black26),
                                  const Center(
                                    child: Icon(
                                      CupertinoIcons.camera_fill,
                                      color: Colors.white,
                                      size: 48,
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 16,
                                    right: 16,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6FBF4F),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        'Переснять',
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
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
                                    size: 48,
                                    color: isDark ? Colors.white24 : Colors.black12,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Нажмите, чтобы сделать фото',
                                    style: TextStyle(color: CupertinoColors.systemGrey),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Bottom Action
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: CupertinoButton(
                  color: const Color(0xFF6FBF4F),
                  disabledColor: CupertinoColors.systemGrey4,
                  borderRadius: BorderRadius.circular(16),
                  onPressed: (_certificatePhoto == null || _submitting) ? null : _submit,
                  child: _submitting 
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : const Text(
                          'ОТПРАВИТЬ НА ПРОВЕРКУ',
                          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
            child: const Icon(CupertinoIcons.xmark, color: CupertinoColors.systemGrey),
          ),
          const SizedBox(width: 8),
          const Text(
            'Верификация документов',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          _AiBadge(),
        ],
      ),
    );
  }
}

class _AiBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF6FBF4F).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF6FBF4F).withValues(alpha: 0.3)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.sparkles, color: Color(0xFF6FBF4F), size: 12),
          SizedBox(width: 4),
          Text(
            'AI SCAN',
            style: TextStyle(color: Color(0xFF6FBF4F), fontSize: 10, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
