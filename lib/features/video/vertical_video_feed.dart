import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/supabase_client.dart';

class VerticalVideoFeed extends StatefulWidget {
  const VerticalVideoFeed({super.key});

  @override
  State<VerticalVideoFeed> createState() => _VerticalVideoFeedState();
}

class _VerticalVideoFeedState extends State<VerticalVideoFeed> {
  final PageController _pageController = PageController();
  List<Map<String, dynamic>> videos = [];
  bool loading = true;
  String? error;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    loadVideos();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> loadVideos() async {
    try {
      final result = await supabase.rpc(
        'get_personalized_posts',
        params: {'limit_count': 100},
      );
      final all = List<Map<String, dynamic>>.from(result);
      final filtered = all.where((post) {
        return post['media_type'] == 'video' && post['media_url'] != null;
      }).toList();

      if (!mounted) return;
      setState(() {
        videos = filtered;
        loading = false;
        error = null;
        _currentIndex = 0;
      });
    } catch (loadError) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = loadError.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Trendy Videos',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not load videos: $error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    TextButton(
                      onPressed: loadVideos,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : videos.isEmpty
          ? const Center(
              child: Text(
                'No videos yet. Be the first creator!',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: videos.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                return _VideoPage(
                  key: ValueKey(videos[index]['id']),
                  post: videos[index],
                  isActive: index == _currentIndex,
                );
              },
            ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool isActive;

  const _VideoPage({super.key, required this.post, required this.isActive});

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  late final VideoPlayerController controller;
  late int likeCount;
  int commentCount = 0;
  bool initialized = false;
  bool failed = false;
  bool liked = false;
  bool busy = false;

  String? get userId => supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    final likes = widget.post['likes'] as List? ?? [];
    final comments = widget.post['comments'] as List? ?? [];
    final currentUserId = userId;
    liked =
        currentUserId != null &&
        likes.any((item) => item['user_id'] == currentUserId);
    likeCount = likes.length;
    commentCount = comments.length;
    controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.post['media_url'].toString()),
    );
    _initializeController();
  }

  @override
  void didUpdateWidget(covariant _VideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (initialized && widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        controller.play();
      } else {
        controller.pause();
      }
    }
  }

  Future<void> _initializeController() async {
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) return;
      setState(() => initialized = true);
      if (widget.isActive) await controller.play();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> toggleLike() async {
    if (busy) return;
    final currentUserId = userId;
    if (currentUserId == null) {
      _message('Please log in to like videos.');
      return;
    }

    setState(() => busy = true);
    try {
      final postId = widget.post['id'];
      if (liked) {
        await supabase
            .from('likes')
            .delete()
            .eq('post_id', postId)
            .eq('user_id', currentUserId);
      } else {
        await supabase.from('likes').insert({
          'post_id': postId,
          'user_id': currentUserId,
        });
      }

      if (!mounted) return;
      setState(() {
        liked = !liked;
        likeCount += liked ? 1 : -1;
      });
    } catch (error) {
      _message('Could not update like: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> showComments() async {
    final currentUserId = userId;
    if (currentUserId == null) {
      _message('Please log in to view and add comments.');
      return;
    }

    final input = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF171720),
        builder: (sheetContext) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Comments',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 280,
                    child: FutureBuilder(
                      future: supabase
                          .from('comments')
                          .select('''
                            id, content, created_at,
                            profiles(username, display_name)
                          ''')
                          .eq('post_id', widget.post['id'])
                          .order('created_at'),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Could not load comments: ${snapshot.error}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final rows = snapshot.data!;
                        if (rows.isEmpty) {
                          return const Center(
                            child: Text(
                              'No comments yet.',
                              style: TextStyle(color: Colors.white54),
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final row = rows[index];
                            final profile =
                                row['profiles'] as Map<String, dynamic>? ?? {};
                            return ListTile(
                              title: Text(
                                '@${profile['username'] ?? 'user'}',
                                style: const TextStyle(
                                  color: Color(0xFF22D3EE),
                                ),
                              ),
                              subtitle: Text(
                                row['content'].toString(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: input,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Write a comment...',
                            hintStyle: TextStyle(color: Colors.white54),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: Color(0xFF8B5CF6)),
                        onPressed: () async {
                          final value = input.text.trim();
                          if (value.isEmpty) return;

                          try {
                            await supabase.from('comments').insert({
                              'post_id': widget.post['id'],
                              'user_id': currentUserId,
                              'content': value,
                            });
                            input.clear();
                            if (mounted) {
                              setState(() => commentCount++);
                            }
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          } catch (error) {
                            if (sheetContext.mounted) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(
                                  content: Text('Could not comment: $error'),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      input.dispose();
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.post['profiles'] as Map<String, dynamic>? ?? {};
    final content = widget.post['content']?.toString() ?? '';

    return Stack(
      fit: StackFit.expand,
      children: [
        if (failed)
          const Center(
            child: Icon(Icons.error_outline, color: Colors.white, size: 48),
          )
        else if (!initialized)
          const Center(child: CircularProgressIndicator())
        else
          GestureDetector(
            onTap: () {
              if (controller.value.isPlaying) {
                controller.pause();
              } else if (widget.isActive) {
                controller.play();
              }
              setState(() {});
            },
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        Positioned(
          left: 16,
          right: 85,
          bottom: 35,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '@${profile['username'] ?? 'creator'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              if (content.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  content,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          right: 12,
          bottom: 55,
          child: Column(
            children: [
              IconButton(
                onPressed: busy ? null : toggleLike,
                iconSize: 34,
                color: liked ? Colors.red : Colors.white,
                icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
              ),
              Text('$likeCount', style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 18),
              IconButton(
                onPressed: showComments,
                iconSize: 32,
                color: Colors.white,
                icon: const Icon(Icons.comment_outlined),
              ),
              Text(
                '$commentCount',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 18),
              const Icon(
                Icons.play_circle_outline,
                color: Colors.white,
                size: 30,
              ),
            ],
          ),
        ),
        if (initialized && !controller.value.isPlaying)
          const Center(
            child: Icon(Icons.play_arrow, size: 70, color: Colors.white),
          ),
      ],
    );
  }
}
