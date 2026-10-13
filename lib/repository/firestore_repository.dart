import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../models/partner_models.dart';
import '../models/booking_models.dart';
import '../models/vehicle_inspection.dart';
import '../models/review_models.dart';

/// Repository for Firestore collection 'partners'.
/// Singleton -- create one instance for the whole app.
class FirestoreRepository {
  static final FirestoreRepository instance = FirestoreRepository._();
  FirestoreRepository._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'partners';

  // -- Read ------------------------------------------------------------

  Future<PartnerProfile?> getPartner(String uid) async {
    try {
      final doc = await _db.collection(_collection).doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return PartnerProfile.fromJson(doc.data()!);
      }
    } catch (e, stack) {
      debugPrint('[FirestoreRepository] getPartner() error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'FirestoreRepository.getPartner', fatal: false);
    }
    return null;
  }

  Stream<PartnerProfile?> streamPartner(String uid) {
    return _db.collection(_collection).doc(uid).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return PartnerProfile.fromJson(snapshot.data()!);
      }
      return null;
    });
  }

  // -- Write -----------------------------------------------------------

  /// Create or completely overwrite a partner profile
  Future<void> createPartner(PartnerProfile profile) async {
    await _db
        .collection('partners')
        .doc(profile.id)
        .set(profile.toJson());
  }

  /// Delete a partner profile
  Future<void> deletePartner(String uid) async {
    await _db.collection('partners').doc(uid).delete();
  }

  Future<void> savePartner(PartnerProfile profile) async {
    try {
      await _db
          .collection(_collection)
          .doc(profile.id)
          .set(profile.toJson(), SetOptions(merge: true));
      debugPrint('[FirestoreRepository] savePartner: ${profile.id}');
    } catch (e) {
      debugPrint('[FirestoreRepository] savePartner(${profile.id}) error: $e');
      rethrow;
    }
  }

  Future<void> updatePartner(String uid, Map<String, dynamic> data) async {
    try {
      // Use set with merge: true instead of update.
      // This ensures that if the document doesn't exist (e.g. initial save failed),
      // it will be created instead of throwing a not-found error.
      await _db
          .collection(_collection)
          .doc(uid)
          .set(data, SetOptions(merge: true));
      debugPrint(
        '[FirestoreRepository] updatePartner: $uid fields=${data.keys}',
      );
    } catch (e) {
      debugPrint('[FirestoreRepository] updatePartner($uid) error: $e');
      rethrow;
    }
  }

  // -- Online status ---------------------------------------------------

  Future<void> setOnlineStatus(String uid, {required bool isOnline}) async {
    try {
      await _db.collection(_collection).doc(uid).update({'isOnline': isOnline});
    } catch (e, stack) {
      debugPrint('[FirestoreRepository] setOnlineStatus($uid) error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'FirestoreRepository.setOnlineStatus', fatal: false);
    }
  }

  Future<ActiveTrip?> getActiveTripById(String tripId) async {
    try {
      final doc = await _db.collection('active_trips').doc(tripId).get();
      if (doc.exists && doc.data() != null) {
        return ActiveTrip.fromJson(doc.data()!);
      }
    } catch (e, stack) {
      debugPrint('[FirestoreRepository] getActiveTrip() error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'FirestoreRepository.getActiveTripById', fatal: false);
    }
    return null;
  }

  // -- Incoming orders -------------------------------------------------

  /// Stream active_trips where this partner is the driver OR guide.
  /// Uses two merged queries since Firestore cannot do OR across two different fields
  /// with inequality on a different field in a single query.
  /// NOTE: For simple presence checks, prefer [streamAllTripsByPartner] which already
  /// handles both roles. This method exists for driver-specific UIs that require
  /// explicit driverId filtering as a first pass.
  Stream<List<ActiveTrip>> streamActiveTripsByPartner(String partnerId) {
    late StreamController<List<ActiveTrip>> controller;
    StreamSubscription? subDriver;
    StreamSubscription? subGuide;
    List<ActiveTrip> latestDriver = [];
    List<ActiveTrip> latestGuide = [];

    void emit() {
      if (controller.isClosed) return;
      final seen = <String>{};
      final all = [
        ...latestDriver,
        ...latestGuide,
      ].where((t) => seen.add(t.id)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(all);
    }

    controller = StreamController<List<ActiveTrip>>.broadcast(
      onListen: () {
        subDriver = _db
            .collection('active_trips')
            .where('driverId', isEqualTo: partnerId)
            .where('status', whereIn: [TripStatus.scheduled.value, TripStatus.waiting.value, TripStatus.inProgress.value])
            .snapshots()
            .listen((s) {
          latestDriver = s.docs.map((d) => ActiveTrip.fromJson(d.data())).toList();
          emit();
        });
        subGuide = _db
            .collection('active_trips')
            .where('guideId', isEqualTo: partnerId)
            .where('status', whereIn: [TripStatus.scheduled.value, TripStatus.waiting.value, TripStatus.inProgress.value])
            .snapshots()
            .listen((s) {
          latestGuide = s.docs.map((d) => ActiveTrip.fromJson(d.data())).toList();
          emit();
        });
      },
      onCancel: () {
        subDriver?.cancel();
        subGuide?.cancel();
      },
    );

    return controller.stream;
  }

  /// Stream active_trips that are unassigned (no driverId) and status = 'scheduled'
  /// These are "available orders" that any driver can accept.
  Stream<List<ActiveTrip>> streamAvailableOrders() {
    return _db
        .collection('active_trips')
        .where('status', isEqualTo: TripStatus.scheduled.value)
        .where('driverId', isNull: true)
        .snapshots()
        .map((snapshot) {
          final trips = snapshot.docs
              .map((doc) => ActiveTrip.fromJson(doc.data()))
              .toList();
          trips.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return trips;
        });
  }

  /// Stream completed trips for a partner (for history screen).
  Stream<List<ActiveTrip>> streamCompletedTripsByPartner(String partnerId) {
    return _db
        .collection('active_trips')
        .where(Filter.or(
          Filter('driverId', isEqualTo: partnerId),
          Filter('guideId', isEqualTo: partnerId),
        ))
        .where('status', isEqualTo: TripStatus.completed.value)
        .snapshots()
        .map((snapshot) {
          final trips = snapshot.docs
              .map((doc) => ActiveTrip.fromJson(doc.data()))
              .toList();
          trips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return trips;
        });
  }



  /// Returns monthly statistics for this month: {count, totalEarnings}.
  /// Queries `bookings` collection for confiremed/completed bookings
  /// where driverId == partnerId and createdAt is within the current month.
  Future<Map<String, dynamic>> getMonthlyStats(String partnerId, {bool isDriver = true}) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final monthEnd = DateTime(now.year, now.month + 1, 1).toIso8601String();

    try {
      final field = isDriver ? 'driverId' : 'guideId';
      final snap = await _db
          .collection('bookings')
          .where(field, isEqualTo: partnerId)
          .where('status', whereIn: [BookingStatus.completed.name, BookingStatus.inProgress.name])
          .where('startDate', isGreaterThanOrEqualTo: monthStart)
          .where('startDate', isLessThan: monthEnd)
          .get();

      final docs = snap.docs;
      if (docs.isEmpty) return {'count': 0, 'avgEarnings': 0.0, 'totalEarnings': 0.0};

      double total = 0;
      for (final doc in docs) {
        total += (doc.data()['totalPrice'] as num?)?.toDouble() ?? 0.0;
      }
      return {
        'count': docs.length,
        'avgEarnings': total / docs.length,
        'totalEarnings': total,
      };
    } catch (e, stack) {
      debugPrint('[FirestoreRepository] getMonthlyStats error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'FirestoreRepository.getMonthlyStats', fatal: false);
      return {'count': 0, 'avgEarnings': 0.0, 'totalEarnings': 0.0};
    }
  }

  /// Stream monthly stats — re-queries every time bookings collection changes for this partner.
  Stream<Map<String, dynamic>> streamMonthlyStats(String partnerId, {bool isDriver = true}) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final monthEnd = DateTime(now.year, now.month + 1, 1).toIso8601String();
    final field = isDriver ? 'driverId' : 'guideId';

    return _db
        .collection('bookings')
        .where(field, isEqualTo: partnerId)
        .where('status', whereIn: [BookingStatus.completed.name, BookingStatus.inProgress.name])
        .where('startDate', isGreaterThanOrEqualTo: monthStart)
        .where('startDate', isLessThan: monthEnd)
        .snapshots()
        .map((snap) {
          final docs = snap.docs;
          if (docs.isEmpty) return {'count': 0, 'avgEarnings': 0.0, 'totalEarnings': 0.0};
          double total = 0;
          for (final doc in docs) {
            total += (doc.data()['totalPrice'] as num?)?.toDouble() ?? 0.0;
          }
          return {
            'count': docs.length,
            'avgEarnings': total / docs.length,
            'totalEarnings': total,
          };
        });
  }

  /// Assign a driver to an unassigned trip and confirm the booking atomically.
  Future<void> claimAvailableOrder(
    String tripId,
    String bookingId,
    String driverId,
    String driverName,
  ) async {
    final batch = _db.batch();
    batch.update(_db.collection('active_trips').doc(tripId), {
      'driverId': driverId,
      'driverName': driverName,
      'status': TripStatus.waiting.value,
      'driverAccepted': true,
    });
    batch.update(_db.collection('bookings').doc(bookingId), {
      'driverId': driverId,
      'driverName': driverName,
      'status': BookingStatus.confirmed.name,
    });
    await batch.commit();
    debugPrint('[FirestoreRepository] claimAvailableOrder: trip=$tripId driver=$driverId');
  }

  Future<void> assignDriver(
    String tripId,
    String bookingId,
    String driverId,
    String driverName,
  ) async {
    final batch = _db.batch();
    batch.update(_db.collection('active_trips').doc(tripId), {
      'driverId': driverId,
      'driverName': driverName,
      'status': TripStatus.scheduled.value,     // keep scheduled until driver explicitly accepts
      'driverAccepted': false,   // driver must confirm via acceptTrip()
    });
    batch.update(_db.collection('bookings').doc(bookingId), {
      'driverId': driverId,
      'driverName': driverName,
      'status': BookingStatus.pending.name, // still pending until driver accepts
    });
    await batch.commit();
    debugPrint('[FirestoreRepository] assignDriver: trip=$tripId driver=$driverId');
  }


  /// Fetch a booking by its ID
  Future<Booking?> getBookingById(String bookingId) async {
    try {
      final doc = await _db.collection('bookings').doc(bookingId).get();
      if (doc.exists && doc.data() != null) {
        return Booking.fromJson(doc.data()!);
      }
    } catch (e) {
      debugPrint('[FirestoreRepository] getBookingById($bookingId) error: $e');
    }
    return null;
  }

  /// Live version of [getBookingById] — used by the order feed so a
  /// partner's own counter-offer (or the passenger accepting/declining it)
  /// is reflected on the card without a manual refresh.
  Stream<Booking?> streamBookingById(String bookingId) {
    return _db.collection('bookings').doc(bookingId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return Booking.fromJson(doc.data()!);
    });
  }

  /// A driver/guide proposes a different price for a live-feed order
  /// instead of accepting the passenger's starting price outright. The
  /// passenger accepts/declines this from the client app (out of scope
  /// here) — this only records the proposal.
  Future<void> proposeCounterOffer(
    String bookingId, {
    required double price,
    required String proposedBy,
  }) async {
    await _db.collection('bookings').doc(bookingId).update({
      'status': BookingStatus.counterOffered.name,
      'counterOfferPrice': price,
      'counterOfferBy': proposedBy,
    });
  }

  /// Withdraw a pending counter-offer, returning the booking to its
  /// original pending state so it (and its original price) is visible in
  /// the feed again.
  Future<void> withdrawCounterOffer(String bookingId) async {
    await _db.collection('bookings').doc(bookingId).update({
      'status': BookingStatus.pending.name,
      'counterOfferPrice': null,
      'counterOfferBy': null,
    });
  }

  /// Get the current state of a trip synchronously
  Future<ActiveTrip?> getTripById(String tripId) async {
    try {
      final doc = await _db.collection('active_trips').doc(tripId).get();
      if (!doc.exists || doc.data() == null) return null;
      return ActiveTrip.fromJson(doc.data()!);
    } catch (e, stack) {
      debugPrint('[FirestoreRepository] getTripById Error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'FirestoreRepository.getTripById', fatal: false);
      return null;
    }
  }

  /// Accept an assigned order: set driverAccepted=true, status→'waiting', booking→'confirmed'
  Future<void> acceptTrip(String tripId, String bookingId) async {
    final batch = _db.batch();
    batch.update(_db.collection('active_trips').doc(tripId), {
      'status': TripStatus.waiting.value,
      'driverAccepted': true,  // unblocks client "Я на месте" button
    });
    batch.update(_db.collection('bookings').doc(bookingId), {
      'status': BookingStatus.confirmed.name,
    });
    await batch.commit();
    debugPrint('[FirestoreRepository] acceptTrip: trip=$tripId → waiting, driverAccepted=true');
  }

  /// Accept an assigned guide order: set guideAccepted=true, status→'waiting', booking→'confirmed'
  Future<void> acceptTripGuide(String tripId, String bookingId) async {
    final batch = _db.batch();
    batch.update(_db.collection('active_trips').doc(tripId), {
      'status': TripStatus.waiting.value,
      'guideAccepted': true,  // unblocks client "Я на месте" button
    });
    batch.update(_db.collection('bookings').doc(bookingId), {
      'status': BookingStatus.confirmed.name,
    });
    await batch.commit();
    debugPrint('[FirestoreRepository] acceptTripGuide: trip=$tripId → waiting, guideAccepted=true');
  }

  /// Stream trips that are assigned to this driver but not yet accepted.
  /// Shown in a new "Assigned to me" section in the partner app.
  Stream<List<ActiveTrip>> streamAssignedTrips(String driverId) {
    return _db
        .collection('active_trips')
        .where('driverId', isEqualTo: driverId)
        .where('driverAccepted', isEqualTo: false)
        .where('status', isEqualTo: TripStatus.scheduled.value)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ActiveTrip.fromJson(d.data()))
            .toList());
  }

  /// Stream trips that are assigned to this guide but not yet accepted.
  Stream<List<ActiveTrip>> streamAssignedGuideTrips(String guideId) {
    return _db
        .collection('active_trips')
        .where('guideId', isEqualTo: guideId)
        .where('guideAccepted', isEqualTo: false)
        .where('status', isEqualTo: TripStatus.scheduled.value)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ActiveTrip.fromJson(d.data()))
            .toList());
  }

  /// Decline an assigned order: unassign the driver so the order becomes available again
  Future<void> declineTrip(String tripId, String bookingId, String driverId) async {
    final batch = _db.batch();
    batch.update(_db.collection('active_trips').doc(tripId), {
      'driverId': FieldValue.delete(),
      'driverName': FieldValue.delete(),
      'declinedByDrivers': FieldValue.arrayUnion([driverId]), // record decline
    });
    batch.update(_db.collection('bookings').doc(bookingId), {
      'driverId': FieldValue.delete(),
      'driverName': FieldValue.delete(),
      // Status remains 'pending' so client sees it as waiting for assign
      'status': BookingStatus.pending.name, 
    });
    await batch.commit();
    debugPrint('[FirestoreRepository] declineTrip: $tripId by $driverId');
  }

  /// Decline a guide assignment: clears guideId/guideName from trip and booking.
  Future<void> declineGuide(String tripId, String bookingId, String guideId) async {
    final batch = _db.batch();
    batch.update(_db.collection('active_trips').doc(tripId), {
      'guideId': FieldValue.delete(),
    });
    batch.update(_db.collection('bookings').doc(bookingId), {
      'guideId': FieldValue.delete(),
      'guideName': FieldValue.delete(),
    });
    await batch.commit();
    debugPrint('[FirestoreRepository] declineGuide: $tripId by $guideId');
  }

  /// Cancel a trip completely (status becomes 'cancelled')
  Future<void> cancelTrip(String tripId, String bookingId) async {
    final batch = _db.batch();
    batch.update(_db.collection('active_trips').doc(tripId), {
      'status': TripStatus.cancelled.value,
    });
    batch.update(_db.collection('bookings').doc(bookingId), {
      'status': BookingStatus.cancelled.name,
    });
    await batch.commit();
    debugPrint('[FirestoreRepository] cancelTrip: $tripId');
  }

  /// Mark partner as ready at the meeting point (sets driverReady or guideReady)
  Future<void> setPartnerReady(String tripId, {required bool isDriver}) async {
    final field = isDriver ? 'driverReady' : 'guideReady';
    await _db.collection('active_trips').doc(tripId).update({field: true});
  }

  /// Update the companions list (e.g. for marking them as ready)
  Future<void> updateCompanions(String tripId, List<Map<String, dynamic>> companionsList) async {
    await _db.collection('active_trips').doc(tripId).update({
      'companions': companionsList,
    });
  }

  /// Broadcast the driver's live location to Firestore.
  Future<void> updateDriverLocation(
    String tripId,
    double lat,
    double lng,
  ) async {
    try {
      await _db.collection('active_trips').doc(tripId).update({
        'driverLocation': {'lat': lat, 'lng': lng},
      });
    } catch (e, stack) {
      debugPrint('[FirestoreRepository] updateDriverLocation error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'FirestoreRepository.updateDriverLocation', fatal: false);
    }
  }

  /// Broadcast the guide's live location to Firestore.
  Future<void> updateGuideLocation(
    String tripId,
    double lat,
    double lng,
  ) async {
    try {
      await _db.collection('active_trips').doc(tripId).update({
        'guideLocation': {'lat': lat, 'lng': lng},
      });
    } catch (e, stack) {
      debugPrint('[FirestoreRepository] updateGuideLocation error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'FirestoreRepository.updateGuideLocation', fatal: false);
    }
  }

  /// Atomic transaction: set trip + booking status to in_progress.
  /// Also ensures the trip ends at the starting point and initializes waypointCheckIns.
  /// Idempotent: no-op if the trip is already in_progress.
  Future<void> startTrip(String tripId, String bookingId) async {
    final tripRef = _db.collection('active_trips').doc(tripId);
    final bookingRef = _db.collection('bookings').doc(bookingId);

    await _db.runTransaction((transaction) async {
      final tripSnap = await transaction.get(tripRef);
      if (!tripSnap.exists) return;

      final tripData = tripSnap.data()!;
      final trip = ActiveTrip.fromJson(tripData);

      // ── Idempotency guard ──────────────────────────────────────────────────
      // Another participant may have already called startTrip() a split-second
      // before us. Skip the write to avoid resetting waypointCheckIns.
      if (trip.status != TripStatus.waiting) {
        debugPrint('[FirestoreRepository] startTrip: trip=$tripId already ${trip.status}, skipping');
        return;
      }
      // ──────────────────────────────────────────────────────────────────────

      final waypoints = List<MeetingPoint>.from(trip.waypoints);

      // 1. Ensure "Return to Start" requirement
      if (waypoints.isNotEmpty) {
        final first = waypoints.first;
        final last = waypoints.last;
        if (first.latitude != last.latitude || first.longitude != last.longitude) {
          waypoints.add(first);
        }
      }

      // 2. Write back waypoints with empty checkIns embedded in each point
      transaction.update(tripRef, {
        'status': TripStatus.inProgress.value,
        'waypoints': waypoints.map((w) {
          final json = w.toJson();
          json['checkIns'] = <String, dynamic>{}; // fresh slate per waypoint
          return json;
        }).toList(),
        'currentWaypointIndex': 0,
      });

      transaction.update(bookingRef, {
        'status': BookingStatus.inProgress.name,
      });
    });

    debugPrint('[FirestoreRepository] startTrip: $tripId (with return logic)');
  }

  /// Participant (driver, guide, or client) checks in at a specific waypoint.
  /// If all required participants have checked in, the currentWaypointIndex is incremented.
  Future<void> checkInAtWaypoint(String tripId, int waypointIndex, String role) async {
    final docRef = _db.collection('active_trips').doc(tripId);
    
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;
      
      final data = snapshot.data()!;
      
      List<dynamic> waypoints = List<dynamic>.from(data['waypoints'] as List? ?? []);
      if (waypointIndex >= waypoints.length) return;

      final pt = Map<String, dynamic>.from(waypoints[waypointIndex] as Map);
      final checkIns = pt['checkIns'] != null
          ? Map<String, dynamic>.from(pt['checkIns'] as Map)
          : <String, dynamic>{};
      
      checkIns[role] = true;
      pt['checkIns'] = checkIns;
      waypoints[waypointIndex] = pt;
      
      // Check if all active participants have checked in
      bool everyoneCheckedIn = checkIns['client'] == true;
      if ((data['driverId'] as String?) != null && checkIns['driver'] != true) everyoneCheckedIn = false;
      if ((data['guideId'] as String?) != null && checkIns['guide'] != true) everyoneCheckedIn = false;

      // Check companions
      final companions = data['companions'] as List<dynamic>? ?? [];
      for (var comp in companions) {
        final uid = (comp as Map<String, dynamic>)['uid'] as String? ?? '';
        if (uid.isNotEmpty && checkIns['companion_$uid'] != true) {
          everyoneCheckedIn = false;
          break;
        }
      }
      
      int nextIndex = (data['currentWaypointIndex'] as num?)?.toInt() ?? 0;
      if (everyoneCheckedIn && waypointIndex == nextIndex) {
        nextIndex++;
      }
      
      transaction.update(docRef, {
        'waypoints': waypoints,
        'currentWaypointIndex': nextIndex,
      });
    });
  }

  /// Atomic batch: set trip + booking status to completed.
  Future<void> completeTrip(String tripId, String bookingId) async {
    final batch = _db.batch();
    batch.update(_db.collection('active_trips').doc(tripId), {
      'status': TripStatus.completed.value,
    });
    batch.update(_db.collection('bookings').doc(bookingId), {
      'status': BookingStatus.completed.name,
    });
    await batch.commit();
    debugPrint('[FirestoreRepository] completeTrip: $tripId');
  }

  /// Step 1 of two-step completion: partner signals they are done.
  /// Sets role-specific flag and legacy completionRequested flag.
  /// The client sees the completion request only when all active parties have confirmed.
  Future<void> requestTripCompletion(String tripId, {required bool isDriver}) async {
    try {
      final field = isDriver ? 'driverCompletionRequested' : 'guideCompletionRequested';
      await _db.collection('active_trips').doc(tripId).update({
        field: true,
        'completionRequested': true, // legacy compat
      });
      debugPrint('[FirestoreRepository] requestTripCompletion($field): $tripId');
    } catch (e) {
      debugPrint('[FirestoreRepository] requestTripCompletion error: $e');
      rethrow;
    }
  }

  /// Stream a single active_trip by ID (for the map screen)
  Stream<ActiveTrip?> streamTripById(String tripId) {
    return _db
        .collection('active_trips')
        .doc(tripId)
        .snapshots()
        .map(
          (doc) => doc.exists && doc.data() != null
              ? ActiveTrip.fromJson(doc.data()!)
              : null,
        );
  }

  Stream<List<ActiveTrip>> streamAllTripsByPartner(String partnerId) {
    late StreamController<List<ActiveTrip>> controller;
    StreamSubscription? subDriver;
    StreamSubscription? subGuide;
    List<ActiveTrip> latestDriver = [];
    List<ActiveTrip> latestGuide = [];

    void emit() {
      if (controller.isClosed) return;
      final seen = <String>{};
      final all = [
        ...latestDriver,
        ...latestGuide,
      ].where((t) => seen.add(t.id)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(all);
    }

    controller = StreamController<List<ActiveTrip>>.broadcast(
      onListen: () {
        subDriver = _db
            .collection('active_trips')
            .where('driverId', isEqualTo: partnerId)
            .where('status', whereIn: [TripStatus.scheduled.value, TripStatus.waiting.value, TripStatus.inProgress.value])
            .snapshots()
            .listen((s) {
          latestDriver = s.docs.map((d) => ActiveTrip.fromJson(d.data())).toList();
          emit();
        });

        subGuide = _db
            .collection('active_trips')
            .where('guideId', isEqualTo: partnerId)
            .where('status', whereIn: [TripStatus.scheduled.value, TripStatus.waiting.value, TripStatus.inProgress.value])
            .snapshots()
            .listen((s) {
          latestGuide = s.docs.map((d) => ActiveTrip.fromJson(d.data())).toList();
          emit();
        });
      },
      onCancel: () {
        subDriver?.cancel();
        subGuide?.cancel();
      },
    );

    return controller.stream;
  }

  // -- FCM Tokens -----------------------------------------------------

  /// Saves the FCM push notification token for the specified user or partner.
  Future<void> saveFcmToken(
    String uid,
    String token, {
    bool isPartner = false,
  }) async {
    try {
      final collection = isPartner ? 'partners' : 'users';
      await _db.collection(collection).doc(uid).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
      debugPrint(
        '[FirestoreRepository] FCM Token saved to $collection/$uid',
      );
    } catch (e, stack) {
      debugPrint(
        '[FirestoreRepository] Error saving FCM token: $e',
      );
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'FirestoreRepository.saveFcmToken', fatal: false);
    }
  }

  // -- Vehicle Inspections --------------------------------------------

  static const _inspections = 'vehicle_inspections';

  /// Submit a new daily inspection report.
  /// Creates a document in `vehicle_inspections/{auto-id}`.
  Future<String> submitInspection(VehicleInspection inspection) async {
    final docRef = _db.collection(_inspections).doc();
    final withId = VehicleInspection(
      id: docRef.id,
      driverId: inspection.driverId,
      driverName: inspection.driverName,
      vehicleModel: inspection.vehicleModel,
      vehiclePlate: inspection.vehiclePlate,
      date: inspection.date,
      status: InspectionStatus.pending,
      sides: inspection.sides,
      submittedAt: inspection.submittedAt,
    );
    await docRef.set(withId.toJson());
    debugPrint('[FirestoreRepository] submitInspection: ${docRef.id}');
    return docRef.id;
  }

  /// Stream the driver's inspection report for today (null if not submitted yet).
  Stream<VehicleInspection?> streamTodayInspection(String driverId) {
    final today = _dateString(DateTime.now());
    return _db
        .collection(_inspections)
        .where('driverId', isEqualTo: driverId)
        .where('date', isEqualTo: today)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      return VehicleInspection.fromJson(snap.docs.first.data());
    });
  }

  /// Stream all inspections with status=pending (for admin review panel).
  Stream<List<VehicleInspection>> streamPendingInspections() {
    return _db
        .collection(_inspections)
        .where('status', isEqualTo: 'pending')
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => VehicleInspection.fromJson(d.data())).toList());
  }

  /// Admin: approve a vehicle inspection report.
  ///
  /// Also flips the driver's own `vehicleInspectionVerified` badge — without
  /// this, [PartnerProfile.vehicleInspectionVerified] never becomes true
  /// anywhere in the codebase, so the "Проверка кузова" status on the
  /// driver's Garage screen would stay stuck on "Требуется" forever even
  /// after an inspection is approved here.
  Future<void> approveInspection(String inspectionId,
      {required String adminUid}) async {
    final doc = await _db.collection(_inspections).doc(inspectionId).get();
    final driverId = doc.data()?['driverId'] as String?;

    final batch = _db.batch();
    batch.update(_db.collection(_inspections).doc(inspectionId), {
      'status': InspectionStatus.approved.name,
      'reviewedAt': Timestamp.now(),
      'reviewedBy': adminUid,
    });
    if (driverId != null) {
      batch.set(_db.collection('partners').doc(driverId),
          {'vehicleInspectionVerified': true}, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Admin: reject a vehicle inspection report with a reason.
  Future<void> rejectInspection(
    String inspectionId, {
    required String adminUid,
    required String reason,
  }) async {
    final doc = await _db.collection(_inspections).doc(inspectionId).get();
    final driverId = doc.data()?['driverId'] as String?;

    final batch = _db.batch();
    batch.update(_db.collection(_inspections).doc(inspectionId), {
      'status': InspectionStatus.rejected.name,
      'rejectionReason': reason,
      'reviewedAt': Timestamp.now(),
      'reviewedBy': adminUid,
    });
    if (driverId != null) {
      batch.set(_db.collection('partners').doc(driverId),
          {'vehicleInspectionVerified': false}, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Returns true if driver currently has an active (non-completed) trip.
  /// Used to block vehicle inspection during active routes.
  Future<bool> hasActiveTrip(String driverId) async {
    final snap = await _db
        .collection('active_trips')
        .where('driverId', isEqualTo: driverId)
        .where('status', whereIn: [TripStatus.waiting.value, TripStatus.inProgress.value])
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  static String _dateString(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  // ── Reviews ──────────────────────────────────────────────────────────────

  /// Checks if the author has already reviewed this target for this booking.
  Future<bool> hasReviewed(String bookingId, String authorId, String targetId) async {
    final snap = await _db
        .collection('reviews')
        .where('bookingId', isEqualTo: bookingId)
        .where('authorId', isEqualTo: authorId)
        .where('targetId', isEqualTo: targetId)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// Submits a review and atomically updates the target's rating.
  Future<void> submitReview(Review review) async {
    await _db.runTransaction((tx) async {
      final reviewRef = _db.collection('reviews').doc();
      final reviewWithId = Review(
        id: reviewRef.id,
        bookingId: review.bookingId,
        authorId: review.authorId,
        authorName: review.authorName,
        authorRole: review.authorRole,
        targetId: review.targetId,
        targetRole: review.targetRole,
        rating: review.rating,
        comment: review.comment,
        createdAt: DateTime.now(),
      );
      tx.set(reviewRef, reviewWithId.toJson());

      // Determine which collection to update for the target
      final String targetCollection = (review.targetRole == 'client') ? 'users' : 'partners';
      final targetRef = _db.collection(targetCollection).doc(review.targetId);
      final targetSnap = await tx.get(targetRef);
      if (targetSnap.exists) {
        final data = targetSnap.data()!;
        final oldCount = (data['reviewCount'] as int?) ?? 0;
        final oldRating = (data['rating'] as num?)?.toDouble() ?? 0.0;
        final newCount = oldCount + 1;
        final newRating = ((oldRating * oldCount) + review.rating) / newCount;
        tx.update(targetRef, {
          'rating': double.parse(newRating.toStringAsFixed(2)),
          'reviewCount': newCount,
        });
      }
    });
  }
}
