import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../media/post_media_widget.dart';
import '../profile/profile_avatar.dart';
import '../social/public_profile_screen.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<Map<String, dynamic>> savedPosts = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadBookmarks();
  }

  Future<void> loadBookmarks() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => loading = false);
        return;
      }

      final result = await supabase
          .from('bookmarks')
          .select('''
            created_at,
            posts(
              id,
              user_id,
              content,
              created_at,
              media_url,
              media_type,
              profiles(id, username, display_name, avatar_url),
              likes(user_id),
              comments(id)
            )
          ''')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final parsed = <Map<String, dynamic>>[];
      for (final row in result) {
        final post = row['posts'];
        if (post != null) {
          parsed.add(Map<String, dynamic>.from(post as Map));
        }
      }

      if (!mounted) return;

      setState(() {
        savedPosts = parsed;
        loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => loading = false);
      _message('Could not load saved posts: $error');
    }
  }

  Future<void> removeBookmark(String postId) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _message('Please log in to manage saved posts.');
        return;
      }

      await supabase
          .from('bookmarks')
          .delete()
          .eq('user_id', user.id)
          .eq('post_id', postId);
      await loadBookmarks();
    } catch (error) {
      _message('Could not remove bookmark: $error');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _postCard(Map<String, dynamic> post) {
    final profile = post['profiles'] as Map<String, dynamic>? ?? {};
    final likes = post['likes'] as List? ?? [];
    final comments = post['comments'] as List? ?? [];
    final content = post['content']?.toString() ?? '';
    final postId = post['id'].toString();
    final profileId = profile['id']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171720),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (profileId != null)
                ProfileAvatar(
                  userId: profileId,
                  avatarUrl: profile['avatar_url'] as String?,
                  radius: 20,
                )
              else
                const CircleAvatar(child: Icon(Icons.person)),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: profileId == null
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PublicProfileScreen(userId: profileId),
                          ),
                        ),
                  child: Text(
                    '@${profile['username'] ?? 'user'}',
                    style: const TextStyle(
                      color: Color(0xFF22D3EE),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => removeBookmark(postId),
                icon: const Icon(
                  Icons.bookmark_remove_outlined,
                  color: Color(0xFF8B5CF6),
                ),
                tooltip: 'Remove saved post',
              ),
            ],
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(content, style: const TextStyle(color: Colors.white)),
          ],
          if (post['media_url'] != null && post['media_type'] != null) ...[
            const SizedBox(height: 12),
            PostMediaWidget(
              mediaUrl: post['media_url'] as String,
              mediaType: post['media_type'] as String,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '${likes.length} likes · ${comments.length} comments',
            style: const TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B10),
        title: const Text('Saved posts', style: TextStyle(color: Colors.white)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadBookmarks,
              child: savedPosts.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            'Your saved posts will appear here.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: savedPosts.length,
                      itemBuilder: (context, index) =>
                          _postCard(savedPosts[index]),
                    ),
            ),
    );
  }
}
