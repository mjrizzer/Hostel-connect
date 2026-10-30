import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

const freePlan = bool.fromEnvironment('FREE_PLAN');

Never unavailable(String message) => throw FirebaseFunctionsException(
  code: 'failed-precondition',
  message: message,
);

Future<Map<String, dynamic>> freePlanCall(
  FirebaseFirestore db,
  String uid,
  String action,
  Map<String, dynamic> p,
) async {
  final stamp = FieldValue.serverTimestamp();
  final user = db.doc('users/$uid');
  if (action == 'profile') {
    await db.runTransaction((t) async {
      final current = await t.get(user);
      if (!current.exists) {
        final alias = const Uuid().v4();
        t.set(user, {
          'displayName':
              p['displayName'] ??
              'Resident${100000 + Random.secure().nextInt(900000)}',
          'publicId': alias,
          'createdAt': stamp,
          'lastActiveAt': stamp,
          'reminders': false,
        });
        t.set(db.doc('publicAliases/$alias'), {'owner': uid});
      } else {
        t.update(user, {
          'displayName': p['displayName'] ?? current.get('displayName'),
          'lastActiveAt': stamp,
        });
      }
    });
    return {'ok': true};
  }
  if (action == 'start' || action == 'finish') {
    final laundry = p['kind'] == 'laundry';
    final resources = laundry ? 'machines' : 'sportsEquipment';
    final sessions = laundry ? 'laundrySessions' : 'sportsSessions';
    final active = db.doc('${laundry ? 'activeLaundry' : 'activeSports'}/$uid');
    final sessionId = action == 'start'
        ? p['requestId'] as String
        : p['sessionId'] as String;
    final session = db.doc('$sessions/$sessionId');
    await db.runTransaction((t) async {
      if (action == 'start') {
        final resource = db.doc('$resources/${p['resourceId']}');
        final lock = await t.get(active);
        final equipment = await t.get(resource);
        if (lock.exists) unavailable('Finish your current session first.');
        if (!equipment.exists || equipment.get('status') != 'available') {
          unavailable('This equipment is no longer available.');
        }
        t.set(session, {
          'sessionOwnerId': uid,
          'resourceId': resource.id,
          'status': 'active',
          'startedAt': stamp,
          'completedAt': null,
        });
        t.set(active, {'sessionId': sessionId});
        t.set(db.doc('resourceClaims/${resource.id}'), {
          'sessionOwnerId': uid,
          'sessionId': sessionId,
          'kind': p['kind'],
        });
        t.update(resource, {
          'status': 'inUse',
          'activeSessionId': sessionId,
          'startedAt': stamp,
          'updatedAt': stamp,
        });
      } else {
        final current = await t.get(session);
        if (!current.exists || current.get('sessionOwnerId') != uid) {
          unavailable('Only the session owner can finish.');
        }
        if (current.get('status') != 'active') return;
        final resource = db.doc('$resources/${current.get('resourceId')}');
        final equipment = await t.get(resource);
        if (equipment.get('activeSessionId') != sessionId) {
          unavailable('Session state needs administrator review.');
        }
        t.update(session, {'status': 'completed', 'completedAt': stamp});
        t.update(resource, {
          'status': 'available',
          'activeSessionId': null,
          'startedAt': null,
          'updatedAt': stamp,
        });
        t.delete(active);
        t.delete(db.doc('resourceClaims/${resource.id}'));
      }
    });
    return {'ok': true, 'sessionId': sessionId};
  }
  if (action == 'reportStatus' ||
      action == 'reportMessage' ||
      action == 'suggestMenu') {
    final col = action == 'reportStatus'
        ? (p['kind'] == 'laundry' ? 'machineReports' : 'sportsReports')
        : action == 'reportMessage'
        ? 'messageReports'
        : 'menuSuggestions';
    final key = action == 'suggestMenu'
        ? const Uuid().v4()
        : '${uid}_${p['resourceId'] ?? p['messageId']}';
    final ref = db.doc('$col/$key');
    final rate = db.doc('freeRateLimits/${uid}_reports');
    await db.runTransaction((t) async {
      final prior = await t.get(rate);
      if (prior.exists &&
          (prior.get('at') as Timestamp)
              .toDate()
              .add(const Duration(seconds: 60))
              .isAfter(DateTime.now())) {
        unavailable(
          'Please wait a minute before submitting another report or suggestion.',
        );
      }
      final data = <String, dynamic>{
        ...p,
        'status': 'pending',
        'createdAt': stamp,
      };
      data[action == 'suggestMenu'
              ? 'proposedBy'
              : action == 'reportMessage'
              ? 'reporterId'
              : 'reportedByUid'] =
          uid;
      t.set(ref, data);
      t.set(rate, {'at': stamp, 'target': '$col/$key'});
    });
    return {'ok': true};
  }
  if (action == 'sendMessage') {
    final id = p['requestId'] as String;
    final content = (p['content'] as String).trim();
    final rate = db.doc('freeRateLimits/${uid}_chat');
    await db.runTransaction((t) async {
      final profile = await t.get(user);
      final previous = await t.get(rate);
      if (previous.exists) {
        final elapsed = DateTime.now().difference(
          (previous.get('at') as Timestamp).toDate(),
        );
        if (elapsed.inSeconds < 5 ||
            (previous.get('content') == content && elapsed.inSeconds < 60)) {
          unavailable('Please wait before sending another message.');
        }
      }
      t.set(db.doc('chatMessages/$id'), {
        'content': content,
        'displayName': profile.get('displayName'),
        'senderKey': profile.get('publicId'),
        'timestamp': stamp,
        'replyTo': p['replyTo'],
        'deleted': false,
        'moderated': false,
      });
      t.set(db.doc('chatAuthors/$id'), {'senderId': uid});
      t.set(rate, {'at': stamp, 'content': content, 'target': id});
    });
    return {'messageId': id};
  }
  if (action == 'deleteMessage') {
    await db.doc('chatMessages/${p['messageId']}').update({
      'content': 'Message deleted',
      'deleted': true,
    });
    return {'ok': true};
  }
  unavailable(
    'This feature requires the server-enabled version. Scheduled reminders are not available on the free plan.',
  );
}
