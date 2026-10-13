import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/partner_models.dart';

class DocumentStatusBanner extends StatelessWidget {
  final bool isDark;
  final PartnerProfile? profile;

  const DocumentStatusBanner({required this.isDark, this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile == null) return const SizedBox.shrink();

    // Build list of missing/unverified required documents
    final missing = <String>[];

    // Driver-only documents
    if (profile!.role.isDriver) {
      if (!profile!.vehicleAdded) {
        missing.add('данные автомобиля');
      }
      if (profile!.driverLicenseFrontUrl == null || profile!.driverLicenseBackUrl == null) {
        missing.add('водительское удостоверение');
      } else if (!profile!.driverLicenseVerified) {
        missing.add('подтверждение прав (на проверке)');
      }
      if (profile!.techPassportFrontUrl == null || profile!.techPassportBackUrl == null) {
        missing.add('тех. паспорт');
      } else if (!profile!.techPassportVerified) {
        missing.add('подтверждение тех. паспорта (на проверке)');
      }
      if (profile!.faceControlUrl == null) {
        missing.add('check-in');
      } else if (profile!.checkInDue) {
        missing.add('check-in (истёк срок)');
      }
      if (profile!.vehicleAdded && !profile!.vehicleInspectionVerified) {
        missing.add('фотоконтроль автомобиля (на проверке)');
      }
    }

    // Guide-only documents
    if (profile!.role.isGuide) {
      if (profile!.guideIdFrontUrl == null || profile!.guideIdBackUrl == null) {
        missing.add('удостоверение личности');
      } else if (!profile!.guideIdVerified) {
        missing.add('подтверждение УЛ (на проверке)');
      }
      if (profile!.guideCertificateUrl == null) {
        missing.add('сертификат гида');
      } else if (!profile!.guideCertificateVerified) {
        missing.add('подтверждение сертификата (на проверке)');
      }
      if (profile!.guideFaceControlUrl == null) {
        missing.add('check-in');
      } else if (profile!.checkInDue) {
        missing.add('check-in (истёк срок)');
      }
    }

    // No missing docs → all good, hide banner
    if (missing.isEmpty) return const SizedBox.shrink();

    final missingText = missing.join(', ');

    return GestureDetector(
      onTap: () {
        if (profile!.role.isGuide) {
          context.push('/guide-documents');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoColors.systemOrange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CupertinoColors.systemOrange.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                CupertinoIcons.exclamationmark_circle_fill,
                color: CupertinoColors.systemOrange,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Участие в заказах недоступно. Введите данные требующиеся в: $missingText',
                style: const TextStyle(
                  color: CupertinoColors.systemOrange,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FaceControlReminder extends StatelessWidget {
  final bool isDark;
  final PartnerRole role;

  const FaceControlReminder({required this.isDark, required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF6FBF4F).withValues(alpha: 0.1) : const Color(0xFF6FBF4F).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF6FBF4F).withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6FBF4F).withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6FBF4F).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.camera_fill, color: Color(0xFF6FBF4F), size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Check-in',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Раз в 10 дней нужно подтверждать личность фото — без этого заказы недоступны.',
            style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              color: const Color(0xFF6FBF4F),
              padding: const EdgeInsets.symmetric(vertical: 14),
              borderRadius: BorderRadius.circular(14),
              child: const Text('Пройти check-in', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Colors.white)),
              onPressed: () => context.push('/face-control', extra: {'role': role, 'isWeekly': false}),
            ),
          ),
        ],
      ),
    );
  }
}
