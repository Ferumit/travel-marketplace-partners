enum Difficulty { easy, moderate, hard, expert }

enum TourFormat { group, private }

enum TransportType { fourByFour, minivan4x4, minibus, bus, none }

//Tour data models
/// Returns the standard passenger capacity for each transport type.
extension TransportTypeCapacity on TransportType {
  int get capacity {
    switch (this) {
      case TransportType.fourByFour:
        return 4; // Including driver
      case TransportType.minivan4x4:
        return 4; // 1 driver + up to 3 passengers (or 2 pax + 1 guide)
      case TransportType.minibus:
        return 15; // Based on UI: "Группы до 15 чел."
      case TransportType.bus:
        return 40;
      case TransportType.none:
        return 1;
    }
  }
}

class Route {
  final String id;
  final String title;
  final String description;
  final String region;
  final int duration; // in days
  final double price;
  final Difficulty difficulty;
  final TourFormat format;
  final TransportType transport;
  final String season;
  final String guideLanguage;
  final double rating;
  final int reviewCount;
  final String imageUrl;
  final double latitude;
  final double longitude;
  final List<String> availableDates;
  final int maxGroupSize;
  final List<String> highlights;
  final List<String> included;
  final List<String> excluded;
  final bool isShared;
  final String category;

  const Route({
    required this.id,
    required this.title,
    required this.description,
    required this.region,
    required this.duration,
    required this.price,
    required this.difficulty,
    required this.format,
    required this.transport,
    required this.season,
    required this.guideLanguage,
    required this.rating,
    required this.reviewCount,
    required this.imageUrl,
    required this.latitude,
    required this.longitude,
    required this.availableDates,
    required this.maxGroupSize,
    required this.highlights,
    required this.included,
    required this.excluded,
    this.isShared = false,
    this.category = 'Общая',
  });

  factory Route.fromJson(Map<String, dynamic> json) {
    return Route(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      region: json['region'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      difficulty:
          Difficulty.values.asNameMap()[json['difficulty'] as String?] ??
          Difficulty.moderate,
      format:
          TourFormat.values.asNameMap()[json['format'] as String?] ??
          TourFormat.group,
      transport:
          TransportType.values.asNameMap()[json['transport'] as String?] ??
          TransportType.minibus,
      season: json['season'] as String? ?? '',
      guideLanguage: json['guideLanguage'] as String? ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      imageUrl: json['imageUrl'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      availableDates:
          (json['availableDates'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      maxGroupSize: (json['maxGroupSize'] as num?)?.toInt() ?? 1,
      highlights:
          (json['highlights'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      included:
          (json['included'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      excluded:
          (json['excluded'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      isShared: json['isShared'] as bool? ?? false,
      category: json['category'] as String? ?? 'Общая',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'region': region,
      'duration': duration,
      'price': price,
      'difficulty': difficulty.name,
      'format': format.name,
      'transport': transport.name,
      'season': season,
      'guideLanguage': guideLanguage,
      'rating': rating,
      'reviewCount': reviewCount,
      'imageUrl': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
      'availableDates': availableDates,
      'maxGroupSize': maxGroupSize,
      'highlights': highlights,
      'included': included,
      'excluded': excluded,
      'isShared': isShared,
      'category': category,
    };
  }
}

class TouristZone {
  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final double latitude;
  final double longitude;
  final List<String> popularRoutes;
  final String bestSeason;

  const TouristZone({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.latitude,
    required this.longitude,
    required this.popularRoutes,
    required this.bestSeason,
  });

  factory TouristZone.fromJson(Map<String, dynamic> json) {
    return TouristZone(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      popularRoutes:
          (json['popularRoutes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      bestSeason: json['bestSeason'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
      'popularRoutes': popularRoutes,
      'bestSeason': bestSeason,
    };
  }
}
