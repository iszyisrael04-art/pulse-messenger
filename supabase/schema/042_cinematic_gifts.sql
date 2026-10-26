-- Additive gift types. Preserve all existing balances, prices, payouts and RPC
-- authorization. The existing galaxy gift gains a Pulse-native display title.
begin;
update pulse_private.gift_catalog set title='Pulse Universe' where sku='galaxy';
insert into pulse_private.gift_catalog(sku,title,emoji,coins,p_coins,enabled) values
('dream','Pulse Dream','',25999,1299.95,true),
('phoenix','Solar Phoenix','',25999,1299.95,true),
('dragon','Dragon Flame','',26999,1349.95,true),
('sports_car','Golden Sports Car','',29999,1499.95,true),
('gorilla','Jungle Silverback','',30000,1500,true),
('royal_lions','Royal Lions','',34000,1700,true),
('pulse_stars','Pulse Stars','',39999,1999.95,true),
('thunder_falcon','Thunder Falcon','',39999,1999.95,true)
on conflict(sku) do nothing;
commit;
