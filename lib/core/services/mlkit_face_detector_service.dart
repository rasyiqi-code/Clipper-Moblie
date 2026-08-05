import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// A single face observation in one sampled frame.
class _FaceObservation {
  final int frameIndex;
  final double xCenter;
  final double area;
  final double mouthOpenness;

  _FaceObservation({
    required this.frameIndex,
    required this.xCenter,
    required this.area,
    required this.mouthOpenness,
  });
}

class MLKitFaceDetectorService {
  late final FaceDetector _faceDetector;

  /// Human-readable reason of the last detection outcome (used to surface
  /// failures in the UI when no face X-center could be determined).
  String? lastStatus;

  /// Lip-motion threshold (stddev of mouth-openness) above which a face is
  /// considered to be actually talking. Below this the largest face wins.
  static const double _talkingThreshold = 0.02;

  /// Floor for the LOCAL (per-frame rolling window) mouth-motion score used to
  /// switch the crop target to whichever face is talking at that moment.
  static const double _talkingFloor = 0.015;

  /// Minimum mouth-openness for a face to be considered as potentially
  /// speaking RIGHT NOW. A stopped talker whose lips are closed drops below
  /// this and immediately loses the crop target (no lingering hold), while
  /// someone whose mouth is open can win even before clear lip motion shows up.
  static const double _mouthOpenFloor = 0.10;

  MLKitFaceDetectorService() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        // Accurate mode is needed for mouth landmarks/contours, which let us
        // tell WHO is talking at any moment (two speakers trading lines will
        // alternate on screen instead of following a single largest face).
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
        enableContours: true,
        enableClassification: false,
      ),
    );
  }

  /// Picks the face that is actually TALKING across [framePaths] — not merely
  /// the largest one — and returns its average X-center (0.0 = left edge,
  /// 1.0 = right edge). Returns `null` when no face can be identified.
  ///
  /// Talking is inferred from lip motion: ML Kit exposes mouth landmarks, so a
  /// face whose nose→bottom-mouth distance varies between frames (stddev of the
  /// mouth-openness ratio) is treated as the active speaker. Faces are tracked
  /// across frames by position; when nobody's lips move, the largest face is
  /// used as a fallback.
  Future<
    ({double? averageX, List<({double timeSec, double xPercent})> keyframes})
  >
  detectSpeakerKeyframesAcrossFrames(
    List<String> framePaths, {
    int? frameWidth,
    List<double>? timeSecs,
    void Function(int processed, int total)? onProgress,
    List<({double start, double end})> voicedWindows = const [],
    double segmentStartSec = 0.0,
  }) async {
    if (framePaths.isEmpty) {
      lastStatus = 'Tidak ada frame untuk dianalisis';
      return (
        averageX: null,
        keyframes: const <({double timeSec, double xPercent})>[],
      );
    }
    if (framePaths.length > 1463) {
      debugPrint(
        '[face-detect] WARNING: ${framePaths.length} frame > 1463 — '
        'analisis akan lambat; sebaiknya batasi di ekstraksi frame.',
      );
    }

    try {
      var totalFaces = 0;
      final facesPerFrame = <List<Face>>[];
      int? metadataWidth;
      for (var i = 0; i < framePaths.length; i++) {
        try {
          final input = InputImage.fromFilePath(framePaths[i]);
          metadataWidth ??= input.metadata?.size.width.toInt();
          final faces = await _faceDetector.processImage(input);
          totalFaces += faces.length;
          facesPerFrame.add(faces);
        } catch (_) {
          facesPerFrame.add(const []);
        }
        onProgress?.call(i + 1, framePaths.length);
      }

      if (totalFaces == 0) {
        lastStatus = 'ML Kit: 0 wajah di ${framePaths.length} frame';
        return (
          averageX: null,
          keyframes: const <({double timeSec, double xPercent})>[],
        );
      }

      final double imageWidth = (frameWidth ?? metadataWidth ?? 0).toDouble();
      if (imageWidth <= 0) {
        lastStatus = 'Metadata ukuran frame tidak tersedia';
        return (
          averageX: null,
          keyframes: const <({double timeSec, double xPercent})>[],
        );
      }

      // Group faces into per-person tracks and compute the average X of the
      // most-talked track (used for the summary chip / starting position).
      List<List<_FaceObservation>> tracks = _buildTracks(facesPerFrame);
      List<_FaceObservation>? primaryTrack = _selectSpeakerTrack(tracks);
      double? avgX;
      if (primaryTrack != null && primaryTrack.isNotEmpty) {
        final rawAvg =
            primaryTrack.map((o) => o.xCenter).reduce((a, b) => a + b) /
            primaryTrack.length;
        avgX = (rawAvg / imageWidth).clamp(0.0, 1.0);
      }

      // Find the first valid face X position to use as starting position
      double? firstDetectedX;
      for (final faces in facesPerFrame) {
        if (faces.isNotEmpty) {
          firstDetectedX = (faces.first.boundingBox.center.dx / imageWidth)
              .clamp(0.0, 1.0);
          break;
        }
      }

      // Per-frame: pick the face that is actually TALKING right now (rolling
      // stddev of mouth-openness within its track), so two speakers who trade
      // lines alternate on screen instead of a single fixed face. Falls back
      // to the largest face; when no face is visible, jumps toward the nearest
      // face in neighbouring samples.
      final keyframes = <({double timeSec, double xPercent})>[];
      double currentSpeakerX = firstDetectedX ?? 0.5;
      var seen = 0;

      for (var i = 0; i < facesPerFrame.length; i++) {
        final timeSec = timeSecs != null && timeSecs.length > i
            ? timeSecs[i]
            : i.toDouble();
        final faces = facesPerFrame[i];

        double? targetX;
        var maxOpen = 0.0;
        var bestScore = 0.0;
        // Voice is the authoritative "is anyone talking" signal: Whisper's
        // word timestamps (offset to the clip, since frame [timeSec] is
        // relative to the segment) say when speech is actually happening. Lip
        // motion alone is unreliable — an open mouth is not proof of talking.
        final speechActive = _speechActiveAt(
          segmentStartSec + timeSec,
          voicedWindows,
        );
        if (faces.isNotEmpty) {
          _FaceObservation? talking;
          _FaceObservation? mostOpen;
          _FaceObservation? largestObs;
          var bestArea = -1.0;
          for (final face in faces) {
            final obs = _observe(face, i);
            if (obs.area > bestArea) {
              bestArea = obs.area;
              largestObs = obs;
            }
            if (obs.mouthOpenness > maxOpen) {
              maxOpen = obs.mouthOpenness;
              mostOpen = obs;
            }
            final track = _trackOf(tracks, i, obs.xCenter);
            // A face only counts as talking while someone is actually speaking
            // AND its mouth is currently open; once speech stops the score is
            // gated to zero so the crop target does not linger on a silent
            // speaker.
            final motion = _localMouthMotion(track, i);
            final score = speechActive &&
                    obs.mouthOpenness >= _mouthOpenFloor
                ? motion
                : 0.0;
            if (score > bestScore) {
              bestScore = score;
              talking = obs;
            }
          }
          if (speechActive) {
            if (talking != null && bestScore >= _talkingFloor) {
              targetX = talking.xCenter / imageWidth;
            } else if (mostOpen != null && maxOpen >= _mouthOpenFloor) {
              // Speech is happening but no clear lip motion yet: the person
              // whose mouth is open is likely the one producing the voice.
              targetX = mostOpen.xCenter / imageWidth;
            } else if (largestObs != null) {
              targetX = largestObs.xCenter / imageWidth;
            }
          } else {
            // Silence: nobody is talking, so don't hold the last speaker —
            // fall back to the most prominent (largest) face instead.
            if (largestObs != null) {
              targetX = largestObs.xCenter / imageWidth;
            }
          }
        } else {
          targetX = _nearestFaceX(facesPerFrame, i, imageWidth);
        }

        if (targetX != null) currentSpeakerX = targetX;
        if (seen < 20) {
          debugPrint(
            '[face-detect] t=${timeSec.toStringAsFixed(1)}s '
            'speech=$speechActive faces=${faces.length} '
            'open=${maxOpen.toStringAsFixed(2)} '
            'sc=${bestScore.toStringAsFixed(3)} '
            'x=${currentSpeakerX.toStringAsFixed(2)}',
          );
          seen++;
        }

        keyframes.add((timeSec: timeSec, xPercent: currentSpeakerX));
      }

      lastStatus = null;
      debugPrint(
        '[face-detect] keyframes: ${keyframes.length} sampel, avgX=$avgX',
      );
      return (averageX: avgX, keyframes: keyframes);
    } catch (e) {
      lastStatus = 'ML Kit error: $e';
      return (
        averageX: null,
        keyframes: const <({double timeSec, double xPercent})>[],
      );
    }
  }

  /// Groups faces into per-person tracks across the sampled frames by greedily
  /// matching each new face to the nearest open track end.
  List<List<_FaceObservation>> _buildTracks(List<List<Face>> facesPerFrame) {
    final tracks = <List<_FaceObservation>>[];
    double? maxFaceWidth;

    for (final faces in facesPerFrame) {
      for (final face in faces) {
        final w = face.boundingBox.width;
        if (maxFaceWidth == null || w > maxFaceWidth) maxFaceWidth = w;
      }
    }
    final matchThreshold = min(60.0, max(30.0, (maxFaceWidth ?? 100) * 0.4));

    for (var fIdx = 0; fIdx < facesPerFrame.length; fIdx++) {
      final faces = facesPerFrame[fIdx];
      if (faces.isEmpty) continue;
      if (tracks.isEmpty) {
        for (final face in faces) {
          tracks.add([_observe(face, fIdx)]);
        }
        continue;
      }

      final matchedTracks = <int>{};
      final sorted = [...faces]
        ..sort(
          (a, b) => a.boundingBox.center.dx.compareTo(b.boundingBox.center.dx),
        );
      for (final face in sorted) {
        double? bestDist;
        int? bestTrack;
        for (var t = 0; t < tracks.length; t++) {
          if (matchedTracks.contains(t)) continue;
          final dist = (face.boundingBox.center.dx - tracks[t].last.xCenter)
              .abs();
          if ((bestDist == null || dist < bestDist) && dist <= matchThreshold) {
            bestDist = dist;
            bestTrack = t;
          }
        }
        if (bestTrack != null) {
          tracks[bestTrack].add(_observe(face, fIdx));
          matchedTracks.add(bestTrack);
        } else {
          tracks.add([_observe(face, fIdx)]);
          matchedTracks.add(tracks.length - 1);
        }
      }
    }
    return tracks;
  }

  /// Chooses the speaker's track: the one with the most lip motion, falling
  /// back to the largest face when no reliable talking signal is present.
  List<_FaceObservation>? _selectSpeakerTrack(
    List<List<_FaceObservation>> tracks,
  ) {
    if (tracks.isEmpty) return null;
    if (tracks.length == 1) return tracks.first;

    List<_FaceObservation>? talking;
    var bestStd = 0.0;
    for (final track in tracks) {
      if (track.length < 2) continue;
      final std = _stddev(track.map((o) => o.mouthOpenness).toList());
      if (std > bestStd) {
        bestStd = std;
        talking = track;
      }
    }
    if (talking != null && bestStd >= _talkingThreshold) return talking;

    List<_FaceObservation>? largest;
    var bestArea = 0.0;
    for (final track in tracks) {
      final area =
          track.map((o) => o.area).reduce((a, b) => a + b) / track.length;
      if (area > bestArea) {
        bestArea = area;
        largest = track;
      }
    }
    return largest;
  }

  _FaceObservation _observe(Face face, int frameIndex) {
    final box = face.boundingBox;
    return _FaceObservation(
      frameIndex: frameIndex,
      xCenter: box.center.dx,
      area: box.width * box.height,
      mouthOpenness: _mouthOpenness(face) ?? 0.0,
    );
  }

  /// Mouth-openness ratio (0.0 = closed, larger = open). Primary signal is the
  /// lip gap (upper-lip bottom ↔ lower-lip top) normalized by mouth width from
  /// landmarks, which directly measures whether the mouth is open right now.
  double? _mouthOpenness(Face face) {
    final upperLip = face.contours[FaceContourType.upperLipBottom];
    final lowerLip = face.contours[FaceContourType.lowerLipTop];
    final left = face.landmarks[FaceLandmarkType.leftMouth];
    final right = face.landmarks[FaceLandmarkType.rightMouth];
    double? mouthWidth;
    if (left != null && right != null) {
      mouthWidth = _distance(left.position, right.position);
    }
    if (upperLip != null &&
        lowerLip != null &&
        upperLip.points.isNotEmpty &&
        lowerLip.points.isNotEmpty &&
        (mouthWidth ?? 0.0) > 0) {
      final topPt = upperLip.points.first;
      final botPt = lowerLip.points.first;
      return _distance(topPt, botPt) / mouthWidth!;
    }

    final nose = face.landmarks[FaceLandmarkType.noseBase];
    final bottom = face.landmarks[FaceLandmarkType.bottomMouth];
    if (nose != null && bottom != null && mouthWidth != null && mouthWidth > 0) {
      return _distance(nose.position, bottom.position) / mouthWidth;
    }

    return null;
  }

  /// Returns the track holding the observation at [frameIndex] whose X matches
  /// [xCenter], so a detected face can be attached to its person's timeline.
  List<_FaceObservation>? _trackOf(
    List<List<_FaceObservation>> tracks,
    int frameIndex,
    double xCenter,
  ) {
    for (final track in tracks) {
      for (final obs in track) {
        if (obs.frameIndex == frameIndex &&
            (obs.xCenter - xCenter).abs() < 8.0) {
          return track;
        }
      }
    }
    return null;
  }

  /// Rolling stddev of mouth-openness over the current + previous sample
  /// within [track]. A high value means the mouth is actively moving
  /// (talking); listeners stay low so the crop target switches to whoever is
  /// currently speaking. Using only two neighbouring samples keeps the
  /// response fast enough for back-and-forth dialogue.
  double _localMouthMotion(List<_FaceObservation>? track, int frameIndex) {
    if (track == null) return 0.0;
    final opens = <double>[];
    for (final obs in track) {
      if (obs.frameIndex >= frameIndex - 1 && obs.frameIndex <= frameIndex) {
        opens.add(obs.mouthOpenness);
      }
    }
    if (opens.length < 2) return 0.0;
    return _stddev(opens);
  }

  /// Whether speech is happening around [timeSec] (absolute video time). A
  /// Whisper word counts within a small tolerance window on either side so
  /// samples that land between words of the same sentence still count as
  /// voiced, while real pauses between sentences read as silence.
  ///
  /// When no transcript is available the gate falls back to "always voiced",
  /// preserving the older lip-motion-only behaviour.
  bool _speechActiveAt(
    double timeSec,
    List<({double start, double end})> voicedWindows, {
    double toleranceSec = 1.0,
  }) {
    if (voicedWindows.isEmpty) return true;
    for (final w in voicedWindows) {
      if (timeSec >= w.start - toleranceSec &&
          timeSec <= w.end + toleranceSec) {
        return true;
      }
    }
    return false;
  }

  /// X-center of the nearest face around [frameIndex] (look-ahead, then
  /// look-back, up to 3 samples) so an empty sample jumps toward a face
  /// instead of freezing on empty scenery.
  double? _nearestFaceX(
    List<List<Face>> facesPerFrame,
    int frameIndex,
    double imageWidth,
  ) {
    for (var d = 1; d <= 3; d++) {
      for (final j in [frameIndex + d, frameIndex - d]) {
        if (j >= 0 &&
            j < facesPerFrame.length &&
            facesPerFrame[j].isNotEmpty) {
          return (facesPerFrame[j].first.boundingBox.center.dx / imageWidth)
              .clamp(0.0, 1.0);
        }
      }
    }
    return null;
  }

  double _stddev(List<double> values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
        values.length;
    return sqrt(variance);
  }

  double _distance(Point<int> a, Point<int> b) =>
      sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));

  void dispose() {
    _faceDetector.close();
  }
}
