import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MediaService {
  static final MediaService _instance = MediaService._internal();
  factory MediaService() => _instance;
  MediaService._internal();

  /// Compresses an image for faster upload/loading without a visible quality loss.
  /// Downscales to fit within [maxDimension] (longest side) and re-encodes as
  /// JPEG at [quality]. Returns the original file if compression fails or
  /// doesn't actually save space.
  Future<File> compressImage(File file, {int quality = 82, int maxDimension = 1440}) async {
    try {
      final int originalSize = await file.length();
      debugPrint("🖼️ [MEDIA_SERVICE] Original image size: ${(originalSize / 1024).toStringAsFixed(0)} KB");

      final Directory tempDir = await getTemporaryDirectory();
      final String targetPath = p.join(
        tempDir.path,
        '${DateTime.now().microsecondsSinceEpoch}_${p.basenameWithoutExtension(file.path)}.jpg',
      );

      final XFile? result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: quality,
        minWidth: maxDimension,
        minHeight: maxDimension,
        keepExif: false,
        format: CompressFormat.jpeg,
      );

      if (result == null) return file;

      final File compressedFile = File(result.path);
      final int compressedSize = await compressedFile.length();

      // Only use the compressed version if it's actually smaller.
      if (compressedSize >= originalSize) {
        debugPrint("🖼️ [MEDIA_SERVICE] Compression didn't help, using original");
        return file;
      }

      debugPrint("🖼️ [MEDIA_SERVICE] Compressed image size: ${(compressedSize / 1024).toStringAsFixed(0)} KB "
          "(${((1 - (compressedSize / originalSize)) * 100).toStringAsFixed(1)}% smaller)");
      return compressedFile;
    } catch (e) {
      debugPrint("🚨 [MEDIA_SERVICE] Image compression error: $e");
      return file; // Return original if compression fails
    }
  }

  /// Compresses video for faster sending and reduced server load
  Future<File?> compressVideo(File file) async {
    try {
      debugPrint("🎬 [MEDIA_SERVICE] Starting video compression: ${file.path}");
      
      // Check file size first
      final int originalSize = await file.length();
      debugPrint("🎬 [MEDIA_SERVICE] Original size: ${(originalSize / (1024 * 1024)).toStringAsFixed(2)} MB");

      // Skip compression if already small (e.g., < 2MB)
      if (originalSize < 2 * 1024 * 1024) {
        debugPrint("🎬 [MEDIA_SERVICE] Video is already small, skipping compression");
        return file;
      }

      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.MediumQuality, // Balanced quality and size
        deleteOrigin: false, // Keep original file
        includeAudio: true,
      );

      if (mediaInfo != null && mediaInfo.file != null) {
        final int compressedSize = await mediaInfo.file!.length();
        debugPrint("🎬 [MEDIA_SERVICE] Compression complete!");
        debugPrint("🎬 [MEDIA_SERVICE] New size: ${(compressedSize / (1024 * 1024)).toStringAsFixed(2)} MB");
        debugPrint("🎬 [MEDIA_SERVICE] Savings: ${((1 - (compressedSize / originalSize)) * 100).toStringAsFixed(1)}%");
        
        return mediaInfo.file;
      }
    } catch (e) {
      debugPrint("🚨 [MEDIA_SERVICE] Compression error: $e");
    }
    return file; // Return original if compression fails
  }

  /// Generates a thumbnail for a video file
  Future<File?> generateThumbnail(File videoFile) async {
    try {
      final thumbnailFile = await VideoCompress.getFileThumbnail(
        videoFile.path,
        quality: 50,
        position: -1, // Use default
      );
      return thumbnailFile;
    } catch (e) {
      debugPrint("🚨 [MEDIA_SERVICE] Thumbnail error: $e");
      return null;
    }
  }

  /// Clears compression cache
  Future<void> clearCache() async {
    await VideoCompress.deleteAllCache();
  }
}
