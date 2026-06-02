import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gogo/features/chat/models/chat_message.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage msg;
  const ChatBubble({super.key, required this.msg});

  @override
  Widget build(BuildContext context) {
    final String timeStr = DateFormat('hh:mm a').format(msg.timestamp);
    
    return Column(
      crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: msg.isMe ? Colors.orangeAccent : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              bottomLeft: Radius.circular(msg.isMe ? 16 : 0),
              topRight: const Radius.circular(16),
              bottomRight: Radius.circular(msg.isMe ? 0 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (msg.type == 'image' || msg.imageUrl != null || msg.localFilePath != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: msg.localFilePath != null 
                        ? Image.file(File(msg.localFilePath!), width: 200, height: 200, fit: BoxFit.cover)
                        : (msg.imageUrl != null ? Image.network(msg.imageUrl!, width: 200, height: 200, fit: BoxFit.cover) : const SizedBox.shrink()),
                  ),
                ),
              if (msg.text != null && msg.text!.isNotEmpty)
                Text(msg.text!, style: TextStyle(color: msg.isMe ? Colors.black : Colors.white, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (msg.isMe) const Icon(Icons.check, size: 14, color: Colors.white54),
          const SizedBox(width: 4),
          Text(timeStr, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ]),
      ],
    );
  }
}
