import 'package:flutter_test/flutter_test.dart';
import '../lib/gift_combo_feed.dart';
void main(){
 test('Only the same sender, recipient, gift and wallet type group within 12 seconds',(){
  final feed=PulseGiftComboFeed();
  Map<String,dynamic> e(int second,{String sku='rose',String to='host',bool test=false})=>{'id':'$second:$sku:$to:$test','sender_id':'sender','recipient_id':to,'sku':sku,'quantity':1,'is_test':test,'created_at':DateTime.utc(2026,10,26,0,0,second).toIso8601String()};
  final first=feed.add(e(0));final second=feed.add(e(1));
  expect(second['combo_quantity'],2);expect(second['combo_id'],first['combo_id']);
  expect(feed.add(e(2,to:'guest'))['combo_quantity'],1);
  expect(feed.add(e(3,sku:'heart'))['combo_quantity'],1);
  expect(feed.add(e(4,test:true))['combo_quantity'],1);
  expect(feed.add(e(20))['combo_quantity'],1);
 });
}
