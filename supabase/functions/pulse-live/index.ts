import { createClient } from 'npm:@supabase/supabase-js@2.99.1';

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {status, headers: {'Content-Type':'application/json'}});
const encode = (value: unknown) => {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  return btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
};
async function sign(key: string, secret: string, identity: string, video: Record<string, unknown>) {
  const now = Math.floor(Date.now()/1000);
  const head = encode({alg:'HS256',typ:'JWT'});
  const body = encode({iss:key,sub:identity,nbf:now-5,exp:now+300,video});
  const cryptoKey = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), {name:'HMAC',hash:'SHA-256'}, false, ['sign']);
  const signature = new Uint8Array(await crypto.subtle.sign('HMAC',cryptoKey,new TextEncoder().encode(`${head}.${body}`)));
  const tail = btoa(String.fromCharCode(...signature)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
  return `${head}.${body}.${tail}`;
}
Deno.serve(async req => {
  if (req.method !== 'POST') return json({error:'POST required'},405);
  const authorization = req.headers.get('Authorization') ?? '';
  if (!authorization.startsWith('Bearer ')) return json({error:'Sign in required'},401);
  const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {global:{headers:{Authorization:authorization}},auth:{persistSession:false}});
  // Custom authentication is deliberate: validate the caller with Auth, not JWT decoding.
  const {data:{user},error:authError} = await client.auth.getUser(authorization.slice(7));
  if (authError || !user) return json({error:'Sign in required'},401);
  const url = Deno.env.get('LIVEKIT_URL'), key = Deno.env.get('LIVEKIT_API_KEY'), secret = Deno.env.get('LIVEKIT_API_SECRET');
  if (!url || !key || !secret) return json({error:'Live broadcasting requires LiveKit configuration.'},503);
  if (!url.startsWith('wss://')) return json({error:'Invalid live service configuration'},503);
  try {
    const body = await req.json();
    let sessionId: string;
    if (body.action === 'start') {
      if (typeof body.title !== 'string' || !body.title.trim() || body.title.length > 100) return json({error:'Invalid title'},400);
      const {data,error} = await client.rpc('pulse_live_start',{p_channel:body.channel_id,p_title:body.title});
      if (error) return json({error:error.message},403);
      sessionId = data;
    } else if (body.action === 'join' || body.action === 'end') {
      sessionId = body.session_id;
    } else return json({error:'Unknown action'},400);
    if (typeof sessionId !== 'string' || !/^[0-9a-f-]{36}$/i.test(sessionId)) return json({error:'Invalid session'},400);
    const {data:session,error} = await client.from('pulse_live_sessions').select('*').eq('id',sessionId).single();
    if (error || !session) return json({error:'Live session unavailable'},404);
    const {data:admin,error:adminError} = await client.rpc('pulse_channel_admin',{p_channel:session.channel_id});
    if (adminError) return json({error:'Authorization unavailable'},503);
    const room = `pulse-channel-${sessionId}`;
    if (body.action === 'end') {
      if (session.host_id !== user.id && admin !== true) return json({error:'Administrator required'},403);
      const token = await sign(key,secret,user.id,{room,roomAdmin:true});
      const endpoint = url.replace('wss://','https://').replace(/\/$/,'')+'/twirp/livekit.RoomService/DeleteRoom';
      const result = await fetch(endpoint,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({room})});
      if (!result.ok && result.status !== 404) return json({error:'Could not stop live room. Please retry.'},502);
      const {error:endError} = await client.rpc('pulse_live_end',{p_session:sessionId});
      if (endError) return json({error:'Could not close live session'},502);
      return json({ended:true});
    }
    if (session.status !== 'live' || Date.parse(session.expires_at) <= Date.now()) return json({error:'This livestream has ended'},409);
    const host = session.host_id === user.id && admin === true;
    const token = await sign(key,secret,user.id,{room,roomJoin:true,canSubscribe:true,canPublish:host,canPublishData:false});
    return json({url,token,session_id:sessionId,host});
  } catch (_) { return json({error:'Could not complete live request'},400); }
});
