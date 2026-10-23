import {createClient}from'npm:@supabase/supabase-js@2.99.1';
const json=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
const encode=(value:unknown)=>btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(value)))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
async function accessToken(sa:{client_email:string;private_key:string}){
 const now=Math.floor(Date.now()/1000),head=encode({alg:'RS256',typ:'JWT'}),body=encode({iss:sa.client_email,scope:'https://www.googleapis.com/auth/firebase.messaging',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+600});
 const pem=sa.private_key.replace(/-----[^-]+-----/g,'').replace(/\s/g,'');
 const key=await crypto.subtle.importKey('pkcs8',Uint8Array.from(atob(pem),c=>c.charCodeAt(0)),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
 const sig=new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,new TextEncoder().encode(head+'.'+body)));
 const assertion=head+'.'+body+'.'+btoa(String.fromCharCode(...sig)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
 const r=await fetch('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion}),signal:AbortSignal.timeout(10000)});
 if(!r.ok)throw Error('FCM authentication unavailable');return(await r.json()).access_token;
}
Deno.serve(async(req:Request)=>{
 if(req.method!=='POST')return json({error:'POST required'},405);
 const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!service||req.headers.get('Authorization')!==`Bearer ${service}`)return json({error:'Dispatcher authorization required'},401);
 const raw=Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
 if(!raw)return json({configured:false,error:'Firebase server credentials are not configured'},503);
 try{
 const sa=JSON.parse(raw);
 if(!/^[a-z][a-z0-9-]{4,62}$/.test(sa.project_id))throw Error('Invalid Firebase project');
 const bearer=await accessToken(sa);
 const db=createClient(Deno.env.get('SUPABASE_URL')!,service,{auth:{persistSession:false}});
 const {data:jobs,error}=await db.rpc('pulse_call_push_jobs');if(error)throw error;
 let sent=0;
 for(const job of jobs??[]){
  const ttl=Math.min(45,Math.floor((Date.parse(job.expires_at)-Date.now())/1000));
  if(ttl<=0)continue;
  let successful=true;
  for(const token of job.tokens??[]){
   const r=await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,{method:'POST',headers:{Authorization:`Bearer ${bearer}`,'Content-Type':'application/json'},body:JSON.stringify({message:{token,data:{type:'call',call_id:job.call_id,recipient_id:job.recipient_id,kind:job.kind,expires_at:job.expires_at},android:{priority:'high',ttl:`${ttl}s`,collapse_key:'pulse_call_'+job.call_id}}}),signal:AbortSignal.timeout(8000)});
   if(!r.ok)successful=false;else sent++;
   await r.body?.cancel();
  }
  await db.rpc('pulse_call_push_finish',{p_call:job.call_id,p_user:job.recipient_id,p_done:successful});
 }
 return json({configured:true,sent});
 }catch{return json({error:'Call push dispatch unavailable'},502);}
});
