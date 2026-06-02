import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MediaPreviewScreen extends StatefulWidget {
  final File file;
  final String type; // 'image' or 'video'

  const MediaPreviewScreen({super.key, required this.file, required this.type});

  @override
  State<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends State<MediaPreviewScreen> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    if (widget.type == 'video') {
      _videoController = VideoPlayerController.file(widget.file)
        ..initialize().then((_) => setState(() {}))
        ..setLooping(true)
        ..play();
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.type == 'image' ? 'Preview Image' : 'Preview Video',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: widget.type == 'image'
                  ? InteractiveViewer(child: Image.file(widget.file))
                  : (_videoController != null && _videoController!.value.isInitialized
                      ? AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        )
                      : const CircularProgressIndicator(color: Colors.orangeAccent)),
            ),
          ),
          
          // Bottom Buttons Area
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 30), // Professional gap from bottom
                child: Row(
                  children: [
                    // Button 1: Send Normally
                    Expanded(
                      child: _buildActionButton(
                        label: 'SEND NORMALLY',
                        icon: Icons.send_rounded,
                        color: Colors.white.withValues(alpha: 0.1),
                        textColor: Colors.white,
                        onTap: () => Navigator.pop(context, {'file': widget.file, 'isViewOnce': false}),
                      ),
                    ),
                    const SizedBox(width: 15),
                    // Button 2: One Time View
                    Expanded(
                      child: _buildActionButton(
                        label: 'ONE TIME VIEW',
                        icon: Icons.looks_one_rounded,
                        color: Colors.orangeAccent,
                        textColor: Colors.black,
                        onTap: () => Navigator.pop(context, {'file': widget.file, 'isViewOnce': true}),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 60,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: textColor, size: 20),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
