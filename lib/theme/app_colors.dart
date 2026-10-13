import 'package:flutter/material.dart';

/// Дизайн-токены Explora Partners — тёмная экспедиционная тема.
///
/// Единый источник правды для цветов. Используйте эти константы вместо
/// хардкода литералов вроде `Color(0xFF6FBF4F)`.
class AppColors {
  AppColors._();

  // ── Фоны ────────────────────────────────────────────────────────────────
  /// Основной фон приложения (почти чёрный с зелёным подтоном).
  static const Color background = Color(0xFF0E1410);

  /// Фон чуть светлее — для секций/градиентных подложек.
  static const Color backgroundElevated = Color(0xFF121A14);

  /// Поверхность карточек.
  static const Color surface = Color(0xFF18211A);

  /// Поверхность карточек выше уровнем (вложенные карточки, поля ввода).
  static const Color surfaceHigh = Color(0xFF1F2A21);

  /// Поверхность для чипов/аватаров.
  static const Color surfaceMuted = Color(0xFF232E25);

  // ── Акцент (бренд-зелёный) ───────────────────────────────────────────────
  /// Основной зелёный акцент (кнопки, активные иконки).
  static const Color accent = Color(0xFF6FBF4F);

  /// Яркий зелёный для текста-ссылок и подсветки значений.
  static const Color accentBright = Color(0xFF8FD46A);

  /// Тёмно-зелёная подложка для зелёных иконок/чипов.
  static const Color accentMuted = Color(0xFF24371F);

  // ── Семантика ─────────────────────────────────────────────────────────────
  /// Красный SOS / тревога.
  static const Color danger = Color(0xFFE5484D);

  /// Фон тревожной карточки (тёмно-красный).
  static const Color dangerSurface = Color(0xFF35191A);

  /// Янтарный — предупреждения / ожидание.
  static const Color warning = Color(0xFFE0A23B);

  /// Фон янтарного чипа.
  static const Color warningSurface = Color(0xFF3A2E15);

  // ── Текст ───────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFEAF0EA);
  static const Color textSecondary = Color(0xFF93A096);
  static const Color textTertiary = Color(0xFF63706A);

  // ── Линии / границы ───────────────────────────────────────────────────────
  static const Color border = Color(0xFF273029);
  static const Color borderStrong = Color(0xFF36443A);

  // ── Радиусы ─────────────────────────────────────────────────────────────
  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 22;
  static const double radiusXl = 28;
}
