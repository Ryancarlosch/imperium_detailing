-- Imperium — Pós-venda + Marketing V1
-- CRM continua responsável por aquisição; estas estruturas cobrem retenção,
-- conteúdo/campanhas e atribuição de resultado.

create table if not exists public.imperium_pos_venda_config (
  empresa_id uuid primary key references public.empresas(id) on delete cascade,
  ativo boolean not null default true,
  dias_retorno bigint not null default 90,
  dias_reativacao bigint not null default 180,
  atualizado_em timestamptz not null default now(),
  constraint imperium_pos_venda_config_dias_ck
    check (dias_retorno >= 1 and dias_reativacao > dias_retorno)
);

create table if not exists public.imperium_pos_venda_interacoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  cliente_id uuid not null,
  ordem_servico_id uuid,
  tipo text not null default 'Contato',
  descricao text not null default '',
  resultado text not null default '',
  proximo_contato date,
  data_interacao timestamptz not null default now(),
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_pos_venda_interacoes_cliente_fk
    foreign key (empresa_id, cliente_id)
    references public.imperium_clientes(empresa_id, id)
    on delete cascade,
  constraint imperium_pos_venda_interacoes_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico(empresa_id, id)
    on delete set null
);

create table if not exists public.imperium_marketing_campanhas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  nome text not null,
  plataforma text not null default 'Outro',
  tipo text not null default 'Orgânico',
  objetivo text not null default '',
  status text not null default 'Rascunho',
  investimento numeric(18,2) not null default 0,
  data_inicio date,
  data_fim date,
  external_campaign_id text,
  utm_source text not null default '',
  utm_medium text not null default '',
  utm_campaign text not null default '',
  alcance bigint not null default 0,
  impressoes bigint not null default 0,
  cliques bigint not null default 0,
  leads bigint not null default 0,
  observacoes text not null default '',
  sincronizado_em timestamptz,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_marketing_campanhas_empresa_id_id_uq
    unique (empresa_id, id),
  constraint imperium_marketing_campanhas_investimento_ck
    check (investimento >= 0),
  constraint imperium_marketing_campanhas_metricas_ck
    check (
      alcance >= 0 and impressoes >= 0 and cliques >= 0 and leads >= 0
    )
);

create table if not exists public.imperium_marketing_publicacoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  campanha_id uuid,
  plataforma text not null default 'Instagram',
  tipo_conteudo text not null default 'Post',
  titulo text not null default '',
  legenda text not null default '',
  status text not null default 'Rascunho',
  agendado_para timestamptz,
  publicado_em timestamptz,
  external_media_id text,
  permalink text not null default '',
  alcance bigint not null default 0,
  impressoes bigint not null default 0,
  curtidas bigint not null default 0,
  comentarios bigint not null default 0,
  compartilhamentos bigint not null default 0,
  salvamentos bigint not null default 0,
  sincronizado_em timestamptz,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_marketing_publicacoes_campanha_fk
    foreign key (empresa_id, campanha_id)
    references public.imperium_marketing_campanhas(empresa_id, id)
    on delete set null,
  constraint imperium_marketing_publicacoes_metricas_ck
    check (
      alcance >= 0 and impressoes >= 0 and curtidas >= 0 and
      comentarios >= 0 and compartilhamentos >= 0 and salvamentos >= 0
    )
);

create table if not exists public.imperium_marketing_atribuicoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  campanha_id uuid not null,
  lead_id uuid,
  cliente_id uuid,
  ordem_servico_id uuid,
  origem text not null default 'Manual',
  modelo text not null default 'Último toque',
  observacoes text not null default '',
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_marketing_atribuicoes_campanha_fk
    foreign key (empresa_id, campanha_id)
    references public.imperium_marketing_campanhas(empresa_id, id)
    on delete cascade,
  constraint imperium_marketing_atribuicoes_lead_fk
    foreign key (empresa_id, lead_id)
    references public.imperium_crm_leads(empresa_id, id)
    on delete set null,
  constraint imperium_marketing_atribuicoes_cliente_fk
    foreign key (empresa_id, cliente_id)
    references public.imperium_clientes(empresa_id, id)
    on delete set null,
  constraint imperium_marketing_atribuicoes_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico(empresa_id, id)
    on delete set null,
  constraint imperium_marketing_atribuicoes_alvo_ck
    check (
      lead_id is not null or cliente_id is not null or ordem_servico_id is not null
    )
);

create index if not exists idx_imperium_pos_venda_interacoes_cliente
  on public.imperium_pos_venda_interacoes
  (empresa_id, cliente_id, data_interacao desc);

create index if not exists idx_imperium_marketing_campanhas_status
  on public.imperium_marketing_campanhas
  (empresa_id, status, atualizado_em desc);

create index if not exists idx_imperium_marketing_publicacoes_status
  on public.imperium_marketing_publicacoes
  (empresa_id, status, agendado_para);

create index if not exists idx_imperium_marketing_atribuicoes_campanha
  on public.imperium_marketing_atribuicoes
  (empresa_id, campanha_id, criado_em desc);

alter table public.imperium_pos_venda_config enable row level security;
alter table public.imperium_pos_venda_interacoes enable row level security;
alter table public.imperium_marketing_campanhas enable row level security;
alter table public.imperium_marketing_publicacoes enable row level security;
alter table public.imperium_marketing_atribuicoes enable row level security;

revoke all on public.imperium_pos_venda_config from anon, authenticated;
revoke all on public.imperium_pos_venda_interacoes from anon, authenticated;
revoke all on public.imperium_marketing_campanhas from anon, authenticated;
revoke all on public.imperium_marketing_publicacoes from anon, authenticated;
revoke all on public.imperium_marketing_atribuicoes from anon, authenticated;

grant select, insert, update on public.imperium_pos_venda_config to authenticated;
grant select, insert, update on public.imperium_pos_venda_interacoes to authenticated;
grant select, insert, update on public.imperium_marketing_campanhas to authenticated;
grant select, insert, update on public.imperium_marketing_publicacoes to authenticated;
grant select, insert, update on public.imperium_marketing_atribuicoes to authenticated;

create policy imperium_pos_venda_config_select
on public.imperium_pos_venda_config
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_pos_venda_config_insert
on public.imperium_pos_venda_config
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_pos_venda_config_update
on public.imperium_pos_venda_config
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')))
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_pos_venda_interacoes_select
on public.imperium_pos_venda_interacoes
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_pos_venda_interacoes_insert
on public.imperium_pos_venda_interacoes
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_pos_venda_interacoes_update
on public.imperium_pos_venda_interacoes
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')))
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_marketing_campanhas_select
on public.imperium_marketing_campanhas
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_marketing_campanhas_insert
on public.imperium_marketing_campanhas
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_marketing_campanhas_update
on public.imperium_marketing_campanhas
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')))
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_marketing_publicacoes_select
on public.imperium_marketing_publicacoes
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_marketing_publicacoes_insert
on public.imperium_marketing_publicacoes
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_marketing_publicacoes_update
on public.imperium_marketing_publicacoes
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')))
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_marketing_atribuicoes_select
on public.imperium_marketing_atribuicoes
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_marketing_atribuicoes_insert
on public.imperium_marketing_atribuicoes
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create policy imperium_marketing_atribuicoes_update
on public.imperium_marketing_atribuicoes
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'crm')))
with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

create trigger imperium_pos_venda_config_touch
before update on public.imperium_pos_venda_config
for each row execute function private.imperium_touch_atualizado_em();

create trigger imperium_pos_venda_interacoes_touch
before update on public.imperium_pos_venda_interacoes
for each row execute function private.imperium_touch_atualizado_em();

create trigger imperium_marketing_campanhas_touch
before update on public.imperium_marketing_campanhas
for each row execute function private.imperium_touch_atualizado_em();

create trigger imperium_marketing_publicacoes_touch
before update on public.imperium_marketing_publicacoes
for each row execute function private.imperium_touch_atualizado_em();

create trigger imperium_marketing_atribuicoes_touch
before update on public.imperium_marketing_atribuicoes
for each row execute function private.imperium_touch_atualizado_em();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_pos_venda_interacoes'
  ) then
    alter publication supabase_realtime
      add table public.imperium_pos_venda_interacoes;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_marketing_campanhas'
  ) then
    alter publication supabase_realtime
      add table public.imperium_marketing_campanhas;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_marketing_publicacoes'
  ) then
    alter publication supabase_realtime
      add table public.imperium_marketing_publicacoes;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_marketing_atribuicoes'
  ) then
    alter publication supabase_realtime
      add table public.imperium_marketing_atribuicoes;
  end if;
end
$$;
