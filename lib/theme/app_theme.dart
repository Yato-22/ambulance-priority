import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ThemeExtension providing custom colors for the schematic road map painter
/// in both light and dark themes.
class MapColors extends ThemeExtension<MapColors> {
  final Color background;
  final Color gridDot;
  final Color openRoad;
  final Color moderateRoad;
  final Color heavyRoad;
  final Color blockedRoad;
  final Color route;
  final Color routeTravelled;
  final Color junctionDot;
  final Color signalHousing;
  final Color signalBorder;
  final Color labelChipBackground;
  final Color labelChipText;
  final Color labelChipBorder;
  final Color hospitalBoxBackground;
  final Color hospitalBoxBorder;
  final Color hospitalCross;
  final Color startCircleFill;
  final Color startCircleBorder;
  final Color startText;
  final Color ambulanceBody;
  final Color ambulanceHalo;
  final Color ambulanceBorder;
  final Color triggerRadiusGreen;
  final Color triggerRadiusYellow;
  final Color signalOverrideRing;
  final Color heldGlow;
  final Color heldRing;

  const MapColors({
    required this.background,
    required this.gridDot,
    required this.openRoad,
    required this.moderateRoad,
    required this.heavyRoad,
    required this.blockedRoad,
    required this.route,
    required this.routeTravelled,
    required this.junctionDot,
    required this.signalHousing,
    required this.signalBorder,
    required this.labelChipBackground,
    required this.labelChipText,
    required this.labelChipBorder,
    required this.hospitalBoxBackground,
    required this.hospitalBoxBorder,
    required this.hospitalCross,
    required this.startCircleFill,
    required this.startCircleBorder,
    required this.startText,
    required this.ambulanceBody,
    required this.ambulanceHalo,
    required this.ambulanceBorder,
    required this.triggerRadiusGreen,
    required this.triggerRadiusYellow,
    required this.signalOverrideRing,
    required this.heldGlow,
    required this.heldRing,
  });

  /// Light theme map colors: soft blue-grey canvas, clearly visible road lines,
  /// dark-bordered signals, and light-background text chips.
  static const MapColors light = MapColors(
    background: Color(0xFFE8F0F8),
    gridDot: Color(0x1F1F2D3D), // subtle dark slate dots
    openRoad: Color(0xFF8FA3B5), // mid grey-blue, clearly visible
    moderateRoad: Color(0xFFE67E22), // vivid amber orange
    heavyRoad: Color(0xFFD32F2F), // vivid traffic red
    blockedRoad: Color(0xFFB71C1C), // deep impassable red
    route: Color(0xFF2563EB), // calm electric blue
    routeTravelled: Color(0xFF94A3B8), // muted slate grey
    junctionDot: Color(0xFF94A3B8), // soft junction marker
    signalHousing: Color(0xFFFFFFFF),
    signalBorder: Color(0xFF334155), // thin dark outline around signals
    labelChipBackground: Color(0xFFF1F5F9), // light rounded chip
    labelChipText: Color(0xFF1E293B), // dark navy label text
    labelChipBorder: Color(0xFFCBD5E1),
    hospitalBoxBackground: Color(0xFFFFFFFF),
    hospitalBoxBorder: Color(0xFFDC2626),
    hospitalCross: Color(0xFFDC2626),
    startCircleFill: Color(0xFF16A34A),
    startCircleBorder: Color(0xFF0F172A),
    startText: Color(0xFF15803D),
    ambulanceBody: Color(0xFFD64545),
    ambulanceHalo: Color(0x40D64545),
    ambulanceBorder: Color(0xFFFFFFFF),
    triggerRadiusGreen: Color(0xFF16A34A),
    triggerRadiusYellow: Color(0xFFD97706),
    signalOverrideRing: Color(0xFF9333EA),
    heldGlow: Color(0x40DC2626),
    heldRing: Color(0xFFDC2626),
  );

  /// Dark theme map colors: original high-contrast dark schematic canvas.
  static const MapColors dark = MapColors(
    background: Color(0xFF161B22),
    gridDot: Color(0x0DFFFFFF),
    openRoad: Color(0xFF607D8B),
    moderateRoad: Color(0xFFFF9800),
    heavyRoad: Color(0xFFE53935),
    blockedRoad: Color(0xFFD32F2F),
    route: Color(0xFF2979FF),
    routeTravelled: Color(0xFF546E7A),
    junctionDot: Color(0xFF37474F),
    signalHousing: Color(0xFF212121),
    signalBorder: Colors.transparent,
    labelChipBackground: Color(0xC0000000),
    labelChipText: Colors.white,
    labelChipBorder: Colors.transparent,
    hospitalBoxBackground: Colors.white,
    hospitalBoxBorder: Color(0xFF757575),
    hospitalCross: Colors.red,
    startCircleFill: Color(0xFF00E676),
    startCircleBorder: Colors.white,
    startText: Color(0xFF00E676),
    ambulanceBody: Color(0xFFE53935),
    ambulanceHalo: Color(0x73FF5252),
    ambulanceBorder: Colors.white,
    triggerRadiusGreen: Color(0xFF00E676),
    triggerRadiusYellow: Color(0xFFFFB300),
    signalOverrideRing: Color(0xFFAB47BC),
    heldGlow: Color(0x59E53935),
    heldRing: Color(0xFFE53935),
  );

  @override
  MapColors copyWith({
    Color? background,
    Color? gridDot,
    Color? openRoad,
    Color? moderateRoad,
    Color? heavyRoad,
    Color? blockedRoad,
    Color? route,
    Color? routeTravelled,
    Color? junctionDot,
    Color? signalHousing,
    Color? signalBorder,
    Color? labelChipBackground,
    Color? labelChipText,
    Color? labelChipBorder,
    Color? hospitalBoxBackground,
    Color? hospitalBoxBorder,
    Color? hospitalCross,
    Color? startCircleFill,
    Color? startCircleBorder,
    Color? startText,
    Color? ambulanceBody,
    Color? ambulanceHalo,
    Color? ambulanceBorder,
    Color? triggerRadiusGreen,
    Color? triggerRadiusYellow,
    Color? signalOverrideRing,
    Color? heldGlow,
    Color? heldRing,
  }) {
    return MapColors(
      background: background ?? this.background,
      gridDot: gridDot ?? this.gridDot,
      openRoad: openRoad ?? this.openRoad,
      moderateRoad: moderateRoad ?? this.moderateRoad,
      heavyRoad: heavyRoad ?? this.heavyRoad,
      blockedRoad: blockedRoad ?? this.blockedRoad,
      route: route ?? this.route,
      routeTravelled: routeTravelled ?? this.routeTravelled,
      junctionDot: junctionDot ?? this.junctionDot,
      signalHousing: signalHousing ?? this.signalHousing,
      signalBorder: signalBorder ?? this.signalBorder,
      labelChipBackground: labelChipBackground ?? this.labelChipBackground,
      labelChipText: labelChipText ?? this.labelChipText,
      labelChipBorder: labelChipBorder ?? this.labelChipBorder,
      hospitalBoxBackground: hospitalBoxBackground ?? this.hospitalBoxBackground,
      hospitalBoxBorder: hospitalBoxBorder ?? this.hospitalBoxBorder,
      hospitalCross: hospitalCross ?? this.hospitalCross,
      startCircleFill: startCircleFill ?? this.startCircleFill,
      startCircleBorder: startCircleBorder ?? this.startCircleBorder,
      startText: startText ?? this.startText,
      ambulanceBody: ambulanceBody ?? this.ambulanceBody,
      ambulanceHalo: ambulanceHalo ?? this.ambulanceHalo,
      ambulanceBorder: ambulanceBorder ?? this.ambulanceBorder,
      triggerRadiusGreen: triggerRadiusGreen ?? this.triggerRadiusGreen,
      triggerRadiusYellow: triggerRadiusYellow ?? this.triggerRadiusYellow,
      signalOverrideRing: signalOverrideRing ?? this.signalOverrideRing,
      heldGlow: heldGlow ?? this.heldGlow,
      heldRing: heldRing ?? this.heldRing,
    );
  }

  @override
  MapColors lerp(ThemeExtension<MapColors>? other, double t) {
    if (other is! MapColors) return this;
    return MapColors(
      background: Color.lerp(background, other.background, t) ?? background,
      gridDot: Color.lerp(gridDot, other.gridDot, t) ?? gridDot,
      openRoad: Color.lerp(openRoad, other.openRoad, t) ?? openRoad,
      moderateRoad: Color.lerp(moderateRoad, other.moderateRoad, t) ?? moderateRoad,
      heavyRoad: Color.lerp(heavyRoad, other.heavyRoad, t) ?? heavyRoad,
      blockedRoad: Color.lerp(blockedRoad, other.blockedRoad, t) ?? blockedRoad,
      route: Color.lerp(route, other.route, t) ?? route,
      routeTravelled: Color.lerp(routeTravelled, other.routeTravelled, t) ?? routeTravelled,
      junctionDot: Color.lerp(junctionDot, other.junctionDot, t) ?? junctionDot,
      signalHousing: Color.lerp(signalHousing, other.signalHousing, t) ?? signalHousing,
      signalBorder: Color.lerp(signalBorder, other.signalBorder, t) ?? signalBorder,
      labelChipBackground: Color.lerp(labelChipBackground, other.labelChipBackground, t) ?? labelChipBackground,
      labelChipText: Color.lerp(labelChipText, other.labelChipText, t) ?? labelChipText,
      labelChipBorder: Color.lerp(labelChipBorder, other.labelChipBorder, t) ?? labelChipBorder,
      hospitalBoxBackground: Color.lerp(hospitalBoxBackground, other.hospitalBoxBackground, t) ?? hospitalBoxBackground,
      hospitalBoxBorder: Color.lerp(hospitalBoxBorder, other.hospitalBoxBorder, t) ?? hospitalBoxBorder,
      hospitalCross: Color.lerp(hospitalCross, other.hospitalCross, t) ?? hospitalCross,
      startCircleFill: Color.lerp(startCircleFill, other.startCircleFill, t) ?? startCircleFill,
      startCircleBorder: Color.lerp(startCircleBorder, other.startCircleBorder, t) ?? startCircleBorder,
      startText: Color.lerp(startText, other.startText, t) ?? startText,
      ambulanceBody: Color.lerp(ambulanceBody, other.ambulanceBody, t) ?? ambulanceBody,
      ambulanceHalo: Color.lerp(ambulanceHalo, other.ambulanceHalo, t) ?? ambulanceHalo,
      ambulanceBorder: Color.lerp(ambulanceBorder, other.ambulanceBorder, t) ?? ambulanceBorder,
      triggerRadiusGreen: Color.lerp(triggerRadiusGreen, other.triggerRadiusGreen, t) ?? triggerRadiusGreen,
      triggerRadiusYellow: Color.lerp(triggerRadiusYellow, other.triggerRadiusYellow, t) ?? triggerRadiusYellow,
      signalOverrideRing: Color.lerp(signalOverrideRing, other.signalOverrideRing, t) ?? signalOverrideRing,
      heldGlow: Color.lerp(heldGlow, other.heldGlow, t) ?? heldGlow,
      heldRing: Color.lerp(heldRing, other.heldRing, t) ?? heldRing,
    );
  }
}

/// AppTheme configuration defining the soft light theme and dark theme.
class AppTheme {
  // Brand & semantic constants
  static const Color primaryBlue = Color(0xFF2F6FD0);
  static const Color emergencyRed = Color(0xFFD64545);
  static const Color warningAmber = Color(0xFFE68A00);
  static const Color successGreen = Color(0xFF2E7D32);

  // Light theme palette (soft light blue-grey, never pure white full-screen)
  static const Color lightScaffoldBg = Color(0xFFEEF4FA);
  static const Color lightCardBg = Color(0xFFF7FAFD);
  static const Color lightCardBorder = Color(0xFFD5DEE8);
  static const Color lightTextPrimary = Color(0xFF1F2D3D);
  static const Color lightTextSecondary = Color(0xFF5B6B7C);
  static const Color lightSurfaceContainerHigh = Color(0xFFE6EFF8);

  // Dark theme palette
  static const Color darkScaffoldBg = Color(0xFF0F141C);
  static const Color darkCardBg = Color(0xFF1A212D);
  static const Color darkCardBorder = Color(0xFF2D3748);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightScaffoldBg,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: primaryBlue,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFDCE8F9),
      onPrimaryContainer: Color(0xFF102A4E),
      secondary: Color(0xFF4A6572),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFE2EAF2),
      onSecondaryContainer: Color(0xFF1B2A36),
      tertiary: Color(0xFF6B5282),
      onTertiary: Colors.white,
      error: emergencyRed,
      onError: Colors.white,
      errorContainer: Color(0xFFFCE8E8),
      onErrorContainer: Color(0xFF5A1515),
      surface: lightCardBg,
      onSurface: lightTextPrimary,
      onSurfaceVariant: lightTextSecondary,
      surfaceContainerHighest: Color(0xFFE3EDF7),
      surfaceContainerHigh: lightSurfaceContainerHigh,
      outline: Color(0xFF94A3B8),
      outlineVariant: lightCardBorder,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: lightCardBg,
      foregroundColor: lightTextPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: lightCardBg,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      iconTheme: IconThemeData(color: lightTextPrimary),
      titleTextStyle: TextStyle(
        color: lightTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: lightCardBg,
      elevation: 1,
      shadowColor: const Color(0x1A1F2D3D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: lightCardBorder, width: 1),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: lightCardBg,
      indicatorColor: const Color(0xFFDCE8F9),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: primaryBlue,
          );
        }
        return const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: lightTextSecondary,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: primaryBlue);
        }
        return const IconThemeData(color: lightTextSecondary);
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: lightCardBorder,
      thickness: 1,
      space: 1,
    ),
    extensions: const [
      MapColors.light,
    ],
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkScaffoldBg,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF60A5FA),
      onPrimary: Color(0xFF0F172A),
      primaryContainer: Color(0xFF1E3A8A),
      onPrimaryContainer: Color(0xFFDBEAFE),
      secondary: Color(0xFF94A3B8),
      onSecondary: Color(0xFF0F172A),
      secondaryContainer: Color(0xFF334155),
      onSecondaryContainer: Color(0xFFF1F5F9),
      tertiary: Color(0xFFC084FC),
      onTertiary: Color(0xFF3B0764),
      error: Color(0xFFEF4444),
      onError: Color(0xFF450A0A),
      errorContainer: Color(0xFF7F1D1D),
      onErrorContainer: Color(0xFFFEE2E2),
      surface: darkCardBg,
      onSurface: darkTextPrimary,
      onSurfaceVariant: darkTextSecondary,
      surfaceContainerHighest: Color(0xFF273244),
      surfaceContainerHigh: Color(0xFF222B3A),
      outline: Color(0xFF64748B),
      outlineVariant: darkCardBorder,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: darkCardBg,
      foregroundColor: darkTextPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: darkCardBg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      iconTheme: IconThemeData(color: darkTextPrimary),
      titleTextStyle: TextStyle(
        color: darkTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: darkCardBg,
      elevation: 2,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: darkCardBorder, width: 1),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: darkCardBg,
      indicatorColor: const Color(0xFF1E3A8A),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF60A5FA),
          );
        }
        return const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: darkTextSecondary,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: Color(0xFF60A5FA));
        }
        return const IconThemeData(color: darkTextSecondary);
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: darkCardBorder,
      thickness: 1,
      space: 1,
    ),
    extensions: const [
      MapColors.dark,
    ],
  );
}

