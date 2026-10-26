/// Presentation-only grouping. Each paid +1 remains its own server transaction.
class PulseGiftComboFeed {
 final _groups = <String, ({DateTime at, int quantity, String id})>{};
 Map<String,dynamic> add(Map<String,dynamic> event) {
  final at=DateTime.tryParse(event['created_at']?.toString()??'');
  if(at==null)return event;
  final key='${event['sender_id']}:${event['recipient_id']}:${event['sku']}:${event['is_test']}';
  final previous=_groups[key];
  final quantity=(event['quantity'] as num? ?? 1).toInt();
  final continued=previous!=null && !at.isBefore(previous.at) && at.difference(previous.at).inMilliseconds<=12000;
  final group=(at:at, quantity:quantity+(continued?previous!.quantity:0), id:continued?previous!.id:event['id'].toString());
  if(_groups.length>=256 && !_groups.containsKey(key))_groups.remove(_groups.keys.first);
  _groups[key]=group;
  return {...event,'combo_quantity':group.quantity,'combo_id':group.id};
 }
}
