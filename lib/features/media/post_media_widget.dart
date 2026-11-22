import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class PostMediaWidget extends StatelessWidget {
  final String mediaUrl;
  final String mediaType;

  const PostMediaWidget({
    super.key,
    required this.mediaUrl,
    required this.mediaType,
  });

  @override
  Widget build(BuildContext context) {
    if (mediaType == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          mediaUrl,
          width: double.infinity,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox(
              height: 180,
              child: Center(
                child: Icon(
                  Icons.broken_image,
                  color: Colors.white54,
                  size: 40,
                ),
              ),
            );
          },
        ),
      );
    }

    if (mediaType == 'video') {
      return _NetworkPostVideo(url: mediaUrl);
    }

    return const SizedBox.shrink();
  }
}

class _NetworkPostVideo extends StatefulWidget {
  final String url;

  const _NetworkPostVideo({required this.url});

  @override
  State<_NetworkPostVideo> createState() => _NetworkPostVideoState();
}

class _NetworkPostVideoState extends State<_NetworkPostVideo> {
  late final VideoPlayerController _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initializeController();
  }

  Future<void> _initializeController() async {
    try {
      await _controller.initialize();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Icon(Icons.error_outline, color: Colors.white54, size: 40),
        ),
      );
    }

    if (!_controller.value.isInitialized) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller),
            IconButton(
              iconSize: 56,
              color: Colors.white,
              onPressed: () {
                if (_controller.value.isPlaying) {
                  _controller.pause();
                } else {
                  _controller.play();
                }
                setState(() {});
              },
              icon: Icon(
                _controller.value.isPlaying
                    ? Icons.pause_circle
                    : Icons.play_circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
