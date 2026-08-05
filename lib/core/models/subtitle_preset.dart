import 'package:flutter/material.dart';
import 'subtitle_style.dart';

class SubtitlePreset {
  final String id;
  final String name;
  final String icon;
  final SubtitleStyle style;

  const SubtitlePreset({
    required this.id,
    required this.name,
    required this.icon,
    required this.style,
  });

  static List<SubtitlePreset> get presets => [
    const SubtitlePreset(
      id: 'mrbeast',
      name: 'MrBeast Viral',
      icon: '🔥',
      style: SubtitleStyle(
        fontFamily: 'Montserrat',
        fontSize: 26.0,
        textColor: Color(0xFFFFD600), // Vibrant Yellow
        strokeColor: Colors.black,
        strokeWidth: 3.5,
        position: SubtitlePosition.center,
        isUppercase: true,
        activeWordColor: Color(0xFFFF3D00), // Neon Orange
      ),
    ),
    const SubtitlePreset(
      id: 'tiktok_capsule',
      name: 'TikTok Capsule',
      icon: '🎵',
      style: SubtitleStyle(
        fontFamily: 'Inter',
        fontSize: 22.0,
        textColor: Colors.white,
        backgroundColor: Colors.black87,
        strokeWidth: 0.0,
        position: SubtitlePosition.bottom,
        isUppercase: true,
        activeWordColor: Color(0xFF00E676),
      ),
    ),
    const SubtitlePreset(
      id: 'neon_cyber',
      name: 'Neon Cyber',
      icon: '⚡',
      style: SubtitleStyle(
        fontFamily: 'Outfit',
        fontSize: 24.0,
        textColor: Color(0xFF00E5FF), // Cyan Neon
        strokeColor: Color(0xFF7C4DFF), // Violet Stroke
        strokeWidth: 2.5,
        position: SubtitlePosition.center,
        isUppercase: true,
        activeWordColor: Color(0xFFFF007F), // Neon Pink
      ),
    ),
    const SubtitlePreset(
      id: 'podcast_clean',
      name: 'Podcast Clean',
      icon: '🎙️',
      style: SubtitleStyle(
        fontFamily: 'Inter',
        fontSize: 20.0,
        textColor: Color(0xFFF8FAFC),
        backgroundColor: Color(0x990F172A),
        strokeWidth: 1.0,
        position: SubtitlePosition.bottom,
        isUppercase: false,
        activeWordColor: Color(0xFFFFD600),
      ),
    ),
  ];
}
