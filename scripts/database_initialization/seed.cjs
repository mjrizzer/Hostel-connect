// Run after `npm --prefix functions run build`. Uses Application Default Credentials.
const backendRequire=require('node:module').createRequire(require('node:path').resolve(__dirname,'../../functions/package.json'));
const {initializeApp}=backendRequire('firebase-admin/app');
const {getFirestore,Timestamp}=backendRequire('firebase-admin/firestore');
const {buildings,machines,equipment,weeklyDay,weekdays}=require('../../functions/lib/domain');
const fs=require('node:fs');
initializeApp({projectId:process.env.GCLOUD_PROJECT});
const db=getFirestore();
async function createOnly(path,data) { await db.runTransaction(async t=>{ const ref=db.doc(path); if (!(await t.get(ref)).exists) t.create(ref,data); }); }
async function main(){
  if (!process.env.GCLOUD_PROJECT) throw Error('Set GCLOUD_PROJECT explicitly.');
  for(const b of buildings) await createOnly(`buildings/${b.id}`,{buildingId:b.id,name:b.name,floorCount:b.floors});
  for(const m of machines) await createOnly(`machines/${m.id}`,{...m,status:'available',activeSessionId:null,startedAt:null,updatedAt:Timestamp.now()});
  for(const e of equipment) await createOnly(`sportsEquipment/${e.id}`,{...e,status:'available',activeSessionId:null,startedAt:null,updatedAt:Timestamp.now()});
  console.log('Inventory ready: 5 buildings, 16 machines, 3 sports facilities. Existing occupancy preserved.');
  const menu=JSON.parse(fs.readFileSync(require('node:path').join(__dirname,'../../assets/menu/weekly-menu.json'),'utf8'));
  if (!menu.verified || menu.verificationNotes.length) { console.log('Menu NOT imported: resolve documented photograph ambiguities and verify the source first.'); return; }
  if(Object.keys(menu.days).length!==7) throw Error('Exactly seven days required');
  for(const day of weekdays){
    const data=weeklyDay.parse(menu.days[day]);
    await createOnly(`weeklyMenu/${day}`,{...data,verified:true,source:menu.source});
    await createOnly(`originalWeeklyMenu/${day}`,{...data,source:menu.source});
  }
  console.log('Verified English menu imported; original translation retained privately.');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
