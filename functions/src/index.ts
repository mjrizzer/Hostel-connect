import {initializeApp} from 'firebase-admin/app';
import {getFirestore, Timestamp, Transaction} from 'firebase-admin/firestore';
import {getFunctions} from 'firebase-admin/functions';
import {getMessaging} from 'firebase-admin/messaging';
import {onCall, HttpsError, CallableRequest} from 'firebase-functions/v2/https';
import {onDocumentCreated} from 'firebase-functions/v2/firestore';
import {onTaskDispatched} from 'firebase-functions/v2/tasks';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {setGlobalOptions} from 'firebase-functions/v2';
import {createHash, randomUUID} from 'node:crypto';
import {z} from 'zod';
import * as d from './domain.js';

initializeApp();
setGlobalOptions({region:'asia-south1',maxInstances:20});
const db = getFirestore();
const hash = (s:string) => createHash('sha256').update(s).digest('hex');
const now = () => Timestamp.now();
const fail = (code:'permission-denied'|'failed-precondition'|'resource-exhausted'|'not-found',message:string):never => { throw new HttpsError(code,message); };
function admin(r:CallableRequest) {
  if (r.auth?.token.admin !== true || r.auth.token.firebase?.sign_in_provider === 'anonymous') fail('permission-denied','Administrator access required.');
}
async function limit(t:Transaction, uid:string, action:string, seconds:number) {
  const ref=db.doc(`rateLimits/${hash(uid+':'+action)}`), snap=await t.get(ref);
  if (snap.exists && snap.get('until').toMillis()>Date.now()) fail('resource-exhausted','Please wait before trying again.');
  // Call only after all other reads in the transaction.
  t.set(ref,{until:Timestamp.fromMillis(Date.now()+seconds*1000)});
}
function paths(kind:'laundry'|'sports') { return kind === 'laundry' ? ['machines','laundrySessions','activeLaundry'] : ['sportsEquipment','sportsSessions','activeSports']; }
function audit(t:Transaction, uid:string, action:string, detail:unknown) { t.create(db.collection('auditRecords').doc(),{actor:uid,action,detail,createdAt:now()}); }
function outbox(t:Transaction, reminderId:string, uid:string, type:'washing'|'drying', sessionId:string) {
  t.create(db.doc(`reminderOutbox/${reminderId}`),{sessionOwnerId:uid,type,sessionId,status:'pending',dueAt:Timestamp.fromMillis(Date.now()+d.reminderDelay(type)*1000),createdAt:now()});
}

export const api = onCall({enforceAppCheck:true}, async r => {
  if (!r.auth) throw new HttpsError('unauthenticated','Please reconnect to your anonymous account.');
  const uid=r.auth.uid;
  try {
    const {action,payload:p}=z.object({action:z.string(),payload:z.record(z.string(),z.unknown()).default({})}).parse(r.data);
    if (action === 'profile') {
      const v=z.object({displayName:z.string().trim().min(2).max(32).regex(/^[a-zA-Z0-9 _-]+$/).optional(),reminders:z.boolean().optional()}).parse(p);
      return db.runTransaction(async t => {
        const ref=db.doc(`users/${uid}`), s=await t.get(ref);
        await limit(t,uid,'profile',2);
        if (!s.exists) t.create(ref,{displayName:v.displayName ?? `Resident${Math.floor(Math.random()*900000)+100000}`,publicId:randomUUID(),createdAt:now(),lastActiveAt:now(),reminders:v.reminders ?? true});
        else t.update(ref,{...v,lastActiveAt:now()});
        return {ok:true};
      });
    }
    if (action === 'token') {
      const v=z.object({token:z.string().min(20).max(4096)}).parse(p);
      await db.runTransaction(async t => { await limit(t,uid,'token',2); t.set(db.doc(`users/${uid}/tokens/${hash(v.token)}`),{token:v.token,updatedAt:now()}); });
      return {ok:true};
    }
    if (action === 'start') {
      const v=z.object({kind:d.kind,resourceId:d.id,requestId:d.id}).parse(p);
      const [resources,sessions,active]=paths(v.kind), sid=hash(`${uid}:${v.requestId}`);
      return db.runTransaction(async t => {
        const resource=db.doc(`${resources}/${v.resourceId}`), session=db.doc(`${sessions}/${sid}`), lock=db.doc(`${active}/${uid}`);
        const [rs,ss,ls]=await t.getAll(resource,session,lock);
        if (ss.exists) return {sessionId:sid};
        if (!rs.exists) fail('not-found','Equipment was not found.');
        if (rs.get('status')!=='available') fail('failed-precondition','Someone else is using this equipment, or it is out of service.');
        if (ls.exists) fail('failed-precondition','Finish your current session first.');
        await limit(t,uid,'start',3);
        const startedAt=now();
        t.create(session,{sessionOwnerId:uid,resourceId:v.resourceId,startedAt,status:'active',completedAt:null});
        t.create(lock,{sessionId:sid});
        t.update(resource,{status:'inUse',activeSessionId:sid,startedAt,updatedAt:startedAt});
        if (v.kind==='laundry') outbox(t,`washing_${sid}`,uid,'washing',sid);
        return {sessionId:sid};
      });
    }
    if (action === 'finish') {
      const v=z.object({kind:d.kind,sessionId:d.id}).parse(p), [resources,sessions,active]=paths(v.kind);
      return db.runTransaction(async t => {
        const ref=db.doc(`${sessions}/${v.sessionId}`), s=await t.get(ref);
        if (!s.exists) fail('not-found','Session was not found.');
        if (s.get('sessionOwnerId')!==uid) fail('permission-denied','Only the session owner can finish.');
        if (s.get('status')!=='active') return {ok:true};
        const resource=db.doc(`${resources}/${s.get('resourceId')}`), rs=await t.get(resource);
        if (rs.get('activeSessionId')!==v.sessionId) fail('failed-precondition','Session state needs administrator review.');
        t.update(ref,{status:'completed',completedAt:now(),...(v.kind==='laundry'?{dryingDecision:'pending'}:{})});
        t.update(resource,{status:'available',activeSessionId:null,startedAt:null,updatedAt:now()});
        t.delete(db.doc(`${active}/${uid}`));
        if (v.kind==='laundry') t.update(db.doc(`reminderOutbox/washing_${v.sessionId}`),{status:'cancelled'});
        return {ok:true};
      });
    }
    if (action === 'drying') {
      const v=z.object({sessionId:d.id}).parse(p);
      return db.runTransaction(async t => {
        const ref=db.doc(`dryingReminders/${v.sessionId}`), [s,existing]=await t.getAll(db.doc(`laundrySessions/${v.sessionId}`),ref);
        if (!s.exists || s.get('sessionOwnerId')!==uid) fail('permission-denied','Only the session owner can create this reminder.');
        if (s.get('status')!=='completed') fail('failed-precondition','Finish washing first.');
        if (existing.exists) return {ok:true};
        if (s.get('dryingDecision')==='no') fail('failed-precondition','This session was finished without outdoor drying.');
        t.create(ref,{sessionOwnerId:uid,status:'pending',startedAt:now(),dueAt:Timestamp.fromMillis(Date.now()+43200000)});
        t.update(s.ref,{dryingDecision:'yes'});
        outbox(t,`drying_${v.sessionId}`,uid,'drying',v.sessionId);
        return {ok:true};
      });
    }
    if (action === 'skipDrying') {
      const v=z.object({sessionId:d.id}).parse(p);
      await db.runTransaction(async t=>{
        const s=await t.get(db.doc(`laundrySessions/${v.sessionId}`));
        if (!s.exists || s.get('sessionOwnerId')!==uid) fail('permission-denied','Only the session owner can choose.');
        if (s.get('status')!=='completed' || s.get('dryingDecision')==='yes') fail('failed-precondition','Use the pending reminder controls to cancel an existing reminder.');
        t.update(s.ref,{dryingDecision:'no'});
      });return {ok:true};
    }
    if (action === 'cancelDrying') {
      const v=z.object({sessionId:d.id,collected:z.boolean()}).parse(p);
      await db.runTransaction(async t => {
        const ref=db.doc(`dryingReminders/${v.sessionId}`), s=await t.get(ref);
        if (!s.exists || s.get('sessionOwnerId')!==uid) fail('permission-denied','Reminder does not belong to you.');
        t.update(ref,{status:v.collected?'collected':'cancelled',closedAt:now()});
        t.update(db.doc(`reminderOutbox/drying_${v.sessionId}`),{status:'cancelled'});
      }); return {ok:true};
    }
    if (action === 'reportStatus') {
      const v=z.object({kind:d.kind,resourceId:d.id,reason:z.enum(d.statusReasons),description:z.string().trim().max(1000).default('')}).parse(p);
      const [resources]=paths(v.kind), col=v.kind==='laundry'?'machineReports':'sportsReports';
      await db.runTransaction(async t => {
        const report=db.doc(`${col}/${hash(uid+v.resourceId)}`), [resource,existing]=await t.getAll(db.doc(`${resources}/${v.resourceId}`),report);
        if (!resource.exists) fail('not-found','Equipment was not found.');
        if (existing.exists && existing.get('status')==='pending') fail('failed-precondition','You already have a pending report for this equipment.');
        await limit(t,uid,'statusReport',60);
        t.set(report,{...v,reportedByUid:uid,status:'pending',createdAt:now()});
      }); return {ok:true};
    }
    if (action === 'suggestMenu') {
      const v=z.object({date:d.date,mealType:d.meal,items:d.items,reason:z.string().trim().max(500).default('')}).parse(p);
      await db.runTransaction(async t => { await limit(t,uid,'menuSuggestion',60); t.create(db.collection('menuSuggestions').doc(),{...v,proposedBy:uid,status:'pending',createdAt:now()}); });
      return {ok:true};
    }
    if (action === 'sendMessage') {
      const v=z.object({content:z.string().trim().min(1).max(2000),replyTo:d.id.nullable().default(null),requestId:d.id}).parse(p);
      const normalized=d.normalizeMessage(v.content);
      // Basic filter is deliberately supplemented by reports and human moderation.
      if (/\b(fuck|shit|cunt|nigger)\b/i.test(normalized)) fail('failed-precondition','Please rephrase your message to follow the community guidelines.');
      const mid=hash(uid+v.requestId);
      await db.runTransaction(async t => {
        const refs=[db.doc(`users/${uid}`),db.doc(`restrictions/${uid}`),db.doc(`chatMessages/${mid}`),db.doc(`messageDuplicates/${hash(uid+normalized)}`)];
        if (v.replyTo) refs.push(db.doc(`chatMessages/${v.replyTo}`));
        const [user,restriction,existing,duplicate,reply]=await t.getAll(...refs);
        if (existing.exists) return;
        if (!user.exists) fail('failed-precondition','Initialize your profile first.');
        if (restriction.exists && restriction.get('until').toMillis()>Date.now()) fail('permission-denied','Your account is temporarily restricted from community chat.');
        if (duplicate.exists && duplicate.get('until').toMillis()>Date.now()) fail('resource-exhausted','Duplicate message. Please wait before posting again.');
        if (v.replyTo && (!reply?.exists || reply.get('deleted'))) fail('failed-precondition','The message you replied to is no longer available.');
        await limit(t,uid,'chat',5);
        t.create(db.doc(`chatMessages/${mid}`),{content:v.content,replyTo:v.replyTo,displayName:user.get('displayName'),senderKey:user.get('publicId'),timestamp:now(),deleted:false,moderated:false});
        t.create(db.doc(`chatAuthors/${mid}`),{senderId:uid});
        t.set(db.doc(`messageDuplicates/${hash(uid+normalized)}`),{until:Timestamp.fromMillis(Date.now()+60000)});
      }); return {messageId:mid};
    }
    if (action === 'deleteMessage') {
      const v=z.object({messageId:d.id}).parse(p);
      await db.runTransaction(async t => {
        const a=await t.get(db.doc(`chatAuthors/${v.messageId}`));
        if (a.get('senderId')!==uid) fail('permission-denied','You can only delete your own messages.');
        t.update(db.doc(`chatMessages/${v.messageId}`),{content:'Message deleted',deleted:true});
      }); return {ok:true};
    }
    if (action === 'reportMessage') {
      const v=z.object({messageId:d.id,reason:z.enum(d.chatReasons),description:z.string().trim().max(1000).default('')}).parse(p);
      await db.runTransaction(async t => {
        const report=db.doc(`messageReports/${hash(uid+v.messageId)}`), [a,existing,message]=await t.getAll(db.doc(`chatAuthors/${v.messageId}`),report,db.doc(`chatMessages/${v.messageId}`));
        if (!a.exists) fail('not-found','Message was not found.');
        if (existing.exists) fail('failed-precondition','You already reported this message.');
        await limit(t,uid,'messageReport',30);
        t.create(report,{...v,messageSnapshot:message.data()??null,reportedUserId:a.get('senderId'),reporterId:uid,status:'pending',createdAt:now()});
      }); return {ok:true};
    }
    admin(r);
    if (action === 'adminStatus') {
      const v=z.object({kind:d.kind,resourceId:d.id,status:z.enum(['available','outOfService']),reason:z.string().trim().min(5).max(500)}).parse(p);
      const [resources,sessions,active]=paths(v.kind);
      await db.runTransaction(async t => {
        const ref=db.doc(`${resources}/${v.resourceId}`), s=await t.get(ref);
        if (!s.exists) fail('not-found','Equipment was not found.');
        const sid=s.get('activeSessionId'), session=sid?await t.get(db.doc(`${sessions}/${sid}`)):null;
        if (session?.exists) {
          t.update(session.ref,{status:'overridden',completedAt:now()});
          t.delete(db.doc(`${active}/${session.get('sessionOwnerId')}`));
          if (v.kind==='laundry') t.update(db.doc(`reminderOutbox/washing_${sid}`),{status:'cancelled'});
        }
        t.update(ref,{status:v.status,activeSessionId:null,startedAt:null,updatedAt:now()});
        audit(t,uid,action,v);
      }); return {ok:true};
    }
    if (action === 'reviewMenu') {
      const v=z.object({suggestionId:d.id,approve:z.boolean(),reason:z.string().trim().min(3).max(500)}).parse(p);
      await db.runTransaction(async t => {
        const ref=db.doc(`menuSuggestions/${v.suggestionId}`), s=await t.get(ref);
        if (!s.exists || s.get('status')!=='pending') fail('failed-precondition','Suggestion is no longer pending.');
        if (s.get('proposedBy')===uid) fail('permission-denied','A different moderator must review your suggestion.');
        const status=v.approve?'approved':'rejected';
        t.update(ref,{status,reviewedBy:uid,reviewedAt:now(),reviewReason:v.reason});
        if (v.approve) t.set(db.doc(`menuOverrides/${s.get('date')}_${s.get('mealType')}`),{date:s.get('date'),mealType:s.get('mealType'),items:s.get('items'),approvedAt:now()});
        t.create(db.collection('menuHistory').doc(),{...s.data(),decision:status,reviewedBy:uid,reviewedAt:now(),reviewReason:v.reason});
        audit(t,uid,action,v);
      }); return {ok:true};
    }
    if (action === 'editWeeklyMenu') {
      const v=z.object({day:z.enum(d.weekdays as [string,...string[]]),menu:d.weeklyDay,reason:z.string().trim().min(5).max(500)}).parse(p);
      await db.runTransaction(async t => {
        const ref=db.doc(`weeklyMenu/${v.day}`), original=await t.get(ref);
        t.set(ref,{...v.menu,verified:true,updatedAt:now()});
        t.create(db.collection('menuHistory').doc(),{day:v.day,before:original.data()??null,after:v.menu,reason:v.reason,reviewedBy:uid,reviewedAt:now()});
        audit(t,uid,action,v);
      }); return {ok:true};
    }
    if (action === 'moderateMessage') {
      const v=z.object({messageId:d.id,restrictHours:z.number().int().min(0).max(720),reason:z.string().trim().min(5).max(500)}).parse(p);
      await db.runTransaction(async t => {
        const a=await t.get(db.doc(`chatAuthors/${v.messageId}`));
        if (!a.exists) fail('not-found','Message was not found.');
        t.update(db.doc(`chatMessages/${v.messageId}`),{content:'Removed by moderation',deleted:true,moderated:true});
        if (v.restrictHours>0) t.set(db.doc(`restrictions/${a.get('senderId')}`),{until:Timestamp.fromMillis(Date.now()+v.restrictHours*3600000),reason:v.reason});
        audit(t,uid,action,v);
      }); return {ok:true};
    }
    if (action === 'resolveReport') {
      const v=z.object({collection:z.enum(['machineReports','sportsReports','messageReports']),reportId:d.id,decision:z.enum(['resolved','dismissed']),reason:z.string().trim().min(5).max(500)}).parse(p);
      await db.runTransaction(async t => {
        const ref=db.doc(`${v.collection}/${v.reportId}`), s=await t.get(ref);
        if (!s.exists) fail('not-found','Report was not found.');
        t.update(ref,{status:v.decision,resolvedAt:now(),resolvedBy:uid,decisionReason:v.reason}); audit(t,uid,action,v);
      }); return {ok:true};
    }
    throw new HttpsError('invalid-argument','Unknown action.');
  } catch(e) {
    if (e instanceof z.ZodError) throw new HttpsError('invalid-argument',e.issues.map(i=>i.message).join('; '));
    throw e;
  }
});

// An outbox survives a crash between reservation commit and Cloud Tasks enqueue.
async function enqueueReminder(id:string) {
  const ref=db.doc(`reminderOutbox/${id}`), s=await ref.get();
  if (!s.exists || s.get('status')!=='pending') return;
  await getFunctions().taskQueue('locations/asia-south1/functions/deliverReminder').enqueue({id},{scheduleTime:new Date(Math.max(Date.now(),s.get('dueAt').toMillis()))});
  await db.runTransaction(async t => { const latest=await t.get(ref); if(latest.get('status')==='pending') t.update(ref,{status:'queued',queuedAt:now()}); });
}
export const queueReminder=onDocumentCreated({document:'reminderOutbox/{id}',retry:true}, async e => { await enqueueReminder(e.params.id); });
export const repairReminderQueue=onSchedule('every 5 minutes',async () => {
  const pending=await db.collection('reminderOutbox').where('status','==','pending').limit(200).get();
  for (const doc of pending.docs) await enqueueReminder(doc.id);
});
export const deliverReminder=onTaskDispatched({retryConfig:{maxAttempts:5,minBackoffSeconds:30},rateLimits:{maxConcurrentDispatches:10},invoker:'private'},async req => {
  const {id}=z.object({id:d.id}).parse(req.data);
  const ref=db.doc(`reminderOutbox/${id}`);
  const delivery=await db.runTransaction(async t => {
    const s=await t.get(ref);
    if (!s.exists || !['pending','queued'].includes(s.get('status'))) return null;
    if (s.get('dueAt').toMillis()>Date.now()+1000) throw new Error('Reminder task arrived before due time');
    const uid=s.get('sessionOwnerId'), type=s.get('type');
    const [session,user]=await t.getAll(db.doc(`${type==='washing'?'laundrySessions':'dryingReminders'}/${s.get('sessionId')}`),db.doc(`users/${uid}`));
    if (session.get('status')!==(type==='washing'?'active':'pending') || user.get('reminders')!==true) { t.update(ref,{status:'cancelled'}); return null; }
    // Claim before FCM: at-most-once send attempt. FCM is not an exactly-once transport.
    t.update(ref,{status:'claimed',claimedAt:now()});
    return {uid,type,sessionId:s.get('sessionId') as string};
  });
  if (!delivery) return;
  const tokens=await db.collection(`users/${delivery.uid}/tokens`).orderBy('updatedAt','desc').limit(10).get();
  if (tokens.empty) { await ref.update({status:'noToken'}); return; }
  const washing=delivery.type==='washing';
  try {
    const result=await getMessaging().sendEachForMulticast({tokens:tokens.docs.map(s=>s.get('token')),notification:{title:washing?'Washing Reminder 🧺':'Clothes Drying Reminder ☀️',body:washing?'Your washing machine has been in use for 20 minutes. Please check your clothes.':"It's been 12 hours since you placed your clothes outside. Don't forget to collect them!"},data:{route:'/laundry',sessionId:delivery.sessionId,reminderId:id},android:{notification:{channelId:'laundry_reminders',tag:id}}});
    await ref.update({status:'sent',sentAt:now(),successCount:result.successCount,failureCount:result.failureCount});
    await Promise.all(result.responses.map((res,i)=>!res.success && ['messaging/registration-token-not-registered','messaging/invalid-registration-token'].includes(res.error?.code??'')?tokens.docs[i].ref.delete():Promise.resolve()));
    if (!washing) await db.doc(`dryingReminders/${delivery.sessionId}`).update({sentAt:now()});
  } catch(e) {
    await ref.update({status:'deliveryUncertain',failedAt:now(),errorCode: typeof e==='object' && e!==null && 'code' in e ? String(e.code):'unknown'});
    // Do not retry an uncertain FCM handoff and risk duplicate delivery.
  }
});

export const pruneAbuseState=onSchedule('every 24 hours',async () => {
  for (const collection of ['rateLimits','messageDuplicates']) {
    const docs=await db.collection(collection).where('until','<',now()).limit(400).get();
    const batch=db.batch(); docs.docs.forEach(s=>batch.delete(s.ref)); await batch.commit();
  }
});
