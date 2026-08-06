enum AspectRatioType { portrait916, square11, landscape169 }

class FaceKeyframe {
  final double timeSec; // Timestamp relative to clip start (in seconds)
  final double xPercent; // 0.0 (left) to 1.0 (right)

  const FaceKeyframe({required this.timeSec, required this.xPercent});

  Map<String, dynamic> toJson() => {'timeSec': timeSec, 'xPercent': xPercent};

  factory FaceKeyframe.fromJson(Map<String, dynamic> json) => FaceKeyframe(
    timeSec: (json['timeSec'] as num?)?.toDouble() ?? 0.0,
    xPercent: (json['xPercent'] as num?)?.toDouble() ?? 0.5,
  );
}

class VideoSegment {
  final String id;
  final String title;
  final Duration startTime;
  final Duration endTime;
  final double viralScore; // 0.0 to 100.0
  final String summary;
  final String transcript;
  final AspectRatioType targetAspectRatio;
  final double
  cropXPercent; // 0.0 (left) to 1.0 (right) for face tracking centering
  final bool enableSmartReframe;
  final bool enableSubtitles;
  final List<FaceKeyframe> faceKeyframes;

  VideoSegment({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.viralScore,
    required this.summary,
    required this.transcript,
    this.targetAspectRatio = AspectRatioType.portrait916,
    this.cropXPercent = 0.5,
    this.enableSmartReframe = true,
    this.enableSubtitles = true,
    this.faceKeyframes = const [],
  });

  Duration get clipDuration =>
      endTime > startTime ? endTime - startTime : Duration.zero;

  String formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  VideoSegment copyWith({
    String? id,
    String? title,
    Duration? startTime,
    Duration? endTime,
    double? viralScore,
    String? summary,
    String? transcript,
    AspectRatioType? targetAspectRatio,
    double? cropXPercent,
    bool? enableSmartReframe,
    bool? enableSubtitles,
    List<FaceKeyframe>? faceKeyframes,
  }) {
    return VideoSegment(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      viralScore: viralScore ?? this.viralScore,
      summary: summary ?? this.summary,
      transcript: transcript ?? this.transcript,
      targetAspectRatio: targetAspectRatio ?? this.targetAspectRatio,
      cropXPercent: cropXPercent ?? this.cropXPercent,
      enableSmartReframe: enableSmartReframe ?? this.enableSmartReframe,
      enableSubtitles: enableSubtitles ?? this.enableSubtitles,
      faceKeyframes: faceKeyframes ?? this.faceKeyframes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startMs': startTime.inMilliseconds,
    'endMs': endTime.inMilliseconds,
    'viralScore': viralScore,
    'summary': summary,
    'transcript': transcript,
    'targetAspectRatio': targetAspectRatio.name,
    'cropXPercent': cropXPercent,
    'enableSmartReframe': enableSmartReframe,
    'enableSubtitles': enableSubtitles,
    'faceKeyframes': faceKeyframes.map((k) => k.toJson()).toList(),
  };

  factory VideoSegment.fromJson(Map<String, dynamic> json) => VideoSegment(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    startTime: Duration(milliseconds: (json['startMs'] as num?)?.toInt() ?? 0),
    endTime: Duration(milliseconds: (json['endMs'] as num?)?.toInt() ?? 0),
    viralScore: (json['viralScore'] as num?)?.toDouble() ?? 0.0,
    summary: json['summary'] as String? ?? '',
    transcript: json['transcript'] as String? ?? '',
    targetAspectRatio: AspectRatioType.values.firstWhere(
      (e) => e.name == json['targetAspectRatio'],
      orElse: () => AspectRatioType.portrait916,
    ),
    cropXPercent: (json['cropXPercent'] as num?)?.toDouble() ?? 0.5,
    enableSmartReframe: json['enableSmartReframe'] as bool? ?? true,
    enableSubtitles: json['enableSubtitles'] as bool? ?? true,
    faceKeyframes:
        (json['faceKeyframes'] as List<dynamic>?)
            ?.map((k) => FaceKeyframe.fromJson(k as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}
