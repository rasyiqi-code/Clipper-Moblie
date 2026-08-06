enum VideoSourceType { local, youtube }

class VideoSource {
  final String id;
  final String title;
  final String pathOrUrl;
  final VideoSourceType type;
  final Duration duration;
  final String? thumbnailUrl;

  VideoSource({
    required this.id,
    required this.title,
    required this.pathOrUrl,
    required this.type,
    required this.duration,
    this.thumbnailUrl,
  });

  String get durationFormatted {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'pathOrUrl': pathOrUrl,
    'type': type.name,
    'durationMs': duration.inMilliseconds,
    'thumbnailUrl': thumbnailUrl,
  };

  factory VideoSource.fromJson(Map<String, dynamic> json) => VideoSource(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    pathOrUrl: json['pathOrUrl'] as String? ?? '',
    type: VideoSourceType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => VideoSourceType.local,
    ),
    duration: Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0),
    thumbnailUrl: json['thumbnailUrl'] as String?,
  );
}
