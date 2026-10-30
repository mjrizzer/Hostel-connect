const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,updateDoc,writeBatch,runTransaction,serverTimestamp,Timestamp}=require('firebase/firestore');
const fs=require('node:fs');
const enabled=process.env.TEST_FREE_PLAN==='1';
let env;
before(async()=>{if(enabled)env=await initializeTestEnvironment({projectId:'demo-hostel-free',firestore:{rules:fs.readFileSync(require('node:path').resolve(__dirname,'../../firestore.free.rules'),'utf8')}});});
after(async()=>{await env?.cleanup();});
const client=uid=>env.authenticatedContext(uid).firestore();
async function profile(uid,alias){const db=client(uid),b=writeBatch(db);b.set(doc(db,'users',uid),{displayName:'Resident123',publicId:alias,createdAt:serverTimestamp(),lastActiveAt:serverTimestamp(),reminders:false});b.set(doc(db,'publicAliases',alias),{owner:uid});return b.commit();}
async function message(uid,id,content){const db=client(uid),p=(await getDoc(doc(db,'users',uid))).data(),b=writeBatch(db);b.set(doc(db,'chatMessages',id),{content,displayName:p.displayName,senderKey:p.publicId,timestamp:serverTimestamp(),replyTo:null,deleted:false,moderated:false});b.set(doc(db,'chatAuthors',id),{senderId:uid});b.set(doc(db,'freeRateLimits',uid+'_chat'),{at:serverTimestamp(),content,target:id});return b.commit();}
async function fixture(){await env.clearFirestore();await env.withSecurityRulesDisabled(async c=>{for(const [col,id] of [['machines','HS1-F1-WM1'],['machines','HS1-F2-WM1'],['sportsEquipment','DJ-TT1']])await setDoc(doc(c.firestore(),col,id),{status:'available',activeSessionId:null,startedAt:null,updatedAt:Timestamp.now()});});}
async function start(uid,id,sid,kind='laundry'){
 const db=client(uid),col=kind==='laundry'?'machines':'sportsEquipment',sessions=kind==='laundry'?'laundrySessions':'sportsSessions',locks=kind==='laundry'?'activeLaundry':'activeSports';
 return runTransaction(db,async t=>{
  const lock=doc(db,locks,uid),r=doc(db,col,id);const ls=await t.get(lock),rs=await t.get(r);if(ls.exists()||rs.data().status!=='available')throw Error('Occupied');
  t.set(doc(db,sessions,sid),{sessionOwnerId:uid,resourceId:id,status:'active',startedAt:serverTimestamp(),completedAt:null});
  t.set(lock,{sessionId:sid});t.set(doc(db,'resourceClaims',id),{sessionOwnerId:uid,sessionId:sid,kind});
  t.update(r,{status:'inUse',activeSessionId:sid,startedAt:serverTimestamp(),updatedAt:serverTimestamp()});
 });
}
async function finish(uid,id,sid,kind='laundry'){
 const db=client(uid),b=writeBatch(db);b.update(doc(db,kind==='laundry'?'machines':'sportsEquipment',id),{status:'available',activeSessionId:null,startedAt:null,updatedAt:serverTimestamp()});
 b.update(doc(db,kind==='laundry'?'laundrySessions':'sportsSessions',sid),{status:'completed',completedAt:serverTimestamp()});
 b.delete(doc(db,kind==='laundry'?'activeLaundry':'activeSports',uid));b.delete(doc(db,'resourceClaims',id));return b.commit();
}
async function communityReport(uid,target,messageId,type='message') {
 const db=client(uid),b=writeBatch(db);
 const counter=doc(db,'communityModeration',target);
 const count=(await getDoc(counter)).data()?.count??0;
 b.set(doc(db,'communityReports',target+'_'+uid),{target,messageId,type,reporterId:uid,reason:'Spam',description:'Test',createdAt:serverTimestamp()});
 b.set(counter,{count:count+1});
 if(type==='message' && count===5)b.update(doc(db,'chatMessages',messageId),{content:'Message removed after community reports',moderated:true});
 b.set(doc(db,'freeRateLimits',uid+'_reports'),{at:serverTimestamp(),target:'communityReports/'+target+'_'+uid});
 return b.commit();
}
test('free-plan authorization and atomic reservations',{skip:!enabled},async t=>{
 await t.test('six unique reports hide a message, duplicates and forged counters fail',async()=>{
  await fixture();await profile('author','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');await message('author','reported','Hello');
  for(let i=1;i<=6;i++){
   const uid='reporter'+i;await profile(uid,`${String(i).repeat(8)}-bbbb-bbbb-bbbb-bbbbbbbbbbbb`);
   await assertSucceeds(communityReport(uid,'m_reported','reported'));
   assert.equal((await getDoc(doc(client(uid),'communityModeration','m_reported'))).data().count,i);
  }
  await assertFails(communityReport('reporter1','m_reported','reported'));
  assert.equal((await getDoc(doc(client('author'),'chatMessages','reported'))).data().content,'Message removed after community reports');
  await assertFails(setDoc(doc(client('reporter1'),'communityModeration','m_forged'),{count:6}));
  await assertFails(getDoc(doc(client('author'),'communityReports','m_reported_reporter1')));
 });
 await t.test('six distinct user reports block posting but preserve resource access',async()=>{
  await fixture();const alias='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';await profile('author',alias);await message('author','reported','Hello');
  await assertFails(communityReport('author','u_'+alias,'reported','user'));
  for(let i=1;i<=6;i++){
   const uid='reporter'+i;await profile(uid,`${String(i).repeat(8)}-bbbb-bbbb-bbbb-bbbbbbbbbbbb`);
   await assertSucceeds(communityReport(uid,'u_'+alias,'reported','user'));
  }
  await env.withSecurityRulesDisabled(async c=>{await setDoc(doc(c.firestore(),'freeRateLimits','author_chat'),{at:Timestamp.fromMillis(1),content:'Old',target:'old'});});
  await assertFails(message('author','blocked','Different text'));
  await assertSucceeds(start('author','HS1-F1-WM1','wash'));
 });
 await t.test('profile creation is valid and cannot steal a public alias',async()=>{await fixture();await assertSucceeds(profile('alice','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));await assertFails(profile('bob','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));});
 await t.test('chat works with rules-enforced rate and author checks',async()=>{await fixture();await profile('alice','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');await assertSucceeds(message('alice','msg1','Hello hostel'));await assertFails(message('alice','msg2','Too soon'));await assertFails(updateDoc(doc(client('bob'),'chatMessages','msg1'),{content:'Message deleted',deleted:true}));await assertSucceeds(updateDoc(doc(client('alice'),'chatMessages','msg1'),{content:'Message deleted',deleted:true}));});
 await t.test('race yields one reservation and ownership survives a fresh client',async()=>{await fixture();const results=await Promise.allSettled([start('alice','HS1-F1-WM1','a'),start('bob','HS1-F1-WM1','b')]);assert.equal(results.filter(r=>r.status==='fulfilled').length,1);const uid=results[0].status==='fulfilled'?'alice':'bob',sid=uid==='alice'?'a':'b';assert.equal((await getDoc(doc(client(uid),'laundrySessions',sid))).data().status,'active');await assertSucceeds(finish(uid,'HS1-F1-WM1',sid));});
 await t.test('owner-only finish and private claims',async()=>{await fixture();await start('alice','HS1-F1-WM1','a');await assertFails(finish('bob','HS1-F1-WM1','a'));await assertFails(getDoc(doc(client('bob'),'resourceClaims','HS1-F1-WM1')));await assertFails(getDoc(doc(client('bob'),'laundrySessions','a')));await assertSucceeds(finish('alice','HS1-F1-WM1','a'));});
 await t.test('second laundry session and standalone availability writes rejected',async()=>{await fixture();await start('alice','HS1-F1-WM1','a');await assert.rejects(start('alice','HS1-F2-WM1','second'));await assertFails(updateDoc(doc(client('alice'),'machines','HS1-F1-WM1'),{status:'available',activeSessionId:null,startedAt:null,updatedAt:serverTimestamp()}));});
 await t.test('cannot bypass active lock with a forged batch',async()=>{await fixture();await start('alice','HS1-F1-WM1','a');const db=client('alice'),b=writeBatch(db);b.set(doc(db,'laundrySessions','forged'),{sessionOwnerId:'alice',resourceId:'HS1-F2-WM1',status:'active',startedAt:serverTimestamp(),completedAt:null});b.update(doc(db,'machines','HS1-F2-WM1'),{status:'inUse',activeSessionId:'forged',startedAt:serverTimestamp(),updatedAt:serverTimestamp()});b.set(doc(db,'resourceClaims','HS1-F2-WM1'),{sessionOwnerId:'alice',sessionId:'forged',kind:'laundry'});await assertFails(b.commit());});
 await t.test('sports has the same owner protection',async()=>{await fixture();await start('alice','DJ-TT1','game','sports');await assertFails(finish('bob','DJ-TT1','game','sports'));await assertSucceeds(finish('alice','DJ-TT1','game','sports'));});
 await t.test('profile cannot self-assign admin or use a client timestamp',async()=>{await fixture();const db=client('alice');await assertFails(setDoc(doc(db,'users','alice'),{displayName:'Resident123',publicId:'123',createdAt:Timestamp.now(),lastActiveAt:Timestamp.now(),reminders:false,admin:true}));});
 await t.test('report cannot modify equipment and students cannot approve menu',async()=>{await fixture();const db=client('alice'),b=writeBatch(db);b.set(doc(db,'machineReports','alice_HS1-F1-WM1'),{kind:'laundry',resourceId:'HS1-F1-WM1',reason:'Machine is broken',description:'Test',status:'pending',createdAt:serverTimestamp(),reportedByUid:'alice'});b.set(doc(db,'freeRateLimits','alice_reports'),{at:serverTimestamp(),target:'machineReports/alice_HS1-F1-WM1'});await assertSucceeds(b.commit());assert.equal((await getDoc(doc(db,'machines','HS1-F1-WM1'))).data().status,'available');await assertFails(setDoc(doc(db,'menuOverrides','2026-10-30_lunch'),{items:['Fake override']}));});
});
