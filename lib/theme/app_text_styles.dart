import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  static TextStyle get _arabicBase => GoogleFonts.cairo(
        color: AppColors.dark,
      );

  static TextStyle get headlineLarge => _arabicBase.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get headlineMedium => _arabicBase.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get headlineSmall => _arabicBase.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
      );

  static TextStyle get titleLarge => _arabicBase.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get titleMedium => _arabicBase.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get titleSmall => _arabicBase.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get bodyLarge => _arabicBase.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get bodyMedium => _arabicBase.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get bodySmall => _arabicBase.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get labelLarge => _arabicBase.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      );

  static TextStyle get green => _arabicBase.copyWith(
        color: AppColors.green,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get red => _arabicBase.copyWith(
        color: AppColors.red,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get greenOnPrimary => _arabicBase.copyWith(
        color: AppColors.greenOnPrimary,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get redOnPrimary => _arabicBase.copyWith(
        color: AppColors.redOnPrimary,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get whiteOnPrimary => _arabicBase.copyWith(
        color: AppColors.white,
        fontWeight: FontWeight.w600,
      );
}