import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../media/post_media_widget.dart';
import '../messaging/chat_screen.dart';
import '../profile/profile_avatar.dart';
import '../safety/safety_service.dart';
import 'follow_list_screen.dart';

class PublicProfileScreen extends StatefulWidget {
  final String userId;

  const PublicProfileScreen({super.key, required this.userId});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> posts = [];
  int followerCount = 0;
  int followingCount = 0;
  bool loading = true;
  bool isFollowing = false;
  bool isBlocked = false;
  bool updatingFollow = false;
  String? error;

  bool get isOwnProfile => supabase.auth.currentUser?.id == widget.userId;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final data = await supabase
          .from('profiles')
          .select('id, username, display_name, bio, avatar_url, avatar_path')
          .eq('id', widget.userId)
          .maybeSingle();

      if (data == null) {
        throw Exception('This profile could not be found.');
      }

      final followers = await supabase
          .from('follows')
          .select('follower_id')
          .eq('following_id', widget.userId);
      final following = await supabase
          .from('follows')
          .select('following_id')
          .eq('follower_id', widget.userId);

      final currentUserId = supabase.auth.currentUser?.id;
      var followsProfile = false;
      final blocked = await SafetyService.isBlocked(widget.userId);
      if (currentUserId != null && currentUserId != widget.userId) {
        final relationship = await supabase
            .from('follows')
            .select('follower_id')
            .eq('follower_id', currentUserId)
            .eq('following_id', widget.userId)
            .maybeSingle();
        followsProfile = relationship != null;
      }

      final postRows = await supabase
          .from('posts')
          .select('id, content, created_at, media_url, media_type')
          .eq('user_id', widget.userId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        profile = data;
        followerCount = followers.length;
        followingCount = following.length;
        isFollowing = followsProfile;
        isBlocked = blocked;
        posts = List<Map<String, dynamic>>.from(postRows);
        loading = false;
      });
    } catch (loadError) {
      if (!mounted) return;

      setState(() {
        error = loadError.toString();
        loading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      _showMessage('Please log in to follow creators.');
      return;
    }
    if (currentUserId == widget.userId || updatingFollow) return;

    setState(() => updatingFollow = true);

    try {
      if (isFollowing) {
        await supabase
            .from('follows')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('following_id', widget.userId);
      } else {
        await supabase.from('follows').insert({
          'follower_id': currentUserId,
          'following_id': widget.userId,
        });
      }

      if (!mounted) return;

      setState(() {
        isFollowing = !isFollowing;
        followerCount += isFollowing ? 1 : -1;
      });
    } catch (followError) {
      _showMessage('Could not update follow status: $followError');
    } finally {
      if (mounted) setState(() => updatingFollow = false);
    }
  }

  Future<void> _profileAction(String action) async {
    if (action == 'report') {
      await showTrendyReportDialog(context, reportedUserId: widget.userId);
      return;
    }

    try {
      if (action == 'block') {
        await SafetyService.blockUser(widget.userId);
        if (!mounted) return;
        setState(() => isBlocked = true);
        _showMessage('User blocked.');
      } else if (action == 'unblock') {
        await SafetyService.unblockUser(widget.userId);
        if (!mounted) return;
        setState(() => isBlocked = false);
        _showMessage('User unblocked.');
      }
    } catch (error) {
      _showMessage('Action failed: $error');
    }
  }

  Future<void> _startChat() async {
    try {
      final result = await supabase.rpc(
        'start_conversation',
        params: {'other_user': widget.userId},
      );

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(conversationId: result.toString()),
        ),
      );
    } catch (error) {
      _showMessage('Could not start conversation: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openFollowList({required bool showFollowers}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowListScreen(
          userId: widget.userId,
          showFollowers: showFollowers,
        ),
      ),
    ).then((_) => loadProfile());
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0B10),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null || profile == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0B10),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0B10),
          title: const Text('Profile'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Could not load profile: ${error ?? 'Unknown error'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                TextButton(
                  onPressed: loadProfile,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final creator = profile!;
    final displayName =
        creator['display_name'] ?? creator['username'] ?? 'Trendy User';
    final username = creator['username'] ?? 'user';
    final bio = creator['bio'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B10),
        title: const Text('Creator profile'),
        actions: [
          if (!isOwnProfile)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (action) => _profileAction(action),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: isBlocked ? 'unblock' : 'block',
                  child: Text(isBlocked ? 'Unblock user' : 'Block user'),
                ),
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Report account'),
                ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadProfile,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Column(
                children: [
                  ProfileAvatar(
                    userId: creator['id'] as String,
                    avatarUrl: creator['avatar_url'] as String?,
                    avatarPath: creator['avatar_path'] as String?,
                    radius: 42,
                    editable: false,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    displayName.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@$username',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  if (bio.toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      bio.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _stat(posts.length.toString(), 'Posts', null),
                      const SizedBox(width: 30),
                      _stat(
                        followerCount.toString(),
                        'Followers',
                        () => _openFollowList(showFollowers: true),
                      ),
                      const SizedBox(width: 30),
                      _stat(
                        followingCount.toString(),
                        'Following',
                        () => _openFollowList(showFollowers: false),
                      ),
                    ],
                  ),
                  if (isBlocked) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'You blocked this creator. Unblock them from the menu '
                      'to interact with their profile.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ] else if (!isOwnProfile) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: isFollowing
                              ? OutlinedButton(
                                  onPressed: updatingFollow
                                      ? null
                                      : _toggleFollow,
                                  child: updatingFollow
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Following'),
                                )
                              : ElevatedButton(
                                  onPressed: updatingFollow
                                      ? null
                                      : _toggleFollow,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF8B5CF6),
                                    foregroundColor: Colors.white,
                                  ),
                                  child: updatingFollow
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Follow'),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _startChat,
                            icon: const Icon(Icons.message_outlined),
                            label: const Text('Message'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'Posts',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (isBlocked)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Posts are hidden because you blocked this creator.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              )
            else if (posts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No posts yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              )
            else
              ...posts.map(_postCard),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label, VoidCallback? onTap) {
    final stat = Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white54)),
      ],
    );

    if (onTap == null) return stat;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(padding: const EdgeInsets.all(4), child: stat),
    );
  }

  Widget _postCard(Map<String, dynamic> post) {
    final content = post['content']?.toString() ?? '';
    final mediaUrl = post['media_url'] as String?;
    final mediaType = post['media_type'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171720),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (content.isNotEmpty)
            Text(
              content,
              style: const TextStyle(color: Colors.white, height: 1.4),
            ),
          if (mediaUrl != null && mediaType != null) ...[
            if (content.isNotEmpty) const SizedBox(height: 12),
            PostMediaWidget(mediaUrl: mediaUrl, mediaType: mediaType),
          ],
        ],
      ),
    );
  }
}
