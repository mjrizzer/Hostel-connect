const backendRequire=require('node:module').createRequire(require('node:path').resolve(__dirname,'../functions/package.json'));
const {initializeApp}=backendRequire('firebase-admin/app');
const {getAuth}=backendRequire('firebase-admin/auth');
initializeApp({projectId:process.env.GCLOUD_PROJECT});
async function main(){
  const uid=process.argv[2];
  if(!uid || !process.env.GCLOUD_PROJECT) throw Error('Usage: set GCLOUD_PROJECT, then node scripts/grant-admin.cjs FIREBASE_UID');
  const user=await getAuth().getUser(uid);
  if(!user.providerData.some(p=>p.providerId==='google.com') || !user.emailVerified) throw Error('Admin must have a verified Google account.');
  await getAuth().setCustomUserClaims(uid,{...user.customClaims,admin:true});
  console.log('Admin claim assigned. Sign in again to refresh the ID token.');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
