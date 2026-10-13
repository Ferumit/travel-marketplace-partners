//Booking data models

// Status flow: pending -> confirmed -> inProgress -> completed / cancelled
// pending        = booked, waiting for scheduled date
// counterOffered = a partner proposed a different price; waiting on the
//                  passenger to accept/decline in the client app
// confirmed      = date arrived, driver/crew on the way
// inProgress     = route physically in progress
// completed      = route finished
enum BookingStatus { pending, counterOffered, confirmed, inProgress, completed, cancelled }

class MeetingPoint {
  final String address;
  final double latitude;
  final double longitude;
  final String time;
  final bool isConfirmed;
  final Map<String, bool> checkIns;

  const MeetingPoint({
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.time,
    required this.isConfirmed,
    this.checkIns = const {},
  });

  factory MeetingPoint.fromJson(Map<String, dynamic> json) {
    return MeetingPoint(
      address: json['address'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      time: json['time'] as String? ?? '',
      isConfirmed: json['isConfirmed'] as bool? ?? false,
      checkIns: json['checkIns'] != null
          ? Map<String, bool>.from(json['checkIns'] as Map)
          : {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'time': time,
      'isConfirmed': isConfirmed,
      'checkIns': checkIns,
    };
  }
}

class Booking {
  final String id;
  final String userId;
  final String routeId;
  final String routeTitle;
  final String? guideId;
  final String? guideName;
  final String? driverId;
  final String? driverName;
  final String? partnerId;
  final double? driverEarning;
  final double? guideEarning;
  final String startDate;
  final String endDate;
  final String createdAt;
  final int participants;
  final double totalPrice;
  final BookingStatus status;
  final List<MeetingPoint> waypoints;
  final bool insuranceIncluded;
  final String? phoneNumber;
  final List<(double, double)>? customRouteCoordinates;
  final bool isCustomRoute;

  // ── Живая лента заказов: цена, торг, контекст поездки ────────────────────
  // Снимок рейтинга и комментарий заполняются клиентским приложением на
  // момент создания заказа — до тех пор, пока explora_app не пишет их,
  // остаются null, и карточка заказа корректно скрывает эти поля.
  final double? passengerRating;
  final String? comments;
  // Цена, которую партнёр предложил взамен totalPrice (см. BookingStatus.counterOffered).
  final double? counterOfferPrice;
  // uid партнёра, приславшего counterOfferPrice.
  final String? counterOfferBy;

  const Booking({
    required this.id,
    required this.userId,
    required this.routeId,
    required this.routeTitle,
    this.guideId,
    this.guideName,
    this.driverId,
    this.driverName,
    this.partnerId,
    this.driverEarning,
    this.guideEarning,
    required this.startDate,
    required this.endDate,
    String? createdAt,
    required this.participants,
    required this.totalPrice,
    required this.status,
    this.waypoints = const [],
    required this.insuranceIncluded,
    this.phoneNumber,
    this.customRouteCoordinates,
    this.isCustomRoute = false,
    this.passengerRating,
    this.comments,
    this.counterOfferPrice,
    this.counterOfferBy,
  }) : createdAt = createdAt ?? startDate;

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      routeId: json['routeId'] as String? ?? '',
      routeTitle: json['routeTitle'] as String? ?? '',
      guideId: json['guideId'] as String?,
      guideName: json['guideName'] as String?,
      driverId: json['driverId'] as String?,
      driverName: json['driverName'] as String?,
      partnerId: json['partnerId'] as String?,
      driverEarning: (json['driverEarning'] as num?)?.toDouble(),
      guideEarning: (json['guideEarning'] as num?)?.toDouble(),
      startDate: json['startDate'] as String? ?? '',
      endDate: json['endDate'] as String? ?? '',
      createdAt: json['createdAt'] as String?,
      participants: (json['participants'] as num?)?.toInt() ?? 1,
      totalPrice: (json['totalPrice'] as num?)?.toDouble() ?? 0.0,
      status:
          BookingStatus.values.asNameMap()[json['status'] as String?] ??
          BookingStatus.pending,
      waypoints:
          (json['waypoints'] as List<dynamic>?)
              ?.map((e) => MeetingPoint.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [
            if (json['meetingPoint'] != null)
              MeetingPoint.fromJson((json['meetingPoint'] as Map).cast()),
            if (json['returnLocation'] != null)
              MeetingPoint.fromJson((json['returnLocation'] as Map).cast()),
          ],
      insuranceIncluded: json['insuranceIncluded'] as bool? ?? false,
      phoneNumber: json['phoneNumber'] as String?,
      customRouteCoordinates: (json['customRouteCoordinates'] as List<dynamic>?)
          ?.map(
            (e) => (
              (e['lat'] as num?)?.toDouble() ?? 0.0,
              (e['lng'] as num?)?.toDouble() ?? 0.0,
            ),
          )
          .toList(),
      isCustomRoute: json['isCustomRoute'] as bool? ?? false,
      passengerRating: (json['passengerRating'] as num?)?.toDouble(),
      comments: json['comments'] as String?,
      counterOfferPrice: (json['counterOfferPrice'] as num?)?.toDouble(),
      counterOfferBy: json['counterOfferBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'routeId': routeId,
      'routeTitle': routeTitle,
      'guideId': guideId,
      'guideName': guideName,
      'driverId': driverId,
      'driverName': driverName,
      'partnerId': partnerId,
      'driverEarning': driverEarning,
      'guideEarning': guideEarning,
      'startDate': startDate,
      'endDate': endDate,
      'createdAt': createdAt,
      'participants': participants,
      'totalPrice': totalPrice,
      'status': status.name,
      'waypoints': waypoints.map((e) => e.toJson()).toList(),
      'insuranceIncluded': insuranceIncluded,
      'phoneNumber': phoneNumber,
      'customRouteCoordinates': customRouteCoordinates
          ?.map((e) => {'lat': e.$1, 'lng': e.$2})
          .toList(),
      'isCustomRoute': isCustomRoute,
      'passengerRating': passengerRating,
      'comments': comments,
      'counterOfferPrice': counterOfferPrice,
      'counterOfferBy': counterOfferBy,
    };
  }
}

/// Данные об одном клиенте-компаньоне, добавленном к маршруту.
class CompanionInfo {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final String addedAt;
  final bool ready;

  const CompanionInfo({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    required this.addedAt,
    this.ready = false,
  });

  factory CompanionInfo.fromJson(Map<String, dynamic> json) {
    return CompanionInfo(
      uid: json['uid'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
      addedAt: json['addedAt'] as String? ?? '',
      ready: json['ready'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'addedAt': addedAt,
    'ready': ready,
  };

  CompanionInfo copyWith({bool? ready}) => CompanionInfo(
    uid: uid,
    displayName: displayName,
    photoUrl: photoUrl,
    addedAt: addedAt,
    ready: ready ?? this.ready,
  );
}

enum TripStatus {
  scheduled('scheduled'),
  waiting('waiting'),
  inProgress('in_progress'),
  completed('completed'),
  cancelled('cancelled');

  final String value;
  const TripStatus(this.value);

  static TripStatus fromString(String? val) {
    return TripStatus.values.firstWhere((e) => e.value == val, orElse: () => TripStatus.waiting);
  }
}

class ActiveTrip {
  final String id;
  final String userId;
  final String? driverId;
  final String? guideId;
  final String? partnerId;
  final String bookingId;
  // 'scheduled' | 'waiting' | 'in_progress' | 'completed' | 'cancelled'
  final TripStatus status;
  final (double, double)? driverLocation;
  final (double, double)? guideLocation;
  final (double, double)? clientLocation;
  final List<(double, double)> routeGeometry;
  final List<MeetingPoint> waypoints;
  final String? estimatedArrivalTime;
  final String createdAt;
  final String? customName;
  // Proximity readiness flags (all must be true to start route)
  final bool driverReady;
  final bool guideReady;
  final bool clientReady;
  // Whether the assigned driver has explicitly accepted this trip
  final bool driverAccepted;
  // Whether the assigned guide has explicitly accepted this trip
  final bool guideAccepted;
  // Two-step completion: driver requests, client confirms
  final bool completionRequested;
  final bool driverCompletionRequested;
  final bool guideCompletionRequested;
  final List<String> declinedByDrivers;
  // Hierarchical waypoint check-ins are now embedded inside MeetingPoint
  final int currentWaypointIndex;

  // ── Companion clients ────────────────────────────────────────────────
  // participantIds = [userId, ...companions.map(c => c.uid)]
  // Используется для Firestore arrayContains запросов
  final List<String> participantIds;
  final List<CompanionInfo> companions;
  // { uid : {lat: double, lng: double} }
  final Map<String, Map<String, double>> companionLocations;

  const ActiveTrip({
    required this.id,
    required this.userId,
    this.driverId,
    this.guideId,
    this.partnerId,
    required this.bookingId,
    required this.status,
    this.driverLocation,
    this.guideLocation,
    this.clientLocation,
    required this.routeGeometry,
    required this.waypoints,
    this.estimatedArrivalTime,
    String? createdAt,
    this.customName,
    this.driverReady = false,
    this.guideReady = false,
    this.clientReady = false,
    this.driverAccepted = false,
    this.guideAccepted = false,
    this.completionRequested = false,
    this.driverCompletionRequested = false,
    this.guideCompletionRequested = false,
    this.declinedByDrivers = const [],
    this.currentWaypointIndex = 0,
    List<String>? participantIds,
    this.companions = const [],
    this.companionLocations = const {},
  }) : createdAt = createdAt ?? '',
       participantIds = participantIds ?? const <String>[];

  factory ActiveTrip.fromJson(Map<String, dynamic> json) {
    return ActiveTrip(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      driverId: json['driverId'] as String?,
      guideId: json['guideId'] as String?,
      partnerId: json['partnerId'] as String?,
      bookingId: json['bookingId'] as String? ?? '',
      status: TripStatus.fromString(json['status'] as String?),
      driverLocation: json['driverLocation'] != null
          ? (
              (json['driverLocation']['lat'] as num?)?.toDouble() ?? 0.0,
              (json['driverLocation']['lng'] as num?)?.toDouble() ?? 0.0,
            )
          : null,
      guideLocation: json['guideLocation'] != null
          ? (
              (json['guideLocation']['lat'] as num?)?.toDouble() ?? 0.0,
              (json['guideLocation']['lng'] as num?)?.toDouble() ?? 0.0,
            )
          : null,
      clientLocation: json['clientLocation'] != null
          ? (
              (json['clientLocation']['lat'] as num?)?.toDouble() ?? 0.0,
              (json['clientLocation']['lng'] as num?)?.toDouble() ?? 0.0,
            )
          : null,
      routeGeometry:
          (json['routeGeometry'] as List<dynamic>?)
              ?.map(
                (e) => (
                  (e['lat'] as num?)?.toDouble() ?? 0.0,
                  (e['lng'] as num?)?.toDouble() ?? 0.0,
                ),
              )
              .toList() ??
          [],
      waypoints:
          (json['waypoints'] as List<dynamic>?)
              ?.map((e) => MeetingPoint.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      estimatedArrivalTime: json['estimatedArrivalTime'] as String?,
      createdAt: json['createdAt'] as String?,
      customName: json['customName'] as String?,
      driverReady: json['driverReady'] as bool? ?? false,
      guideReady: json['guideReady'] as bool? ?? false,
      clientReady: json['clientReady'] as bool? ?? false,
      driverAccepted: json['driverAccepted'] as bool? ?? false,
      guideAccepted: json['guideAccepted'] as bool? ?? false,
      completionRequested: json['completionRequested'] as bool? ?? false,
      driverCompletionRequested: json['driverCompletionRequested'] as bool? ?? false,
      guideCompletionRequested: json['guideCompletionRequested'] as bool? ?? false,
      declinedByDrivers: (json['declinedByDrivers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      currentWaypointIndex: (json['currentWaypointIndex'] as num?)?.toInt() ?? 0,
      participantIds: (json['participantIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      companions: (json['companions'] as List<dynamic>?)
              ?.map((e) => CompanionInfo.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      companionLocations: (json['companionLocations'] as Map<String, dynamic>?)
              ?.map((uid, val) {
                final m = val as Map<String, dynamic>;
                return MapEntry(uid, {
                  'lat': (m['lat'] as num?)?.toDouble() ?? 0.0,
                  'lng': (m['lng'] as num?)?.toDouble() ?? 0.0,
                });
              }) ??
          {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'driverId': driverId,
      'guideId': guideId,
      'partnerId': partnerId,
      'bookingId': bookingId,
      'status': status.value,
      'driverLocation': driverLocation != null
          ? {'lat': driverLocation!.$1, 'lng': driverLocation!.$2}
          : null,
      'guideLocation': guideLocation != null
          ? {'lat': guideLocation!.$1, 'lng': guideLocation!.$2}
          : null,
      'clientLocation': clientLocation != null
          ? {'lat': clientLocation!.$1, 'lng': clientLocation!.$2}
          : null,
      'routeGeometry': routeGeometry
          .map((e) => {'lat': e.$1, 'lng': e.$2})
          .toList(),
      'waypoints': waypoints.map((e) => e.toJson()).toList(),
      'estimatedArrivalTime': estimatedArrivalTime,
      'createdAt': createdAt,
      'customName': customName,
      'driverReady': driverReady,
      'guideReady': guideReady,
      'clientReady': clientReady,
      'driverAccepted': driverAccepted,
      'guideAccepted': guideAccepted,
      'completionRequested': completionRequested,
      'driverCompletionRequested': driverCompletionRequested,
      'guideCompletionRequested': guideCompletionRequested,
      'declinedByDrivers': declinedByDrivers,
      'currentWaypointIndex': currentWaypointIndex,
      'participantIds': participantIds,
      'companions': companions.map((c) => c.toJson()).toList(),
      'companionLocations': companionLocations,
    };
  }
}
