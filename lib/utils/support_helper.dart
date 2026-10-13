import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

class SupportHelper {
  static const String _telegramBotUsername = 'support_bot';
  static const String _whatsappNumber = '70000000000';

  static Future<void> openTelegram() async {
    final Uri url = Uri.parse('https://t.me/$_telegramBotUsername');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        debugPrint('Could not launch Telegram');
      }
    } catch (e) {
      debugPrint('Error launching Telegram: $e');
    }
  }

  static Future<void> openWhatsApp() async {
    final Uri url = Uri.parse('https://wa.me/$_whatsappNumber');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        debugPrint('Could not launch WhatsApp');
      }
    } catch (e) {
      debugPrint('Error launching WhatsApp: $e');
    }
  }
}
