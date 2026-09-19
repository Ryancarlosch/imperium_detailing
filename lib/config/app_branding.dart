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
  static const String wordmarkPrimary = 'IMPERIUM';
  static const String wordmarkSecondary = 'MANAGER';
  static const String loginHeadline = 'Gestão completa para sua empresa';
  static const String loginTagline = 'MAIS QUE GESTÃO  •  MOVEMOS O SEU FUTURO';

  static const Color loginBackground = Color(0xFF07090C);
  static const Color loginSurface = Color(0xFF101419);
  static const Color loginSurfaceRaised = Color(0xFF171C22);
  static const Color loginBorder = Color(0xFF2A313A);
  static const Color loginText = Color(0xFFF5F6F8);
  static const Color loginMuted = Color(0xFF9CA5AF);

  static const Color webBackground = Color(0xFF090B0E);
  static const Color webSurface = Color(0xFF11151A);
  static const Color webSurfaceRaised = Color(0xFF171C22);
  static const Color webBorder = Color(0xFF28303A);
  static const Color webAccent = Color(0xFFF2B84B);
  static const Color webAccentStrong = Color(0xFFFFC857);
}
