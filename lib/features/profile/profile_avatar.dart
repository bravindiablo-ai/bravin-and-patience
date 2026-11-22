import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

class ProfileAvatar extends StatefulWidget {
  final String userId;
  final String? avatarUrl;
  final String? avatarPath;
  final double radius;
  final bool editable;

  const ProfileAvatar({
    super.key,
    required this.userId,
    this.avatarUrl,
    this.avatarPath,
    this.radius = 32,
    this.editable = false,
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  String? _avatarUrl;
  String? _avatarPath;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.avatarUrl;
    _avatarPath = widget.avatarPath;
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.avatarUrl != oldWidget.avatarUrl) {
      _avatarUrl = widget.avatarUrl;
    }
    if (widget.avatarPath != oldWidget.avatarPath) {
      _avatarPath = widget.avatarPath;
    }
  }

  Future<void> _uploadAvatar() async {
    if (supabase.auth.currentUser?.id != widget.userId) return;

    String? uploadedPath;

    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1000,
      );

      if (file == null) return;

      final size = await file.length();
      if (size > 5 * 1024 * 1024) {
        _message('Profile pictures must be 5 MB or smaller.');
        return;
      }

      final extension = file.name.split('.').last.toLowerCase();
      const allowed = ['jpg', 'jpeg', 'png', 'webp'];
      if (!allowed.contains(extension)) {
        _message('Unsupported image format.');
        return;
      }

      if (!mounted) return;
      setState(() => _uploading = true);

      final path =
          '${widget.userId}/${DateTime.now().millisecondsSinceEpoch}.$extension';
      final contentType = switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'application/octet-stream',
      };

      await supabase.storage
          .from('profile-avatars')
          .uploadBinary(
            path,
            await file.readAsBytes(),
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
      uploadedPath = path;

      final publicUrl = supabase.storage
          .from('profile-avatars')
          .getPublicUrl(path);

      try {
        await supabase
            .from('profiles')
            .update({'avatar_url': publicUrl, 'avatar_path': path})
            .eq('id', widget.userId);
      } catch (error) {
        Object? cleanupError;
        try {
          await supabase.storage.from('profile-avatars').remove([path]);
        } catch (error) {
          cleanupError = error;
        }
        uploadedPath = null;

        if (cleanupError != null) {
          throw Exception(
            'Profile update failed: $error. Uploaded image cleanup also '
            'failed: $cleanupError',
          );
        }
        rethrow;
      }

      final oldPath = _avatarPath;
      Object? oldCleanupError;
      if (oldPath != null && oldPath != path) {
        try {
          await supabase.storage.from('profile-avatars').remove([oldPath]);
        } catch (error) {
          oldCleanupError = error;
        }
      }

      if (!mounted) return;

      setState(() {
        _avatarUrl = publicUrl;
        _avatarPath = path;
      });

      if (oldCleanupError == null) {
        _message('Profile picture updated.');
      } else {
        _message(
          'Profile picture updated, but the old image could not be removed: '
          '$oldCleanupError',
        );
      }
    } catch (error) {
      Object? cleanupError;
      if (uploadedPath != null) {
        try {
          await supabase.storage.from('profile-avatars').remove([uploadedPath]);
        } catch (error) {
          cleanupError = error;
        }
      }

      final message = cleanupError == null
          ? 'Could not update profile picture: $error'
          : 'Could not update profile picture: $error. '
                'Uploaded image cleanup also failed: $cleanupError';
      _message(message);
    } finally {
      if (mounted) setState(() => _uploading = false);
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
    final avatar = CircleAvatar(
      radius: widget.radius,
      backgroundColor: const Color(0xFF292238),
      backgroundImage: _avatarUrl != null && _avatarUrl!.isNotEmpty
          ? NetworkImage(_avatarUrl!)
          : null,
      child: _avatarUrl == null || _avatarUrl!.isEmpty
          ? Icon(Icons.person, size: widget.radius, color: Colors.white70)
          : null,
    );

    if (!widget.editable) return avatar;

    return GestureDetector(
      onTap: _uploading ? null : _uploadAvatar,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          avatar,
          CircleAvatar(
            radius: widget.radius * 0.32,
            backgroundColor: const Color(0xFF8B5CF6),
            child: _uploading
                ? const Padding(
                    padding: EdgeInsets.all(5),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.camera_alt, size: 13, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
