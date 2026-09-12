-- Imperium Manager - Estoque Cloud Upload-Only V1
-- Migration version aplicada no Supabase: 20260912023332
-- Etapa 5: itens, lotes e movimentacoes append-only.
-- Nao altera Financeiro e nao habilita download de estoque.

create unique index if not exists imperium_ordens_servico_empresa_id_id_uidx
  on public.imperium_ordens_servico (empresa_id, id);

create table if not exists public.imperium_estoque_itens (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  nome text not null,
  categoria text not null default '',
  quantidade numeric not null default 0,
  quantidade_minima numeric not null default 0,
  unidade text not null default 'un',
  valor_total_pago numeric not null default 0,
  quantidade_total numeric not null default 0,
  ean text not null default '',
  custo_unitario numeric not null default 0,
  custo_unitario_calculado numeric not null default 0,
  fornecedor text not null default '',
  observacoes text not null default '',
  ativo boolean not null default true,
  origem_atualizado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_estoque_itens_origem_unica
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_estoque_itens_empresa_id_id_unica
    unique (empresa_id, id),
  constraint imperium_estoque_itens_origem_local_valida
    check (origem_local_id > 0),
  constraint imperium_estoque_itens_dispositivo_valido
    check (length(trim(origem_dispositivo)) > 0)
);

create index if not exists idx_imperium_estoque_itens_empresa
  on public.imperium_estoque_itens (empresa_id, excluido_em, ativo);
create index if not exists idx_imperium_estoque_itens_nome
  on public.imperium_estoque_itens (empresa_id, nome);
create index if not exists idx_imperium_estoque_itens_ean
  on public.imperium_estoque_itens (empresa_id, ean)
  where ean <> '';

create table if not exists public.imperium_estoque_lotes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  item_estoque_id uuid not null,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  data_compra text not null,
  quantidade_original numeric not null default 0,
  quantidade_normalizada numeric not null default 0,
  quantidade_disponivel numeric not null default 0,
  unidade_original text not null default '',
  unidade_base text not null default 'un',
  valor_total_pago numeric not null default 0,
  custo_unitario numeric not null default 0,
  fornecedor text not null default '',
  observacao text not null default '',
  ativo boolean not null default true,
  origem_criado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_estoque_lotes_origem_unica
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_estoque_lotes_empresa_id_id_unica
    unique (empresa_id, id),
  constraint imperium_estoque_lotes_item_empresa_fk
    foreign key (empresa_id, item_estoque_id)
    references public.imperium_estoque_itens (empresa_id, id)
    on delete restrict,
  constraint imperium_estoque_lotes_origem_local_valida
    check (origem_local_id > 0),
  constraint imperium_estoque_lotes_dispositivo_valido
    check (length(trim(origem_dispositivo)) > 0)
);

create index if not exists idx_imperium_estoque_lotes_item
  on public.imperium_estoque_lotes (empresa_id, item_estoque_id, ativo, excluido_em);
create index if not exists idx_imperium_estoque_lotes_data
  on public.imperium_estoque_lotes (empresa_id, data_compra);

create table if not exists public.imperium_estoque_movimentacoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  item_estoque_id uuid not null,
  lote_id uuid,
  ordem_servico_id uuid,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  tipo text not null,
  quantidade numeric not null default 0,
  quantidade_anterior numeric not null default 0,
  quantidade_posterior numeric not null default 0,
  custo_unitario numeric not null default 0,
  observacoes text not null default '',
  motivo text not null default '',
  origem text not null default 'Manual',
  origem_ordem_servico_local_id bigint,
  origem_nota_fiscal_local_id bigint,
  origem_nota_fiscal_item_local_id bigint,
  data text not null,
  origem_criado_em text,
  criado_em timestamptz not null default now(),
  constraint imperium_estoque_mov_origem_unica
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_estoque_mov_item_empresa_fk
    foreign key (empresa_id, item_estoque_id)
    references public.imperium_estoque_itens (empresa_id, id)
    on delete restrict,
  constraint imperium_estoque_mov_lote_empresa_fk
    foreign key (empresa_id, lote_id)
    references public.imperium_estoque_lotes (empresa_id, id)
    on delete restrict,
  constraint imperium_estoque_mov_os_empresa_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico (empresa_id, id)
    on delete restrict,
  constraint imperium_estoque_mov_origem_local_valida
    check (origem_local_id > 0),
  constraint imperium_estoque_mov_dispositivo_valido
    check (length(trim(origem_dispositivo)) > 0)
);

create index if not exists idx_imperium_estoque_mov_item
  on public.imperium_estoque_movimentacoes (empresa_id, item_estoque_id, criado_em);
create index if not exists idx_imperium_estoque_mov_lote
  on public.imperium_estoque_movimentacoes (empresa_id, lote_id)
  where lote_id is not null;
create index if not exists idx_imperium_estoque_mov_os
  on public.imperium_estoque_movimentacoes (empresa_id, ordem_servico_id)
  where ordem_servico_id is not null;
create index if not exists idx_imperium_estoque_mov_data
  on public.imperium_estoque_movimentacoes (empresa_id, data);

alter table public.imperium_estoque_itens enable row level security;
alter table public.imperium_estoque_lotes enable row level security;
alter table public.imperium_estoque_movimentacoes enable row level security;

create policy imperium_estoque_itens_select
  on public.imperium_estoque_itens
  for select to authenticated
  using (private.imperium_pode_modulo(empresa_id, 'estoque'));
create policy imperium_estoque_itens_insert
  on public.imperium_estoque_itens
  for insert to authenticated
  with check (private.imperium_pode_modulo(empresa_id, 'estoque'));
create policy imperium_estoque_itens_update
  on public.imperium_estoque_itens
  for update to authenticated
  using (private.imperium_pode_modulo(empresa_id, 'estoque'))
  with check (private.imperium_pode_modulo(empresa_id, 'estoque'));

create policy imperium_estoque_lotes_select
  on public.imperium_estoque_lotes
  for select to authenticated
  using (private.imperium_pode_modulo(empresa_id, 'estoque'));
create policy imperium_estoque_lotes_insert
  on public.imperium_estoque_lotes
  for insert to authenticated
  with check (private.imperium_pode_modulo(empresa_id, 'estoque'));
create policy imperium_estoque_lotes_update
  on public.imperium_estoque_lotes
  for update to authenticated
  using (private.imperium_pode_modulo(empresa_id, 'estoque'))
  with check (private.imperium_pode_modulo(empresa_id, 'estoque'));

-- Movimentacoes sao append-only para clientes autenticados:
-- SELECT + INSERT, sem UPDATE e sem DELETE.
create policy imperium_estoque_mov_select
  on public.imperium_estoque_movimentacoes
  for select to authenticated
  using (private.imperium_pode_modulo(empresa_id, 'estoque'));
create policy imperium_estoque_mov_insert
  on public.imperium_estoque_movimentacoes
  for insert to authenticated
  with check (private.imperium_pode_modulo(empresa_id, 'estoque'));

drop trigger if exists trg_imperium_estoque_itens_touch
  on public.imperium_estoque_itens;
create trigger trg_imperium_estoque_itens_touch
  before update on public.imperium_estoque_itens
  for each row execute function private.imperium_touch_atualizado_em();

drop trigger if exists trg_imperium_estoque_lotes_touch
  on public.imperium_estoque_lotes;
create trigger trg_imperium_estoque_lotes_touch
  before update on public.imperium_estoque_lotes
  for each row execute function private.imperium_touch_atualizado_em();

grant select, insert, update on public.imperium_estoque_itens to authenticated;
grant select, insert, update on public.imperium_estoque_lotes to authenticated;
grant select, insert on public.imperium_estoque_movimentacoes to authenticated;

comment on table public.imperium_estoque_itens is
  'Estoque cloud V1 - itens sincronizados por empresa e origem de dispositivo.';
comment on table public.imperium_estoque_lotes is
  'Estoque cloud V1 - lotes sincronizados por empresa e origem de dispositivo.';
comment on table public.imperium_estoque_movimentacoes is
  'Estoque cloud V1 - movimentacoes append-only e idempotentes por origem.';
