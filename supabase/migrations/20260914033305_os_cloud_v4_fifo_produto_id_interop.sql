-- OS Cloud V4 - interoperabilidade de composicao FIFO.
--
-- A RPC imperium_os_produtos_publicar_v4 consolidada na migration principal
-- resolve cada composicao pelo campo produto_id quando disponivel e usa
-- (origem_dispositivo, produto_origem_local_id) apenas como fallback.
--
-- Isso cobre o fluxo:
--   produto criado no Web -> sincronizado no Android -> finalizado no Android.
--
-- Version marker do hardening aplicado no Supabase:
--   v_produto_id := public.imperium_os_produto_resolver_v4(
--     p_empresa_id,
--     p_ordem_servico_id,
--     nullif(v_lote->>'produto_id','')::uuid,
--     p_origem_dispositivo,
--     v_origem_local_id
--   );
do $$
begin
  if to_regprocedure(
    'public.imperium_os_produto_resolver_v4(uuid,uuid,uuid,text,bigint)'
  ) is null then
    raise exception 'Resolver FIFO V4 ausente.';
  end if;
end;
$$;
