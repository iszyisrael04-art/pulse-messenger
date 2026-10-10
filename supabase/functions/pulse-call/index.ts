import { createClient } from 'npm:@supabase/supabase-js@2.99.1';

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: {'Content-Type': 'application/json'} });
const encode = (value: unknown) => btoa(String.fromCharCode(...new TextEncoder().encode(JSON.stringify(value)))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
async function token(key: string, secret: string, identity: string, video: Record<string, unknown>) {
  const now = Math.floor(Date.now()/1000);
  const head = encode({alg:'HS256',typ:'JWT'});
  const body = encode({iss:key,sub:identity,nbf:now-5,exp:now+300,video});
  const k = await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC',k,new TextEncoder().encode(`${head}.${body}`)));
  return `${head}.${body}.${btoa(String.fromCharCode(...sig)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','')}`;
}
Deno.serve(async req => {
  if (req.method !== 'POST') return json({error:'POST required'},405);
  const authorization = req.headers.get('Authorization') ?? '';
  if (!authorization.startsWith('Bearer ')) return json({error:'Sign in required'},401);
  const db = createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:authorization}},auth:{persistSession:false}});
  const {data:{user},error:authError} = await db.auth.getUser(authorization.slice(7));
  if (authError || !user) return json({error:'Sign in required'},401);
  try {
    const body = await req.json();
    if (!['start','accept','join','leave','decline'].includes(body.action)) return json({error:'Unknown action'},400);
    const url = Deno.env.get('LIVEKIT_URL'), key = Deno.env.get('LIVEKIT_API_KEY'), secret = Deno.env.get('LIVEKIT_API_SECRET');
    const configured = !!url?.startsWith('wss://') && !!key && !!secret;
    const leaving = body.action === 'leave' || body.action === 'decline';
    if (!configured && !leaving) return json({error:'Calls require LIVEKIT_URL, LIVEKIT_API_KEY and LIVEKIT_API_SECRET in Supabase Edge Function secrets.'},503);
    let id: string;
    if (body.action === 'start') {
      const {data,error} = await db.rpc('pulse_call_start',{p_chat:body.chat_id,p_kind:body.kind});
      if (error) return json({error:error.message},403);
      id = data;
    } else {
      id = body.call_id;
      if (typeof id !== 'string' || !/^[0-9a-f-]{36}$/i.test(id)) return json({error:'Invalid call'},400);
      if (body.action === 'accept') {
        const {error} = await db.rpc('pulse_call_accept',{p_call:id});
        if (error) return json({error:error.message},403);
      }
      if (leaving) {
        const {error} = await db.rpc('pulse_call_leave',{p_call:id,p_decline:body.action === 'decline'});
        if (error) return json({error:error.message},403);
      }
    }
    const {data:call,error} = await db.rpc('pulse_call_state',{p_call:id,p_touch:!leaving});
    if (error || !call) return json({error:'Call unavailable'},403);
    const room = `pulse-call-${id}`;
    if (leaving) {
      if (configured) {
        const admin = await token(key!,secret!,user.id,{room,roomAdmin:true});
        const method = call.status === 'ended' ? 'DeleteRoom' : 'RemoveParticipant';
        const payload = call.status === 'ended' ? {room} : {room,identity:user.id};
        const response = await fetch(url!.replace('wss://','https://').replace(/\/$/,'')+'/twirp/livekit.RoomService/'+method,{
          method:'POST',headers:{Authorization:`Bearer ${admin}`,'Content-Type':'application/json'},
          body:JSON.stringify(payload),signal:AbortSignal.timeout(10000),
        });
        if (!response.ok && response.status !== 404) return json({error:'Call state updated, but media disconnect needs retry.'},502);
      }
      return json({call,ended:call.status === 'ended'});
    }
    const member = call.members.find((m: {user_id:string,state:string}) => m.user_id === user.id);
    if (call.status === 'ended' || member?.state !== 'joined') return json({error:'Call ended or not accepted'},409);
    const jwt = await token(key!,secret!,user.id,{
      room,roomJoin:true,canSubscribe:true,canPublish:true,canPublishData:false,
      canPublishSources:call.kind === 'voice' ? ['microphone'] : ['microphone','camera'],
    });
    return json({url,token:jwt,call});
  } catch (_) { return json({error:'Call service unavailable. Please retry.'},502); }
});
