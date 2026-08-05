import 'dart:convert';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/video_source.dart';
import 'whisper_service.dart';

class YouTubeService {
  /// Fetches video details from a YouTube URL or Video ID.
  /// Uses YoutubeExplode with a fallback to YouTube's official oEmbed API
  /// to ensure metadata fetching never fails on mobile networks/devices.
  Future<VideoSource> fetchVideoInfo(String urlOrId) async {
    final cleanId = VideoId.parseVideoId(urlOrId.trim()) ?? urlOrId.trim();

    // 1. Try YoutubeExplode with a fresh client
    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(cleanId);
      final source = VideoSource(
        id: video.id.value,
        title: video.title,
        pathOrUrl: video.url,
        type: VideoSourceType.youtube,
        duration: video.duration ?? const Duration(minutes: 5),
        thumbnailUrl: video.thumbnails.highResUrl,
      );
      yt.close();
      return source;
    } catch (_) {
      yt.close();
    }

    // 2. Fallback: Official YouTube oEmbed API (100% reliable, works even when Innertube is blocked on mobile)
    try {
      final uri = Uri.parse(
        'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$cleanId&format=json',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final title = data['title'] as String? ?? 'YouTube Video';
        final thumbnail = data['thumbnail_url'] as String? ??
            'https://i.ytimg.com/vi/$cleanId/hqdefault.jpg';

        return VideoSource(
          id: cleanId,
          title: title,
          pathOrUrl: 'https://www.youtube.com/watch?v=$cleanId',
          type: VideoSourceType.youtube,
          duration: const Duration(minutes: 5),
          thumbnailUrl: thumbnail,
        );
      }
    } catch (e2) {
      // Fallthrough if oEmbed network error
    }

    throw Exception(
      'Gagal mengambil info video YouTube. Pastikan koneksi internet lancar dan link video publik.',
    );
  }

  /// Downloads YouTube video stream locally for processing.
  /// Prefers a muxed (video+audio) stream; if none exists it downloads the
  /// best video-only and audio-only streams and merges them with FFmpeg.
  Future<File> downloadVideo(
    String videoIdOrUrl, {
    Function(double progress)? onProgress,
  }) async {
    final videoId =
        VideoId.parseVideoId(videoIdOrUrl.trim()) ?? videoIdOrUrl.trim();
    final tempDir = await getTemporaryDirectory();

    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      final yt = YoutubeExplode();
      try {
        final manifest = await yt.videos.streamsClient.getManifest(videoId);

        if (manifest.muxed.isNotEmpty) {
          final streamInfo = manifest.muxed.withHighestBitrate();
          final file = await _downloadStream(
            yt,
            streamInfo,
            '${tempDir.path}/yt_$videoId.mp4',
            onProgress,
          );
          yt.close();
          return file;
        }

        if (manifest.videoOnly.isNotEmpty) {
          final videoInfo = manifest.videoOnly.withHighestBitrate();
          final videoFile = await _downloadStream(
            yt,
            videoInfo,
            '${tempDir.path}/yt_${videoId}_v.mp4',
            onProgress,
          );

          if (manifest.audioOnly.isNotEmpty) {
            final audioInfo = manifest.audioOnly.withHighestBitrate();
            final audioFile = await _downloadStream(
              yt,
              audioInfo,
              '${tempDir.path}/yt_${videoId}_a.m4a',
              null,
            );

            final mergedFile = File('${tempDir.path}/yt_$videoId.mp4');
            final session = await FFmpegKit.executeWithArguments([
              '-y',
              '-i',
              videoFile.path,
              '-i',
              audioFile.path,
              '-c',
              'copy',
              '-shortest',
              mergedFile.path,
            ]);
            final returnCode = await session.getReturnCode();
            yt.close();
            if (ReturnCode.isSuccess(returnCode) &&
                await mergedFile.exists() &&
                (await mergedFile.length()) > 1024) {
              return mergedFile;
            }
          }

          yt.close();
          return videoFile;
        }

        yt.close();
        throw Exception('Tidak ada stream video yang dapat diunduh');
      } catch (e) {
        lastError = e;
        yt.close();
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 600 * attempt));
        }
      }
    }

    throw Exception('Gagal mengunduh video YouTube: $lastError');
  }

  /// Fetches the video's built-in caption track (subtitle) as word-level
  /// timestamps, reusing YouTube's own transcript instead of running Whisper.
  /// Returns `null` when the video has no usable captions so the caller can
  /// fall back to local transcription.
  Future<List<WhisperWord>?> fetchTranscript(String videoIdOrUrl) async {
    final videoId =
        VideoId.parseVideoId(videoIdOrUrl.trim()) ?? videoIdOrUrl.trim();
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.closedCaptions.getManifest(videoId);
      final track = _pickTrack(manifest.tracks);
      if (track == null) {
        yt.close();
        return null;
      }

      final captions = await yt.videos.closedCaptions.get(track);
      final words = _captionsToWords(captions.captions);
      yt.close();
      return words;
    } catch (e) {
      yt.close();
      return null;
    }
  }

  ClosedCaptionTrackInfo? _pickTrack(List<ClosedCaptionTrackInfo> tracks) {
    if (tracks.isEmpty) return null;

    ClosedCaptionTrackInfo? manualFallback;
    for (final track in tracks) {
      final code = track.language.code.toLowerCase();
      if (!track.isAutoGenerated) manualFallback ??= track;
      if (!track.isAutoGenerated &&
          (code == 'id' || code == 'id-id' || code == 'in')) {
        return track;
      }
    }
    for (final track in tracks) {
      final code = track.language.code.toLowerCase();
      if (!track.isAutoGenerated && code == 'en') return track;
    }
    if (manualFallback != null) return manualFallback;
    for (final track in tracks) {
      final code = track.language.code.toLowerCase();
      if (code == 'id' || code == 'id-id' || code == 'in') return track;
    }
    return tracks.first;
  }

  List<WhisperWord> _captionsToWords(List<ClosedCaption> captions) {
    final words = <WhisperWord>[];
    for (final caption in captions) {
      final text = caption.text.trim();
      if (text.isEmpty) continue;

      if (caption.parts.isNotEmpty) {
        for (var i = 0; i < caption.parts.length; i++) {
          final part = caption.parts[i];
          final start = caption.offset + part.offset;
          final nextOffset = i + 1 < caption.parts.length
              ? caption.parts[i + 1].offset
              : caption.duration;
          final delta = nextOffset - part.offset;
          final end = start + (delta.isNegative ? Duration.zero : delta);
          words.add(
            WhisperWord(word: part.text.trim(), start: start, end: end),
          );
        }
      } else {
        words.add(
          WhisperWord(word: text, start: caption.offset, end: caption.end),
        );
      }
    }
    return words;
  }

  Future<File> _downloadStream(
    YoutubeExplode yt,
    StreamInfo streamInfo,
    String filePath,
    Function(double progress)? onProgress,
  ) async {
    final stream = yt.videos.streamsClient.get(streamInfo);
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
    }

    final output = file.openWrite();
    final totalBytes = streamInfo.size.totalBytes;
    var downloadedBytes = 0;

    await for (final chunk in stream) {
      downloadedBytes += chunk.length;
      output.add(chunk);
      if (onProgress != null && totalBytes > 0) {
        onProgress(downloadedBytes / totalBytes);
      }
    }

    await output.flush();
    await output.close();

    return file;
  }

  void dispose() {}
}
