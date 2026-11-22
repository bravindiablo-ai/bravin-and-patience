import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  final Map<String, bool> preferences = {
    'follows_enabled': true,
    'likes_enabled': true,
    'comments_enabled': true,
    'messages_enabled': true,
  };

  bool loading = true;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    loadPreferences();
  }

  Future<void> loadPreferences() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Please log in to manage notification settings.';
        });
      }
      return;
    }

    try {
      final result = await supabase
          .from('notification_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (result != null) {
        for (final key in preferences.keys) {
          preferences[key] = result[key] == true;
        }
      } else {
        await supabase.from('notification_preferences').insert({
          'user_id': userId,
        });
      }

      if (!mounted) return;
      setState(() {
        loading = false;
        error = null;
      });
    } catch (loadError) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = loadError.toString();
      });
    }
  }

  Future<void> savePreferences() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _message('Please log in to save notification settings.');
      return;
    }

    setState(() => saving = true);
    try {
      await supabase.from('notification_preferences').upsert({
        'user_id': userId,
        ...preferences,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      _message('Notification settings saved.');
    } catch (error) {
      _message('Could not save settings: $error');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _preferenceTile(String key, String title, String subtitle) {
    return SwitchListTile(
      value: preferences[key] ?? true,
      activeThumbColor: const Color(0xFF8B5CF6),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white60)),
      onChanged: saving
          ? null
          : (value) => setState(() => preferences[key] = value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B10),
        title: const Text(
          'Notification settings',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could not load preferences: $error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    TextButton(
                      onPressed: loadPreferences,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Choose what Trendy can notify you about.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                _preferenceTile(
                  'follows_enabled',
                  'New followers',
                  'When someone follows you.',
                ),
                _preferenceTile(
                  'likes_enabled',
                  'Likes',
                  'When someone likes your post.',
                ),
                _preferenceTile(
                  'comments_enabled',
                  'Comments',
                  'When someone comments on your post.',
                ),
                _preferenceTile(
                  'messages_enabled',
                  'Messages',
                  'When someone sends you a message.',
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: saving ? null : savePreferences,
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save preferences'),
                  ),
                ),
              ],
            ),
    );
  }
}
