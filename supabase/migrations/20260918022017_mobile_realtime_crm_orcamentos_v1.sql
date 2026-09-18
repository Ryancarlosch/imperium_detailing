do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_orcamentos'
  ) then
    alter publication supabase_realtime add table public.imperium_orcamentos;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_orcamento_itens'
  ) then
    alter publication supabase_realtime add table public.imperium_orcamento_itens;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_crm_leads'
  ) then
    alter publication supabase_realtime add table public.imperium_crm_leads;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_crm_interacoes'
  ) then
    alter publication supabase_realtime add table public.imperium_crm_interacoes;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_crm_campanhas'
  ) then
    alter publication supabase_realtime add table public.imperium_crm_campanhas;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_crm_cupons'
  ) then
    alter publication supabase_realtime add table public.imperium_crm_cupons;
  end if;
end
$$;
