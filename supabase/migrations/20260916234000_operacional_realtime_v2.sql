-- Operacional Realtime V2
-- Publica somente tabelas tenant-safe já protegidas por RLS.
-- O cliente Flutter ainda filtra por empresa_id em cada assinatura.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_clientes'
  ) then
    alter publication supabase_realtime add table public.imperium_clientes;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_veiculos'
  ) then
    alter publication supabase_realtime add table public.imperium_veiculos;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_agendamentos'
  ) then
    alter publication supabase_realtime add table public.imperium_agendamentos;
  end if;
end
$$;
