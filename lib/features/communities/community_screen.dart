import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  List<Map<String, dynamic>> communities = [];
  Set<String> joinedIds = {};
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    loadCommunities();
  }

  Future<void> loadCommunities() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            loading = false;
            error = 'Please log in to view communities.';
          });
        }
        return;
      }

      final results = await Future.wait([
        supabase
            .from('communities')
            .select('id, name, slug, description, owner_id, created_at')
            .order('created_at', ascending: false)
            .limit(100),
        supabase
            .from('community_members')
            .select('community_id')
            .eq('user_id', user.id),
      ]);

      if (!mounted) return;

      setState(() {
        communities = List<Map<String, dynamic>>.from(results[0]);
        joinedIds = results[1]
            .map<String>((item) => item['community_id'].toString())
            .toSet();
        loading = false;
        error = null;
      });
    } catch (loadError) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = loadError.toString();
      });
      _message('Could not load communities: $loadError');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> createCommunity(String name, String description) async {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    if (slug.length < 3 || slug.length > 50) {
      _message('Choose a name that creates a valid community URL.');
      return;
    }

    try {
      await supabase.rpc(
        'create_community',
        params: {
          'community_name': name.trim(),
          'community_slug': slug,
          'community_description': description.trim(),
        },
      );
      await loadCommunities();
      _message('Community created successfully.');
    } catch (error) {
      _message('Could not create community: $error');
    }
  }

  Future<void> joinCommunity(String id) async {
    try {
      await supabase.rpc('join_community', params: {'target_community': id});
      await loadCommunities();
      _message('You joined the community.');
    } catch (error) {
      _message('Could not join community: $error');
    }
  }

  Future<void> leaveCommunity(String id) async {
    try {
      await supabase.rpc('leave_community', params: {'target_community': id});
      await loadCommunities();
      _message('You left the community.');
    } catch (error) {
      _message('Could not leave community: $error');
    }
  }

  void showCreateDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171720),
          title: const Text(
            'Create community',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  maxLength: 60,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Community name',
                    hintStyle: TextStyle(color: Colors.white54),
                  ),
                ),
                TextField(
                  controller: descriptionController,
                  maxLength: 500,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Description',
                    hintStyle: TextStyle(color: Colors.white54),
                  ),
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
              onPressed: () {
                final name = nameController.text;
                final description = descriptionController.text;
                if (name.trim().length < 3) {
                  _message('Community names must be at least 3 characters.');
                  return;
                }

                Navigator.pop(dialogContext);
                createCommunity(name, description);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    ).then((_) {
      nameController.dispose();
      descriptionController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B10),
        title: const Text(
          'Communities',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: showCreateDialog,
            icon: const Icon(Icons.add, color: Colors.white),
            tooltip: 'Create community',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadCommunities,
              child: error != null
                  ? ListView(
                      children: [
                        const SizedBox(height: 100),
                        Center(
                          child: Text(
                            error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        Center(
                          child: TextButton(
                            onPressed: loadCommunities,
                            child: const Text('Try again'),
                          ),
                        ),
                      ],
                    )
                  : communities.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            'No communities yet. Create the first one!',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: communities.length,
                      itemBuilder: (context, index) {
                        final community = communities[index];
                        final id = community['id'].toString();
                        final joined = joinedIds.contains(id);

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
                              Text(
                                community['name'].toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                community['description']?.toString() ?? '',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'trendy/${community['slug']}',
                                      style: const TextStyle(
                                        color: Color(0xFF22D3EE),
                                      ),
                                    ),
                                  ),
                                  if (joined)
                                    OutlinedButton(
                                      onPressed: () => leaveCommunity(id),
                                      child: const Text('Leave'),
                                    )
                                  else
                                    ElevatedButton(
                                      onPressed: () => joinCommunity(id),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF8B5CF6,
                                        ),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Join'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
