import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../models/partner_models.dart';
import '../services/auth_service.dart';
import '../services/firebase_storage_service.dart';
import '../repository/firestore_repository.dart';

class FaceControlScreen extends StatefulWidget {
  final PartnerRole role;
  final bool isWeeklyVerification;

  const FaceControlScreen({
    super.key,
    required this.role,
    this.isWeeklyVerification = false,
  });

  @override
  State<FaceControlScreen> createState() => _FaceControlScreenState();
}

class _FaceControlScreenState extends State<FaceControlScreen> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDriver = widget.role.isDriver;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: CupertinoNavigationBar(
        middle: Text(
          'Check-in',
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        backgroundColor: Colors.transparent,
        border: null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // ── Camera Placeholder ──────────────────────────────────────
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: const Color(0xFF6FBF4F).withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(
                        CupertinoIcons.viewfinder,
                        size: 100,
                        color: Color(0xFF6FBF4F),
                      ),
                      if (_isProcessing)
                        const CupertinoActivityIndicator(radius: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ── Instructions ────────────────────────────────────────────
              Text(
                'Инструкция',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              
              _InstructionItem(
                icon: CupertinoIcons.device_phone_portrait,
                text: 'Держите телефон на уровне лица',
                isDark: isDark,
              ),
              _InstructionItem(
                icon: CupertinoIcons.person_2_fill,
                text: 'Убедитесь, что в кадре только вы',
                isDark: isDark,
              ),

              if (isDriver) ...[
                _InstructionItem(
                  icon: CupertinoIcons.car_fill,
                  text: 'Сядьте за руль',
                  isDark: isDark,
                ),
                _InstructionItem(
                  icon: CupertinoIcons.eye_slash_fill,
                  text: 'Снимите головной убор и очки',
                  isDark: isDark,
                ),
              ] else ...[
                _InstructionItem(
                  icon: CupertinoIcons.square_fill,
                  text: 'Встаньте на белом фоне',
                  isDark: isDark,
                ),
              ],

              const SizedBox(height: 32),

              // ── Action Button ───────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: CupertinoButton(
                  color: const Color(0xFF6FBF4F),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: _isProcessing ? null : () async {
                    setState(() => _isProcessing = true);
                    
                    try {
                      final picker = ImagePicker();
                      final xFile = await picker.pickImage(
                        source: ImageSource.camera,
                        preferredCameraDevice: CameraDevice.front,
                        imageQuality: 80,
                        maxWidth: 1080,
                      );

                      if (xFile == null) {
                        setState(() => _isProcessing = false);
                        return; // User canceled
                      }

                      final uid = AuthService.instance.currentUser?.uid;
                      if (uid != null) {
                        final file = File(xFile.path);
                        final path = 'partners/$uid/face_control/${DateTime.now().millisecondsSinceEpoch}.jpg';
                        final url = await FirebaseStorageService.instance.uploadFile(file: file, path: path);
                        
                        if (url != null) {
                          final now = DateTime.now().toIso8601String();
                          if (isDriver) {
                            await FirestoreRepository.instance.updatePartner(uid, {
                              'faceControlUrl': url,
                              'faceControlVerified': true,
                              'lastCheckInAt': now,
                            });
                          } else {
                            await FirestoreRepository.instance.updatePartner(uid, {
                              'guideFaceControlUrl': url,
                              'guideFaceControlVerified': true,
                              'guideLastCheckInAt': now,
                            });
                          }
                          if (!context.mounted) return;
                          context.pop(true);
                        } else if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Не удалось загрузить фото. Попробуйте ещё раз.')),
                          );
                        }
                      }
                    } catch (e) {
                      debugPrint('Face control error: $e');
                      if (context.mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text('Ошибка при загрузке фото. Проверьте права на камеру.')),
                         );
                      }
                    } finally {
                      if (mounted) setState(() => _isProcessing = false);
                    }
                  },
                  child: const Text(
                    'Сделать фото',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstructionItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isDark;

  const _InstructionItem({
    required this.icon,
    required this.text,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6FBF4F).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF6FBF4F)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
