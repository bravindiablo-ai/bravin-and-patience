import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/supabase_client.dart';
import 'features/auth/login_screen.dart';
import 'features/bookmarks/bookmarks_screen.dart';
import 'features/communities/community_screen.dart';
import 'features/discovery/discover_screen.dart';
import 'features/media/create_screen.dart';
import 'features/media/post_media_widget.dart';
import 'features/messaging/messaging_screen.dart';
import 'features/moderation/moderation_dashboard_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/profile/profile_avatar.dart';
import 'features/safety/safety_service.dart';
import 'features/social/follow_list_screen.dart';
import 'features/video/vertical_video_feed.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://lzlkjowshjfooykckntl.supabase.co',
    publishableKey: 'sb_publishable_aQLPoonUyuqFuPwBl8lRlQ_83AqFPht',
  );

  runApp(const TrendyApp());
}

const Color backgroundColor = Color(0xFF0B0B10);
const Color surfaceColor = Color(0xFF171720);
const Color primaryColor = Color(0xFF8B5CF6);
const Color secondaryColor = Color(0xFF22D3EE);

class TrendyApp extends StatelessWidget {
  const TrendyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Trendy',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: ColorScheme.dark(
          primary: primaryColor,
          secondary: secondaryColor,
          surface: surfaceColor,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int selectedIndex = 0;

  final List<Widget> screens = const [
    HomeScreen(),
    DiscoverScreen(),
    CreateScreen(),
    CommunityScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: selectedIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        backgroundColor: surfaceColor,
        indicatorColor: primaryColor.withValues(alpha: 0.2),
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline, size: 30),
            selectedIcon: Icon(Icons.add_circle, size: 30),
            label: 'Create',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Community',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// HOME SCREEN

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> posts = [];
  bool loading = true;
  bool _personalized = false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    loadPosts();
  }

  Future<void> loadPosts({bool? personalized}) async {
    final usePersonalized = personalized ?? _personalized;
    if (personalized != null) {
      setState(() {
        _personalized = personalized;
        loading = true;
        loadError = null;
      });
    }

    try {
      final List<Map<String, dynamic>> loadedPosts;
      if (usePersonalized) {
        final result = await supabase.rpc(
          'get_personalized_posts',
          params: {'limit_count': 30},
        );
        loadedPosts = List<Map<String, dynamic>>.from(result);
      } else {
        final result = await supabase
            .from('posts')
            .select('''
              id,
              user_id,
              content,
              created_at,
              media_url,
              media_type,
              media_path,
              profiles (
                id,
                username,
                display_name,
                avatar_url
              ),
              likes(user_id),
              comments(id)
            ''')
            .order('created_at', ascending: false);
        loadedPosts = List<Map<String, dynamic>>.from(result);
      }

      if (!mounted) return;

      setState(() {
        posts = loadedPosts;
        loading = false;
        loadError = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        loading = false;
        loadError = error.toString();
      });
    }
  }

  Future<void> _savePost(String postId) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _showMessage('Please log in to save posts.');
        return;
      }

      await supabase
          .from('bookmarks')
          .upsert(
            {'user_id': user.id, 'post_id': postId},
            onConflict: 'user_id,post_id',
            ignoreDuplicates: true,
          );

      _showMessage('Post saved!');
    } catch (error) {
      _showMessage('Could not save post: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> deletePost(String postId) async {
    try {
      final post = await supabase
          .from('posts')
          .select('media_path')
          .eq('id', postId)
          .single();

      final mediaPath = post['media_path'] as String?;

      if (mediaPath != null) {
        await supabase.storage.from('posts-media').remove([mediaPath]);
      }

      await supabase.from('posts').delete().eq('id', postId);
      await loadPosts();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete post: $error')));
    }
  }

  Future<void> confirmDeletePost(String postId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        title: const Text('Delete post?'),
        content: const Text(
          'This will permanently delete the post and its uploaded media.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await deletePost(postId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'trendy',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Notifications',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.notifications_outlined),
                    ),
                    IconButton(
                      tooltip: 'Messages',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MessagingScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                    ),
                    IconButton(
                      tooltip: 'Trendy Videos',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const VerticalVideoFeed(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_circle_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: loadPosts,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Your world, discovered.',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Discover what the community is sharing.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Latest')),
                      ButtonSegment(value: true, label: Text('For You')),
                    ],
                    selected: {_personalized},
                    onSelectionChanged: (selection) {
                      loadPosts(personalized: selection.first);
                    },
                  ),
                  const SizedBox(height: 20),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (loadError != null)
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Could not load posts: $loadError',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          TextButton(
                            onPressed: loadPosts,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    )
                  else if (posts.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No posts yet. Be the first to share something!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ...posts.map(_buildPostCard),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post) {
    final profile = post['profiles'] as Map<String, dynamic>? ?? {};
    final displayName = profile['display_name'] as String? ?? 'Trendy User';
    final username = profile['username'] as String? ?? 'user';
    final avatarUrl = profile['avatar_url'] as String?;
    final content = post['content']?.toString() ?? '';
    final mediaUrl = post['media_url'] as String?;
    final mediaType = post['media_type'] as String?;
    final isOwner = post['user_id'] == supabase.auth.currentUser?.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProfileAvatar(
                userId: (profile['id'] ?? post['user_id']).toString(),
                avatarUrl: avatarUrl,
                radius: 24,
                editable: false,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '@$username',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              if (isOwner)
                PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'delete') {
                      await confirmDeletePost(post['id'].toString());
                    } else if (action == 'report') {
                      await showTrendyReportDialog(
                        context,
                        postId: post['id'].toString(),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    if (isOwner)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete post'),
                      ),
                    const PopupMenuItem(
                      value: 'report',
                      child: Text('Report post'),
                    ),
                  ],
                ),
              if (!isOwner)
                PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'report') {
                      await showTrendyReportDialog(
                        context,
                        postId: post['id'].toString(),
                      );
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'report', child: Text('Report post')),
                  ],
                ),
            ],
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(content, style: const TextStyle(fontSize: 15, height: 1.5)),
          ],
          if (mediaUrl != null && mediaType != null) ...[
            const SizedBox(height: 12),
            PostMediaWidget(mediaUrl: mediaUrl, mediaType: mediaType),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.favorite_border, size: 21),
              SizedBox(width: 6),
              Text('${(post['likes'] as List?)?.length ?? 0} Like'),
              SizedBox(width: 25),
              const Icon(Icons.chat_bubble_outline, size: 21),
              SizedBox(width: 6),
              Text('${(post['comments'] as List?)?.length ?? 0} Comment'),
              const Spacer(),
              IconButton(
                tooltip: 'Save post',
                onPressed: () => _savePost(post['id'].toString()),
                icon: const Icon(
                  Icons.bookmark_add_outlined,
                  color: primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// PROFILE SCREEN

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? profile;
  bool loading = true;
  bool showPosts = true;
  int followerCount = 0;
  int followingCount = 0;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (mounted) setState(() => loading = false);
        return;
      }

      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        profile = data;
        loading = false;
      });

      if (data == null) return;

      try {
        final followers = await supabase
            .from('follows')
            .select('follower_id')
            .eq('following_id', user.id);
        final following = await supabase
            .from('follows')
            .select('following_id')
            .eq('follower_id', user.id);

        if (!mounted) return;

        setState(() {
          followerCount = followers.length;
          followingCount = following.length;
        });
      } catch (error) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load follow counts: $error')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => loading = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load profile: $error')),
        );
      }
    }
  }

  Future<void> editProfile() async {
    if (profile == null) return;

    final nameController = TextEditingController(
      text: profile!['display_name'] ?? '',
    );

    final usernameController = TextEditingController(
      text: profile!['username'] ?? '',
    );

    final bioController = TextEditingController(text: profile!['bio'] ?? '');

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: surfaceColor,
          title: const Text('Edit Profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                TextField(
                  controller: bioController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Bio'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final username = usernameController.text.trim().toLowerCase();

                if (username.length < 3 ||
                    !RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a valid username.')),
                  );
                  return;
                }

                try {
                  await supabase
                      .from('profiles')
                      .update({
                        'display_name': nameController.text.trim(),
                        'username': username,
                        'bio': bioController.text.trim(),
                        'updated_at': DateTime.now().toIso8601String(),
                      })
                      .eq('id', supabase.auth.currentUser!.id);

                  if (!mounted || !dialogContext.mounted) return;

                  Navigator.pop(dialogContext);
                  await loadProfile();
                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Profile updated successfully!'),
                    ),
                  );
                } catch (error) {
                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Profile update failed: $error')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    usernameController.dispose();
    bioController.dispose();
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: backgroundColor,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (profile == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Profile could not be found.'),
              TextButton(
                onPressed: loadProfile,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final name = profile!['display_name'] ?? 'Trendy User';
    final username = profile!['username'] ?? 'user';
    final bio = profile!['bio'] ?? '';

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: logout,
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
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
                    userId: profile!['id'] as String,
                    avatarUrl: profile!['avatar_url'] as String?,
                    avatarPath: profile!['avatar_path'] as String?,
                    radius: 48,
                    editable: true,
                  ),

                  const SizedBox(height: 15),

                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    '@$username',
                    style: const TextStyle(color: Colors.grey),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    bio,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _stat('0', 'Posts'),
                      const SizedBox(width: 35),
                      _followStat(
                        followerCount.toString(),
                        'Followers',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FollowListScreen(
                              userId: profile!['id'] as String,
                              showFollowers: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 35),
                      _followStat(
                        followingCount.toString(),
                        'Following',
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FollowListScreen(
                              userId: profile!['id'] as String,
                              showFollowers: false,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: editProfile,
                      child: const Text('Edit Profile'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            ListTile(
              leading: const Icon(
                Icons.bookmarks_outlined,
                color: primaryColor,
              ),
              title: const Text(
                'Saved posts',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BookmarksScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.admin_panel_settings,
                color: Colors.white,
              ),
              title: const Text(
                'Moderation dashboard',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ModerationDashboardScreen(),
                  ),
                );
              },
            ),

            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      setState(() => showPosts = true);
                    },
                    child: Text(
                      'Posts',
                      style: TextStyle(
                        color: showPosts ? primaryColor : Colors.grey,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      setState(() => showPosts = false);
                    },
                    child: Text(
                      'About',
                      style: TextStyle(
                        color: !showPosts ? primaryColor : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (showPosts)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: Text(
                    'Your posts will appear here.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ListTile(
                leading: const Icon(
                  Icons.email_outlined,
                  color: secondaryColor,
                ),
                title: const Text('Email'),
                subtitle: Text(
                  supabase.auth.currentUser?.email ?? 'Not available',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _followStat(String value, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: _stat(value, label),
      ),
    );
  }
}
// TEMPORARY SCREEN COMPONENT

class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 65, color: primaryColor),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? supabase.auth.currentSession;

        if (session == null) {
          return const LoginScreen();
        }

        return const MainNavigation();
      },
    );
  }
}
