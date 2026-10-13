import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String text;
  final String senderId;
  final bool isPartner;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.isPartner,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(String id, Map<String, dynamic> json) {
    return ChatMessage(
      id: id,
      text: json['text'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      isPartner: json['isPartner'] as bool? ?? false,
      timestamp: json['timestamp'] != null
          ? (json['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'senderId': senderId,
    'isPartner': isPartner,
    'timestamp': FieldValue.serverTimestamp(),
  };
}
