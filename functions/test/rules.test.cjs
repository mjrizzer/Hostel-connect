const {test,before,after}=require('node:test');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,collection,query,where,getDocs}=require('firebase/firestore');
const fs=require('node:fs');
let env;
const emulator=process.env.FIRESTORE_EMULATOR_HOST;
before(async()=>{if(!emulator)return;env=await initializeTestEnvironment({projectId:'demo-hostel-connect',firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}}); await env.withSecurityRulesDisabled(async c=>{
 const db=c.firestore();
 await Promise.all([
 setDoc(doc(db,'machines/HS1-F1-WM1'),{status:'inUse',activeSessionId:'session'}),
 setDoc(doc(db,'laundrySessions/session'),{sessionOwnerId:'alice',status:'active'}),
 setDoc(doc(db,'messageReports/report'),{reporterId:'alice'}),
 setDoc(doc(db,'users/alice/tokens/token'),{token:'private'}),
 setDoc(doc(db,'chatAuthors/message'),{senderId:'alice'}),
 ]);
});});
after(async()=>{await env?.cleanup();});
test('public availability readable; anonymous visitor denied',{skip:!emulator},async()=>{
 await assertSucceeds(getDoc(doc(env.authenticatedContext('bob').firestore(),'machines/HS1-F1-WM1')));
 await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'machines/HS1-F1-WM1')));
});
test('private sessions only visible to owner and filtered owner query',{skip:!emulator},async()=>{
 const alice=env.authenticatedContext('alice').firestore(),bob=env.authenticatedContext('bob').firestore();
 await assertSucceeds(getDoc(doc(alice,'laundrySessions/session')));
 await assertFails(getDoc(doc(bob,'laundrySessions/session')));
 await assertSucceeds(getDocs(query(collection(alice,'laundrySessions'),where('sessionOwnerId','==','alice'),where('status','==','active'))));
 await assertFails(getDocs(collection(alice,'laundrySessions')));
});
test('clients cannot mutate availability, roles, sessions or messages',{skip:!emulator},async()=>{
 const db=env.authenticatedContext('alice').firestore();
 for(const path of ['machines/HS1-F1-WM1','users/alice','laundrySessions/session','chatMessages/message','menuOverrides/2026-10-22_lunch','adminRoles/alice']) await assertFails(setDoc(doc(db,path),{admin:true,status:'completed'}));
});
test('private moderation identities and device tokens are not public',{skip:!emulator},async()=>{
 const db=env.authenticatedContext('bob').firestore();
 for(const path of ['messageReports/report','chatAuthors/message','users/alice/tokens/token'])await assertFails(getDoc(doc(db,path)));
});
test('anonymous accounts rejected even with an admin claim',{skip:!emulator},async()=>{
 const db=env.authenticatedContext('evil',{admin:true,firebase:{sign_in_provider:'anonymous'}}).firestore();
 await assertFails(getDoc(doc(db,'messageReports/report')));
 const admin=env.authenticatedContext('moderator',{admin:true,firebase:{sign_in_provider:'google.com'}}).firestore();
 await assertSucceeds(getDoc(doc(admin,'messageReports/report')));
 await assertFails(setDoc(doc(admin,'machines/HS1-F1-WM1'),{status:'available'}));
});
