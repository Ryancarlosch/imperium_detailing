do $$
begin

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_precificacao_colaboradores_custo'
  ) then
    alter publication supabase_realtime add table public.imperium_precificacao_colaboradores_custo;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_precificacao_config'
  ) then
    alter publication supabase_realtime add table public.imperium_precificacao_config;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_precificacao_servico_produtos'
  ) then
    alter publication supabase_realtime add table public.imperium_precificacao_servico_produtos;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_precificacao_servicos'
  ) then
    alter publication supabase_realtime add table public.imperium_precificacao_servicos;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_precificacao_servicos_catalogo'
  ) then
    alter publication supabase_realtime add table public.imperium_precificacao_servicos_catalogo;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_precificacao_simulacoes'
  ) then
    alter publication supabase_realtime add table public.imperium_precificacao_simulacoes;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_precificacao_snapshots'
  ) then
    alter publication supabase_realtime add table public.imperium_precificacao_snapshots;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_configuracoes_empresa'
  ) then
    alter publication supabase_realtime add table public.imperium_configuracoes_empresa;
  end if;
end
$$;
