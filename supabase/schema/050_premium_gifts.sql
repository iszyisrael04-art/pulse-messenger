begin;
-- Retire old wildlife gifts without deleting historical receipts.
update pulse_private.gift_catalog set enabled=false where sku in ('lion','royal_lions','gorilla','thunder_falcon');
insert into pulse_private.gift_catalog(sku,title,emoji,coins,p_coins,enabled) values
('premium_royal_stallion','Royal Stallion','',30000,1500,true),
('premium_white_tiger','White Tiger','',35000,1750,true),
('premium_fire_dragon','Fire Dragon','',40000,2000,true),
('premium_great_shark','Great Shark','',45000,2250,true)
on conflict(sku) do update set title=excluded.title,coins=excluded.coins,p_coins=excluded.p_coins,enabled=true;
commit;
