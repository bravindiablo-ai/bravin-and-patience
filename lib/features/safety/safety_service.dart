import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';

class SafetyService {
  static Future<void> blockUser(String userId) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      throw Exception('Please log in first.');
    }

    await supabase.from('user_blocks').upsert({
      'blocker_id': currentUser.id,
      'blocked_id': userId,
    }, onConflict: 'blocker_id,blocked_id');
  }

  static Future<void> unblockUser(String userId) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      throw Exception('Please log in first.');
    }

    await supabase
        .from('user_blocks')
        .delete()
        .eq('blocker_id', currentUser.id)
        .eq('blocked_id', userId);
  }

  static Future<bool> isBlocked(String userId) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return false;

    final result = await supabase
        .from('user_blocks')
        .select('id')
        .eq('blocker_id', currentUser.id)
        .eq('blocked_id', userId)
        .maybeSingle();

    return result != null;
  }

  static Future<List<Map<String, dynamic>>> getBlockedUsers() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return [];

    final result = await supabase
        .from('user_blocks')
        .select('blocked_id, created_at')
        .eq('blocker_id', currentUser.id)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(result);
  }

  static Future<void> reportContent({
    String? reportedUserId,
    String? postId,
    String? commentId,
    required String reason,
    String details = '',
  }) async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) {
      throw Exception('Please log in first.');
    }

    await supabase.from('content_reports').insert({
      'reporter_id': currentUser.id,
      'reported_user_id': reportedUserId,
      'post_id': postId,
      'comment_id': commentId,
      'reason': reason,
      'details': details.trim(),
    });
  }
}

Future<void> showTrendyReportDialog(
  BuildContext context, {
  String? reportedUserId,
  String? postId,
  String? commentId,
}) async {
  const reasons = [
    'Harassment or bullying',
    'Hate speech',
    'Violence or threats',
    'Spam or scams',
    'Sexual or inappropriate content',
    'False information',
    'Copyright violation',
    'Other',
  ];

  var selectedReason = reasons.first;
  final detailsController = TextEditingController();

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var submitting = false;

        return StatefulBuilder(
          builder: (_, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF171720),
              title: const Text(
                'Report content',
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedReason,
                      dropdownColor: const Color(0xFF171720),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Reason',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                      items: reasons.map((reason) {
                        return DropdownMenuItem(
                          value: reason,
                          child: Text(reason),
                        );
                      }).toList(),
                      onChanged: submitting
                          ? null
                          : (value) {
                              if (value != null) {
                                setDialogState(() => selectedReason = value);
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: detailsController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Additional details (optional)',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          setDialogState(() => submitting = true);

                          try {
                            await SafetyService.reportContent(
                              reportedUserId: reportedUserId,
                              postId: postId,
                              commentId: commentId,
                              reason: selectedReason,
                              details: detailsController.text,
                            );

                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Report submitted. Thank you.'),
                              ),
                            );
                          } catch (error) {
                            if (!context.mounted) return;
                            setDialogState(() => submitting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Could not submit report: $error',
                                ),
                              ),
                            );
                          }
                        },
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit report'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    detailsController.dispose();
  }
}
