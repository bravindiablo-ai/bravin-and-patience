import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final TextEditingController _contentController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  XFile? _selectedFile;
  String? _mediaType;
  bool _isUploading = false;
  late final Future<Map<String, dynamic>?> _profileFuture;

  static const int _maxCharacters = 5000;
  static const int _maxImageBytes = 10 * 1024 * 1024;
  static const int _maxVideoBytes = 100 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    final userId = supabase.auth.currentUser?.id;
    _profileFuture = userId == null
        ? Future.value(null)
        : supabase
              .from('profiles')
              .select('display_name, username')
              .eq('id', userId)
              .maybeSingle();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia(String type) async {
    try {
      final file = type == 'image'
          ? await _picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
              maxWidth: 2000,
            )
          : await _picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: const Duration(minutes: 2),
            );

      if (file == null || !mounted) return;

      final size = await file.length();
      if (!mounted) return;

      final limit = type == 'image' ? _maxImageBytes : _maxVideoBytes;
      if (size > limit) {
        _showMessage(
          type == 'image'
              ? 'Images must be 10 MB or smaller.'
              : 'Videos must be 100 MB or smaller.',
        );
        return;
      }

      setState(() {
        _selectedFile = file;
        _mediaType = type;
      });
    } catch (error) {
      _showMessage('Could not select media: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _publishPost() async {
    final user = supabase.auth.currentUser;
    final content = _contentController.text.trim();

    if (user == null) {
      _showMessage('Please log in before publishing.');
      return;
    }

    if (content.isEmpty && _selectedFile == null) {
      _showMessage('Write something or select an image or video.');
      return;
    }

    if (content.length > _maxCharacters) {
      _showMessage('Your post is too long. Maximum is 5,000 characters.');
      return;
    }

    setState(() => _isUploading = true);
    String? uploadedPath;

    try {
      String? mediaUrl;
      String? mediaPath;
      String? mediaType;

      if (_selectedFile != null && _mediaType != null) {
        final extension = _selectedFile!.name.split('.').last.toLowerCase();
        final allowedExtensions = _mediaType == 'image'
            ? ['jpg', 'jpeg', 'png', 'webp', 'gif']
            : ['mp4', 'mov', 'm4v'];

        if (!allowedExtensions.contains(extension)) {
          throw Exception('This file format is not supported.');
        }

        final contentType = switch (extension) {
          'jpg' || 'jpeg' => 'image/jpeg',
          'png' => 'image/png',
          'webp' => 'image/webp',
          'gif' => 'image/gif',
          'mp4' => 'video/mp4',
          'mov' => 'video/quicktime',
          'm4v' => 'video/x-m4v',
          _ => 'application/octet-stream',
        };

        mediaType = _mediaType;
        mediaPath =
            '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$extension';
        final bytes = await _selectedFile!.readAsBytes();

        await supabase.storage
            .from('posts-media')
            .uploadBinary(
              mediaPath,
              bytes,
              fileOptions: FileOptions(contentType: contentType, upsert: false),
            );

        uploadedPath = mediaPath;
        mediaUrl = supabase.storage.from('posts-media').getPublicUrl(mediaPath);
      }

      await supabase.from('posts').insert({
        'user_id': user.id,
        'content': content.isEmpty ? null : content,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'media_path': mediaPath,
      });

      if (!mounted) return;

      _contentController.clear();
      setState(() {
        _selectedFile = null;
        _mediaType = null;
      });
      _showMessage('Your post has been published!');
    } catch (error) {
      Object? cleanupError;
      if (uploadedPath != null) {
        try {
          await supabase.storage.from('posts-media').remove([uploadedPath]);
        } catch (error) {
          cleanupError = error;
        }
      }

      final message = cleanupError == null
          ? 'Could not publish your post: $error'
          : 'Could not publish your post: $error. '
                'Media cleanup also failed: $cleanupError';
      _showMessage(message);
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B10),
        title: const Text(
          'Create post',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FutureBuilder<Map<String, dynamic>?>(
                future: _profileFuture,
                builder: (context, snapshot) {
                  final data = snapshot.data;

                  return Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFF8B5CF6),
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              snapshot.hasError
                                  ? 'Profile unavailable'
                                  : data?['display_name'] ?? 'Trendy User',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '@${data?['username'] ?? 'user'}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 25),
              TextField(
                controller: _contentController,
                maxLines: 7,
                maxLength: _maxCharacters,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "What's happening?",
                  hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                  filled: true,
                  fillColor: const Color(0xFF171720),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_selectedFile != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171720),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _mediaType == 'image' ? Icons.image : Icons.video_file,
                        color: const Color(0xFF8B5CF6),
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedFile!.name,
                          style: const TextStyle(color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: _isUploading
                            ? null
                            : () {
                                setState(() {
                                  _selectedFile = null;
                                  _mediaType = null;
                                });
                              },
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              OutlinedButton.icon(
                onPressed: _isUploading ? null : () => _pickMedia('image'),
                icon: const Icon(Icons.image),
                label: const Text('Choose image'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF22D3EE),
                  padding: const EdgeInsets.all(15),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _isUploading ? null : () => _pickMedia('video'),
                icon: const Icon(Icons.video_library),
                label: const Text('Choose video'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF22D3EE),
                  padding: const EdgeInsets.all(15),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isUploading ? null : _publishPost,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                ),
                child: _isUploading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Publish post',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
