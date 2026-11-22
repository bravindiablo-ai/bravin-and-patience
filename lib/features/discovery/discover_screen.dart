import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../media/post_media_widget.dart';
import '../profile/profile_avatar.dart';
import '../social/public_profile_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final TextEditingController _search = TextEditingController();

  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> posts = [];
  List<Map<String, dynamic>> trending = [];
  List<Map<String, dynamic>> hashtags = [];
  bool loading = false;
  bool searched = false;
  int _searchRequest = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    loadTrending();
    loadHashtags();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> searchAll(String value) async {
    final query = value.trim();
    final request = ++_searchRequest;

    if (query.isEmpty) {
      setState(() {
        searched = false;
        loading = false;
        users = [];
        posts = [];
      });
      return;
    }

    setState(() {
      loading = true;
      searched = true;
    });

    try {
      final cleanQuery = query.replaceAll(',', ' ');
      final results = await Future.wait([
        supabase
            .from('profiles')
            .select('id, username, display_name, avatar_url')
            .ilike('username', '%$cleanQuery%')
            .limit(20),
        supabase
            .from('posts')
            .select('''
              id, user_id, content, created_at,
              media_url, media_type,
              profiles(id, username, display_name, avatar_url),
              likes(user_id),
              comments(id)
            ''')
            .ilike('content', '%$cleanQuery%')
            .order('created_at', ascending: false)
            .limit(30),
      ]);

      if (!mounted || request != _searchRequest) return;

      setState(() {
        users = List<Map<String, dynamic>>.from(results[0]);
        posts = List<Map<String, dynamic>>.from(results[1]);
        loading = false;
      });
    } catch (error) {
      if (!mounted || request != _searchRequest) return;
      setState(() => loading = false);
      _message('Search failed: $error');
    }
  }

  Future<void> loadTrending() async {
    try {
      final result = await supabase
          .from('posts')
          .select('''
            id, user_id, content, created_at,
            media_url, media_type,
            profiles(id, username, display_name, avatar_url),
            likes(user_id),
            comments(id)
          ''')
          .gte(
            'created_at',
            DateTime.now()
                .subtract(const Duration(days: 7))
                .toUtc()
                .toIso8601String(),
          )
          .order('created_at', ascending: false)
          .limit(100);

      final list = List<Map<String, dynamic>>.from(result);
      list.sort((a, b) {
        final scoreA =
            ((a['likes'] as List?)?.length ?? 0) * 2 +
            ((a['comments'] as List?)?.length ?? 0) * 3;
        final scoreB =
            ((b['likes'] as List?)?.length ?? 0) * 2 +
            ((b['comments'] as List?)?.length ?? 0) * 3;
        return scoreB.compareTo(scoreA);
      });

      if (!mounted) return;
      setState(() => trending = list);
    } catch (error) {
      _message('Could not load trending posts: $error');
    }
  }

  Future<void> loadHashtags() async {
    try {
      final result = await supabase
          .from('post_hashtags')
          .select('''
            hashtag_id,
            hashtags(id, name)
          ''')
          .limit(200);

      final counts = <String, int>{};
      for (final row in result) {
        final tag = row['hashtags'];
        if (tag == null) continue;

        final name = tag['name'] as String;
        counts[name] = (counts[name] ?? 0) + 1;
      }

      final list = counts.entries
          .map((entry) => {'name': entry.key, 'count': entry.value})
          .toList();
      list.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      if (!mounted) return;
      setState(() => hashtags = list.take(20).toList());
    } catch (error) {
      _message('Could not load hashtags: $error');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PublicProfileScreen(userId: userId)),
    );
  }

  Widget _userCard(Map<String, dynamic> user) {
    final avatar = user['avatar_url'] as String?;
    final userId = user['id'] as String;

    return ListTile(
      onTap: () => _openProfile(userId),
      leading: ProfileAvatar(
        userId: userId,
        avatarUrl: avatar,
        radius: 22,
        editable: false,
      ),
      title: Text(
        (user['display_name'] ?? user['username'] ?? 'User').toString(),
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        '@${user['username'] ?? ''}',
        style: const TextStyle(color: Colors.white54),
      ),
    );
  }

  Widget _postCard(Map<String, dynamic> post) {
    final profile = post['profiles'] as Map<String, dynamic>? ?? {};
    final likes = post['likes'] as List? ?? [];
    final comments = post['comments'] as List? ?? [];
    final content = post['content']?.toString() ?? '';

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
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: profile['id'] == null
                ? null
                : () => _openProfile(profile['id'].toString()),
            leading: profile['id'] == null
                ? const CircleAvatar(child: Icon(Icons.person))
                : ProfileAvatar(
                    userId: profile['id'].toString(),
                    avatarUrl: profile['avatar_url'] as String?,
                    radius: 20,
                    editable: false,
                  ),
            title: Text(
              '@${profile['username'] ?? 'user'}',
              style: const TextStyle(
                color: Color(0xFF22D3EE),
                fontWeight: FontWeight.bold,
              ),
            ),
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
            '${likes.length} likes  ·  ${comments.length} comments',
            style: const TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _searchResults() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!searched) {
      return const Center(
        child: Text(
          'Search for creators and posts',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'CREATORS',
          style: TextStyle(
            color: Color(0xFF22D3EE),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (users.isEmpty)
          const Text(
            'No creators found.',
            style: TextStyle(color: Colors.white54),
          ),
        ...users.map(_userCard),
        const SizedBox(height: 20),
        const Text(
          'POSTS',
          style: TextStyle(
            color: Color(0xFF22D3EE),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (posts.isEmpty)
          const Text(
            'No matching posts.',
            style: TextStyle(color: Colors.white54),
          ),
        ...posts.map(_postCard),
      ],
    );
  }

  Widget _trendingTab() {
    return RefreshIndicator(
      onRefresh: loadTrending,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Trending this week',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (trending.isEmpty)
            const Text(
              'No trending posts yet. Be among the first to create something!',
              style: TextStyle(color: Colors.white54),
            ),
          ...trending.map(_postCard),
        ],
      ),
    );
  }

  Widget _hashtagsTab() {
    return RefreshIndicator(
      onRefresh: loadHashtags,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Explore topics',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (hashtags.isEmpty)
            const Text(
              'Hashtags will appear as people publish posts.',
              style: TextStyle(color: Colors.white54),
            ),
          ...hashtags.map((tag) {
            return ListTile(
              leading: const Icon(Icons.tag, color: Color(0xFF8B5CF6)),
              title: Text(
                '#${tag['name']}',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                '${tag['count']} recent posts',
                style: const TextStyle(color: Colors.white54),
              ),
              onTap: () {
                final name = tag['name'].toString();
                _search.text = '#$name';
                searchAll(name);
                _tabs.animateTo(0);
              },
            );
          }),
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
        title: const Text(
          'Discover',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _search,
              onChanged: searchAll,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search creators, posts and topics',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF8B5CF6)),
                filled: true,
                fillColor: const Color(0xFF171720),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          TabBar(
            controller: _tabs,
            indicatorColor: const Color(0xFF8B5CF6),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: const [
              Tab(text: 'Search'),
              Tab(text: 'Trending'),
              Tab(text: 'Topics'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_searchResults(), _trendingTab(), _hashtagsTab()],
            ),
          ),
        ],
      ),
    );
  }
}
