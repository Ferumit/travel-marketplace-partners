import 'package:cloud_firestore/cloud_firestore.dart';

/// Модель SOS-сигнала, сохраняемого в Firebase Firestore (коллекция `sos_signals`).
/// Используется в explora_partners_app для relay-записей.
class SosSignal {
  final String signalId;
  final String senderId;
  final String senderName;
  final String? tripId;
  final double? lat;
  final double? lng;
  final DateTime sentAt;
  final DateTime uploadedAt;
  final String uploadedBy;
  final bool isRelay;
  final String status;

  const SosSignal({
    required this.signalId,
    required this.senderId,
    required this.senderName,
    this.tripId,
    this.lat,
    this.lng,
    required this.sentAt,
    required this.uploadedAt,
    required this.uploadedBy,
    this.isRelay = false,
    this.status = 'active',
  });

  factory SosSignal.fromJson(Map<String, dynamic> json) {
    DateTime parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.parse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return DateTime.now();
    }

    return SosSignal(
      signalId: json['signalId'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? 'Участник',
      tripId: json['tripId'] as String?,
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      sentAt: parseTimestamp(json['sentAt']),
      uploadedAt: parseTimestamp(json['uploadedAt']),
      uploadedBy: json['uploadedBy'] as String? ?? '',
      isRelay: json['isRelay'] as bool? ?? false,
      status: json['status'] as String? ?? 'active',
    );
  }

  Map<String, dynamic> toJson() => {
        'signalId': signalId,
        'senderId': senderId,
        'senderName': senderName,
        if (tripId != null) 'tripId': tripId,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'sentAt': Timestamp.fromDate(sentAt),
        'uploadedAt': Timestamp.fromDate(uploadedAt),
        'uploadedBy': uploadedBy,
        'isRelay': isRelay,
        'status': status,
      };
}
