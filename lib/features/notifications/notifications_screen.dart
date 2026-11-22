import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import 'notification_preferences_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String? get userId => supabase.auth.currentUser?.id;

  Future<void> markAsRead(String id) async {
    try {
      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id);
    } catch (error) {
      _message('Could not mark notification as read: $error');
    }
  }

  Future<void> markAllAsRead() async {
    final id = userId;
    if (id == null) return;

    try {
      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', id)
          .eq('is_read', false);
    } catch (error) {
      _message('Could not mark notifications as read: $error');
    }
  }

  IconData notificationIcon(String type) {
    switch (type) {
      case 'follow':
        return Icons.person_add_alt_1;
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.mode_comment;
      case 'message':
        return Icons.chat_bubble;
      default:
        return Icons.notifications;
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = userId;
    if (currentUserId == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0B10),
        body: Center(
          child: Text(
            'Please log in to view notifications.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B10),
        title: const Text(
          'Notifications',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: 'Notification settings',
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationPreferencesScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Mark all as read',
            icon: const Icon(Icons.done_all, color: Colors.white),
            onPressed: markAllAsRead,
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase
            .from('notifications')
            .stream(primaryKey: ['id'])
            .eq('user_id', currentUserId)
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load notifications: ${snapshot.error}',
                style: const TextStyle(color: Colors.white70),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data!;
          if (notifications.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 55,
                    color: Colors.white38,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'You are all caught up.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (_, _) =>
                const Divider(color: Colors.white10, height: 1),
            itemBuilder: (context, index) {
              final item = notifications[index];
              final isRead = item['is_read'] == true;
              final type = item['type']?.toString() ?? 'system';

              return ListTile(
                tileColor: isRead
                    ? Colors.transparent
                    : const Color(0xFF171720),
                leading: CircleAvatar(
                  backgroundColor: const Color(
                    0xFF8B5CF6,
                  ).withValues(alpha: 0.2),
                  child: Icon(
                    notificationIcon(type),
                    color: const Color(0xFF8B5CF6),
                  ),
                ),
                title: Text(
                  item['title']?.toString() ?? 'Notification',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  item['body']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: isRead
                    ? null
                    : const Icon(
                        Icons.circle,
                        size: 9,
                        color: Color(0xFF22D3EE),
                      ),
                onTap: isRead ? null : () => markAsRead(item['id'].toString()),
              );
            },
          );
        },
      ),
    );
  }
}
