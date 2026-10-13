/// Роль партнёра в системе Explora.
enum PartnerRole {
  /// Гид пешеходных / эко маршрутов
  guide,

  /// Городской обзорный гид
  cityGuide,

  /// Водитель внедорожника
  suvDriver,

  /// Водитель автобуса (большие группы)
  busDriver,

  /// Водитель микроавтобуса (до 15 чел.)
  minibusDriver,

  /// Водитель минивена (комфорт до 7 чел.)
  minivanDriver,
}

/// Расширение для получения читаемого названия роли на русском.
extension PartnerRoleX on PartnerRole {
  String get displayName => switch (this) {
    PartnerRole.guide => 'Гид',
    PartnerRole.cityGuide => 'Городской гид',
    PartnerRole.suvDriver => 'Водитель внедорожника',
    PartnerRole.busDriver => 'Водитель автобуса',
    PartnerRole.minibusDriver => 'Водитель микроавтобуса',
    PartnerRole.minivanDriver => 'Водитель минивена',
  };

  bool get isDriver => switch (this) {
    PartnerRole.suvDriver ||
    PartnerRole.busDriver ||
    PartnerRole.minibusDriver ||
    PartnerRole.minivanDriver => true,
    _ => false,
  };

  bool get isGuide => !isDriver;

  /// guideType-совместимое значение для обратной совместимости.
  /// 'city' для городского гида, 'hiking' для всех остальных.
  String get guideType => this == PartnerRole.cityGuide ? 'city' : 'hiking';

  /// Класс автомобиля для [PartnerProfile.vehicleType] ('' для гидов).
  String get vehicleTypeCode => switch (this) {
    PartnerRole.suvDriver => 'suv',
    PartnerRole.busDriver => 'bus',
    PartnerRole.minibusDriver => 'minibus',
    PartnerRole.minivanDriver => 'minivan',
    _ => '',
  };
}

/// Единый профиль партнёра (водителя или гида).
///
/// Хранится в коллекции `partners/{uid}`.
/// Читается обоими приложениями — explora_app и explora_partners_app.
class PartnerProfile {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final PartnerRole role;

  // ── Публичные данные ───────────────────────────────────────────────────────
  final String? photoUrl;
  final double rating;
  final int reviewCount;
  final String level; // Bronze, Silver, Gold, Platinum
  final int priority;
  final bool isVerified;
  final bool isOnline;
  final String bio;
  final String description;
  final List<String> languages;

  // ── Guide-специфичные ─────────────────────────────────────────────────────
  final List<String> specializations;
  final int experience; // лет опыта
  final List<String> certifications;
  final double pricePerDay;
  final List<String> tourAreas;
  final int maxGroupSize;
  final List<String> galleryUrls; // Фотографии портфолио гида

  // ── Driver-специфичные ────────────────────────────────────────────────────
  final String vehicleModel;
  final String vehicleType; // suv | bus | minibus | minivan
  final String vehiclePlate; // Гос. номер автомобиля
  final int vehicleCapacity; // общее кол-во мест в авто (включая водителя)
  final double pricePerKm;
  final int dailyMileageLimit; // Лимит пробега водителя в день (default 300)
  final double overagePricePerKm; // Стоимость километра перепробега
  final double driverStayPerDay; // Суточные/командировочные водителя

  // ── Документы водителя ────────────────────────────────────────────────────
  final String? driverLicenseFrontUrl; // Лицевая сторона водительского удостоверения
  final String? driverLicenseBackUrl;  // Обратная сторона водительского удостоверения
  final DateTime? driverLicenseUpdatedAt; // Дата последней загрузки прав (обновление каждые 10 дней)
  final String? techPassportFrontUrl; // Лицевая сторона техпаспорта
  final String? techPassportBackUrl;  // Обратная сторона техпаспорта
  final String? faceControlUrl;       // Фото-контроль лица
  final DateTime? lastCheckInAt;      // Дата последнего check-in водителя (раз в 10 дней)
  final bool hasStarlink;             // Наличие Starlink
  final bool hasRentalGear;           // Снаряжение в аренду

  // ── Статусы верификации документов ───────────────────────────────────────
  final bool driverLicenseVerified;   // Права верифицированы администратором
  final bool techPassportVerified;    // Техпаспорт верифицирован
  final bool faceControlVerified;     // Фото-контроль лица подтверждён
  final bool vehicleAdded;            // Автомобиль добавлен в гараж
  final bool vehicleInspectionVerified; // Проверка кузова (осмотр) подтверждена
  final String? guideCertificateUrl;    // Фото сертификата гида
  final bool guideCertificateVerified;  // Сертификат подтверждён администратором
  final String? guideIdFrontUrl;        // Лицевая сторона удостоверения
  final String? guideIdBackUrl;         // Обратная сторона удостоверения
  final bool guideIdVerified;           // Удостоверение подтверждено
  final String? guideFaceControlUrl;    // Фото лица гида
  final bool guideFaceControlVerified;  // Лицо гида подтверждено
  final DateTime? guideLastCheckInAt;   // Дата последнего check-in гида (раз в 10 дней)

  // ── Системные ─────────────────────────────────────────────────────────────
  final String? fcmToken; // для push-уведомлений и будущих чатов
  final double balance; // Баланс партнера
  final String? savedCard; // Привязанная карта партнера для выплат

  const PartnerProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    this.photoUrl,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.level = 'Bronze',
    this.priority = 0,
    this.isVerified = false,
    this.isOnline = false,
    this.bio = '',
    this.description = '',
    this.languages = const [],
    this.specializations = const [],
    this.experience = 0,
    this.certifications = const [],
    this.pricePerDay = 0.0,
    this.vehicleModel = '',
    this.vehicleType = '',
    this.vehiclePlate = '',
    this.vehicleCapacity = 0,
    this.pricePerKm = 0.0,
    this.dailyMileageLimit = 300,
    this.overagePricePerKm = 300.0,
    this.driverStayPerDay = 15000.0,
    this.driverLicenseFrontUrl,
    this.driverLicenseBackUrl,
    this.driverLicenseUpdatedAt,
    this.techPassportFrontUrl,
    this.techPassportBackUrl,
    this.faceControlUrl,
    this.lastCheckInAt,
    this.hasStarlink = false,
    this.hasRentalGear = false,
    this.driverLicenseVerified = false,
    this.techPassportVerified = false,
    this.faceControlVerified = false,
    this.vehicleAdded = false,
    this.vehicleInspectionVerified = false,
    this.guideCertificateUrl,
    this.guideCertificateVerified = false,
    this.guideIdFrontUrl,
    this.guideIdBackUrl,
    this.guideIdVerified = false,
    this.guideFaceControlUrl,
    this.guideFaceControlVerified = false,
    this.guideLastCheckInAt,
    this.tourAreas = const [],
    this.maxGroupSize = 15,
    this.galleryUrls = const [],
    this.fcmToken,
    this.balance = 0.0,
    this.savedCard,
  });

  // ── Вычисляемые поля ──────────────────────────────────────────────────────

  /// «Ерлан А.»
  String get shortName {
    if (lastName.isEmpty) return firstName;
    return '$firstName ${lastName[0]}.';
  }

  /// «Ерлан Алиев»
  String get fullName => '$firstName $lastName'.trim();

  /// Совместимость с booking_screen (ранее driver.ownerName).
  String get ownerName => fullName;

  /// Совместимость с booking_screen (ранее driver.name).
  String get name => shortName;

  /// Раз в 10 дней и гиды, и водители обязаны пройти check-in (фото-контроль
  /// личности) заново — раньше это было одноразовой проверкой навсегда,
  /// теперь дата последнего check-in истекает по возрасту, как и права/техпаспорт.
  static const Duration checkInValidity = Duration(days: 10);

  bool get checkInDue {
    final lastAt = role.isDriver ? lastCheckInAt : guideLastCheckInAt;
    final verified = role.isDriver ? faceControlVerified : guideFaceControlVerified;
    if (!verified || lastAt == null) return true;
    return DateTime.now().difference(lastAt) >= checkInValidity;
  }

  // ── Serialization ─────────────────────────────────────────────────────────

  factory PartnerProfile.fromJson(Map<String, dynamic> json) {
    return PartnerProfile(
      id: json['id'] as String? ?? '',
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role:
          PartnerRole.values.asNameMap()[json['role'] as String?] ??
          PartnerRole.guide,
      photoUrl: json['photoUrl'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      level: json['level'] as String? ?? 'Bronze',
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      isVerified: json['isVerified'] as bool? ?? false,
      isOnline: json['isOnline'] as bool? ?? false,
      bio: json['bio'] as String? ?? '',
      description: json['description'] as String? ?? '',
      languages:
          (json['languages'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      specializations:
          (json['specializations'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      experience: (json['experience'] as num?)?.toInt() ?? 0,
      certifications:
          (json['certifications'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      galleryUrls:
          (json['galleryUrls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      pricePerDay: (json['pricePerDay'] as num?)?.toDouble() ?? 0.0,
      vehicleModel: json['vehicleModel'] as String? ?? '',
      vehicleType: json['vehicleType'] as String? ?? '',
      vehiclePlate: json['vehiclePlate'] as String? ?? '',
      vehicleCapacity: (json['vehicleCapacity'] as num?)?.toInt() ?? 0,
      pricePerKm: (json['pricePerKm'] as num?)?.toDouble() ?? 0.0,
      dailyMileageLimit: (json['dailyMileageLimit'] as num?)?.toInt() ?? 300,
      overagePricePerKm:
          (json['overagePricePerKm'] as num?)?.toDouble() ?? 300.0,
      driverStayPerDay:
          (json['driverStayPerDay'] as num?)?.toDouble() ?? 15000.0,
      driverLicenseFrontUrl: json['driverLicenseFrontUrl'] as String?,
      driverLicenseBackUrl: json['driverLicenseBackUrl'] as String?,
      driverLicenseUpdatedAt: json['driverLicenseUpdatedAt'] != null
          ? DateTime.tryParse(json['driverLicenseUpdatedAt'] as String)
          : null,
      techPassportFrontUrl: json['techPassportFrontUrl'] as String?,
      techPassportBackUrl: json['techPassportBackUrl'] as String?,
      faceControlUrl: json['faceControlUrl'] as String?,
      lastCheckInAt: json['lastCheckInAt'] != null
          ? DateTime.tryParse(json['lastCheckInAt'] as String)
          : null,
      hasStarlink: json['hasStarlink'] as bool? ?? false,
      hasRentalGear: json['hasRentalGear'] as bool? ?? false,
      driverLicenseVerified: json['driverLicenseVerified'] as bool? ?? false,
      techPassportVerified: json['techPassportVerified'] as bool? ?? false,
      faceControlVerified: json['faceControlVerified'] as bool? ?? false,
      vehicleAdded: json['vehicleAdded'] as bool? ?? false,
      vehicleInspectionVerified: json['vehicleInspectionVerified'] as bool? ?? false,
      guideCertificateUrl: json['guideCertificateUrl'] as String?,
      guideCertificateVerified: json['guideCertificateVerified'] as bool? ?? false,
      guideIdFrontUrl: json['guideIdFrontUrl'] as String?,
      guideIdBackUrl: json['guideIdBackUrl'] as String?,
      guideIdVerified: json['guideIdVerified'] as bool? ?? false,
      guideFaceControlUrl: json['guideFaceControlUrl'] as String?,
      guideFaceControlVerified: json['guideFaceControlVerified'] as bool? ?? false,
      guideLastCheckInAt: json['guideLastCheckInAt'] != null
          ? DateTime.tryParse(json['guideLastCheckInAt'] as String)
          : null,
      tourAreas:
          (json['tourAreas'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      maxGroupSize: (json['maxGroupSize'] as num?)?.toInt() ?? 15,
      fcmToken: json['fcmToken'] as String?,
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      savedCard: json['savedCard'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'role': role.name,
    'photoUrl': photoUrl,
    'rating': rating,
    'reviewCount': reviewCount,
    'level': level,
    'priority': priority,
    'isVerified': isVerified,
    'isOnline': isOnline,
    'bio': bio,
    'description': description,
    'languages': languages,
    'specializations': specializations,
    'experience': experience,
    'certifications': certifications,
    'pricePerDay': pricePerDay,
    'vehicleModel': vehicleModel,
    'vehicleType': vehicleType,
    'vehiclePlate': vehiclePlate,
    'vehicleCapacity': vehicleCapacity,
    'pricePerKm': pricePerKm,
    'dailyMileageLimit': dailyMileageLimit,
    'overagePricePerKm': overagePricePerKm,
    'driverStayPerDay': driverStayPerDay,
    'driverLicenseFrontUrl': driverLicenseFrontUrl,
    'driverLicenseBackUrl': driverLicenseBackUrl,
    'driverLicenseUpdatedAt': driverLicenseUpdatedAt?.toIso8601String(),
    'techPassportFrontUrl': techPassportFrontUrl,
    'techPassportBackUrl': techPassportBackUrl,
    'faceControlUrl': faceControlUrl,
    'lastCheckInAt': lastCheckInAt?.toIso8601String(),
    'hasStarlink': hasStarlink,
    'hasRentalGear': hasRentalGear,
    'driverLicenseVerified': driverLicenseVerified,
    'techPassportVerified': techPassportVerified,
    'faceControlVerified': faceControlVerified,
    'vehicleAdded': vehicleAdded,
    'vehicleInspectionVerified': vehicleInspectionVerified,
    'guideCertificateUrl': guideCertificateUrl,
    'guideCertificateVerified': guideCertificateVerified,
    'guideIdFrontUrl': guideIdFrontUrl,
    'guideIdBackUrl': guideIdBackUrl,
    'guideIdVerified': guideIdVerified,
    'guideFaceControlUrl': guideFaceControlUrl,
    'guideFaceControlVerified': guideFaceControlVerified,
    'guideLastCheckInAt': guideLastCheckInAt?.toIso8601String(),
    'tourAreas': tourAreas,
    'maxGroupSize': maxGroupSize,
    'fcmToken': fcmToken,
    'balance': balance,
    'savedCard': savedCard,
  };

  PartnerProfile copyWith({
    String? id,
    String? firstName,
    String? lastName,
    String? email,
    PartnerRole? role,
    String? photoUrl,
    double? rating,
    int? reviewCount,
    String? level,
    int? priority,
    bool? isVerified,
    bool? isOnline,
    String? bio,
    String? description,
    List<String>? languages,
    List<String>? specializations,
    int? experience,
    List<String>? certifications,
    double? pricePerDay,
    String? vehicleModel,
    String? vehicleType,
    String? vehiclePlate,
    int? vehicleCapacity,
    double? pricePerKm,
    int? dailyMileageLimit,
    double? overagePricePerKm,
    double? driverStayPerDay,
    String? driverLicenseFrontUrl,
    String? driverLicenseBackUrl,
    DateTime? driverLicenseUpdatedAt,
    String? techPassportFrontUrl,
    String? techPassportBackUrl,
    String? faceControlUrl,
    DateTime? lastCheckInAt,
    bool? hasStarlink,
    bool? hasRentalGear,
    bool? driverLicenseVerified,
    bool? techPassportVerified,
    bool? faceControlVerified,
    bool? vehicleAdded,
    bool? vehicleInspectionVerified,
    String? guideCertificateUrl,
    bool? guideCertificateVerified,
    String? guideIdFrontUrl,
    String? guideIdBackUrl,
    bool? guideIdVerified,
    String? guideFaceControlUrl,
    bool? guideFaceControlVerified,
    DateTime? guideLastCheckInAt,
    List<String>? tourAreas,
    int? maxGroupSize,
    String? fcmToken,
    double? balance,
    String? savedCard,
  }) {
    return PartnerProfile(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      role: role ?? this.role,
      photoUrl: photoUrl ?? this.photoUrl,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      level: level ?? this.level,
      priority: priority ?? this.priority,
      isVerified: isVerified ?? this.isVerified,
      isOnline: isOnline ?? this.isOnline,
      bio: bio ?? this.bio,
      description: description ?? this.description,
      languages: languages ?? this.languages,
      specializations: specializations ?? this.specializations,
      experience: experience ?? this.experience,
      certifications: certifications ?? this.certifications,
      pricePerDay: pricePerDay ?? this.pricePerDay,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleType: vehicleType ?? this.vehicleType,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      vehicleCapacity: vehicleCapacity ?? this.vehicleCapacity,
      pricePerKm: pricePerKm ?? this.pricePerKm,
      dailyMileageLimit: dailyMileageLimit ?? this.dailyMileageLimit,
      overagePricePerKm: overagePricePerKm ?? this.overagePricePerKm,
      driverStayPerDay: driverStayPerDay ?? this.driverStayPerDay,
      driverLicenseFrontUrl: driverLicenseFrontUrl ?? this.driverLicenseFrontUrl,
      driverLicenseBackUrl: driverLicenseBackUrl ?? this.driverLicenseBackUrl,
      driverLicenseUpdatedAt: driverLicenseUpdatedAt ?? this.driverLicenseUpdatedAt,
      techPassportFrontUrl: techPassportFrontUrl ?? this.techPassportFrontUrl,
      techPassportBackUrl: techPassportBackUrl ?? this.techPassportBackUrl,
      faceControlUrl: faceControlUrl ?? this.faceControlUrl,
      lastCheckInAt: lastCheckInAt ?? this.lastCheckInAt,
      hasStarlink: hasStarlink ?? this.hasStarlink,
      hasRentalGear: hasRentalGear ?? this.hasRentalGear,
      driverLicenseVerified: driverLicenseVerified ?? this.driverLicenseVerified,
      techPassportVerified: techPassportVerified ?? this.techPassportVerified,
      faceControlVerified: faceControlVerified ?? this.faceControlVerified,
      vehicleAdded: vehicleAdded ?? this.vehicleAdded,
      vehicleInspectionVerified: vehicleInspectionVerified ?? this.vehicleInspectionVerified,
      guideCertificateUrl: guideCertificateUrl ?? this.guideCertificateUrl,
      guideCertificateVerified: guideCertificateVerified ?? this.guideCertificateVerified,
      guideIdFrontUrl: guideIdFrontUrl ?? this.guideIdFrontUrl,
      guideIdBackUrl: guideIdBackUrl ?? this.guideIdBackUrl,
      guideIdVerified: guideIdVerified ?? this.guideIdVerified,
      guideFaceControlUrl: guideFaceControlUrl ?? this.guideFaceControlUrl,
      guideFaceControlVerified: guideFaceControlVerified ?? this.guideFaceControlVerified,
      guideLastCheckInAt: guideLastCheckInAt ?? this.guideLastCheckInAt,
      tourAreas: tourAreas ?? this.tourAreas,
      maxGroupSize: maxGroupSize ?? this.maxGroupSize,
      fcmToken: fcmToken ?? this.fcmToken,
      balance: balance ?? this.balance,
      savedCard: savedCard ?? this.savedCard,
    );
  }
}
