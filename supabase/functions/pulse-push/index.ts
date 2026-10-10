import { createClient } from 'npm:@supabase/supabase-js@2.99.1';
const json = (body:unknown,status=200) => new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
const b64 = (bytes:Uint8Array) => btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
const encode = (body:unknown) => b64(new TextEncoder().encode(JSON.stringify(body)));
async function googleToken(account:Record<string,string>) {
 const now=Math.floor(Date.now()/1000);
 const payload=encode({iss:account.client_email,scope:'https://www.googleapis.com/auth/firebase.messaging',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600});
 const head=encode({alg:'RS256',typ:'JWT'});
 const pem=account.private_key.replace(/-----[^-]+-----/g,'').replace(/\s/g,'');
 const key=await crypto.subtle.importKey('pkcs8',Uint8Array.from(atob(pem),c=>c.charCodeAt(0)),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
 const signature=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,new TextEncoder().encode(`${head}.${payload}`));
 const response=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:`${head}.${payload}.${b64(new Uint8Array(signature))}`})});
 if(!response.ok)throw new Error('Google authentication failed');
 return (await response.json()).access_token as string;
}
Deno.serve(async req=>{
 if(req.method!=='POST')return json({error:'POST required'},405);
 const expected=Deno.env.get('PUSH_DISPATCH_SECRET');
 const authorization=req.headers.get('Authorization')??'';
 if(!expected||authorization!==`Bearer ${expected}`)return json({error:'Unauthorized'},401);
 const config=Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
 if(!config)return json({error:'Firebase service account not configured'},503);
 try{
  const account=JSON.parse(config);
  const token=await googleToken(account);
  const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
  const {data:jobs,error}=await db.rpc('pulse_push_claim');
  if(error)throw error;
  let completed=0;
  for(const job of jobs??[]){
   let success=true;
   const {data:allowed,error:eligibilityError}=await db.rpc('pulse_push_allowed',{p_message:job.message_id,p_recipient:job.recipient_id});
   if(eligibilityError)success=false;
   if(allowed===true){
    for(const device of job.tokens){
     try{
      const response=await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({message:{token:device,notification:{title:'Pulse Messenger',body:'You have a new message.'},data:{message_id:job.message_id},android:{priority:'high',notification:{channel_id:'pulse_messages',tag:job.message_id,icon:'ic_pulse_notification'}}}})});
      if(!response.ok){
       const detail=await response.json();
       const unregistered=detail?.error?.details?.some((d:{errorCode?:string})=>d.errorCode==='UNREGISTERED');
       if(unregistered)await db.rpc('pulse_push_invalid',{p_token:device});else success=false;
      }
     }catch(_){success=false;}
    }
   }
   const {error:finishError}=await db.rpc('pulse_push_finish',{p_id:job.id,p_success:success});
   if(!finishError&&success)completed++;
  }
  return json({claimed:jobs?.length??0,completed});
 }catch(_){return json({error:'Push dispatcher failed. Check service configuration.'},502);}
});
