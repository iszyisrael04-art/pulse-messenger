// Public credential exchange; auth and throttling are implemented here.
import {createClient} from 'npm:@supabase/supabase-js@2.99.1';
const json=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
Deno.serve(async req=>{
  if(req.method!=='POST')return json({error:'Method not allowed'},405);
  if(Number(req.headers.get('content-length')||0)>4096)return json({error:'Request too large'},413);
  try {
    const raw=await req.text();
    if(raw.length>4096)return json({error:'Request too large'},413);
    const {username,password}=JSON.parse(raw);
    if(typeof username!=='string'||typeof password!=='string'||!(/^[a-z][a-z0-9_]{2,23}$/.test(username))||password.length>256)return json({error:'Invalid credentials'},401);
    const url=Deno.env.get('SUPABASE_URL')!;
    const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
    // Username-wide limit prevents bypassing throttling with spoofed client IPs.
    const key=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode('pulse-login:'+username)))).map(x=>x.toString(16).padStart(2,'0')).join('');
    const {data:email,error}=await admin.rpc('pulse_login_lookup',{p_username:username,p_key:key});
    if(error||!email)return json({error:'Invalid credentials or too many attempts. Try again later.'},401);
    const auth=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
    const result=await auth.auth.signInWithPassword({email,password});
    if(result.error||!result.data.session)return json({error:'Invalid credentials or too many attempts. Try again later.'},401);
    return json({access_token:result.data.session.access_token,refresh_token:result.data.session.refresh_token});
  }catch{return json({error:'Unable to sign in'},400);}
});
