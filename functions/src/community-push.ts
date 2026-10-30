import {getFirestore} from 'firebase-admin/firestore';
import {getMessaging} from 'firebase-admin/messaging';
import {onDocumentCreated} from 'firebase-functions/v2/firestore';

// Requires Blaze deployment. This sends only Community messages, never games.
// Claim before FCM to avoid duplicate attempts after a trigger retry; uncertain
// handoffs are not retried. FCM delivery is best effort, not exactly once.
export const communityMessagePush = onDocumentCreated({document:'chatMessages/{id}',region:'asia-south1',retry:false}, async event => {
  const message=event.data?.data();
  if (!message || message.deleted || message.moderated || !/^[a-f0-9-]{36}$/.test(message.senderKey)) return;
  const db=getFirestore();
  const claimed=await db.runTransaction(async t=>{
    const claim=db.doc(`communityPushDeliveries/${event.params.id}`);
    const [existing,userReports,messageReports]=await t.getAll(claim,db.doc(`communityModeration/u_${message.senderKey}`),db.doc(`communityModeration/m_${event.params.id}`));
    if(existing.exists || (userReports.get('count')??0)>=6 || (messageReports.get('count')??0)>=6)return false;
    t.create(claim,{status:'claimed',createdAt:new Date()});return true;
  });
  if(!claimed)return;
  const claim=db.doc(`communityPushDeliveries/${event.params.id}`);
  try {
    await getMessaging().send({condition:`'myhostel_community' in topics && !('myhostel_sender_${message.senderKey}' in topics)`,
      notification:{title:`${message.displayName} · myHostel`,body:String(message.content).slice(0,180)},
      data:{route:'/community',messageId:event.params.id},
      android:{priority:'high',notification:{channelId:'community_messages',icon:'ic_notification',tag:event.params.id}},
      apns:{payload:{aps:{sound:'default'}}}});
    await claim.update({status:'sent'});
  }catch{await claim.update({status:'deliveryUncertain'});}
});
