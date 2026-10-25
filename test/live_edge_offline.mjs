import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {stripTypeScriptTypes} from 'node:module';
import {webcrypto} from 'node:crypto';
const session='00000000-0000-4000-8000-000000000001';
const host='00000000-0000-4000-8000-000000000002';
const guest='00000000-0000-4000-8000-000000000003';
let personal=true;
let actor=guest, admin=false, state='pending', active=true, signedIn=true, configured=true, probeLimited=false;
const calls=[];
const client={auth:{getUser:async(token)=>({data:{user:signedIn&&token==='valid'?{id:actor}:null},error:null})},
 rpc:async(name,args={})=>{
  if(name==='pulse_personal_live')return {data:{session:{id:session}},error:null};
  if(name==='pulse_live_probe')return{data:null,error:probeLimited?{message:'Too many checks'}:null};
  if(name==='pulse_account_status')return{data:{active},error:null};
  if(name==='pulse_live_moderator')return{data:admin,error:null};
  if(name==='pulse_live_end')return{data:null,error:null};
  if(name==='pulse_live_party'){
   const target=args.p_user??actor;
   if(args.p_action==='access'){
    if(target!==actor&&!admin)return{data:null,error:{message:'Own access only'}};
    return{data:{watch:active,publish:target===host||state==='approved',mode:target===host?'video':'audio'},error:null};
   }
   if(['approve','remove','reject'].includes(args.p_action)&&!admin)return{data:null,error:{message:'Administrator required'}};
   if(args.p_action==='approve')state='approved';
   if(['remove','leave','reject'].includes(args.p_action))state='removed';
   return{data:{saved:true},error:null};
  }
  return{data:null,error:{message:'Unexpected RPC'}};
 },from:()=>({select:()=>({eq:()=>({single:async()=>({data:{id:session,channel_id:personal?null:session,host_id:host,status:'live',expires_at:new Date(Date.now()+60000).toISOString()},error:null})})})})};
let handler;
const source=fs.readFileSync(new URL('../supabase/functions/pulse-live/index.ts',import.meta.url),'utf8').replace(/^import .*\n/,'');
const context=vm.createContext({createClient:()=>client,Deno:{env:{get:(key)=>({SUPABASE_URL:'https://example.invalid',SUPABASE_ANON_KEY:'public',LIVEKIT_URL:'wss://live.example.invalid',LIVEKIT_API_KEY:'public-live-key',LIVEKIT_API_SECRET:'fixture-server-secret'})[key] && (configured || !key.startsWith('LIVEKIT_')) ? ({SUPABASE_URL:'https://example.invalid',SUPABASE_ANON_KEY:'public',LIVEKIT_URL:'wss://live.example.invalid',LIVEKIT_API_KEY:'public-live-key',LIVEKIT_API_SECRET:'fixture-server-secret'})[key] : undefined},serve:f=>handler=f},TextEncoder,Response,Request,AbortSignal,btoa,crypto:webcrypto,fetch:async(url,options)=>{calls.push({url,payload:JSON.parse(options.body)});return new Response(JSON.stringify(url.endsWith('ListParticipants')?{participants:[]}:{}),{status:200});}});
vm.runInContext(stripTypeScriptTypes(source,{mode:'strip'}),context);
async function request(body){const r=await handler(new Request('https://edge.example.invalid',{method:'POST',headers:{Authorization:'Bearer valid','Content-Type':'application/json'},body:JSON.stringify({session_id:session,party_version:1,...body})}));return{status:r.status,data:await r.json()};}
let r=await request({action:'join'});
assert.equal(r.status,200);
let claims=JSON.parse(Buffer.from(r.data.token.split('.')[1],'base64url').toString());
assert.equal(claims.video.canPublish,false,'viewers never get publisher JWTs');
r=await request({action:'party',party_action:'approve',user_id:guest});assert.equal(r.status,403);assert.equal(calls.length,0);
actor=host;admin=true;
r=await request({action:'join'});claims=JSON.parse(Buffer.from(r.data.token.split('.')[1],'base64url').toString());assert.equal(claims.video.canPublish,false,'host also uses server-side grants');
r=await request({action:'party',party_action:'approve',user_id:guest});assert.equal(r.status,200);assert.equal(calls.at(-1).payload.identity,guest);assert.equal(calls.at(-1).payload.permission.canPublish,true);assert.deepEqual(calls.at(-1).payload.permission.canPublishSources,[2]);
r=await request({action:'party',party_action:'remove',user_id:guest});assert.equal(r.status,200);assert.equal(calls.at(-1).payload.permission.canPublish,false,'remove revokes publishing on LiveKit');
actor=guest;admin=false;
r=await request({action:'party-sync'});assert.equal(r.status,200);assert.equal(r.data.publish,false);assert.equal(calls.at(-1).payload.permission.canPublish,false);
actor=host;admin=true;r=await request({action:'join',party_version:0});claims=JSON.parse(Buffer.from(r.data.token.split('.')[1],'base64url').toString());assert.equal(claims.video.canPublish,true,'legacy hosts remain compatible');
actor=guest;admin=false;r=await request({action:'join',party_version:0});claims=JSON.parse(Buffer.from(r.data.token.split('.')[1],'base64url').toString());assert.equal(claims.video.canPublish,false,'legacy flag never elevates viewers');
active=false;r=await request({action:'join'});assert.equal(r.status,403);
active=true;signedIn=false;r=await request({action:'join'});assert.equal(r.status,401);
console.log('TEST PASS live_edge_offline: read-only JWTs, staff/host authorization, audio-only grants, removal, restricted accounts');

signedIn=true;active=true;actor=guest;admin=false;configured=true;probeLimited=false;
r=await request({action:'health'});assert.equal(r.status,200);assert.deepEqual(r.data,{configured:true,control_plane:true,media_tested:false});assert.ok(!JSON.stringify(r.data).includes('fixture-server-secret'));
probeLimited=true;r=await request({action:'health'});assert.equal(r.status,429);probeLimited=false;
configured=false;r=await request({action:'health'});assert.equal(r.status,503);assert.equal(r.data.code,'not_configured');assert.equal(r.data.media_tested,false);configured=true;
signedIn=false;r=await request({action:'health'});assert.equal(r.status,401);
console.log('TEST PASS live health: authenticated, rate limited, no secret exposure, control API only');

signedIn=true;personal=true;actor=host;admin=true;
r=await request({action:'start',kind:'personal',title:'Personal LIVE'});assert.equal(r.status,200);assert.equal(r.data.host,true);
claims=JSON.parse(Buffer.from(r.data.token.split('.')[1],'base64url').toString());assert.equal(claims.video.room,`pulse-user-${session}`);
actor=guest;admin=false;r=await request({action:'end'});assert.equal(r.status,403);
r=await request({action:'join'});assert.equal(r.status,200);assert.equal(r.data.host,false);
console.log('TEST PASS personal LIVE room isolation and host-only end');

personal=false;actor=host;admin=true;r=await request({action:'join'});assert.equal(r.status,410);r=await request({action:'start',kind:'channel',channel_id:session,title:'Not allowed'});assert.equal(r.status,410);console.log('TEST PASS channel LIVE blocked');
