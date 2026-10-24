import {initializeApp} from 'firebase/app';
import {initializeAppCheck,ReCaptchaEnterpriseProvider} from 'firebase/app-check';
import {getAuth,GoogleAuthProvider,signInWithPopup,signOut,onAuthStateChanged} from 'firebase/auth';
import {getFirestore,collection,query,limit,onSnapshot,orderBy,doc,getDoc} from 'firebase/firestore';
import {getFunctions,httpsCallable} from 'firebase/functions';
import './style.css';
const root=document.querySelector('#app');
function el(tag,text,attrs={}){const e=document.createElement(tag);if(text)e.textContent=text;Object.assign(e,attrs);return e;}
function button(text,action){const b=el('button',text);b.onclick=async()=>{b.disabled=true;try{await action();}catch(e){message(e.message,true);}finally{b.disabled=false;}};return b;}
function message(text,error=false){document.querySelector('#notice')?.remove();const n=el('p',text,{id:'notice',className:error?'notice error':'notice'});root.prepend(n);}
const env=import.meta.env;
if(!env.VITE_FIREBASE_API_KEY||!env.VITE_RECAPTCHA_ENTERPRISE_SITE_KEY){root.append(el('h1','Hostel Connect Administration'),el('p','Configure admin/.env from .env.example, then rebuild. Administrator access requires a provisioned Google account and App Check.'));}
else{
 initializeApp({apiKey:env.VITE_FIREBASE_API_KEY,authDomain:env.VITE_FIREBASE_AUTH_DOMAIN,projectId:env.VITE_FIREBASE_PROJECT_ID,appId:env.VITE_FIREBASE_APP_ID});
 initializeAppCheck(undefined,{provider:new ReCaptchaEnterpriseProvider(env.VITE_RECAPTCHA_ENTERPRISE_SITE_KEY),isTokenAutoRefreshEnabled:true});
 const auth=getAuth(),db=getFirestore(),call=httpsCallable(getFunctions(undefined,'asia-south1'),'api');
 const mutate=async(action,payload)=>{await call({action,payload});message('Saved.');};
 let unsubscribe;
 function field(form,label,value='',type='input'){const l=el('label',label),input=el(type);input.value=value;l.append(input);form.append(l);return input;}
 function reason(){const v=prompt('Reason for the audit record (at least 5 characters):');if(!v||v.trim().length<5)throw Error('A meaningful reason is required.');return v.trim();}
 function rows(col,render){unsubscribe?.();const content=document.querySelector('#content');content.replaceChildren(el('p','Loading…'));unsubscribe=onSnapshot(query(collection(db,col),orderBy(col==='machines'||col==='sportsEquipment'?'buildingId':col==='weeklyMenu'?'__name__':'createdAt','desc'),limit(200)),s=>{content.replaceChildren();if(s.empty)content.append(el('p','No records yet.'));s.docs.forEach(d=>render(content,d.id,d.data()));},e=>message(e.message,true));}
 function inventory(kind){rows(kind==='laundry'?'machines':'sportsEquipment',(c,id,d)=>{const card=el('article');card.append(el('h2',id),el('p',`Status: ${d.status}`));const actions=el('div','',{className:'actions'});for(const status of ['available','outOfService'])actions.append(button(status==='available'?'Release / mark available':'Mark out of service',()=>mutate('adminStatus',{kind,resourceId:id,status,reason:reason()})));card.append(actions);c.append(card);});}
 function reports(col){rows(col,(c,id,d)=>{const card=el('article');card.append(el('h2',d.reason),el('p',`Status: ${d.status}`),el('p',d.description||'No description'),el('pre',JSON.stringify(d,null,2)));const actions=el('div','',{className:'actions'});if(d.status==='pending'){for(const decision of ['resolved','dismissed'])actions.append(button(decision,()=>mutate('resolveReport',{collection:col,reportId:id,decision,reason:reason()})));if(col==='messageReports')actions.append(button('Remove message / restrict account',async()=>{const hours=Number(prompt('Restriction duration in hours (0 removes only; max 720):','0'));if(!Number.isInteger(hours))throw Error('Use a whole number.');await mutate('moderateMessage',{messageId:d.messageId,restrictHours:hours,reason:reason()});}));}card.append(actions);c.append(card);});}
 function suggestions(){rows('menuSuggestions',(c,id,d)=>{const card=el('article');card.append(el('h2',`${d.date} · ${d.mealType}`),el('p',d.items.join(' · ')),el('p',d.reason),el('p',d.status));if(d.status==='pending'){const actions=el('div','',{className:'actions'});for(const approve of [true,false])actions.append(button(approve?'Approve':'Reject',()=>mutate('reviewMenu',{suggestionId:id,approve,reason:reason()})));card.append(actions);}c.append(card);});}
 function weekly(){
  unsubscribe?.();const c=document.querySelector('#content');c.replaceChildren();const card=el('article');
  card.append(el('h2','Revise the official weekly menu'),el('p','Use only officially verified English items. Revisions are preserved in history.'));
  const day=field(card,'Day','Monday','select');for(const d of ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'])day.append(el('option',d,{value:d}));
  const fields={};for(const meal of ['breakfast','lunch','snacks','dinner'])fields[meal]=field(card,`${meal} (one item per line)`,'','textarea');
  const save=button('Publish official revision',()=>mutate('editWeeklyMenu',{day:day.value,menu:Object.fromEntries(Object.entries(fields).map(([k,v])=>[k,v.value.split('\n').map(s=>s.trim()).filter(Boolean)])),reason:reason()}));
  const load=async()=>{save.disabled=true;const selected=day.value;try{const current=await getDoc(doc(db,'weeklyMenu',selected));if(day.value!==selected)return;for(const [meal,input]of Object.entries(fields))input.value=(current.data()?.[meal]??[]).join('\n');save.disabled=false;}catch(e){message(e.message,true);}};
  day.onchange=load;card.append(save);c.append(card);load();
 }
 function history(){rows('auditRecords',(c,id,d)=>{const card=el('article');card.append(el('h2',d.action),el('pre',JSON.stringify(d,null,2)));c.append(card);});}
 onAuthStateChanged(auth,async user=>{unsubscribe?.();root.replaceChildren();const header=el('header');header.append(el('h1','Hostel Connect · Admin'));root.append(header);
  if(!user){root.append(el('p','Sign in with your provisioned administrator Google account.'),button('Sign in with Google',()=>signInWithPopup(auth,new GoogleAuthProvider())));return;}
  header.append(button('Sign out',()=>signOut(auth)));
  try{const token=await user.getIdTokenResult(true);if(token.claims.admin!==true||user.isAnonymous){message('This account has no administrator privilege. Ask the project owner to provision access.',true);return;}
  const nav=el('nav');for(const [label,action] of [['Laundry',()=>inventory('laundry')],['Laundry reports',()=>reports('machineReports')],['Games',()=>inventory('sports')],['Games reports',()=>reports('sportsReports')],['Menu suggestions',suggestions],['Weekly menu',weekly],['Chat reports',()=>reports('messageReports')],['Audit history',history]])nav.append(button(label,action));root.append(nav,el('section','',{id:'content'}));inventory('laundry');}catch(e){message(e.message,true);}
 });
}
