import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

class MusklNavItem {
  const MusklNavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Barra inferior con una selección visible y animada.
class MusklBottomNav extends StatelessWidget {
  const MusklBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<MusklNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgDeep.withValues(alpha: .78),
            border: Border(
              top: BorderSide(
                  color: AppColors.glassBorder.withValues(alpha: .8)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 70),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == currentIndex,
                        label: items[i].label,
                        onTap: () => onTap(i),
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: () => onTap(i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Center(
                              heightFactor: 1,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  gradient: i == currentIndex
                                      ? const LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0x42FF5263),
                                            Color(0x18FF3348),
                                          ],
                                        )
                                      : null,
                                  border: i == currentIndex
                                      ? Border.all(
                                          color: AppColors.red
                                              .withValues(alpha: .3))
                                      : null,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      items[i].icon,
                                      size: 21,
                                      color: i == currentIndex
                                          ? AppColors.redLight
                                          : AppColors.textMuted,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      items[i].label,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.nunitoSans(
                                        fontSize: 11,
                                        fontWeight: i == currentIndex
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: i == currentIndex
                                            ? AppColors.redLight
                                            : AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
