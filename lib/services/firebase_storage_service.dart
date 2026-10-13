import 'dart:io';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Uploads partner profile photos to Firebase Storage.
class FirebaseStorageService {
  static final FirebaseStorageService instance = FirebaseStorageService._();
  FirebaseStorageService._();

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  /// Pick a photo from camera only (no gallery / album)
  Future<File?> pickImageFromCamera() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        maxWidth: 800,
      );
      if (picked != null) return File(picked.path);
    } catch (e, stack) {
      debugPrint('[FirebaseStorageService] pickImage error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerStorageService.pickImageFromCamera', fatal: false);
    }
    return null;
  }

  /// Upload file to Firebase Storage, returns public download URL
  Future<String?> uploadFile({required File file, required String path}) async {
    try {
      final Reference ref = _storage.ref().child(path);
      final UploadTask task = ref.putFile(file);
      final TaskSnapshot snapshot = await task;
      return await snapshot.ref.getDownloadURL();
    } catch (e, stack) {
      debugPrint('[FirebaseStorageService] uploadFile error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'PartnerStorageService.uploadFile', fatal: false);
      return null;
    }
  }

  /// Convenience: pick camera photo and immediately upload to the given path
  Future<String?> pickCameraAndUpload({required String storagePath}) async {
    final file = await pickImageFromCamera();
    if (file == null) return null;
    return uploadFile(file: file, path: storagePath);
  }

  /// Upload an inspection side photo to Firebase Storage.
  /// Path: vehicle_inspections/{driverId}/{date}/{side}.jpg
  /// Returns download URL or null on failure.
  Future<String?> uploadInspectionPhoto({
    required File file,
    required String driverId,
    required String date, // e.g. "2026-03-19"
    required String side, // e.g. "front"
  }) async {
    final path = 'vehicle_inspections/$driverId/$date/$side.jpg';
    return uploadFile(file: file, path: path);
  }
}
