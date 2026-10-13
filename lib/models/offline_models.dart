// Models for MESH offline communication (Bridgefy BLE mesh)

enum OfflineMessageType {
  /// PTT voice chunk (partial or final audio segment)
  voiceChunk,
  /// Plain text message from a peer
  text,
  /// SOS beacon broadcast (location ping with active/inactive flag)
  beacon,
  /// Lightweight presence heartbeat — updates the peer list
  presence,
  /// Legacy/unknown type (ignored)
  unknown,
}

/// A message received from the MESH network.
class OfflineMessage {
  final String id;
  final OfflineMessageType type;
  final String tripId;
  final String userId;
  final String userName;
  final DateTime timestamp;

  /// Whether this message was sent by the current device.
  final bool isMine;

  // ── Text message fields ──────────────────────────────────────────────────
  /// Plain text content of the message.
  final String? text;

  // ── Voice chunk fields ───────────────────────────────────────────────────
  /// The index of this chunk within the voice message (0-based).
  final int? chunkIndex;
  /// Total number of chunks in this voice message.
  final int? totalChunks;
  /// Unique ID for the entire voice memo (shared by all its chunks).
  final String? voiceMessageId;
  /// Raw compressed audio data for this chunk.
  final List<int>? audioChunk;

  // ── Beacon / Presence fields ─────────────────────────────────────────────
  final double? lat;
  final double? lng;
  /// Whether the SOS beacon is active (true) or deactivated (false).
  final bool? beaconActive;

  const OfflineMessage({
    required this.id,
    required this.type,
    required this.tripId,
    required this.userId,
    required this.userName,
    required this.timestamp,
    this.isMine = false,
    this.text,
    this.chunkIndex,
    this.totalChunks,
    this.voiceMessageId,
    this.audioChunk,
    this.lat,
    this.lng,
    this.beaconActive,
  });

  factory OfflineMessage.fromJson(
    Map<String, dynamic> json, {
    required String currentUserId,
    String? overrideId,
  }) {
    final typeStr = json['type'] as String? ?? '';
    final type = _typeFromString(typeStr);
    final userId = json['userId'] as String? ?? '';

    // Audio chunk: JSON decodes numbers as 'num', not 'int' — use map.
    List<int>? audioChunk;
    final rawChunk = json['audioChunk'];
    if (rawChunk is List) {
      audioChunk = rawChunk.map((e) => (e as num).toInt()).toList();
    }

    return OfflineMessage(
      id: overrideId ?? '$userId-${json['ts'] ?? 0}',
      type: type,
      tripId: json['tripId'] as String? ?? '',
      userId: userId,
      userName: json['userName'] as String? ?? 'Участник',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['ts'] as num?)?.toInt() ?? 0,
      ),
      isMine: userId == currentUserId,
      text: json['text'] as String?,
      chunkIndex:    (json['chunkIndex'] as num?)?.toInt(),
      totalChunks:   (json['totalChunks'] as num?)?.toInt(),
      voiceMessageId: json['voiceMessageId'] as String?,
      audioChunk:    audioChunk,
      lat:  (json['lat'] as num?)?.toDouble(),
      lng:  (json['lng'] as num?)?.toDouble(),
      beaconActive: json['beaconActive'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': _typeToString(type),
    'tripId': tripId,
    'userId': userId,
    'userName': userName,
    'ts': timestamp.millisecondsSinceEpoch,
    if (text != null)           'text': text,
    if (chunkIndex != null)     'chunkIndex': chunkIndex,
    if (totalChunks != null)    'totalChunks': totalChunks,
    if (voiceMessageId != null) 'voiceMessageId': voiceMessageId,
    if (audioChunk != null)     'audioChunk': audioChunk,
    if (lat != null)            'lat': lat,
    if (lng != null)            'lng': lng,
    if (beaconActive != null)   'beaconActive': beaconActive,
  };

  static OfflineMessageType _typeFromString(String s) {
    switch (s) {
      case 'voice_chunk': return OfflineMessageType.voiceChunk;
      case 'text':        return OfflineMessageType.text;
      case 'beacon':      return OfflineMessageType.beacon;
      case 'presence':    return OfflineMessageType.presence;
      default:            return OfflineMessageType.unknown;
    }
  }

  static String _typeToString(OfflineMessageType t) {
    switch (t) {
      case OfflineMessageType.voiceChunk: return 'voice_chunk';
      case OfflineMessageType.text:       return 'text';
      case OfflineMessageType.beacon:     return 'beacon';
      case OfflineMessageType.presence:   return 'presence';
      default:                            return 'unknown';
    }
  }
}

/// A nearby peer visible in the MESH session.
class OfflinePeer {
  final String peerId;
  final String? userId;
  final String? userName;
  final double? lat;
  final double? lng;
  final DateTime lastSeen;
  final bool hasLocation;
  /// Whether this peer has an active SOS beacon.
  final bool sosBroadcasting;

  const OfflinePeer({
    required this.peerId,
    this.userId,
    this.userName,
    this.lat,
    this.lng,
    required this.lastSeen,
    this.hasLocation = false,
    this.sosBroadcasting = false,
  });

  OfflinePeer copyWith({
    String? userId,
    String? userName,
    double? lat,
    double? lng,
    DateTime? lastSeen,
    bool? hasLocation,
    bool? sosBroadcasting,
  }) => OfflinePeer(
    peerId:          peerId,
    userId:          userId          ?? this.userId,
    userName:        userName        ?? this.userName,
    lat:             lat             ?? this.lat,
    lng:             lng             ?? this.lng,
    lastSeen:        lastSeen        ?? this.lastSeen,
    hasLocation:     hasLocation     ?? this.hasLocation,
    sosBroadcasting: sosBroadcasting ?? this.sosBroadcasting,
  );
}

/// A text message in the MESH chat history.
class MeshTextMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime receivedAt;
  final bool isMine;

  const MeshTextMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.receivedAt,
    this.isMine = false,
  });
}
