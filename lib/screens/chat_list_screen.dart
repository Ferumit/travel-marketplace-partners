import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../repository/firestore_repository.dart';
import '../repository/chat_repository.dart';
import '../models/booking_models.dart';
import '../models/chat_message.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uid = AuthService.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: isDark ? CupertinoColors.black : const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('Сообщения', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      body: uid == null
          ? const Center(child: Text('Не авторизован'))
          : StreamBuilder<List<ActiveTrip>>(
              stream: FirestoreRepository.instance.streamAllTripsByPartner(uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CupertinoActivityIndicator());
                }
                final trips = snapshot.data ?? [];
                if (trips.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.chat_bubble_2, size: 48, color: CupertinoColors.systemGrey3),
                        const SizedBox(height: 12),
                        Text(
                          'У вас пока нет активных чатов',
                          style: TextStyle(color: CupertinoColors.systemGrey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: trips.length,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    indent: 70,
                    color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
                  ),
                  itemBuilder: (context, index) {
                    final trip = trips[index];
                    return _ChatTile(isDark: isDark, trip: trip);
                  },
                );
              },
            ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final bool isDark;
  final ActiveTrip trip;

  const _ChatTile({
    required this.isDark,
    required this.trip,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Booking?>(
      future: FirestoreRepository.instance.getBookingById(trip.bookingId),
      builder: (context, bookingSnapshot) {
        final booking = bookingSnapshot.data;
        final title = trip.customName ?? booking?.routeTitle ?? 'Чат маршрута';

        return StreamBuilder<List<ChatMessage>>(
          stream: ChatRepository.instance.streamMessages(trip.id),
          builder: (context, msgSnapshot) {
            final messages = msgSnapshot.data ?? [];
            final lastMessage = messages.isNotEmpty ? messages.first : null;
            final lastMsgText = lastMessage?.text ?? 'Нет сообщений';
            final time = lastMessage != null
                ? '${lastMessage.timestamp.hour.toString().padLeft(2, '0')}:${lastMessage.timestamp.minute.toString().padLeft(2, '0')}'
                : '';
            // Unread indicators not yet supported

            return ListTile(
              onTap: () => context.push('/messenger', extra: {
                'tripId': trip.id,
                'title': title,
              }),
              leading: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF6FBF4F).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.chat_bubble_fill, color: Color(0xFF6FBF4F)),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.normal,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    time,
                    style: const TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  lastMsgText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CupertinoColors.systemGrey,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
