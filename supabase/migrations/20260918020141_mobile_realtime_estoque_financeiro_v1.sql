do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_estoque_itens'
  ) then
    alter publication supabase_realtime add table public.imperium_estoque_itens;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_estoque_lotes'
  ) then
    alter publication supabase_realtime add table public.imperium_estoque_lotes;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_estoque_movimentacoes'
  ) then
    alter publication supabase_realtime add table public.imperium_estoque_movimentacoes;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_financeiro_contas'
  ) then
    alter publication supabase_realtime add table public.imperium_financeiro_contas;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_financeiro_movimentos'
  ) then
    alter publication supabase_realtime add table public.imperium_financeiro_movimentos;
  end if;
end
$$;
