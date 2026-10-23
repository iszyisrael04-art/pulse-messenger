"""Live API test. Requires three disposable fixture users; never use real users.
Fixture creation and deletion are a separate administrator-controlled step.
No tokens or passwords are logged.
"""
import json,os,urllib.request,urllib.error,uuid
from pathlib import Path
CONFIG=json.loads(Path(os.environ['PULSE_CONFIG']).read_text())
FIXTURES=json.loads(Path(os.environ['PULSE_TEST_FIXTURES']).read_text())
URL=CONFIG['SUPABASE_URL']; KEY=CONFIG['SUPABASE_PUBLISHABLE_KEY']
def request(path,data=None,token=None,method=None):
    headers={'apikey':KEY,'Content-Type':'application/json'}
    if token:headers['Authorization']='Bearer '+token
    body=None if data is None else json.dumps(data).encode()
    req=urllib.request.Request(URL+path,data=body,headers=headers,method=method or ('POST' if data is not None else 'GET'))
    try:
        with urllib.request.urlopen(req,timeout=30) as response:
            raw=response.read();return response.status,json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw=e.read();return e.code,json.loads(raw) if raw else None

def require(value,message):
    if not value:raise AssertionError(message)

def rpc(name,data,token):return request('/rest/v1/rpc/pulse_'+name,data,token)

def main():
    tokens={}
    for user in FIXTURES['users']:
        status,result=request('/auth/v1/token?grant_type=password',{'email':user['email'],'password':FIXTURES['password']})
        require(status==200 and result.get('access_token'),'Password login failed')
        tokens[user['name']]=result['access_token']
    print('PASS: password authentication for three disposable users')
    status,_=request('/auth/v1/token?grant_type=password',{'email':FIXTURES['users'][0]['email'],'password':'wrong-password'})
    require(status!=200,'Wrong password accepted')
    alice,bob,outsider=[tokens[k] for k in ['alice','bob','outsider']]
    aid,bid=[next(u['id'] for u in FIXTURES['users'] if u['name']==k) for k in ['alice','bob']]
    username='api_'+aid.replace('-','')[:12]
    status,_=rpc('save_profile',{'p_username':username,'p_name':'API Test Alice','p_bio':'Disposable','p_avatar':None},alice)
    require(status<300,'Profile update failed')
    status,session=request('/functions/v1/pulse-login',{'username':username,'password':FIXTURES['password']})
    require(status==200 and session.get('refresh_token'),'Pulse username login failed')
    status,refreshed=request('/auth/v1/token?grant_type=refresh_token',{'refresh_token':session['refresh_token']})
    require(status==200 and refreshed.get('access_token'),'Session refresh failed')
    status,cid=rpc('start_chat',{'p_users':[bid],'p_name':'Test','p_group':False},alice)
    require(status<300 and isinstance(cid,str),'Chat creation failed')
    mid=str(uuid.uuid4())
    data={'p_id':mid,'p_chat':cid,'p_body':'Integration hello','p_reply':None,'p_attachment':None}
    for _ in range(2):require(rpc('send_message',data,alice)[0]<300,'Send/retry failed')
    status,rows=request('/rest/v1/pulse_messages?chat_id=eq.'+cid,token=bob)
    require(status==200 and len(rows)==1 and rows[0]['body']=='Integration hello','Recipient read/idempotency failed')
    status,rows=request('/rest/v1/pulse_messages?chat_id=eq.'+cid,token=outsider)
    require(status==200 and rows==[],'Outsider read permitted')
    require(rpc('send_message',{**data,'p_id':str(uuid.uuid4())},outsider)[0]>=400,'Outsider send permitted')
    require(rpc('change_message',{'p_id':mid,'p_body':'attack','p_delete':False},bob)[0]>=400,'Recipient edit permitted')
    require(rpc('mark_read',{'p_chat':cid},bob)[0]<300,'Read receipt failed')
    require(rpc('redeem',{'p_code':'30DAYSPULSE'},alice)[0]>=400,'Retired redemption still enabled')
    require(rpc('admin_overview',{},alice)[0]>=400,'Unprivileged admin access accepted')
    require(rpc('block_user',{'p_user':aid,'p_block':True},bob)[0]<300,'Block failed')
    require(rpc('send_message',{**data,'p_id':str(uuid.uuid4())},alice)[0]>=400,'Blocked send accepted')
    print('PASS: wrong-password rejection, username login, refresh, profiles, messaging, retry idempotency, RLS isolation, ownership, read receipt, retired redemption, admin isolation and blocking')

if __name__=='__main__':main()
