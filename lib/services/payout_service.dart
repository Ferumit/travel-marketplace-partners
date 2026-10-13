import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class PayoutService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Запрашивает выплату на карту партнёра
  static Future<bool> requestPayout({
    required String partnerId,
    required double amount,
    required String cardPan,
  }) async {
    try {
      final result = await _functions.httpsCallable('requestFreedomPayout').call({
        'partnerId': partnerId,
        'amount': amount,
        'cardPan': cardPan,
      });

      final data = result.data;
      if (data['success'] == true) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Payout Flow Error: $e');
      throw Exception('Ошибка при выводе средств. Проверьте баланс или попробуйте позже.');
    }
  }
}
