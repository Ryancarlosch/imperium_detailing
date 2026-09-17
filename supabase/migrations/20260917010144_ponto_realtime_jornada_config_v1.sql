-- Ponto Realtime V1 — jornada e configuração compartilhadas
-- Mantém as políticas RLS existentes e apenas publica as tabelas no Realtime.

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'ponto_jornada'
  ) then
    execute 'alter publication supabase_realtime add table public.ponto_jornada';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'ponto_config'
  ) then
    execute 'alter publication supabase_realtime add table public.ponto_config';
  end if;
end;
$$;
