create table if not exists public.imperium_financeiro_plano_contas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  codigo text not null,
  nome text not null,
  tipo text not null,
  natureza text not null,
  grupo_dre text not null default 'Não DRE',
  parent_codigo text,
  ativo boolean not null default true,
  ordem bigint not null default 0,
  origem_criado_em text,
  origem_atualizado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_financeiro_plano_contas_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_financeiro_plano_contas_codigo_uq
    unique (empresa_id, codigo),
  constraint imperium_financeiro_plano_contas_empresa_id_id_uq
    unique (empresa_id, id)
);

create table if not exists public.imperium_financeiro_contas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  nome text not null,
  tipo text not null default 'Conta bancária',
  instituicao text not null default '',
  saldo_inicial numeric(18,2) not null default 0,
  data_saldo_inicial text,
  observacoes text not null default '',
  ativo boolean not null default true,
  origem_criado_em text,
  origem_atualizado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_financeiro_contas_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_financeiro_contas_nome_uq
    unique (empresa_id, nome),
  constraint imperium_financeiro_contas_empresa_id_id_uq
    unique (empresa_id, id)
);

create table if not exists public.imperium_financeiro_pagamentos_os (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  ordem_servico_id uuid not null,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  status text not null default 'Pago',
  valor numeric(18,2) not null default 0,
  forma_pagamento text not null default '',
  data_pagamento text,
  parcela_numero bigint,
  total_parcelas bigint,
  vencimento text,
  comprovante_origem_caminho text,
  observacoes text not null default '',
  taxa_percentual numeric(12,6),
  taxa_operacao numeric(18,2) not null default 0,
  valor_liquido numeric(18,2) not null default 0,
  origem_regra_taxa_local_id bigint,
  parcelas_taxa bigint not null default 1,
  estornado_em text,
  motivo_estorno text not null default '',
  origem_criado_em text,
  origem_atualizado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_financeiro_pagamentos_os_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_financeiro_pagamentos_os_empresa_id_id_uq
    unique (empresa_id, id),
  constraint imperium_financeiro_pagamentos_os_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico(empresa_id, id)
    on delete cascade
);

create table if not exists public.imperium_financeiro_movimentos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  tipo text not null,
  descricao text not null,
  valor numeric(18,2) not null default 0,
  forma_pagamento text,
  data text not null,
  cliente_id uuid,
  agendamento_id uuid,
  ordem_servico_id uuid,
  pagamento_id uuid,
  plano_conta_id uuid,
  conta_id uuid,
  origem_cliente_local_id bigint,
  origem_agendamento_local_id bigint,
  origem_ordem_servico_local_id bigint,
  origem_pagamento_local_id bigint,
  origem_plano_conta_local_id bigint,
  origem_conta_local_id bigint,
  origem_fornecedor_local_id bigint,
  origem_transferencia_local_id bigint,
  origem_nota_fiscal_local_id bigint,
  parcela_numero bigint,
  total_parcelas bigint not null default 1,
  natureza text not null default 'Não classificado',
  origem text not null default 'Manual',
  status text not null default 'Realizado',
  data_competencia text,
  data_vencimento text,
  data_pagamento text,
  numero_documento text not null default '',
  observacoes text not null default '',
  impacta_dre boolean not null default true,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_financeiro_movimentos_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_financeiro_movimentos_empresa_id_id_uq
    unique (empresa_id, id),
  constraint imperium_financeiro_movimentos_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico(empresa_id, id)
    on delete set null,
  constraint imperium_financeiro_movimentos_pagamento_fk
    foreign key (empresa_id, pagamento_id)
    references public.imperium_financeiro_pagamentos_os(empresa_id, id)
    on delete set null,
  constraint imperium_financeiro_movimentos_plano_fk
    foreign key (empresa_id, plano_conta_id)
    references public.imperium_financeiro_plano_contas(empresa_id, id)
    on delete set null,
  constraint imperium_financeiro_movimentos_conta_fk
    foreign key (empresa_id, conta_id)
    references public.imperium_financeiro_contas(empresa_id, id)
    on delete set null
);

create index if not exists idx_imperium_fin_plano_empresa_ativo
  on public.imperium_financeiro_plano_contas(empresa_id, ativo, ordem, codigo);
create index if not exists idx_imperium_fin_contas_empresa_ativo
  on public.imperium_financeiro_contas(empresa_id, ativo, nome);
create index if not exists idx_imperium_fin_pag_os
  on public.imperium_financeiro_pagamentos_os(empresa_id, ordem_servico_id, status);
create index if not exists idx_imperium_fin_mov_data
  on public.imperium_financeiro_movimentos(empresa_id, data);
create index if not exists idx_imperium_fin_mov_conta
  on public.imperium_financeiro_movimentos(
    empresa_id, conta_id, status, data_pagamento
  );
create index if not exists idx_imperium_fin_mov_os
  on public.imperium_financeiro_movimentos(empresa_id, ordem_servico_id);
create index if not exists idx_imperium_fin_mov_pagamento
  on public.imperium_financeiro_movimentos(empresa_id, pagamento_id);

alter table public.imperium_financeiro_plano_contas enable row level security;
alter table public.imperium_financeiro_contas enable row level security;
alter table public.imperium_financeiro_pagamentos_os enable row level security;
alter table public.imperium_financeiro_movimentos enable row level security;

revoke all on public.imperium_financeiro_plano_contas from anon, authenticated;
revoke all on public.imperium_financeiro_contas from anon, authenticated;
revoke all on public.imperium_financeiro_pagamentos_os from anon, authenticated;
revoke all on public.imperium_financeiro_movimentos from anon, authenticated;

grant select, insert, update
on public.imperium_financeiro_plano_contas to authenticated;
grant select, insert, update
on public.imperium_financeiro_contas to authenticated;
grant select, insert, update
on public.imperium_financeiro_pagamentos_os to authenticated;
grant select, insert, update
on public.imperium_financeiro_movimentos to authenticated;

create policy imperium_fin_plano_select
on public.imperium_financeiro_plano_contas
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_fin_plano_insert
on public.imperium_financeiro_plano_contas
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_fin_plano_update
on public.imperium_financeiro_plano_contas
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_fin_contas_select
on public.imperium_financeiro_contas
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_fin_contas_insert
on public.imperium_financeiro_contas
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_fin_contas_update
on public.imperium_financeiro_contas
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_fin_pag_select
on public.imperium_financeiro_pagamentos_os
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_fin_pag_insert
on public.imperium_financeiro_pagamentos_os
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_fin_pag_update
on public.imperium_financeiro_pagamentos_os
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_fin_mov_select
on public.imperium_financeiro_movimentos
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_fin_mov_insert
on public.imperium_financeiro_movimentos
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_fin_mov_update
on public.imperium_financeiro_movimentos
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create trigger imperium_fin_plano_touch
before update on public.imperium_financeiro_plano_contas
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_fin_contas_touch
before update on public.imperium_financeiro_contas
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_fin_pag_touch
before update on public.imperium_financeiro_pagamentos_os
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_fin_mov_touch
before update on public.imperium_financeiro_movimentos
for each row execute function private.imperium_touch_atualizado_em();
