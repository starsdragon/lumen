import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LumenColors extends ThemeExtension<LumenColors> {
  const LumenColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.sidebar,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.primarySoft,
    required this.onPrimary,
    required this.userBubble,
    required this.userBubbleText,
    required this.codeBackground,
    required this.danger,
    required this.success,
    required this.warning,
    required this.shadow,
    required this.overlay,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color sidebar;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color primary;
  final Color primarySoft;
  final Color onPrimary;
  final Color userBubble;
  final Color userBubbleText;
  final Color codeBackground;
  final Color danger;
  final Color success;
  final Color warning;
  final Color shadow;
  final Color overlay;

  static const light = LumenColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF7F8FA),
    sidebar: Color(0xFFF7F8FA),
    border: Color(0xFFE9EBF1),
    borderStrong: Color(0xFFD8DDE8),
    textPrimary: Color(0xFF14161A),
    textSecondary: Color(0xFF5C6470),
    textTertiary: Color(0xFF929AAA),
    primary: Color(0xFF426EFE),
    primarySoft: Color(0xFFEEF2FF),
    onPrimary: Colors.white,
    userBubble: Color(0xFFEFF3FF),
    userBubbleText: Color(0xFF17203A),
    codeBackground: Color(0xFFF6F8FB),
    danger: Color(0xFFE5484D),
    success: Color(0xFF0F9F78),
    warning: Color(0xFFE08A00),
    shadow: Color(0x140F172A),
    overlay: Color(0x66000000),
  );

  static const dark = LumenColors(
    background: Color(0xFF0E1015),
    surface: Color(0xFF151820),
    surfaceAlt: Color(0xFF1B1F28),
    sidebar: Color(0xFF11141A),
    border: Color(0xFF262C38),
    borderStrong: Color(0xFF333B4A),
    textPrimary: Color(0xFFF2F4F8),
    textSecondary: Color(0xFFA4ADBE),
    textTertiary: Color(0xFF727D90),
    primary: Color(0xFF7C97FF),
    primarySoft: Color(0xFF1D2745),
    onPrimary: Color(0xFF0B1020),
    userBubble: Color(0xFF202B4D),
    userBubbleText: Color(0xFFEDF1FF),
    codeBackground: Color(0xFF0A0D13),
    danger: Color(0xFFFF6B6B),
    success: Color(0xFF45D6A0),
    warning: Color(0xFFF5B83D),
    shadow: Color(0x66000000),
    overlay: Color(0x99000000),
  );

  @override
  LumenColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? sidebar,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? primary,
    Color? primarySoft,
    Color? onPrimary,
    Color? userBubble,
    Color? userBubbleText,
    Color? codeBackground,
    Color? danger,
    Color? success,
    Color? warning,
    Color? shadow,
    Color? overlay,
  }) {
    return LumenColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      sidebar: sidebar ?? this.sidebar,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      primary: primary ?? this.primary,
      primarySoft: primarySoft ?? this.primarySoft,
      onPrimary: onPrimary ?? this.onPrimary,
      userBubble: userBubble ?? this.userBubble,
      userBubbleText: userBubbleText ?? this.userBubbleText,
      codeBackground: codeBackground ?? this.codeBackground,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      shadow: shadow ?? this.shadow,
      overlay: overlay ?? this.overlay,
    );
  }

  @override
  LumenColors lerp(ThemeExtension<LumenColors>? other, double t) {
    if (other is! LumenColors) return this;
    return LumenColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      userBubbleText: Color.lerp(userBubbleText, other.userBubbleText, t)!,
      codeBackground: Color.lerp(codeBackground, other.codeBackground, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
    );
  }
}

extension LumenThemeX on BuildContext {
  LumenColors get colors => Theme.of(this).extension<LumenColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

ThemeData buildLumenTheme({required Brightness brightness}) {
  final c = brightness == Brightness.dark ? LumenColors.dark : LumenColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    secondary: c.primary,
    onSecondary: c.onPrimary,
    error: c.danger,
    onError: Colors.white,
    surface: c.surface,
    onSurface: c.textPrimary,
    surfaceContainerHighest: c.surfaceAlt,
    onSurfaceVariant: c.textSecondary,
    outline: c.borderStrong,
    outlineVariant: c.border,
    shadow: c.shadow,
    scrim: c.overlay,
    inverseSurface: c.textPrimary,
    onInverseSurface: c.background,
    inversePrimary: c.primarySoft,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    fontFamily: 'Inter',
    fontFamilyFallback: const ['NotoSansSC', 'Microsoft YaHei UI', 'PingFang SC', 'sans-serif'],
    visualDensity: VisualDensity.standard,
  );

  final text = base.textTheme
      .apply(bodyColor: c.textPrimary, displayColor: c.textPrimary)
      .copyWith(
        displaySmall: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: base.textTheme.bodyLarge?.fontFamilyFallback,
          fontSize: 32,
          height: 1.18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.8,
          color: c.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          height: 1.25,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: c.textPrimary,
        ),
        headlineSmall: TextStyle(
          fontSize: 21,
          height: 1.3,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
          color: c.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          height: 1.35,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.15,
          color: c.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 15.5,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: c.textSecondary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.7,
          fontWeight: FontWeight.w400,
          color: c.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14.5,
          height: 1.6,
          fontWeight: FontWeight.w400,
          color: c.textPrimary,
        ),
        bodySmall: TextStyle(
          fontSize: 12.5,
          height: 1.45,
          fontWeight: FontWeight.w400,
          color: c.textSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: 13.5,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          height: 1.25,
          fontWeight: FontWeight.w500,
          color: c.textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          height: 1.25,
          fontWeight: FontWeight.w500,
          color: c.textTertiary,
        ),
      );

  return base.copyWith(
    textTheme: text,
    primaryTextTheme: text,
    dividerColor: c.border,
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    iconTheme: IconThemeData(color: c.textPrimary, size: 21),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: text.labelLarge?.copyWith(fontSize: 14.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textPrimary,
        minimumSize: const Size(44, 44),
        side: BorderSide(color: c.borderStrong),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.primary,
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.textSecondary,
        hoverColor: c.surfaceAlt,
        highlightColor: c.surfaceAlt,
        minimumSize: const Size(40, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceAlt,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: text.bodyMedium?.copyWith(color: c.textTertiary),
      labelStyle: text.bodyMedium?.copyWith(color: c.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.primary.withValues(alpha: 0.7), width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c.danger),
      ),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      showDragHandle: false,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: brightness == Brightness.dark ? const Color(0xFFE9ECF5) : const Color(0xFF1B1F28),
      contentTextStyle: text.bodyMedium?.copyWith(
        color: brightness == Brightness.dark ? const Color(0xFF15181F) : Colors.white,
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.white : c.textTertiary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.primary : c.borderStrong,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.primary,
      inactiveTrackColor: c.borderStrong,
      thumbColor: c.primary,
      overlayColor: c.primary.withValues(alpha: 0.12),
      trackHeight: 4,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: c.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.border),
      ),
      textStyle: text.bodyMedium,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: brightness == Brightness.dark ? const Color(0xFF2A3140) : const Color(0xFF222833),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12, height: 1.3),
      waitDuration: const Duration(milliseconds: 500),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(c.textTertiary.withValues(alpha: 0.35)),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(5),
    ),
    extensions: [c],
  );
}
