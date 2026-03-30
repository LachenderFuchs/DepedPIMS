import 'package:flutter/material.dart';

class ResponsiveLayout {
  static const double compactBreakpoint = 720;
  static const double mediumBreakpoint = 1100;
  static const double sidebarBreakpoint = 1080;

  static bool isCompactWidth(
    double width, {
    double breakpoint = compactBreakpoint,
  }) {
    return width < breakpoint;
  }

  static bool isMediumWidth(
    double width, {
    double breakpoint = mediumBreakpoint,
  }) {
    return width < breakpoint;
  }

  static EdgeInsets pagePaddingForWidth(
    double width, {
    double compactHorizontal = 16,
    double mediumHorizontal = 24,
    double wideHorizontal = 32,
    double compactVertical = 16,
    double mediumVertical = 24,
    double wideVertical = 32,
  }) {
    if (width < compactBreakpoint) {
      return EdgeInsets.symmetric(
        horizontal: compactHorizontal,
        vertical: compactVertical,
      );
    }
    if (width < mediumBreakpoint) {
      return EdgeInsets.symmetric(
        horizontal: mediumHorizontal,
        vertical: mediumVertical,
      );
    }
    return EdgeInsets.symmetric(
      horizontal: wideHorizontal,
      vertical: wideVertical,
    );
  }

  static double drawerWidth(double width) {
    if (width < 420) return width * 0.9;
    if (width < 720) return width * 0.82;
    return 320;
  }
}
