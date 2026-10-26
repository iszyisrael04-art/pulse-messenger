-- Additions are available through the existing authenticated, server-priced RPC.
do $$
begin
 if (select count(*) from pulse_private.gift_catalog where sku in
   ('dream','phoenix','dragon','sports_car','gorilla','royal_lions','pulse_stars','thunder_falcon') and enabled)<>8 then
  raise exception 'missing cinematic gifts';
 end if;
 if (select title from pulse_private.gift_catalog where sku='galaxy')<>'Pulse Universe' then raise exception 'universe branding';end if;
 if (select coins from pulse_private.gift_catalog where sku='galaxy')<>2500
   or (select coins from pulse_private.gift_catalog where sku='lion')<>5000
   or (select p_coins from pulse_private.gift_catalog where sku='rose')<>0.5 then
  raise exception 'existing economy changed';
 end if;
 if exists(select 1 from pulse_private.gift_catalog where coins<=0 or p_coins<=0 or p_coins>coins) then raise exception 'invalid gift price';end if;
end $$;
