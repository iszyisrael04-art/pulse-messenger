// Internal worker. Never deploy this with a public/shared scheduler credential.
import {createClient} from 'npm:@supabase/supabase-js@2.99.1';
const json=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers:{'content-type':'application/json','cache-control':'no-store'}});
Deno.serve(async(req)=>{
 const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!service||req.headers.get('authorization')!==`Bearer ${service}`)return json({error:'Forbidden'},403);
 if(req.method!=='POST')return json({error:'Method not allowed'},405);
 const key=Deno.env.get('BREVO_API_KEY'),sender=Deno.env.get('PULSE_SENDER_EMAIL');
 if(!key||!sender)return json({error:'Server mail credentials are not configured'},503);
 const db=createClient(Deno.env.get('SUPABASE_URL')!,service,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data,error}=await db.rpc('pulse_mail_worker',{p_action:'claim'});
 if(error)return json({error:'Queue unavailable'},503);
 let accepted=0,failed=0;
 for(const job of data as Array<{id:string;recipient:string;subject:string;body:string;video_path:string|null}>){
  let ok=false;
  try{
   let text=job.body;
   if(job.video_path){const {data:link,error:linkError}=await db.storage.from('pulse-appeals').createSignedUrl(job.video_path,3600);if(linkError||!link)throw new Error('Private video unavailable');text+=`\n\nAppeal video (private link expires in one hour): ${link.signedUrl}`;}
   const res=await fetch('https://api.brevo.com/v3/smtp/email',{method:'POST',headers:{'api-key':key,'content-type':'application/json'},body:JSON.stringify({sender:{email:sender,name:'Pulse'},to:[{email:job.recipient}],subject:job.subject,textContent:text}),signal:AbortSignal.timeout(15000)});
   ok=res.ok;await res.body?.cancel();
  }catch{ok=false;}
  await db.rpc('pulse_mail_worker',{p_action:'finish',p_id:job.id,p_ok:ok});
  if(ok)accepted++;else failed++;
 }
 return json({accepted_by_provider:accepted,failed});
});
