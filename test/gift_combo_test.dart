import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/repository.dart' hide Row;
import '../lib/live_gifts.dart';
class GiftOfflineClient implements SupabaseClient {
 @override dynamic noSuchMethod(Invocation i)=>throw StateError('Unexpected SDK access');
}
class GiftRepo extends PulseRepository {
 GiftRepo():super(GiftOfflineClient());
 @override String get uid=>'viewer';
 int coins=100;bool loseAcknowledgement=true;
 final ids=<String>{};final requests=<Map<String,dynamic>>[];
 @override Future<dynamic> rpc(String name,Map<String,dynamic> p)async{
  if(name=='gift_feed')return {'items':[],'after':'2026-10-26T00:00:00Z','cursor':'cursor'};
  if(name=='test_wallet')return {'coins':0};
  if(name=='wallet')return {'coins':coins};
  if(name=='live_battle')return {'state':'none'};
  if(name=='live_party')return {'host':{'user_id':'host','display_name':'Host'},'members':[]};
  if(name=='live_gifts'&&p['p_action']=='info')return {'gifts':[],'recent':[]};
  if(name=='live_gifts'){
   requests.add(Map.from(p));expect(p['p_quantity'],1);
   if(ids.add(p['p_id'] as String))coins-=10;
   if(loseAcknowledgement){loseAcknowledgement=false;throw StateError('Lost response');}
   return {};
  }
  throw StateError('Unexpected RPC $name');
 }
}
void main(){
 testWidgets('Lost send acknowledgement retries once without another debit; combo creates one new unit',(tester)async{
  final repo=GiftRepo();final key=GlobalKey<PulseLiveGiftsState>();
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:PulseLiveGifts(key:key,repo:repo,session:'live',host:false,compact:true))));
  await tester.pump();
  const gift={'sku':'rose','title':'Rose','coins':10,'recipient':'host'};
  await key.currentState!.sendOne(gift,test:false);await tester.pump();
  expect(repo.coins,90);expect(key.currentState!.pendingGift,isNotNull);
  await key.currentState!.sendOne(gift,test:false);expect(repo.requests.length,1);
  await key.currentState!.sendPending();await tester.pump();
  expect(repo.coins,90);expect(repo.requests[0]['p_id'],repo.requests[1]['p_id']);
  expect(key.currentState!.comboCount,1);expect(find.byType(AlertDialog),findsNothing);
  await tester.tap(find.textContaining('+1 · 10 coins'));await tester.pump();await tester.pump();
  expect(repo.coins,80);expect(repo.ids.length,2);expect(key.currentState!.comboCount,2);
  expect(repo.requests.last['p_quantity'],1);
  await tester.pumpWidget(const SizedBox());await tester.pump(const Duration(seconds:5));
 });
}
