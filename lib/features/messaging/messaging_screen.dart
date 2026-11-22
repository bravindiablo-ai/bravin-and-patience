import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../profile/profile_avatar.dart';
import 'chat_screen.dart';

class MessagingScreen extends StatefulWidget {
  const MessagingScreen({super.key});

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  List<Map<String, dynamic>> conversations = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    loadConversations();
  }

  Future<void> loadConversations() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            loading = false;
            error = 'Please log in to view messages.';
          });
        }
        return;
      }

      final result = await supabase
          .from('conversations')
          .select('id, user_one, user_two, last_message_at')
          .or('user_one.eq.${user.id},user_two.eq.${user.id}')
          .order('last_message_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(result);
      final otherIds = rows
          .map((row) {
            return row['user_one'] == user.id
                ? row['user_two'].toString()
                : row['user_one'].toString();
          })
          .toSet()
          .toList();

      final profiles = <String, Map<String, dynamic>>{};
      if (otherIds.isNotEmpty) {
        final profileRows = await supabase
            .from('profiles')
            .select('id, username, display_name, avatar_url')
            .inFilter('id', otherIds);

        for (final profile in profileRows) {
          profiles[profile['id'].toString()] = Map<String, dynamic>.from(
            profile,
          );
        }
      }

      if (!mounted) return;

      setState(() {
        conversations = rows.map((row) {
          final otherId = row['user_one'] == user.id
              ? row['user_two'].toString()
              : row['user_one'].toString();
          return {...row, 'other_profile': profiles[otherId] ?? {}};
        }).toList();
        loading = false;
        error = null;
      });
    } catch (loadError) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = loadError.toString();
      });
      _message('Could not load conversations: $loadError');
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> startChat(String userId) async {
    try {
      final result = await supabase.rpc(
        'start_conversation',
        params: {'other_user': userId},
      );
      final conversationId = result.toString();
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(conversationId: conversationId),
        ),
      );
      await loadConversations();
    } catch (error) {
      _message('Could not start conversation: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B10),
        title: const Text('Messages', style: TextStyle(color: Colors.white)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadConversations,
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
                            onPressed: loadConversations,
                            child: const Text('Try again'),
                          ),
                        ),
                      ],
                    )
                  : conversations.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text(
                            'Your conversations will appear here.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final conversation = conversations[index];
                        final profile =
                            conversation['other_profile']
                                as Map<String, dynamic>? ??
                            {};
                        final profileId = profile['id']?.toString();

                        return ListTile(
                          leading: profileId == null
                              ? const CircleAvatar(child: Icon(Icons.person))
                              : ProfileAvatar(
                                  userId: profileId,
                                  avatarUrl: profile['avatar_url'] as String?,
                                  radius: 24,
                                ),
                          title: Text(
                            (profile['display_name'] ??
                                    profile['username'] ??
                                    'User')
                                .toString(),
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            '@${profile['username'] ?? ''}',
                            style: const TextStyle(color: Colors.white54),
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  conversationId: conversation['id'].toString(),
                                ),
                              ),
                            );
                            await loadConversations();
                          },
                        );
                      },
                    ),
            ),
    );
  }
}
