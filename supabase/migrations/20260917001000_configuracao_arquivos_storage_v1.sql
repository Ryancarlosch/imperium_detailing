-- Configurações Arquivos Cloud V1
-- Logo e assinatura da empresa em Storage privado por tenant.

create table if not exists public.imperium_configuracao_arquivos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  tipo text not null,
  storage_bucket text not null default 'imperium-configuracoes-arquivos',
  storage_path text not null,
  nome_original text not null default '',
  sha256 text not null,
  tamanho bigint not null default 0,
  mime text not null default 'application/octet-stream',
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_config_arquivo_tipo_ck
    check (tipo in ('logo', 'assinatura_empresa')),
  constraint imperium_config_arquivo_empresa_tipo_uq unique (empresa_id, tipo)
);

alter table public.imperium_configuracao_arquivos enable row level security;

revoke all on public.imperium_configuracao_arquivos from anon, authenticated;
grant select, insert, update on public.imperium_configuracao_arquivos to authenticated;

drop policy if exists imperium_config_arquivos_select
  on public.imperium_configuracao_arquivos;
drop policy if exists imperium_config_arquivos_insert
  on public.imperium_configuracao_arquivos;
drop policy if exists imperium_config_arquivos_update
  on public.imperium_configuracao_arquivos;

create policy imperium_config_arquivos_select
on public.imperium_configuracao_arquivos
for select to authenticated
using ((select private.imperium_eh_admin_empresa(empresa_id)));

create policy imperium_config_arquivos_insert
on public.imperium_configuracao_arquivos
for insert to authenticated
with check ((select private.imperium_eh_admin_empresa(empresa_id)));

create policy imperium_config_arquivos_update
on public.imperium_configuracao_arquivos
for update to authenticated
using ((select private.imperium_eh_admin_empresa(empresa_id)))
with check ((select private.imperium_eh_admin_empresa(empresa_id)));

drop trigger if exists imperium_config_arquivos_touch
  on public.imperium_configuracao_arquivos;
create trigger imperium_config_arquivos_touch
before update on public.imperium_configuracao_arquivos
for each row execute function private.imperium_touch_atualizado_em();

insert into storage.buckets (id, name, public, file_size_limit)
values (
  'imperium-configuracoes-arquivos',
  'imperium-configuracoes-arquivos',
  false,
  10485760
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'imperium_config_arquivos_storage_select'
  ) then
    create policy imperium_config_arquivos_storage_select
    on storage.objects
    for select to authenticated
    using (
      bucket_id = 'imperium-configuracoes-arquivos'
      and case
        when split_part(name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (select private.imperium_eh_admin_empresa(split_part(name, '/', 1)::uuid))
        else false
      end
    );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'imperium_config_arquivos_storage_insert'
  ) then
    create policy imperium_config_arquivos_storage_insert
    on storage.objects
    for insert to authenticated
    with check (
      bucket_id = 'imperium-configuracoes-arquivos'
      and case
        when split_part(name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (select private.imperium_eh_admin_empresa(split_part(name, '/', 1)::uuid))
        else false
      end
    );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'imperium_config_arquivos_storage_update'
  ) then
    create policy imperium_config_arquivos_storage_update
    on storage.objects
    for update to authenticated
    using (
      bucket_id = 'imperium-configuracoes-arquivos'
      and case
        when split_part(name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (select private.imperium_eh_admin_empresa(split_part(name, '/', 1)::uuid))
        else false
      end
    )
    with check (
      bucket_id = 'imperium-configuracoes-arquivos'
      and case
        when split_part(name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (select private.imperium_eh_admin_empresa(split_part(name, '/', 1)::uuid))
        else false
      end
    );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_configuracao_arquivos'
  ) then
    alter publication supabase_realtime add table public.imperium_configuracao_arquivos;
  end if;
end $$;
