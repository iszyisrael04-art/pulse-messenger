import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/gift_assets.dart';
import '../lib/gift_visuals.dart';
import '../lib/gifter_ranks.dart';
void main(){
 test('Only allowlisted wildlife gifts priced at least 300 can play video',(){
  for(final sku in ['rose','heart','crown','wizard_filter','galaxy','untrusted']){
   expect(pulseGiftHasVideo({'sku':sku,'coins':10,'quantity':100}),false);
  }
  expect(pulseGiftHasVideo({'sku':'lion','coins':299}),false);
  expect(pulseGiftHasVideo({'sku':'lion','coins':300}),true);
  expect(pulseGiftHasVideo({'sku':'lion'}),true);
  expect(pulseGiftHasVideo({'sku':'https://evil.test/video','coins':99999}),false);
 });
 testWidgets('Small-screen notification includes sender, gift image and count without overflow',(tester)async{
  tester.view.physicalSize=const Size(320,568);tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PulseGiftNotice(
   name:'A very long sender name',title:'Rose',quantity:7,avatar:CircleAvatar(child:Text('A')),gift:PulseGiftModel(sku:'rose'),
  ))));
  expect(find.text('Sent Rose'),findsOneWidget);expect(find.text('×7'),findsOneWidget);
  expect(find.byType(PulseGiftModel),findsOneWidget);expect(tester.takeException(),isNull);
 });
 testWidgets('Ten earned rank badges remain available',(tester)async{
  for(var rank=1;rank<=10;rank++){
   await tester.pumpWidget(MaterialApp(home:PulseRankBadge(rank:rank,size:100,label:true)));
   expect(find.text(pulseGifterNames[rank]),findsOneWidget);
  }
 });
}
