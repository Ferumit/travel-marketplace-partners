import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_colors.dart';


enum TurnDirection {
  straight,
  left,
  right,
  slightLeft,
  slightRight,
  uTurn,
  destination,
}

class TurnInstruction {
  final TurnDirection direction;
  final double distanceMeters;

  const TurnInstruction(this.direction, this.distanceMeters);
}

class NavigationOverlay extends StatelessWidget {
  final double speedKmh;
  final TurnInstruction? nextTurn;

  const NavigationOverlay({super.key, this.speedKmh = 0.0, this.nextTurn});

  IconData _getTurnIcon(TurnDirection direction) {
    switch (direction) {
      case TurnDirection.left:
        return LucideIcons.cornerUpLeft;
      case TurnDirection.right:
        return LucideIcons.cornerUpRight;
      case TurnDirection.slightLeft:
        return LucideIcons.arrowUpLeft;
      case TurnDirection.slightRight:
        return LucideIcons.arrowUpRight;
      case TurnDirection.uTurn:
        return LucideIcons.cornerDownLeft;
      case TurnDirection.straight:
        return LucideIcons.arrowUp;
      case TurnDirection.destination:
        return LucideIcons.mapPin;
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toInt()} м';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} км';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60, // below back button
      left: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Next Turn Indicator
          if (nextTurn != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: context.surfaceColor.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: context.borderColor.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: context.primaryColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getTurnIcon(nextTurn!.direction),
                      color: context.textPrimary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDistance(nextTurn!.distanceMeters),
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Speedometer
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: context.surfaceColor.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: context.borderColor.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  speedKmh.toInt().toString(),
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                Text(
                  'км/ч',
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

extension NavigationThemeExt on BuildContext {
  Color get primaryColor => AppColors.accent;
  Color get errorColor => AppColors.danger;
  Color get surfaceColor => AppColors.surface;
  Color get borderColor => AppColors.border;
  Color get textPrimary => AppColors.textPrimary;
  Color get textSecondary => AppColors.textSecondary;
}

