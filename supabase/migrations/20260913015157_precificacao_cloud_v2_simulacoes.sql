create table if not exists public.imperium_precificacao_simulacoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  nome text not null,
  margem_cliente numeric(8,4) not null,
  margem_revenda_1_4 numeric(8,4) not null,
  margem_revenda_5_9 numeric(8,4) not null,
  margem_revenda_10_mais numeric(8,4) not null,
  margem_minima numeric(8,4) not null,
  taxa_cartao_percentual numeric(12,6) not null default 0,
  custo_hora numeric(18,6) not null default 0,
  meta_faturamento numeric(18,2) not null default 0,
  meses_media bigint not null default 3 check (meses_media between 1 and 12),
  resultado_json jsonb not null default '{}'::jsonb,
  observacoes text not null default '',
  criado_por uuid default auth.uid(),
  criado_em timestamptz not null default now(),
  constraint imperium_prec_simulacoes_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id)
);

create index if not exists idx_imperium_prec_simulacoes_empresa_data
  on public.imperium_precificacao_simulacoes(empresa_id, criado_em desc);

alter table public.imperium_precificacao_simulacoes enable row level security;

revoke all on public.imperium_precificacao_simulacoes from anon, authenticated;
grant select, insert on public.imperium_precificacao_simulacoes to authenticated;

create policy imperium_prec_simulacoes_select
on public.imperium_precificacao_simulacoes
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_prec_simulacoes_insert
on public.imperium_precificacao_simulacoes
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
