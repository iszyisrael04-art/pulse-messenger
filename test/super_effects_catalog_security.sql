begin;
do $$begin
 if (select count(*) from pulse_private.gift_catalog where enabled and sku in ('voltage_dominion','void_rift','solar_overdrive','quantum_cathedral','prism_avalanche','aurora_ascension','gravity_collapse','pulse_supernova'))<>8 then raise exception 'FAIL super effects missing';end if;
 if exists(select 1 from pulse_private.gift_catalog where enabled and sku in ('lion','butterfly','dream','phoenix','dragon','sports_car','gorilla','royal_lions','pulse_stars','thunder_falcon')) then raise exception 'FAIL retired animals or old scenes enabled';end if;
 if not exists(select 1 from pulse_private.gift_catalog where sku='galaxy' and enabled and title='Pulse Universe' and coins=2500) then raise exception 'FAIL Pulse Universe changed';end if;
 if exists(select 1 from pulse_private.gift_catalog where sku in ('voltage_dominion','void_rift','solar_overdrive','quantum_cathedral','prism_avalanche','aurora_ascension','gravity_collapse','pulse_supernova') and (coins<29999 or p_coins<>coins*.05)) then raise exception 'FAIL effect pricing';end if;
 if (select p_coins from pulse_private.gift_catalog where sku='rose')<>.5 then raise exception 'FAIL old gifting economy changed';end if;
end $$;
rollback;
