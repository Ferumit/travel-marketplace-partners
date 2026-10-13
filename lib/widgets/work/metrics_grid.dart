import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../models/partner_models.dart';

class MetricsGrid extends StatelessWidget {
  final bool isDark;
  final PartnerProfile? profile;

  const MetricsGrid({super.key, required this.isDark, this.profile});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MetricCard(
            title: 'Рейтинг',
            value: (profile?.rating.toStringAsFixed(2) ?? '5.0'),
            icon: CupertinoIcons.star_fill,
            iconColor: Colors.amber,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricCard(
            title: 'Уровень',
            value: (profile?.level ?? 'Bronze'),
            icon: CupertinoIcons.graph_square_fill,
            iconColor: Theme.of(context).primaryColor,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricCard(
            title: 'Приоритет',
            value: '+${profile?.priority ?? 0}',
            icon: CupertinoIcons.shield_fill,
            iconColor: CupertinoColors.systemGreen,
            isDark: isDark,
          ),
        ),
      ],
    );
  }
}

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final bool isDark;

  const MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF2A2D34).withValues(alpha: 0.8),
                  const Color(0xFF1C1C1E).withValues(alpha: 0.9),
                ]
              : [
                  Colors.white,
                  const Color(0xFFF9F9FB),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: CupertinoColors.systemGrey,
            ),
          ),
        ],
      ),
    );
  }
}
