create table if not exists public.imperium_financeiro_custos_fixos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  nome text not null,
  valor_mensal numeric(18,2) not null default 0,
  categoria text not null default 'Despesa fixa',
  dia_vencimento bigint,
  plano_conta_id uuid,
  origem_plano_conta_local_id bigint,
  observacoes text not null default '',
  ativo boolean not null default true,
  origem_criado_em text,
  origem_atualizado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_fin_custos_fixos_origem_uq unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_fin_custos_fixos_empresa_id_id_uq unique (empresa_id, id),
  constraint imperium_fin_custos_fixos_plano_fk foreign key (empresa_id, plano_conta_id)
    references public.imperium_financeiro_plano_contas(empresa_id, id) on delete set null
);

create table if not exists public.imperium_financeiro_metas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  ano bigint not null,
  mes bigint not null,
  tipo text not null,
  plano_conta_id uuid,
  origem_plano_conta_local_id bigint,
  valor_meta numeric(18,2) not null default 0,
  observacoes text not null default '',
  ativo boolean not null default true,
  origem_criado_em text,
  origem_atualizado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_fin_metas_origem_uq unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_fin_metas_empresa_id_id_uq unique (empresa_id, id),
  constraint imperium_fin_metas_plano_fk foreign key (empresa_id, plano_conta_id)
    references public.imperium_financeiro_plano_contas(empresa_id, id) on delete set null
);

create table if not exists public.imperium_financeiro_conciliacoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  conta_id uuid not null,
  origem_conta_local_id bigint,
  data_conciliacao text not null,
  saldo_calculado numeric(18,2) not null default 0,
  saldo_informado numeric(18,2) not null default 0,
  diferenca numeric(18,2) not null default 0,
  status text not null default 'Conciliado',
  movimento_ajuste_id uuid,
  origem_movimento_ajuste_local_id bigint,
  observacoes text not null default '',
  origem_criado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_fin_conc_origem_uq unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_fin_conc_empresa_id_id_uq unique (empresa_id, id),
  constraint imperium_fin_conc_conta_fk foreign key (empresa_id, conta_id)
    references public.imperium_financeiro_contas(empresa_id, id) on delete restrict,
  constraint imperium_fin_conc_mov_ajuste_fk foreign key (empresa_id, movimento_ajuste_id)
    references public.imperium_financeiro_movimentos(empresa_id, id) on delete set null
);

alter table public.imperium_financeiro_pagamentos_os add column if not exists comprovante_storage_bucket text;
alter table public.imperium_financeiro_pagamentos_os add column if not exists comprovante_storage_path text;
alter table public.imperium_financeiro_pagamentos_os add column if not exists comprovante_nome_original text;
alter table public.imperium_financeiro_pagamentos_os add column if not exists comprovante_sha256 text;
alter table public.imperium_financeiro_pagamentos_os add column if not exists comprovante_tamanho bigint;
alter table public.imperium_financeiro_pagamentos_os add column if not exists comprovante_mime text;

create index if not exists idx_imperium_fin_custos_empresa_ativo
  on public.imperium_financeiro_custos_fixos(empresa_id, ativo, nome);
create index if not exists idx_imperium_fin_metas_empresa_periodo
  on public.imperium_financeiro_metas(empresa_id, ano, mes, ativo);
create index if not exists idx_imperium_fin_conc_empresa_conta_data
  on public.imperium_financeiro_conciliacoes(empresa_id, conta_id, data_conciliacao);
create index if not exists idx_imperium_fin_pag_comprovante
  on public.imperium_financeiro_pagamentos_os(empresa_id, comprovante_storage_path)
  where comprovante_storage_path is not null;

alter table public.imperium_financeiro_custos_fixos enable row level security;
alter table public.imperium_financeiro_metas enable row level security;
alter table public.imperium_financeiro_conciliacoes enable row level security;

revoke all on public.imperium_financeiro_custos_fixos from anon, authenticated;
revoke all on public.imperium_financeiro_metas from anon, authenticated;
revoke all on public.imperium_financeiro_conciliacoes from anon, authenticated;

grant select, insert, update on public.imperium_financeiro_custos_fixos to authenticated;
grant select, insert, update on public.imperium_financeiro_metas to authenticated;
grant select, insert, update on public.imperium_financeiro_conciliacoes to authenticated;

create policy imperium_fin_custos_select on public.imperium_financeiro_custos_fixos
for select to authenticated using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_fin_custos_insert on public.imperium_financeiro_custos_fixos
for insert to authenticated with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_fin_custos_update on public.imperium_financeiro_custos_fixos
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_fin_metas_select on public.imperium_financeiro_metas
for select to authenticated using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_fin_metas_insert on public.imperium_financeiro_metas
for insert to authenticated with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_fin_metas_update on public.imperium_financeiro_metas
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create policy imperium_fin_conc_select on public.imperium_financeiro_conciliacoes
for select to authenticated using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_fin_conc_insert on public.imperium_financeiro_conciliacoes
for insert to authenticated with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));
create policy imperium_fin_conc_update on public.imperium_financeiro_conciliacoes
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

create trigger imperium_fin_custos_touch before update on public.imperium_financeiro_custos_fixos
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_fin_metas_touch before update on public.imperium_financeiro_metas
for each row execute function private.imperium_touch_atualizado_em();
create trigger imperium_fin_conc_touch before update on public.imperium_financeiro_conciliacoes
for each row execute function private.imperium_touch_atualizado_em();

insert into storage.buckets (id, name, public, file_size_limit)
values ('imperium-financeiro-comprovantes','imperium-financeiro-comprovantes',false,10485760)
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit;

create policy imperium_fin_comprovantes_select on storage.objects
for select to authenticated using (
  bucket_id = 'imperium-financeiro-comprovantes'
  and split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (select private.imperium_pode_modulo(split_part(name, '/', 1)::uuid, 'financeiro'))
);
create policy imperium_fin_comprovantes_insert on storage.objects
for insert to authenticated with check (
  bucket_id = 'imperium-financeiro-comprovantes'
  and split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (select private.imperium_pode_modulo(split_part(name, '/', 1)::uuid, 'financeiro'))
);
create policy imperium_fin_comprovantes_update on storage.objects
for update to authenticated using (
  bucket_id = 'imperium-financeiro-comprovantes'
  and split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (select private.imperium_pode_modulo(split_part(name, '/', 1)::uuid, 'financeiro'))
)
with check (
  bucket_id = 'imperium-financeiro-comprovantes'
  and split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and (select private.imperium_pode_modulo(split_part(name, '/', 1)::uuid, 'financeiro'))
);
