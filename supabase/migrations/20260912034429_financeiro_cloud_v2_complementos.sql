create table if not exists public.imperium_financeiro_fornecedores (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  nome text not null,
  documento text not null default '',
  telefone text not null default '',
  email text not null default '',
  endereco text not null default '',
  cidade text not null default '',
  estado text not null default '',
  categoria text not null default '',
  observacoes text not null default '',
  ativo boolean not null default true,
  origem_criado_em text,
  origem_atualizado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_fin_fornecedores_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_fin_fornecedores_empresa_id_id_uq
    unique (empresa_id, id)
);

create table if not exists public.imperium_financeiro_regras_taxa (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  nome text not null,
  forma_pagamento text not null,
  parcelas bigint not null default 1,
  conta_id uuid,
  origem_conta_local_id bigint,
  taxa_percentual numeric(12,6) not null default 0,
  taxa_fixa numeric(18,2) not null default 0,
  prazo_recebimento_dias bigint not null default 0,
  prioridade bigint not null default 0,
  repassar_cliente boolean not null default false,
  observacoes text not null default '',
  ativo boolean not null default true,
  origem_criado_em text,
  origem_atualizado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_fin_regras_taxa_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_fin_regras_taxa_empresa_id_id_uq
    unique (empresa_id, id),
  constraint imperium_fin_regras_taxa_conta_fk
    foreign key (empresa_id, conta_id)
    references public.imperium_financeiro_contas(empresa_id, id)
    on delete set null
);

create table if not exists public.imperium_financeiro_transferencias (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  conta_origem_id uuid not null,
  conta_destino_id uuid not null,
  valor numeric(18,2) not null,
  data text not null,
  descricao text not null default '',
  observacoes text not null default '',
  origem_criado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_fin_transferencias_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_fin_transferencias_empresa_id_id_uq
    unique (empresa_id, id),
  constraint imperium_fin_transferencias_origem_conta_fk
    foreign key (empresa_id, conta_origem_id)
    references public.imperium_financeiro_contas(empresa_id, id)
    on delete restrict,
  constraint imperium_fin_transferencias_destino_conta_fk
    foreign key (empresa_id, conta_destino_id)
    references public.imperium_financeiro_contas(empresa_id, id)
    on delete restrict
);

alter table public.imperium_financeiro_pagamentos_os
  add column if not exists regra_taxa_id uuid;

alter table public.imperium_financeiro_movimentos
  add column if not exists fornecedor_id uuid;

alter table public.imperium_financeiro_movimentos
  add column if not exists transferencia_id uuid;

DO $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'imperium_fin_pag_regra_taxa_fk'
  ) then
    alter table public.imperium_financeiro_pagamentos_os
      add constraint imperium_fin_pag_regra_taxa_fk
      foreign key (empresa_id, regra_taxa_id)
      references public.imperium_financeiro_regras_taxa(empresa_id, id)
      on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'imperium_fin_mov_fornecedor_fk'
  ) then
    alter table public.imperium_financeiro_movimentos
      add constraint imperium_fin_mov_fornecedor_fk
      foreign key (empresa_id, fornecedor_id)
      references public.imperium_financeiro_fornecedores(empresa_id, id)
      on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'imperium_fin_mov_transferencia_fk'
  ) then
    alter table public.imperium_financeiro_movimentos
      add constraint imperium_fin_mov_transferencia_fk
      foreign key (empresa_id, transferencia_id)
      references public.imperium_financeiro_transferencias(empresa_id, id)
      on delete set null;
  end if;
end $$;

create index if not exists idx_imperium_fin_fornecedores_empresa_ativo
  on public.imperium_financeiro_fornecedores(empresa_id, ativo, nome);

create index if not exists idx_imperium_fin_regras_empresa_ativo
  on public.imperium_financeiro_regras_taxa(
    empresa_id, ativo, forma_pagamento, parcelas, prioridade
  );

create index if not exists idx_imperium_fin_transferencias_empresa_data
  on public.imperium_financeiro_transferencias(empresa_id, data);

create index if not exists idx_imperium_fin_pag_regra_taxa
  on public.imperium_financeiro_pagamentos_os(empresa_id, regra_taxa_id);

create index if not exists idx_imperium_fin_mov_fornecedor
  on public.imperium_financeiro_movimentos(empresa_id, fornecedor_id);

create index if not exists idx_imperium_fin_mov_transferencia
  on public.imperium_financeiro_movimentos(empresa_id, transferencia_id);

alter table public.imperium_financeiro_fornecedores enable row level security;
alter table public.imperium_financeiro_regras_taxa enable row level security;
alter table public.imperium_financeiro_transferencias enable row level security;

revoke all on public.imperium_financeiro_fornecedores from anon, authenticated;
revoke all on public.imperium_financeiro_regras_taxa from anon, authenticated;
revoke all on public.imperium_financeiro_transferencias from anon, authenticated;

grant select, insert, update
on public.imperium_financeiro_fornecedores to authenticated;

grant select, insert, update
on public.imperium_financeiro_regras_taxa to authenticated;

grant select, insert, update
on public.imperium_financeiro_transferencias to authenticated;

create policy imperium_fin_fornecedores_select
on public.imperium_financeiro_fornecedores
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_fin_fornecedores_insert
on public.imperium_financeiro_fornecedores
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_fin_fornecedores_update
on public.imperium_financeiro_fornecedores
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_fin_regras_taxa_select
on public.imperium_financeiro_regras_taxa
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_fin_regras_taxa_insert
on public.imperium_financeiro_regras_taxa
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_fin_regras_taxa_update
on public.imperium_financeiro_regras_taxa
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_fin_transferencias_select
on public.imperium_financeiro_transferencias
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_fin_transferencias_insert
on public.imperium_financeiro_transferencias
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_fin_transferencias_update
on public.imperium_financeiro_transferencias
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create trigger imperium_fin_fornecedores_touch
before update on public.imperium_financeiro_fornecedores
for each row execute function private.imperium_touch_atualizado_em();

create trigger imperium_fin_regras_taxa_touch
before update on public.imperium_financeiro_regras_taxa
for each row execute function private.imperium_touch_atualizado_em();

create trigger imperium_fin_transferencias_touch
before update on public.imperium_financeiro_transferencias
for each row execute function private.imperium_touch_atualizado_em();
