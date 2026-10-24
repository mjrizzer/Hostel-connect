const {test,before}=require('node:test');
const assert=require('node:assert/strict');
const enabled=Boolean(process.env.FIRESTORE_EMULATOR_HOST);
let api,deliverReminder,db,Timestamp;
before(async()=>{
 if(!enabled)return;
 process.env.GCLOUD_PROJECT='demo-hostel-connect';
 ({api,deliverReminder}=require('../lib/index'));
 ({Timestamp}=require('firebase-admin/firestore'));db=require('firebase-admin/firestore').getFirestore();
});
const invoke=(uid,action,payload={},admin=false)=>api.run({auth:{uid,token:{admin,firebase:{sign_in_provider:admin?'google.com':'anonymous'}}},data:{action,payload}});
const reset=async()=>{for(const col of (await db.listCollections()))await db.recursiveDelete(col);};
async function setup(){await reset();for(const uid of ['alice','bob'])await invoke(uid,'profile');await db.doc('machines/HS1-F1-WM1').set({status:'available',activeSessionId:null});await db.doc('machines/HS1-F2-WM1').set({status:'available',activeSessionId:null});await db.doc('sportsEquipment/DJ-TT1').set({status:'available',activeSessionId:null});}
test('transactional session, moderation and reminder integration',{skip:!enabled},async t=>{
 await t.test('seed creates the exact inventory and all meals without overwriting occupancy',async()=>{
  await reset();const script=require('node:path').resolve('../scripts/database_initialization/seed.cjs');
  const run=()=>require('node:child_process').execFileSync(process.execPath,[script],{env:process.env});run();
  assert.equal((await db.collection('buildings').get()).size,5);assert.equal((await db.collection('machines').get()).size,16);assert.equal((await db.collection('sportsEquipment').get()).size,3);assert.equal((await db.collection('weeklyMenu').get()).size,7);
  await db.doc('machines/HS1-F1-WM1').update({status:'outOfService'});run();assert.equal((await db.doc('machines/HS1-F1-WM1').get()).get('status'),'outOfService');assert.equal((await db.collection('originalWeeklyMenu').get()).size,7);
 });
 await t.test('competing reservations produce exactly one owner and one reminder',async()=>{
  await setup();const results=await Promise.allSettled(['alice','bob'].map(uid=>invoke(uid,'start',{kind:'laundry',resourceId:'HS1-F1-WM1',requestId:uid})));
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert.equal((await db.collection('laundrySessions').get()).size,1);assert.equal((await db.collection('reminderOutbox').get()).size,1);
  const session=(await db.collection('laundrySessions').get()).docs[0],owner=session.get('sessionOwnerId'),other=owner==='alice'?'bob':'alice';
  await assert.rejects(invoke(other,'finish',{kind:'laundry',sessionId:session.id}),e=>e.code==='permission-denied');
  await assert.rejects(invoke(owner,'start',{kind:'laundry',resourceId:'HS1-F2-WM1',requestId:'second'}),e=>e.code==='failed-precondition');
  const resource=(await db.doc('machines/HS1-F1-WM1').get()).data();assert.equal(resource.sessionOwnerId,undefined);
  const reminder=(await db.collection('reminderOutbox').get()).docs[0];assert.ok(Math.abs(reminder.get('dueAt').toMillis()-session.get('startedAt').toMillis()-1200000)<1000);
  await invoke(owner,'finish',{kind:'laundry',sessionId:session.id});assert.equal((await reminder.ref.get()).get('status'),'cancelled');assert.equal((await db.collection('dryingReminders').get()).size,0);
  await invoke(owner,'drying',{sessionId:session.id});await invoke(owner,'drying',{sessionId:session.id});assert.equal((await db.collection('dryingReminders').get()).size,1);
  const drying=await db.doc(`dryingReminders/${session.id}`).get();assert.equal(drying.get('dueAt').toMillis()-drying.get('startedAt').toMillis(),43200000);
  await invoke(owner,'cancelDrying',{sessionId:session.id,collected:true});assert.equal((await drying.ref.get()).get('status'),'collected');
 });
 await t.test('request retry is idempotent; status reports do not change occupancy',async()=>{
  await setup();const p={kind:'laundry',resourceId:'HS1-F1-WM1',requestId:'same-request'};
  assert.deepEqual(await invoke('alice','start',p),await invoke('alice','start',p));
  const report={kind:'laundry',resourceId:'HS1-F1-WM1',reason:'Machine is actually free'};await invoke('bob','reportStatus',report);await assert.rejects(invoke('bob','reportStatus',report));
  assert.equal((await db.doc('machines/HS1-F1-WM1').get()).get('status'),'inUse');
  await assert.rejects(invoke('bob','adminStatus',{kind:'laundry',resourceId:'HS1-F1-WM1',status:'available',reason:'Test override'}));
  await invoke('admin','adminStatus',{kind:'laundry',resourceId:'HS1-F1-WM1',status:'outOfService',reason:'Verified broken'},true);
  assert.equal((await db.doc('machines/HS1-F1-WM1').get()).get('status'),'outOfService');assert.equal((await db.collection('activeLaundry').get()).size,0);
 });
 await t.test('No drying decision persists and cannot later schedule a reminder',async()=>{
  await setup();const {sessionId}=await invoke('alice','start',{kind:'laundry',resourceId:'HS1-F1-WM1',requestId:'no-drying'});
  await invoke('alice','finish',{kind:'laundry',sessionId});assert.equal((await db.doc(`laundrySessions/${sessionId}`).get()).get('dryingDecision'),'pending');
  await invoke('alice','skipDrying',{sessionId});await assert.rejects(invoke('alice','drying',{sessionId}),e=>e.code==='failed-precondition');
  assert.equal((await db.collection('dryingReminders').get()).size,0);
 });
 await t.test('sports has owner control and creates no notification records',async()=>{
  await setup();const {sessionId}=await invoke('alice','start',{kind:'sports',resourceId:'DJ-TT1',requestId:'game'});
  await assert.rejects(invoke('bob','finish',{kind:'sports',sessionId}));await invoke('alice','finish',{kind:'sports',sessionId});
  assert.equal((await db.collection('reminderOutbox').get()).size,0);
 });
 await t.test('menu approval produces a date-only override without altering fixed menu',async()=>{
  await setup();await db.doc('weeklyMenu/Thursday').set({lunch:['Rice']});
  await invoke('alice','suggestMenu',{date:'2026-10-22',mealType:'lunch',items:['Appam'],reason:'Official change'});
  const id=(await db.collection('menuSuggestions').get()).docs[0].id;
  await assert.rejects(invoke('alice','reviewMenu',{suggestionId:id,approve:true,reason:'Test'}));
  await invoke('admin','reviewMenu',{suggestionId:id,approve:true,reason:'Confirmed with mess'},true);
  assert.deepEqual((await db.doc('weeklyMenu/Thursday').get()).get('lunch'),['Rice']);assert.deepEqual((await db.doc('menuOverrides/2026-10-22_lunch').get()).get('items'),['Appam']);assert.equal((await db.doc('menuOverrides/2026-10-23_lunch').get()).exists,false);
 });
 await t.test('chat ownership, reply, rate limit, private reporting and moderation',async()=>{
  await setup();const {messageId}=await invoke('alice','sendMessage',{content:'Hello hostel',requestId:'first'});
  assert.equal((await db.doc(`chatMessages/${messageId}`).get()).get('senderId'),undefined);
  await assert.rejects(invoke('alice','sendMessage',{content:'Too soon',requestId:'second'}),e=>e.code==='resource-exhausted');
  await invoke('bob','sendMessage',{content:'Welcome!',requestId:'reply',replyTo:messageId});
  await assert.rejects(invoke('bob','deleteMessage',{messageId}));
  await invoke('bob','reportMessage',{messageId,reason:'Spam'});assert.equal((await db.collection('restrictions').get()).size,0);
  await invoke('admin','moderateMessage',{messageId,restrictHours:24,reason:'Repeated verified spam'},true);
  await assert.rejects(invoke('alice','sendMessage',{content:'Another message',requestId:'third'}),e=>e.code==='permission-denied');
 });
 await t.test('reminder handler invalidates ended sessions and disabled preferences',async()=>{
  await setup();const {sessionId}=await invoke('alice','start',{kind:'laundry',resourceId:'HS1-F1-WM1',requestId:'reminder'});
  const ref=db.doc(`reminderOutbox/washing_${sessionId}`);await ref.update({dueAt:Timestamp.fromMillis(Date.now()-1000)});await db.doc('users/alice').update({reminders:false});
  await deliverReminder.run({data:{id:`washing_${sessionId}`}});assert.equal((await ref.get()).get('status'),'cancelled');
 });
 await t.test('duplicate task delivery attempts send only to the owner and keep machine occupied',async()=>{
  await setup();const {sessionId}=await invoke('alice','start',{kind:'laundry',resourceId:'HS1-F1-WM1',requestId:'owner-reminder'});
  const ref=db.doc(`reminderOutbox/washing_${sessionId}`);await ref.update({dueAt:Timestamp.fromMillis(Date.now()-1000)});
  await db.doc('users/alice/tokens/one').set({token:'alice-token',updatedAt:Timestamp.now()});await db.doc('users/bob/tokens/two').set({token:'bob-token',updatedAt:Timestamp.now()});
  const messaging=require('firebase-admin/messaging').getMessaging(),original=messaging.sendEachForMulticast;let sends=0;
  messaging.sendEachForMulticast=async message=>{sends++;assert.deepEqual(message.tokens,['alice-token']);assert.equal(message.data.sessionId,sessionId);return {successCount:1,failureCount:0,responses:[{success:true}]};};
  try {await Promise.all([deliverReminder.run({data:{id:`washing_${sessionId}`}}),deliverReminder.run({data:{id:`washing_${sessionId}`}})]);assert.equal(sends,1);assert.equal((await ref.get()).get('status'),'sent');assert.equal((await db.doc('machines/HS1-F1-WM1').get()).get('status'),'inUse');}finally{messaging.sendEachForMulticast=original;}
 });
});
