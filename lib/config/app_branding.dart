import 'package:flutter/material.dart';

/// Fonte única para identidade pública do produto.
///
/// O nome atual é provisório. Quando o produto for rebatizado, a maior parte
/// da interface Web deve mudar apenas aqui, sem alterar regras de negócio.
class AppBranding {
  AppBranding._();

  static const String developmentName = 'Imperium';
  static const String productName = 'Imperium Manager';
  static const String webTitle = 'Imperium Manager Web';

  static const Color webBackground = Color(0xFF090B0E);
  static const Color webSurface = Color(0xFF11151A);
  static const Color webSurfaceRaised = Color(0xFF171C22);
  static const Color webBorder = Color(0xFF28303A);
  static const Color webAccent = Color(0xFFF2B84B);
  static const Color webAccentStrong = Color(0xFFFFC857);
}
