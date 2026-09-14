-- OS Cloud V4 - produtos imutaveis depois de finalizacao Web.
--
-- A funcao imperium_os_produtos_publicar_v4 da migration principal deste
-- repositorio ja representa o estado final endurecido. Este version marker
-- espelha a migration aplicada no Supabase e documenta o contrato:
--
--   if v_os.status='Finalizada' and exists(
--     select 1 from public.imperium_os_finalizacoes_web ...
--   ) then
--     raise exception
--       'Produtos de uma OS finalizada pelo Web sao imutaveis.'
--       using errcode='40001';
--   end if;
--
-- Manter esta versao separada evita drift entre o historico local e
-- supabase_migrations.schema_migrations.
do $$
begin
  if to_regprocedure(
    'public.imperium_os_produtos_publicar_v4(uuid,uuid,timestamptz,text,jsonb,jsonb,text,bigint)'
  ) is null then
    raise exception 'RPC imperium_os_produtos_publicar_v4 ausente.';
  end if;
end;
$$;
