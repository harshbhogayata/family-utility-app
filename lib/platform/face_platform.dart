import 'dart:ui' show Rect;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../engines/image/passport_photo.dart';

/// Feature 043 — on-device face detection with ML Kit. The picture never
/// leaves the phone; the model ships inside the app.
class MlKitFaceFinder implements FaceFinder {
  const MlKitFaceFinder();

  @override
  Future<List<FaceBox>> find(String path) async {
    final FaceDetector detector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
    );
    try {
      final List<Face> faces = await detector.processImage(InputImage.fromFilePath(path));
      return <FaceBox>[
        for (final Face f in faces) _box(f.boundingBox),
      ];
    } finally {
      await detector.close();
    }
  }

  static FaceBox _box(Rect r) => FaceBox(r.left, r.top, r.width, r.height);
}
