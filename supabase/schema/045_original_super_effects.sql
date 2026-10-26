-- Retain historical gift events and balances. Retired SKUs cannot be sent again.
begin;
update pulse_private.gift_catalog set enabled=false
 where sku in ('lion','butterfly','dream','phoenix','dragon','sports_car','gorilla','royal_lions','pulse_stars','thunder_falcon');
insert into pulse_private.gift_catalog(sku,title,emoji,coins,p_coins,enabled) values
('voltage_dominion','Voltage Dominion','',29999,1499.95,true),
('void_rift','Void Rift','',34999,1749.95,true),
('solar_overdrive','Solar Overdrive','',39999,1999.95,true),
('quantum_cathedral','Quantum Cathedral','',49999,2499.95,true),
('prism_avalanche','Prism Avalanche','',59999,2999.95,true),
('aurora_ascension','Aurora Ascension','',69999,3499.95,true),
('gravity_collapse','Gravity Collapse','',79999,3999.95,true),
('pulse_supernova','Pulse Supernova','',99999,4999.95,true)
on conflict(sku) do nothing;
commit;
