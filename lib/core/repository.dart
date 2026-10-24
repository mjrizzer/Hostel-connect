import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';

class Repository {
  Repository({FirebaseFirestore? firestore})
    : db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore db;
  FirebaseAuth get auth => FirebaseAuth.instance;
  FirebaseFunctions get functions =>
      FirebaseFunctions.instanceFor(region: 'asia-south1');
  bool get mutationsEnabled => true;
  String get uid => auth.currentUser!.uid;
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final result = await functions.httpsCallable('api').call<dynamic>({
      'action': action,
      'payload': payload,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> initialize() async {
    if (auth.currentUser != null) {
      // Restore cached content after restart even when a network is unavailable.
      try {
        final cached = await db
            .doc('users/$uid')
            .get(const GetOptions(source: Source.cache));
        if (cached.exists) return;
      } on FirebaseException {
        // A retained Auth account may exist before its first profile is cached.
      }
    } else {
      await auth.signInAnonymously();
    }
    await call('profile');
  }

  Stream<Profile> profile() => db
      .doc('users/$uid')
      .snapshots()
      .where((s) => s.exists)
      .map((s) => Profile.fromMap(s.data()!));
  Stream<QuerySnapshot<Map<String, dynamic>>> resources(String kind) => db
      .collection(kind == 'laundry' ? 'machines' : 'sportsEquipment')
      .snapshots(includeMetadataChanges: true);
  Stream<List<Session>> sessions(String kind) => db
      .collection(kind == 'laundry' ? 'laundrySessions' : 'sportsSessions')
      .where('sessionOwnerId', isEqualTo: uid)
      .where('status', isEqualTo: 'active')
      .snapshots()
      .map((s) => s.docs.map(Session.fromDoc).toList());
}

final repositoryProvider = Provider((ref) => Repository());
final profileProvider = StreamProvider(
  (ref) => ref.watch(repositoryProvider).profile(),
);
final resourcesProvider =
    StreamProvider.family<QuerySnapshot<Map<String, dynamic>>, String>(
      (ref, kind) => ref.watch(repositoryProvider).resources(kind),
    );
final sessionsProvider = StreamProvider.family<List<Session>, String>(
  (ref, kind) => ref.watch(repositoryProvider).sessions(kind),
);
final clockProvider = StreamProvider<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 10), (_) => DateTime.now()),
);
