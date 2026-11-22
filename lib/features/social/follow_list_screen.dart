import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../profile/profile_avatar.dart';
import 'public_profile_screen.dart';

class FollowListScreen extends StatefulWidget {
  final String userId;
  final bool showFollowers;

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.showFollowers,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  List<Map<String, dynamic>> users = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    loadUsers();
  }

  Future<void> loadUsers() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final result = widget.showFollowers
          ? await supabase
                .from('follows')
                .select('''
                  follower_id,
                  profiles!follows_follower_id_fkey (
                    id,
                    username,
                    display_name,
                    avatar_url
                  )
                ''')
                .eq('following_id', widget.userId)
                .order('created_at', ascending: false)
          : await supabase
                .from('follows')
                .select('''
                  following_id,
                  profiles!follows_following_id_fkey (
                    id,
                    username,
                    display_name,
                    avatar_url
                  )
                ''')
                .eq('follower_id', widget.userId)
                .order('created_at', ascending: false);

      final parsed = <Map<String, dynamic>>[];
      for (final item in result) {
        final profile = item['profiles'];
        if (profile != null) {
          parsed.add(Map<String, dynamic>.from(profile as Map));
        }
      }

      if (!mounted) return;

      setState(() {
        users = parsed;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B10),
        title: Text(
          widget.showFollowers ? 'Followers' : 'Following',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: loadUsers,
        child: loading
            ? ListView(
                children: const [
                  SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : error != null
            ? ListView(
                children: [
                  const SizedBox(height: 100),
                  Center(
                    child: Text(
                      'Could not load users.\n$error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: loadUsers,
                      child: const Text('Try again'),
                    ),
                  ),
                ],
              )
            : users.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Text(
                      widget.showFollowers
                          ? 'No followers yet.'
                          : 'Not following anyone yet.',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];
                  final avatarUrl = user['avatar_url'] as String?;

                  return ListTile(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PublicProfileScreen(userId: user['id'] as String),
                        ),
                      );
                    },
                    leading: ProfileAvatar(
                      userId: user['id'] as String,
                      avatarUrl: avatarUrl,
                      radius: 20,
                      editable: false,
                    ),
                    title: Text(
                      (user['display_name'] ?? user['username'] ?? 'User')
                          .toString(),
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '@${user['username'] ?? ''}',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
