create table if not exists public.imperium_ordem_servico_fotos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  ordem_servico_id uuid not null,
  etapa text not null default 'Antes',
  descricao text not null default '',
  data_registro text not null,
  ordem bigint not null default 0,
  origem_caminho text,
  storage_bucket text,
  storage_path text,
  nome_original text,
  sha256 text,
  tamanho bigint,
  mime text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_os_fotos_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_os_fotos_empresa_id_id_uq unique (empresa_id, id),
  constraint imperium_os_fotos_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico(empresa_id, id)
    on delete cascade
);

alter table public.imperium_ordem_servico_checklist
  add column if not exists foto_avaria_origem_caminho text,
  add column if not exists foto_avaria_storage_bucket text,
  add column if not exists foto_avaria_nome_original text,
  add column if not exists foto_avaria_sha256 text,
  add column if not exists foto_avaria_tamanho bigint,
  add column if not exists foto_avaria_mime text;

alter table public.imperium_ordens_servico
  add column if not exists assinatura_origem_caminho text,
  add column if not exists assinatura_storage_bucket text,
  add column if not exists assinatura_nome_original text,
  add column if not exists assinatura_sha256 text,
  add column if not exists assinatura_tamanho bigint,
  add column if not exists assinatura_mime text;

create index if not exists idx_imperium_os_fotos_os_ordem
  on public.imperium_ordem_servico_fotos(
    empresa_id,
    ordem_servico_id,
    etapa,
    ordem
  );

alter table public.imperium_ordem_servico_fotos enable row level security;

revoke all on public.imperium_ordem_servico_fotos
from anon, authenticated;

grant select, insert, update
on public.imperium_ordem_servico_fotos
to authenticated;

create policy imperium_os_fotos_select
on public.imperium_ordem_servico_fotos
for select to authenticated
using (
  (
    select private.imperium_pode_modulo(
      empresa_id,
      'ordens_servico'
    )
  )
);

create policy imperium_os_fotos_insert
on public.imperium_ordem_servico_fotos
for insert to authenticated
with check (
  (
    select private.imperium_pode_modulo(
      empresa_id,
      'ordens_servico'
    )
  )
);

create policy imperium_os_fotos_update
on public.imperium_ordem_servico_fotos
for update to authenticated
using (
  (
    select private.imperium_pode_modulo(
      empresa_id,
      'ordens_servico'
    )
  )
)
with check (
  (
    select private.imperium_pode_modulo(
      empresa_id,
      'ordens_servico'
    )
  )
);

create trigger imperium_os_fotos_touch
before update on public.imperium_ordem_servico_fotos
for each row execute function private.imperium_touch_atualizado_em();

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit
)
values (
  'imperium-os-arquivos',
  'imperium-os-arquivos',
  false,
  20971520
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'imperium_os_arquivos_select'
  ) then
    create policy imperium_os_arquivos_select
    on storage.objects
    for select to authenticated
    using (
      bucket_id = 'imperium-os-arquivos'
      and case
        when split_part(name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (
          select private.imperium_pode_modulo(
            split_part(name, '/', 1)::uuid,
            'ordens_servico'
          )
        )
        else false
      end
    );
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'imperium_os_arquivos_insert'
  ) then
    create policy imperium_os_arquivos_insert
    on storage.objects
    for insert to authenticated
    with check (
      bucket_id = 'imperium-os-arquivos'
      and case
        when split_part(name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (
          select private.imperium_pode_modulo(
            split_part(name, '/', 1)::uuid,
            'ordens_servico'
          )
        )
        else false
      end
    );
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'imperium_os_arquivos_update'
  ) then
    create policy imperium_os_arquivos_update
    on storage.objects
    for update to authenticated
    using (
      bucket_id = 'imperium-os-arquivos'
      and case
        when split_part(name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (
          select private.imperium_pode_modulo(
            split_part(name, '/', 1)::uuid,
            'ordens_servico'
          )
        )
        else false
      end
    )
    with check (
      bucket_id = 'imperium-os-arquivos'
      and case
        when split_part(name, '/', 1) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (
          select private.imperium_pode_modulo(
            split_part(name, '/', 1)::uuid,
            'ordens_servico'
          )
        )
        else false
      end
    );
  end if;
end $$;
