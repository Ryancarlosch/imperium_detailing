create table if not exists public.imperium_migracao_modulos (
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  modulo text not null,
  status text not null default 'pendente',
  promovido_em timestamptz,
  rollback_em timestamptz,
  promovido_por uuid,
  observacao text not null default '',
  atualizado_em timestamptz not null default now(),
  primary key (empresa_id, modulo),
  constraint imperium_migracao_modulos_modulo_chk check (
    modulo in (
      'operacional',
      'ordens_servico',
      'arquivos_os',
      'crm_orcamentos',
      'estoque',
      'financeiro',
      'precificacao',
      'configuracoes',
      'ponto'
    )
  ),
  constraint imperium_migracao_modulos_status_chk check (
    status in ('pendente', 'promovido', 'rollback')
  )
);

alter table public.imperium_migracao_modulos enable row level security;

revoke all on table public.imperium_migracao_modulos from anon;
revoke all on table public.imperium_migracao_modulos from authenticated;

grant select, insert, update on table public.imperium_migracao_modulos
  to authenticated;

drop policy if exists imperium_migracao_modulos_admin_select
  on public.imperium_migracao_modulos;
drop policy if exists imperium_migracao_modulos_admin_insert
  on public.imperium_migracao_modulos;
drop policy if exists imperium_migracao_modulos_admin_update
  on public.imperium_migracao_modulos;

create policy imperium_migracao_modulos_admin_select
on public.imperium_migracao_modulos
for select
to authenticated
using (private.usuario_admin_empresa(empresa_id));

create policy imperium_migracao_modulos_admin_insert
on public.imperium_migracao_modulos
for insert
to authenticated
with check (
  private.usuario_admin_empresa(empresa_id)
  and promovido_por = (select auth.uid())
);

create policy imperium_migracao_modulos_admin_update
on public.imperium_migracao_modulos
for update
to authenticated
using (private.usuario_admin_empresa(empresa_id))
with check (
  private.usuario_admin_empresa(empresa_id)
  and promovido_por = (select auth.uid())
);
