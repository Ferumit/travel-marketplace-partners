import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/booking_models.dart';
import '../repository/firestore_repository.dart';
import '../models/partner_models.dart';

import 'package:firebase_auth/firebase_auth.dart';

// Provider for FirestoreRepository instance
final firestoreRepositoryProvider = Provider<FirestoreRepository>((ref) {
  return FirestoreRepository.instance;
});

// Provider for the currently authenticated user UID
final authUserProvider = StreamProvider<String?>((ref) {
  return FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);
});

// Provider for the partner profile
final profileProvider = StreamProvider<PartnerProfile?>((ref) {
  final uid = ref.watch(authUserProvider).value;
  if (uid == null) {
    return Stream.value(null);
  }
  return FirestoreRepository.instance.streamPartner(uid);
});

// Provider for the active trip assigned to the current user
final activeTripProvider = StreamProvider<ActiveTrip?>((ref) {
  final uid = ref.watch(authUserProvider).value;
  if (uid == null) {
    return Stream.value(null);
  }
  return FirestoreRepository.instance.streamActiveTripsByPartner(uid).map((trips) {
    return trips.where((t) => 
      (t.driverId == uid ? t.driverAccepted : true) &&
      (t.guideId == uid ? t.guideAccepted : true)
    ).firstOrNull;
  });
});

// Provider for the booking corresponding to the active trip
final activeBookingProvider = FutureProvider<Booking?>((ref) async {
  final trip = ref.watch(activeTripProvider).value;
  if (trip == null) return null;
  return FirestoreRepository.instance.getBookingById(trip.bookingId);
});

// Provider for all trips assigned to the current user
final allTripsProvider = StreamProvider<List<ActiveTrip>>((ref) {
  final uid = ref.watch(authUserProvider).value;
  if (uid == null) {
    return Stream.value([]);
  }
  return FirestoreRepository.instance.streamActiveTripsByPartner(uid);
});
