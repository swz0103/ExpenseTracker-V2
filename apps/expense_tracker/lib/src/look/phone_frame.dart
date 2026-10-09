import 'package:flutter/material.dart';

import 'theme.dart';

/// Shows the app at phone size on a wide screen: a 390 × 844 screen in a
/// dark bezel, scaled down to fit. On a phone-sized screen the app fills
/// it as usual.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child});

  final Widget child;

  static const screen = Size(390, 844);
  static const _bezel = 10.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width <= 520) return child;
    return ColoredBox(
      color: const Color(0xFFE8E1D2),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FittedBox(
          child: Container(
            padding: const EdgeInsets.all(_bezel),
            decoration: BoxDecoration(
              color: const Color(0xFF26302A),
              borderRadius: BorderRadius.circular(48),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 30,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(38),
              child: SizedBox.fromSize(
                size: screen,
                child: MediaQuery(
                  data: media.copyWith(
                    size: screen,
                    padding: const EdgeInsets.only(top: 24),
                    viewPadding: const EdgeInsets.only(top: 24),
                    viewInsets: EdgeInsets.zero,
                  ),
                  child: ColoredBox(color: Hue.paper, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
