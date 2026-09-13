create table if not exists public.imperium_orcamentos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  cliente_id uuid not null,
  veiculo_id uuid,
  servico text not null default '',
  descricao text not null default '',
  valor numeric(18,2) not null default 0,
  data_emissao text not null,
  validade text not null default '',
  status text not null default 'Pendente',
  observacoes text not null default '',
  desconto numeric(18,2) not null default 0,
  perfil_preco text not null default 'informado',
  origem_atualizado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_orcamentos_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_orcamentos_empresa_id_id_uq
    unique (empresa_id, id),
  constraint imperium_orcamentos_cliente_fk
    foreign key (empresa_id, cliente_id)
    references public.imperium_clientes(empresa_id, id)
    on delete restrict,
  constraint imperium_orcamentos_veiculo_fk
    foreign key (empresa_id, veiculo_id)
    references public.imperium_veiculos(empresa_id, id)
    on delete set null
);

create table if not exists public.imperium_orcamento_itens (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  orcamento_id uuid not null,
  servico_catalogo_id uuid,
  origem_servico_catalogo_local_id bigint,
  servico text not null default '',
  descricao text not null default '',
  quantidade numeric(18,6) not null default 1,
  valor_unitario numeric(18,2) not null default 0,
  ordem bigint not null default 0,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_orc_itens_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_orc_itens_empresa_id_id_uq
    unique (empresa_id, id),
  constraint imperium_orc_itens_orc_fk
    foreign key (empresa_id, orcamento_id)
    references public.imperium_orcamentos(empresa_id, id)
    on delete cascade,
  constraint imperium_orc_itens_serv_fk
    foreign key (empresa_id, servico_catalogo_id)
    references public.imperium_precificacao_servicos_catalogo(empresa_id, id)
    on delete set null
);

create table if not exists public.imperium_crm_leads (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  nome text not null,
  telefone text not null default '',
  email text not null default '',
  cliente_id uuid,
  veiculo_id uuid,
  origem text not null default 'Outro',
  servico_interesse text not null default '',
  veiculo_interesse text not null default '',
  valor_potencial numeric(18,2) not null default 0,
  etapa text not null default 'Novo contato',
  responsavel text not null default '',
  proximo_contato text,
  observacoes text not null default '',
  motivo_perda text not null default '',
  agendamento_id uuid,
  origem_criado_em text,
  origem_atualizado_em text,
  convertido_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_crm_leads_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_crm_leads_empresa_id_id_uq
    unique (empresa_id, id),
  constraint imperium_crm_leads_cliente_fk
    foreign key (empresa_id, cliente_id)
    references public.imperium_clientes(empresa_id, id)
    on delete set null,
  constraint imperium_crm_leads_veiculo_fk
    foreign key (empresa_id, veiculo_id)
    references public.imperium_veiculos(empresa_id, id)
    on delete set null,
  constraint imperium_crm_leads_agendamento_fk
    foreign key (empresa_id, agendamento_id)
    references public.imperium_agendamentos(empresa_id, id)
    on delete set null
);

create table if not exists public.imperium_crm_interacoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  lead_id uuid not null,
  tipo text not null default 'Contato',
  descricao text not null,
  data_interacao text not null,
  origem_criado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_crm_interacoes_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_crm_interacoes_empresa_id_id_uq
    unique (empresa_id, id),
  constraint imperium_crm_interacoes_lead_fk
    foreign key (empresa_id, lead_id)
    references public.imperium_crm_leads(empresa_id, id)
    on delete cascade
);

create table if not exists public.imperium_crm_campanhas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  nome text not null,
  tipo text not null default 'Manual',
  beneficio_tipo text not null default 'Percentual',
  beneficio_valor numeric(18,2) not null default 0,
  beneficio_descricao text not null default '',
  valor_minimo numeric(18,2) not null default 0,
  dias_validade bigint not null default 30,
  dias_sem_retorno bigint not null default 180,
  ativo boolean not null default true,
  origem_criado_em text,
  origem_atualizado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_crm_campanhas_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_crm_campanhas_empresa_id_id_uq
    unique (empresa_id, id)
);

create table if not exists public.imperium_crm_cupons (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  codigo text not null,
  campanha_id uuid,
  cliente_id uuid,
  lead_id uuid,
  beneficio_tipo text not null,
  beneficio_valor numeric(18,2) not null default 0,
  beneficio_descricao text not null default '',
  valor_minimo numeric(18,2) not null default 0,
  validade_inicio text not null,
  validade_fim text not null,
  status text not null default 'Ativo',
  usado_em text,
  ordem_servico_id uuid,
  chave_geracao text not null default '',
  origem_criado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_crm_cupons_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_crm_cupons_empresa_id_id_uq
    unique (empresa_id, id),
  constraint imperium_crm_cupons_codigo_uq
    unique (empresa_id, codigo),
  constraint imperium_crm_cupons_campanha_fk
    foreign key (empresa_id, campanha_id)
    references public.imperium_crm_campanhas(empresa_id, id)
    on delete set null,
  constraint imperium_crm_cupons_cliente_fk
    foreign key (empresa_id, cliente_id)
    references public.imperium_clientes(empresa_id, id)
    on delete set null,
  constraint imperium_crm_cupons_lead_fk
    foreign key (empresa_id, lead_id)
    references public.imperium_crm_leads(empresa_id, id)
    on delete set null,
  constraint imperium_crm_cupons_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico(empresa_id, id)
    on delete set null
);

create index if not exists idx_imperium_orcamentos_empresa_status
  on public.imperium_orcamentos(empresa_id, status, data_emissao desc);
create index if not exists idx_imperium_orc_itens_orc
  on public.imperium_orcamento_itens(empresa_id, orcamento_id, ordem);
create index if not exists idx_imperium_crm_leads_empresa_etapa
  on public.imperium_crm_leads(empresa_id, etapa, atualizado_em desc);
create index if not exists idx_imperium_crm_interacoes_lead
  on public.imperium_crm_interacoes(empresa_id, lead_id, data_interacao desc);
create index if not exists idx_imperium_crm_campanhas_ativo
  on public.imperium_crm_campanhas(empresa_id, ativo, nome);
create index if not exists idx_imperium_crm_cupons_status
  on public.imperium_crm_cupons(empresa_id, status, validade_fim);

alter table public.imperium_orcamentos enable row level security;
alter table public.imperium_orcamento_itens enable row level security;
alter table public.imperium_crm_leads enable row level security;
alter table public.imperium_crm_interacoes enable row level security;
alter table public.imperium_crm_campanhas enable row level security;
alter table public.imperium_crm_cupons enable row level security;

revoke all on public.imperium_orcamentos from anon, authenticated;
revoke all on public.imperium_orcamento_itens from anon, authenticated;
revoke all on public.imperium_crm_leads from anon, authenticated;
revoke all on public.imperium_crm_interacoes from anon, authenticated;
revoke all on public.imperium_crm_campanhas from anon, authenticated;
revoke all on public.imperium_crm_cupons from anon, authenticated;

grant select, insert, update on public.imperium_orcamentos to authenticated;
grant select, insert, update on public.imperium_orcamento_itens to authenticated;
grant select, insert, update on public.imperium_crm_leads to authenticated;
grant select, insert, update on public.imperium_crm_interacoes to authenticated;
grant select, insert, update on public.imperium_crm_campanhas to authenticated;
grant select, insert, update on public.imperium_crm_cupons to authenticated;

create policy imperium_orcamentos_select
on public.imperium_orcamentos
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'orcamentos')));
create policy imperium_orcamentos_insert
on public.imperium_orcamentos
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'orcamentos')));
create policy imperium_orcamentos_update
on public.imperium_orcamentos
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'orcamentos')))
with check ((select private.imperium_pode_modulo(empresa_id, 'orcamentos')));

create policy imperium_orc_itens_select
on public.imperium_orcamento_itens
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'orcamentos')));
create policy imperium_orc_itens_insert
on public.imperium_orcamento_itens
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'orcamentos')));
create policy imperium_orc_itens_update
on public.imperium_orcamento_itens
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'orcamentos')))
with check ((select private.imperium_pode_modulo(empresa_id, 'orcamentos')));

create policy imperium_crm_leads_select
on public.imperium_crm_leads
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')));
create policy imperium_crm_leads_insert
on public.imperium_crm_leads
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));
create policy imperium_crm_leads_update
on public.imperium_crm_leads
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')))
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_crm_interacoes_select
on public.imperium_crm_interacoes
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')));
create policy imperium_crm_interacoes_insert
on public.imperium_crm_interacoes
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));
create policy imperium_crm_interacoes_update
on public.imperium_crm_interacoes
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')))
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_crm_campanhas_select
on public.imperium_crm_campanhas
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')));
create policy imperium_crm_campanhas_insert
on public.imperium_crm_campanhas
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));
create policy imperium_crm_campanhas_update
on public.imperium_crm_campanhas
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')))
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_crm_cupons_select
on public.imperium_crm_cupons
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')));
create policy imperium_crm_cupons_insert
on public.imperium_crm_cupons
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));
create policy imperium_crm_cupons_update
on public.imperium_crm_cupons
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')))
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create trigger imperium_orcamentos_touch
before update on public.imperium_orcamentos
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_orc_itens_touch
before update on public.imperium_orcamento_itens
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_crm_leads_touch
before update on public.imperium_crm_leads
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_crm_interacoes_touch
before update on public.imperium_crm_interacoes
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_crm_campanhas_touch
before update on public.imperium_crm_campanhas
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_crm_cupons_touch
before update on public.imperium_crm_cupons
for each row execute function private.imperium_touch_atualizado_em();
