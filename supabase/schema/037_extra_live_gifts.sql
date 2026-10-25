-- Additive gift catalogue. Existing prices and balances unchanged.
begin;
insert into pulse_private.gift_catalog(sku,title,emoji,coins,p_coins,enabled) values
('pearl','Moon Pearl','',25,10,true),
('butterfly','Aurora Butterfly','',50,20,true),
('fireworks','Celebration Fireworks','',100,40,true),
('trophy','Champion Trophy','',250,100,true),
('saturn','Celestial Saturn','',500,200,true),
('castle','Crystal Castle','',1000,400,true)
on conflict(sku)do nothing;
commit;
