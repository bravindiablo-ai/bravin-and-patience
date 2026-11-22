import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final Set<String> _readAttempts = {};
  late final Stream<List<Map<String, dynamic>>> _messageStream;

  bool sending = false;

  String get userId => supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _messageStream = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', widget.conversationId)
        .order('created_at');
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> sendMessage({XFile? image}) async {
    final senderId = userId;
    if (senderId.isEmpty) {
      _message('Please log in to send messages.');
      return;
    }

    final content = controller.text.trim();
    if (content.isEmpty && image == null) return;

    setState(() => sending = true);
    String? uploadedPath;

    try {
      if (image != null) {
        if (await image.length() > 10 * 1024 * 1024) {
          throw Exception('Images must be 10 MB or smaller.');
        }

        final extension = image.name.split('.').last.toLowerCase();
        const allowed = ['jpg', 'jpeg', 'png', 'webp'];
        if (!allowed.contains(extension)) {
          throw Exception('Unsupported image format.');
        }

        final path =
            '$senderId/${widget.conversationId}/${DateTime.now().millisecondsSinceEpoch}.$extension';
        final contentType = switch (extension) {
          'jpg' || 'jpeg' => 'image/jpeg',
          'png' => 'image/png',
          'webp' => 'image/webp',
          _ => 'application/octet-stream',
        };

        await supabase.storage
            .from('message-media')
            .uploadBinary(
              path,
              await image.readAsBytes(),
              fileOptions: FileOptions(contentType: contentType),
            );
        uploadedPath = path;
      }

      await supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': senderId,
        'content': content.isEmpty ? null : content,
        'attachment_path': uploadedPath,
        'attachment_type': uploadedPath == null ? null : 'image',
      });

      if (mounted) controller.clear();
    } catch (error) {
      Object? cleanupError;
      if (uploadedPath != null) {
        try {
          await supabase.storage.from('message-media').remove([uploadedPath]);
        } catch (error) {
          cleanupError = error;
        }
      }

      final message = cleanupError == null
          ? 'Could not send message: $error'
          : 'Could not send message: $error. '
                'Attachment cleanup also failed: $cleanupError';
      _message(message);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> pickImage() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (file != null && mounted) await sendMessage(image: file);
    } catch (error) {
      _message('Could not select image: $error');
    }
  }

  Future<void> markAsRead(Map<String, dynamic> message) async {
    if (message['sender_id'] == userId ||
        message['read_at'] != null ||
        !_readAttempts.add(message['id'].toString())) {
      return;
    }

    try {
      await supabase
          .from('messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', message['id']);
    } catch (error) {
      _readAttempts.remove(message['id'].toString());
      debugPrint('Could not mark message as read: $error');
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Widget messageImage(String path) {
    return FutureBuilder<String>(
      future: supabase.storage
          .from('message-media')
          .createSignedUrl(path, 3600),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SizedBox(
            height: 100,
            width: 150,
            child: Center(
              child: Icon(Icons.broken_image, color: Colors.white54),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const SizedBox(
            height: 100,
            width: 150,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            snapshot.data!,
            width: 190,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image, color: Colors.white54),
          ),
        );
      },
    );
  }

  Widget messageBubble(Map<String, dynamic> message) {
    final mine = message['sender_id'] == userId;
    final content = message['content']?.toString() ?? '';
    final attachment = message['attachment_path'] as String?;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 290),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFF6540B5) : const Color(0xFF242430),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (attachment != null) messageImage(attachment),
            if (content.isNotEmpty) ...[
              if (attachment != null) const SizedBox(height: 8),
              Text(content, style: const TextStyle(color: Colors.white)),
            ],
            if (mine)
              Align(
                alignment: Alignment.bottomRight,
                child: Icon(
                  message['read_at'] == null ? Icons.check : Icons.done_all,
                  color: Colors.white70,
                  size: 15,
                ),
              ),
          ],
        ),
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
          'Conversation',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messageStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Could not load messages: ${snapshot.error}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (scrollController.hasClients) {
                    scrollController.jumpTo(
                      scrollController.position.maxScrollExtent,
                    );
                  }
                });
                for (final message in messages) {
                  markAsRead(message);
                }

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Start the conversation.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) =>
                      messageBubble(messages[index]),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: sending ? null : pickImage,
                    icon: const Icon(
                      Icons.image_outlined,
                      color: Color(0xFF22D3EE),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Write a message...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF171720),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => sending ? null : sendMessage(),
                    ),
                  ),
                  IconButton(
                    onPressed: sending ? null : () => sendMessage(),
                    icon: const Icon(Icons.send, color: Color(0xFF8B5CF6)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
