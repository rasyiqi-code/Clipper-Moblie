import 'dart:io';
import 'transcribed_word.dart';
import 'video_segment.dart';
import 'video_source.dart';

enum ClippingStatus { unclipped, clipped }

class VideoProject {
  final String id;
  final VideoSource source;
  final File? localFile;
  final DateTime createdAt;
  final ClippingStatus status;
  final int renderedClipsCount;
  final List<String> exportedClipPaths;
  final List<VideoSegment> segments;
  final List<TranscribedWord> transcribedWords;

  VideoProject({
    required this.id,
    required this.source,
    this.localFile,
    required this.createdAt,
    this.status = ClippingStatus.unclipped,
    this.renderedClipsCount = 0,
    this.exportedClipPaths = const [],
    this.segments = const [],
    this.transcribedWords = const [],
  });

  VideoProject copyWith({
    String? id,
    VideoSource? source,
    File? localFile,
    DateTime? createdAt,
    ClippingStatus? status,
    int? renderedClipsCount,
    List<String>? exportedClipPaths,
    List<VideoSegment>? segments,
    List<TranscribedWord>? transcribedWords,
  }) {
    return VideoProject(
      id: id ?? this.id,
      source: source ?? this.source,
      localFile: localFile ?? this.localFile,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      renderedClipsCount: renderedClipsCount ?? this.renderedClipsCount,
      exportedClipPaths: exportedClipPaths ?? this.exportedClipPaths,
      segments: segments ?? this.segments,
      transcribedWords: transcribedWords ?? this.transcribedWords,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source.toJson(),
    'localFilePath': localFile?.path,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'renderedClipsCount': renderedClipsCount,
    'exportedClipPaths': exportedClipPaths,
    'segments': segments.map((s) => s.toJson()).toList(),
    'transcribedWords': transcribedWords.map((w) => w.toJson()).toList(),
  };

  factory VideoProject.fromJson(Map<String, dynamic> json) => VideoProject(
    id: json['id'] as String? ?? '',
    source: VideoSource.fromJson(
      (json['source'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    ),
    localFile: json['localFilePath'] == null
        ? null
        : File(json['localFilePath'] as String),
    createdAt: json['createdAt'] != null
        ? (DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now())
        : DateTime.now(),
    status: ClippingStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => ClippingStatus.unclipped,
    ),
    renderedClipsCount: (json['renderedClipsCount'] as num?)?.toInt() ?? 0,
    exportedClipPaths: (json['exportedClipPaths'] as List<dynamic>? ?? const [])
        .cast<String>(),
    segments: (json['segments'] as List<dynamic>? ?? const [])
        .map((e) => VideoSegment.fromJson(e as Map<String, dynamic>))
        .toList(),
    transcribedWords:
        (json['transcribedWords'] as List<dynamic>? ?? const [])
            .map((e) => TranscribedWord.fromJson(e as Map<String, dynamic>))
            .toList(),
  );
}
