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
  bool _isViewOnce = false;
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
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              _isViewOnce ? Icons.looks_one_rounded : Icons.looks_one_outlined,
              color: _isViewOnce ? Colors.orangeAccent : Colors.white,
            ),
            onPressed: () {
              setState(() => _isViewOnce = !_isViewOnce);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_isViewOnce ? 'View Once ON' : 'View Once OFF'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: widget.type == 'image'
                ? Image.file(widget.file)
                : (_videoController != null && _videoController!.value.isInitialized
                    ? AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
                      )
                    : const CircularProgressIndicator(color: Colors.orangeAccent)),
          ),
          Positioned(
            bottom: 40,
            right: 20,
            child: FloatingActionButton(
              backgroundColor: Colors.orangeAccent,
              onPressed: () => Navigator.pop(context, {'file': widget.file, 'isViewOnce': _isViewOnce}),
              child: const Icon(Icons.send_rounded, color: Colors.black),
            ),
          ),
          if (_isViewOnce)
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.looks_one_rounded, color: Colors.orangeAccent, size: 16),
                      SizedBox(width: 8),
                      Text('Send as One-Time View', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
