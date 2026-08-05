import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Regression test for the vendored `google_mlkit_face_detection` patch:
/// ML Kit can return a landmark as a 1-element list ([x] only) when a face is
/// cut off at the image edge; the stock plugin crashes on `pos[1]` with
/// `RangeError (length): Invalid value: Only valid value is 0: 1`.
void main() {
  test('Face.fromJson tolerates a 1-element landmark list', () {
    final face = Face.fromJson({
      'rect': {'left': 0, 'top': 0, 'right': 100, 'bottom': 120},
      'landmarks': {
        'noseBase': [50, 50],
        'bottomMouth': [50, 70],
        'leftMouth': [40, 62],
        'rightMouth': [60, 62],
        // Edge-cut landmark arrives with only the visible coordinate.
        'leftEye': [30],
        'rightEye': [70],
      },
      'contours': <String, dynamic>{},
    });

    expect(face.landmarks[FaceLandmarkType.noseBase], isNotNull);
    expect(face.landmarks[FaceLandmarkType.bottomMouth], isNotNull);
    expect(face.landmarks[FaceLandmarkType.leftMouth], isNotNull);
    expect(face.landmarks[FaceLandmarkType.rightMouth], isNotNull);
    // Malformed landmarks are dropped instead of crashing.
    expect(face.landmarks[FaceLandmarkType.leftEye], isNull);
    expect(face.landmarks[FaceLandmarkType.rightEye], isNull);
  });

  test('Face.fromJson tolerates a 1-element contour point', () {
    final face = Face.fromJson({
      'rect': {'left': 0, 'top': 0, 'right': 100, 'bottom': 120},
      'landmarks': {
        'noseBase': [50, 50],
        'bottomMouth': [50, 70],
        'leftMouth': [40, 62],
        'rightMouth': [60, 62],
      },
      'contours': {
        'face': [
          [0, 0],
          [100, 0],
          [100, 120],
          [0, 120],
          [1], // Edge-cut contour point.
        ],
      },
    });

    expect(face.contours[FaceContourType.face], isNotNull);
    expect(face.contours[FaceContourType.face]!.points, hasLength(4));
  });
}
