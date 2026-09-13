create table if not exists public.imperium_precificacao_config (
  empresa_id uuid primary key references public.empresas(id) on delete cascade,
  horas_produtivas_mes numeric(10,2) not null default 220
    check (horas_produtivas_mes = 220),
  meses_media bigint not null default 3 check (meses_media between 1 and 12),
  margem_cliente numeric(8,4) not null default 35,
  margem_revenda_1_4 numeric(8,4) not null default 25,
  margem_revenda_5_9 numeric(8,4) not null default 20,
  margem_revenda_10_mais numeric(8,4) not null default 16,
  margem_minima numeric(8,4) not null default 10,
  origem_dispositivo text,
  origem_atualizado_em text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists public.imperium_precificacao_servicos_catalogo (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  nome text not null,
  categoria text not null default '',
  descricao text not null default '',
  observacoes_padrao text not null default '',
  preco_padrao numeric(18,2) not null default 0,
  duracao_minutos bigint not null default 0,
  ativo boolean not null default true,
  origem_criado_em text,
  origem_atualizado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_prec_servicos_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_prec_servicos_empresa_id_id_uq unique (empresa_id, id)
);

create table if not exists public.imperium_precificacao_servicos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  servico_id uuid not null,
  tempo_precificacao_minutos numeric(12,4),
  aceita_revenda boolean not null default false,
  origem_atualizado_em text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_prec_servico_pref_uq unique (empresa_id, servico_id),
  constraint imperium_prec_servico_pref_fk
    foreign key (empresa_id, servico_id)
    references public.imperium_precificacao_servicos_catalogo(empresa_id, id)
    on delete cascade
);

create table if not exists public.imperium_precificacao_servico_produtos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  servico_id uuid not null,
  item_estoque_id uuid not null,
  quantidade_padrao numeric(18,6) not null default 0,
  unidade text not null default '',
  obrigatorio boolean not null default false,
  marcado_por_padrao boolean not null default false,
  ordem bigint not null default 0,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  excluido_em timestamptz,
  constraint imperium_prec_serv_prod_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_prec_serv_prod_serv_fk
    foreign key (empresa_id, servico_id)
    references public.imperium_precificacao_servicos_catalogo(empresa_id, id)
    on delete cascade,
  constraint imperium_prec_serv_prod_item_fk
    foreign key (empresa_id, item_estoque_id)
    references public.imperium_estoque_itens(empresa_id, id)
    on delete restrict
);

create table if not exists public.imperium_precificacao_colaboradores_custo (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  nome text not null,
  funcao text not null default '',
  remuneracao_mensal numeric(18,2) not null default 0,
  encargos_mensais numeric(18,2) not null default 0,
  outros_custos_mensais numeric(18,2) not null default 0,
  horas_produtivas_mes numeric(10,2) not null default 0,
  observacoes text not null default '',
  ativo boolean not null default true,
  origem_criado_em text,
  origem_atualizado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_prec_colab_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_prec_colab_empresa_id_id_uq unique (empresa_id, id)
);

create table if not exists public.imperium_precificacao_snapshots (
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  servico_id uuid not null,
  preco_atual numeric(18,2) not null default 0,
  tempo_precificacao_minutos numeric(12,4) not null default 0,
  tempo_medio_real_minutos numeric(12,4),
  amostras_tempo_real bigint not null default 0,
  custo_produtos numeric(18,2) not null default 0,
  custo_estrutura numeric(18,2) not null default 0,
  custo_base numeric(18,2) not null default 0,
  preco_equilibrio numeric(18,2) not null default 0,
  preco_minimo_seguro numeric(18,2) not null default 0,
  preco_sugerido numeric(18,2) not null default 0,
  preco_revenda_1_4 numeric(18,2) not null default 0,
  preco_revenda_5_9 numeric(18,2) not null default 0,
  preco_revenda_10_mais numeric(18,2) not null default 0,
  margem_atual numeric(12,6) not null default 0,
  custo_hora numeric(18,6) not null default 0,
  base_mensal_usada numeric(18,2) not null default 0,
  taxa_cartao_media_percentual numeric(12,6) not null default 0,
  meses_considerados bigint not null default 3,
  calculado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  primary key (empresa_id, servico_id),
  constraint imperium_prec_snapshot_serv_fk
    foreign key (empresa_id, servico_id)
    references public.imperium_precificacao_servicos_catalogo(empresa_id, id)
    on delete cascade
);

create index if not exists idx_imperium_prec_servicos_ativo
  on public.imperium_precificacao_servicos_catalogo(empresa_id, ativo, nome);
create index if not exists idx_imperium_prec_colab_ativo
  on public.imperium_precificacao_colaboradores_custo(empresa_id, ativo, nome);
create index if not exists idx_imperium_prec_receita_servico
  on public.imperium_precificacao_servico_produtos(empresa_id, servico_id, ordem);

alter table public.imperium_precificacao_config enable row level security;
alter table public.imperium_precificacao_servicos_catalogo enable row level security;
alter table public.imperium_precificacao_servicos enable row level security;
alter table public.imperium_precificacao_servico_produtos enable row level security;
alter table public.imperium_precificacao_colaboradores_custo enable row level security;
alter table public.imperium_precificacao_snapshots enable row level security;

revoke all on public.imperium_precificacao_config from anon, authenticated;
revoke all on public.imperium_precificacao_servicos_catalogo from anon, authenticated;
revoke all on public.imperium_precificacao_servicos from anon, authenticated;
revoke all on public.imperium_precificacao_servico_produtos from anon, authenticated;
revoke all on public.imperium_precificacao_colaboradores_custo from anon, authenticated;
revoke all on public.imperium_precificacao_snapshots from anon, authenticated;

grant select, insert, update on public.imperium_precificacao_config to authenticated;
grant select, insert, update on public.imperium_precificacao_servicos_catalogo to authenticated;
grant select, insert, update on public.imperium_precificacao_servicos to authenticated;
grant select, insert, update on public.imperium_precificacao_servico_produtos to authenticated;
grant select, insert, update on public.imperium_precificacao_colaboradores_custo to authenticated;
grant select, insert, update on public.imperium_precificacao_snapshots to authenticated;

create policy imperium_prec_config_select
on public.imperium_precificacao_config
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_prec_config_insert
on public.imperium_precificacao_config
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_prec_config_update
on public.imperium_precificacao_config
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_prec_serv_cat_select
on public.imperium_precificacao_servicos_catalogo
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_prec_serv_cat_insert
on public.imperium_precificacao_servicos_catalogo
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_prec_serv_cat_update
on public.imperium_precificacao_servicos_catalogo
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_prec_pref_select
on public.imperium_precificacao_servicos
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_prec_pref_insert
on public.imperium_precificacao_servicos
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_prec_pref_update
on public.imperium_precificacao_servicos
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_prec_prod_select
on public.imperium_precificacao_servico_produtos
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_prec_prod_insert
on public.imperium_precificacao_servico_produtos
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_prec_prod_update
on public.imperium_precificacao_servico_produtos
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_prec_colab_select
on public.imperium_precificacao_colaboradores_custo
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_prec_colab_insert
on public.imperium_precificacao_colaboradores_custo
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_prec_colab_update
on public.imperium_precificacao_colaboradores_custo
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_prec_snapshot_select
on public.imperium_precificacao_snapshots
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_prec_snapshot_insert
on public.imperium_precificacao_snapshots
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_prec_snapshot_update
on public.imperium_precificacao_snapshots
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create trigger imperium_prec_config_touch
before update on public.imperium_precificacao_config
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_prec_serv_cat_touch
before update on public.imperium_precificacao_servicos_catalogo
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_prec_pref_touch
before update on public.imperium_precificacao_servicos
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_prec_prod_touch
before update on public.imperium_precificacao_servico_produtos
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_prec_colab_touch
before update on public.imperium_precificacao_colaboradores_custo
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_prec_snapshot_touch
before update on public.imperium_precificacao_snapshots
for each row execute function private.imperium_touch_atualizado_em();
