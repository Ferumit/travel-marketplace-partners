class OfflineAction {
  final String id;
  final String type; // 'startTrip', 'finishTrip', 'checkIn'
  final Map<String, dynamic> payload;
  final int timestamp;

  OfflineAction({
    required this.id,
    required this.type,
    required this.payload,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'payload': payload,
      'timestamp': timestamp,
    };
  }

  factory OfflineAction.fromMap(Map<dynamic, dynamic> map) {
    return OfflineAction(
      id: map['id'] as String,
      type: map['type'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      timestamp: map['timestamp'] as int,
    );
  }
}
