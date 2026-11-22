import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';

class ModerationDashboardScreen extends StatefulWidget {
  const ModerationDashboardScreen({super.key});

  @override
  State<ModerationDashboardScreen> createState() =>
      _ModerationDashboardScreenState();
}

class _ModerationDashboardScreenState extends State<ModerationDashboardScreen> {
  bool loading = true;
  bool isModerator = false;
  List<Map<String, dynamic>> reports = [];
  String? error;

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Please log in to view the moderation dashboard.';
        });
      }
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final moderator = await supabase
          .from('moderation_admins')
          .select('user_id')
          .eq('user_id', userId)
          .maybeSingle();

      final loadedReports = moderator == null
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await supabase
                  .from('content_reports')
                  .select()
                  .order('created_at', ascending: false),
            );

      if (!mounted) return;
      setState(() {
        isModerator = moderator != null;
        reports = loadedReports;
        loading = false;
      });
    } catch (loadError) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = loadError.toString();
      });
    }
  }

  Future<void> takeAction(Map<String, dynamic> report, String action) async {
    final moderatorId = supabase.auth.currentUser?.id;
    if (moderatorId == null) {
      _message('Please log in first.');
      return;
    }

    try {
      final postId = report['post_id']?.toString();
      final commentId = report['comment_id']?.toString();
      final targetUserId = report['reported_user_id']?.toString();

      if (action == 'remove_post' && postId != null) {
        final post = await supabase
            .from('posts')
            .select('media_path')
            .eq('id', postId)
            .maybeSingle();
        final mediaPath = post?['media_path'] as String?;
        if (mediaPath != null) {
          await supabase.storage.from('posts-media').remove([mediaPath]);
        }
        await supabase.from('posts').delete().eq('id', postId);
      } else if (action == 'remove_comment' && commentId != null) {
        await supabase.from('comments').delete().eq('id', commentId);
      }

      final dismiss = action == 'dismiss_report';
      await supabase.from('moderation_actions').insert({
        'moderator_id': moderatorId,
        'report_id': report['id'],
        'target_user_id': targetUserId,
        'action': action,
        'notes': 'Action taken through Trendy moderation dashboard.',
      });

      await supabase
          .from('content_reports')
          .update({
            'status': dismiss ? 'dismissed' : 'actioned',
            'reviewed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', report['id']);

      await loadDashboard();
      _message('Moderation action recorded.');
    } catch (error) {
      _message('Action failed: $error');
    }
  }

  Future<void> reviewReport(Map<String, dynamic> report) async {
    try {
      await supabase
          .from('content_reports')
          .update({'status': 'under_review'})
          .eq('id', report['id']);
      await loadDashboard();
    } catch (error) {
      _message('Could not update report: $error');
    }
  }

  Future<void> showActions(Map<String, dynamic> report) async {
    final hasPost = report['post_id'] != null;
    final hasComment = report['comment_id'] != null;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF171720),
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              const ListTile(
                title: Text(
                  'Moderation actions',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              if (hasPost)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.redAccent),
                  title: const Text(
                    'Remove reported post',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    takeAction(report, 'remove_post');
                  },
                ),
              if (hasComment)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.redAccent),
                  title: const Text(
                    'Remove reported comment',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    takeAction(report, 'remove_comment');
                  },
                ),
              ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.orange),
                title: const Text(
                  'Record user warning',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  takeAction(report, 'warn_user');
                },
              ),
              ListTile(
                leading: const Icon(Icons.check, color: Colors.green),
                title: const Text(
                  'Dismiss report',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  takeAction(report, 'dismiss_report');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B10),
        title: const Text(
          'Moderation dashboard',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: loadDashboard,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load moderation dashboard: $error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            )
          : !isModerator
          ? const Center(
              child: Text(
                'You do not have moderator access.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : reports.isEmpty
          ? const Center(
              child: Text(
                'No reports to review.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : ListView.builder(
              itemCount: reports.length,
              itemBuilder: (context, index) {
                final report = reports[index];
                final status = report['status']?.toString() ?? 'pending';

                return Card(
                  color: const Color(0xFF171720),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    title: Text(
                      report['reason']?.toString() ?? 'Report',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      'Status: $status\n'
                      '${report['details'] ?? 'No additional details'}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onSelected: (value) {
                        if (value == 'review') {
                          reviewReport(report);
                        } else if (value == 'actions') {
                          showActions(report);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'review',
                          child: Text('Mark under review'),
                        ),
                        PopupMenuItem(
                          value: 'actions',
                          child: Text('Take action'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
