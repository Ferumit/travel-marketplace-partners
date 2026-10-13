import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_message.dart';

class ChatRepository {
  static final ChatRepository instance = ChatRepository._();
  ChatRepository._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Отправляет сообщение в чат поездки
  Future<void> sendMessage({
    required String tripId,
    required String text,
    required String senderId,
    required bool isPartner,
  }) async {
    final docRef = _firestore
        .collection('active_trips_chats')
        .doc(tripId)
        .collection('messages')
        .doc();

    final message = ChatMessage(
      id: docRef.id,
      text: text,
      senderId: senderId,
      isPartner: isPartner,
      timestamp: DateTime.now(), // Используется serverTimestamp() при toJson()
    );

    await docRef.set(message.toJson());
  }

  /// Получает стрим сообщений для конкретной поездки
  Stream<List<ChatMessage>> streamMessages(String tripId) {
    return _firestore
        .collection('active_trips_chats')
        .doc(tripId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return ChatMessage.fromJson(doc.id, doc.data());
          }).toList();
        });
  }
}
