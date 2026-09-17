do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_ordens_servico'
  ) then
    execute 'alter publication supabase_realtime add table public.imperium_ordens_servico';
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_ordem_servico_itens'
  ) then
    execute 'alter publication supabase_realtime add table public.imperium_ordem_servico_itens';
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_financeiro_pagamentos_os'
  ) then
    execute 'alter publication supabase_realtime add table public.imperium_financeiro_pagamentos_os';
  end if;
end
$$;
