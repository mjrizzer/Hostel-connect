import 'package:cloud_firestore/cloud_firestore.dart';

enum Availability { available, inUse, outOfService }

class Resource {
  final String id, buildingId, label;
  final int floor;
  final Availability status;
  final DateTime? startedAt;
  Resource(
    this.id,
    this.buildingId,
    this.label,
    this.floor,
    this.status,
    this.startedAt,
  );
  factory Resource.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Resource(
      doc.id,
      d['buildingId'] as String,
      d['equipmentType'] as String? ?? 'Washing Machine ${d['machineNumber']}',
      d['floorNumber'] as int? ?? 0,
      Availability.values.byName(d['status'] as String),
      (d['startedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class Session {
  final String id, resourceId;
  final DateTime startedAt;
  Session(this.id, this.resourceId, this.startedAt);
  factory Session.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Session(
      doc.id,
      d['resourceId'] as String,
      (d['startedAt'] as Timestamp).toDate(),
    );
  }
}

class Profile {
  final String name, publicId;
  final bool reminders;
  Profile(this.name, this.publicId, this.reminders);
  factory Profile.fromMap(Map<String, dynamic> d) => Profile(
    d['displayName'] as String,
    d['publicId'] as String,
    d['reminders'] as bool? ?? true,
  );
}

class ChatMessage {
  final String id, content, name, senderKey;
  final String? replyTo;
  final DateTime time;
  final bool deleted;
  ChatMessage(
    this.id,
    this.content,
    this.name,
    this.senderKey,
    this.replyTo,
    this.time,
    this.deleted,
  );
  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ChatMessage(
      doc.id,
      d['content'] as String,
      d['displayName'] as String,
      d['senderKey'] as String,
      d['replyTo'] as String?,
      (d['timestamp'] as Timestamp).toDate(),
      d['deleted'] as bool,
    );
  }
}

const weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const meals = {
  'breakfast': 'Breakfast',
  'lunch': 'Lunch',
  'snacks': 'Evening Snacks',
  'dinner': 'Dinner',
};
DateTime hostelNow([DateTime? instant]) => (instant ?? DateTime.now())
    .toUtc()
    .add(const Duration(hours: 5, minutes: 30));
String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String buildingName(String id) => id == 'KENNEDY' ? 'Kennedy' : id;
