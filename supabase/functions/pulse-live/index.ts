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
  const {data:{user},error:authError} = await client.auth.getUser(authorization.slice(7));
  if (authError || !user) return json({error:'Sign in required'},401);
  const {data:account,error:accountError} = await client.rpc('pulse_account_status');
  if (accountError || account?.active !== true) return json({error:'An active Pulse account is required.'},403);
  const url = Deno.env.get('LIVEKIT_URL'), key = Deno.env.get('LIVEKIT_API_KEY'), secret = Deno.env.get('LIVEKIT_API_SECRET');
  if (!url || !key || !secret || !url.startsWith('wss://')) return json({error:'Live broadcasting requires LiveKit configuration.',code:'not_configured',configured:false,media_tested:false},503);
  try {
    const body = await req.json();
    if(body.action==='health') {
      const {error:probeError}=await client.rpc('pulse_live_probe');
      if(probeError)return json({error:'Please wait before checking again.',code:'rate_limited',media_tested:false},429);
      const probeToken=await sign(key,secret,user.id,{roomList:true});
      const response=await fetch(url.replace('wss://','https://').replace(/\/$/,'')+'/twirp/livekit.RoomService/ListRooms',{method:'POST',headers:{Authorization:`Bearer ${probeToken}`,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(5000)});
      await response.body?.cancel();
      return response.ok?json({configured:true,control_plane:true,media_tested:false}):json({error:'LiveKit control service did not accept the connection.',configured:true,control_plane:false,media_tested:false},502);
    }
    let sessionId: string;
    if (body.action === 'start') {
      if (typeof body.title !== 'string' || !body.title.trim() || body.title.length > 100) return json({error:'Invalid title'},400);
      if (body.kind !== 'personal' || body.channel_id != null) return json({error:'Channel LIVE has been removed. Go live from your personal account.'},410);
      const {data,error} = await client.rpc('pulse_personal_live',{p_action:'start',p_title:body.title});
      if (error) return json({error:error.message},403);
      sessionId = data?.session?.id;
    } else if (['join','end','party','party-sync'].includes(body.action)) sessionId = body.session_id;
    else return json({error:'Unknown action'},400);
    if (typeof sessionId !== 'string' || !/^[0-9a-f-]{36}$/i.test(sessionId)) return json({error:'Invalid session'},400);
    const {data:session,error} = await client.from('pulse_live_sessions').select('*').eq('id',sessionId).single();
    if (error || !session) return json({error:'Live session unavailable'},404);
    if(session.channel_id != null) return json({error:'Channel LIVE is no longer available.'},410);
    const {data:admin,error:adminError} = await client.rpc('pulse_live_moderator',{p_session:sessionId});
    if (adminError) return json({error:'Authorization unavailable'},503);
    const room = `${session.channel_id == null ? 'pulse-user' : 'pulse-channel'}-${sessionId}`;
    const roomCall = async (method:string, payload:Record<string,unknown>) => {
      const token = await sign(key,secret,user.id,{room,roomAdmin:true,roomList:true});
      return fetch(url.replace('wss://','https://').replace(/\/$/,'')+'/twirp/livekit.RoomService/'+method,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({room,...payload}),signal:AbortSignal.timeout(10000)});
    };
    const access = async (identity:string) => {
      const r = await client.rpc('pulse_live_party',{p_action:'access',p_session:sessionId,p_user:identity});
      if(r.error) throw new Error('Could not verify participant access');
      return r.data;
    };
    const setPermission = async (identity:string, value:Record<string,unknown>, missingAllowed=false) => {
      const response = await roomCall('UpdateParticipant',{identity,permission:{canSubscribe:value.watch===true,canPublish:value.publish===true,canPublishData:false,canPublishSources:value.mode==='audio'?[2]:[1,2]}});
      if(!response.ok && !(missingAllowed && response.status===404)) throw new Error('Could not synchronize media permissions; retry');
    };
    if (body.action === 'end') {
      if (session.host_id !== user.id && admin !== true) return json({error:'Administrator required'},403);
      const {error:endError} = await client.rpc('pulse_live_end',{p_session:sessionId});
      if (endError) return json({error:'Could not close live session'},502);
      let mediaClosed=false;
      try {const result=await roomCall('DeleteRoom',{});mediaClosed=result.ok||result.status===404;} catch(_){}
      return json({ended:true,media_closed:mediaClosed});
    }
    if (session.status !== 'live' || Date.parse(session.expires_at) <= Date.now()) return json({error:'This livestream has ended'},409);
    if (body.action === 'party') {
      const action=body.party_action;
      if(!['request','leave','approve','reject','remove'].includes(action)) return json({error:'Invalid party action'},400);
      const target=action==='leave'||action==='request'?user.id:body.user_id;
      const {error:partyError}=await client.rpc('pulse_live_party',{p_action:action,p_session:sessionId,p_user:target,p_mode:body.mode??'video'});
      if(partyError)return json({error:partyError.message},403);
      if(action!=='request') await setPermission(target,await access(target),true);
      return json({saved:true});
    }
    if (body.action === 'party-sync') {
      const own=await access(user.id);
      await setPermission(user.id,own);
      if(body.reconcile===true && admin===true){
        const response=await roomCall('ListParticipants',{});
        if(!response.ok)throw new Error('Could not reconcile participant permissions');
        const participants=(await response.json()).participants??[];
        // Bound each reconciliation batch. Subsequent cycles cover new participants.
        for(const participant of participants.filter((p:{tracks?:unknown[]})=>(p.tracks?.length??0)>0).slice(0,16)){
          if(participant.identity===user.id)continue;
          await setPermission(participant.identity,await access(participant.identity),true);
        }
      }
      return json(own);
    }
    const host = session.host_id === user.id && admin === true;
    // Modern party clients use server grants; legacy host clients keep their
    // existing broadcast behavior. Viewers never receive publisher JWT grants.
    const legacyHost = host && body.party_version !== 1;
    const token = await sign(key,secret,user.id,{room,roomJoin:true,canSubscribe:true,canPublish:legacyHost,canPublishData:false});
    return json({url,token,session_id:sessionId,host});
  } catch (_) { return json({error:'Could not complete LIVE request or synchronize media permissions. Retry.'},502); }
});
