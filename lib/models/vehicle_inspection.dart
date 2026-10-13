import 'package:cloud_firestore/cloud_firestore.dart';

/// Статус ежедневного отчёта об осмотре автомобиля.
enum InspectionStatus { pending, approved, rejected }

extension InspectionStatusX on InspectionStatus {
  String get label => switch (this) {
        InspectionStatus.pending => 'На рассмотрении',
        InspectionStatus.approved => 'Одобрен',
        InspectionStatus.rejected => 'Отклонён',
      };
  String get emoji => switch (this) {
        InspectionStatus.pending => '⏳',
        InspectionStatus.approved => '✅',
        InspectionStatus.rejected => '❌',
      };
}

/// Результат одной стороны осмотра.
class SideInspection {
  final String? photoUrl;
  final Map<String, bool> damageFlags;

  const SideInspection({this.photoUrl, required this.damageFlags});

  factory SideInspection.fromJson(Map<String, dynamic> json) => SideInspection(
        photoUrl: json['photoUrl'] as String?,
        damageFlags: (json['damageFlags'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as bool)) ??
            {},
      );

  Map<String, dynamic> toJson() => {
        'photoUrl': photoUrl,
        'damageFlags': damageFlags,
      };

  bool get hasDamage => damageFlags.values.any((v) => v);
}

/// Ежедневный отчёт водителя об осмотре кузова.
/// Хранится в Firestore: `vehicle_inspections/{id}`
class VehicleInspection {
  final String id;
  final String driverId;
  final String driverName;
  final String vehicleModel;
  final String vehiclePlate;
  final String date; // "2026-03-19"
  final InspectionStatus status;
  final String? rejectionReason;
  final Map<String, SideInspection> sides; // key = "front"|"right"|"back"|"left"|"roof"
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  const VehicleInspection({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.vehicleModel,
    required this.vehiclePlate,
    required this.date,
    required this.status,
    this.rejectionReason,
    required this.sides,
    required this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
  });

  bool get hasDamage => sides.values.any((s) => s.hasDamage);
  int get photoCount => sides.values.where((s) => s.photoUrl != null).length;

  factory VehicleInspection.fromJson(Map<String, dynamic> json) {
    final sidesRaw = json['sides'] as Map<String, dynamic>? ?? {};
    return VehicleInspection(
      id: json['id'] as String? ?? '',
      driverId: json['driverId'] as String? ?? '',
      driverName: json['driverName'] as String? ?? '',
      vehicleModel: json['vehicleModel'] as String? ?? '',
      vehiclePlate: json['vehiclePlate'] as String? ?? '',
      date: json['date'] as String? ?? '',
      status: InspectionStatus.values.asNameMap()[json['status'] as String?] ??
          InspectionStatus.pending,
      rejectionReason: json['rejectionReason'] as String?,
      sides: sidesRaw.map(
        (k, v) => MapEntry(k, SideInspection.fromJson(v as Map<String, dynamic>)),
      ),
      submittedAt: (json['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reviewedAt: (json['reviewedAt'] as Timestamp?)?.toDate(),
      reviewedBy: json['reviewedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'driverId': driverId,
        'driverName': driverName,
        'vehicleModel': vehicleModel,
        'vehiclePlate': vehiclePlate,
        'date': date,
        'status': status.name,
        'rejectionReason': rejectionReason,
        'sides': sides.map((k, v) => MapEntry(k, v.toJson())),
        'submittedAt': Timestamp.fromDate(submittedAt),
        'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
        'reviewedBy': reviewedBy,
      };
}
