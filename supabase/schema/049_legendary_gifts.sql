begin;
-- Additive catalog update; historical gifts, receipts, balances and RPC guards remain intact.
insert into pulse_private.gift_catalog(sku,title,emoji,coins,p_coins,enabled) values
('legend_lion_king','Lion King','',1000,50.0,true),
('legend_phoenix','Phoenix','',5000,250.0,true),
('legend_thunder_god','Thunder God','',7500,375.0,true),
('legend_phantom_supercar','Phantom Supercar','',10000,500.0,true),
('legend_cosmic_rocket','Cosmic Rocket','',15000,750.0,true),
('legend_royal_palace','Royal Palace','',20000,1000.0,true),
('legend_galaxy_dragon','Galaxy Dragon','',30000,1500.0,true),
('legend_pulse_legend','Pulse Legend','',50000,2500.0,true),
('legend_pulse_universe','Pulse Universe','',60000,3000.0,true)
on conflict(sku) do update set title=excluded.title,coins=excluded.coins,p_coins=excluded.p_coins,enabled=true;
commit;
