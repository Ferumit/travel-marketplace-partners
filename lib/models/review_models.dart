import 'package:cloud_firestore/cloud_firestore.dart';

class Review {
  final String id;
  final String bookingId;
  final String authorId;
  final String authorName;
  final String authorRole; // 'client' | 'driver' | 'guide'
  final String targetId;
  final String targetRole; // 'client' | 'driver' | 'guide'
  final double rating; // 1.0–5.0
  final String comment;
  final DateTime createdAt;

  const Review({
    required this.id,
    required this.bookingId,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    required this.targetId,
    required this.targetRole,
    required this.rating,
    this.comment = '',
    required this.createdAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        id: json['id'] as String? ?? '',
        bookingId: json['bookingId'] as String? ?? '',
        authorId: json['authorId'] as String? ?? '',
        authorName: json['authorName'] as String? ?? '',
        authorRole: json['authorRole'] as String? ?? 'client',
        targetId: json['targetId'] as String? ?? '',
        targetRole: json['targetRole'] as String? ?? 'client',
        rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
        comment: json['comment'] as String? ?? '',
        createdAt: json['createdAt'] is Timestamp
            ? (json['createdAt'] as Timestamp).toDate()
            : DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookingId': bookingId,
        'authorId': authorId,
        'authorName': authorName,
        'authorRole': authorRole,
        'targetId': targetId,
        'targetRole': targetRole,
        'rating': rating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
