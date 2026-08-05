import 'package:flutter/material.dart';

enum SubtitlePosition { top, center, bottom }

class SubtitleStyle {
  final String fontFamily;
  final double fontSize;
  final Color textColor;
  final Color backgroundColor;
  final Color strokeColor;
  final double strokeWidth;
  final SubtitlePosition position;
  final bool isUppercase;
  final bool highlightActiveWord;
  final Color activeWordColor;

  const SubtitleStyle({
    this.fontFamily = 'Inter',
    this.fontSize = 24.0,
    this.textColor = Colors.white,
    this.backgroundColor = Colors.black45,
    this.strokeColor = Colors.black,
    this.strokeWidth = 2.0,
    this.position = SubtitlePosition.bottom,
    this.isUppercase = true,
    this.highlightActiveWord = true,
    this.activeWordColor = const Color(0xFFFFD600), // Yellow neon
  });

  SubtitleStyle copyWith({
    String? fontFamily,
    double? fontSize,
    Color? textColor,
    Color? backgroundColor,
    Color? strokeColor,
    double? strokeWidth,
    SubtitlePosition? position,
    bool? isUppercase,
    bool? highlightActiveWord,
    Color? activeWordColor,
  }) {
    return SubtitleStyle(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      position: position ?? this.position,
      isUppercase: isUppercase ?? this.isUppercase,
      highlightActiveWord: highlightActiveWord ?? this.highlightActiveWord,
      activeWordColor: activeWordColor ?? this.activeWordColor,
    );
  }
}
