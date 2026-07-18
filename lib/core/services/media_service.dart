import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart';

class MediaService {
  static final MediaService _instance = MediaService._internal();
  factory MediaService() => _instance;
  MediaService._internal();

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
