import 'package:flutter/material.dart';
import '../models/chat_message.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage msg;
  const ChatBubble({super.key, required this.msg});

  @override
  Widget build(BuildContext context) {
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
          child: Text(msg.text ?? "", style: TextStyle(color: msg.isMe ? Colors.black : Colors.white, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (msg.isMe) const Icon(Icons.check, size: 14, color: Colors.white54),
          const SizedBox(width: 4),
          const Text('12:48 PM', style: TextStyle(color: Colors.white54, fontSize: 10)),
        ]),
      ],
    );
  }
}
