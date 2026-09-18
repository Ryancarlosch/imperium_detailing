create table if not exists public.imperium_funcionario_realtime_sinais (
  acesso_id uuid not null
    references public.imperium_funcionario_acessos(id) on delete cascade,
  empresa_id uuid not null
    references public.empresas(id) on delete cascade,
  auth_user_id uuid not null,
  versao bigint not null default 1,
  evento text not null default 'acesso_atualizado',
  atualizado_em timestamptz not null default now(),
  primary key (acesso_id, auth_user_id)
);

alter table public.imperium_funcionario_realtime_sinais enable row level security;

revoke all on table public.imperium_funcionario_realtime_sinais from anon;
revoke all on table public.imperium_funcionario_realtime_sinais from authenticated;
grant select on table public.imperium_funcionario_realtime_sinais to authenticated;

drop policy if exists imperium_funcionario_realtime_proprio
  on public.imperium_funcionario_realtime_sinais;

create policy imperium_funcionario_realtime_proprio
on public.imperium_funcionario_realtime_sinais
for select
to authenticated
using (auth_user_id = (select auth.uid()));

create or replace function private.imperium_funcionario_realtime_sinalizar()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_evento text := 'acesso_atualizado';
begin
  if tg_op = 'UPDATE' then
    if old.ativo is distinct from new.ativo then
      v_evento := case
        when new.ativo then 'acesso_ativado'
        else 'acesso_desativado'
      end;
    elsif old.auth_user_id is distinct from new.auth_user_id
       or old.permitir_novo_dispositivo is distinct from new.permitir_novo_dispositivo then
      v_evento := 'vinculo_alterado';
    elsif old.permissoes is distinct from new.permissoes then
      v_evento := 'permissoes_alteradas';
    end if;
  end if;

  if tg_op = 'INSERT' then
    if new.auth_user_id is not null then
      insert into public.imperium_funcionario_realtime_sinais (
        acesso_id,
        empresa_id,
        auth_user_id,
        versao,
        evento,
        atualizado_em
      ) values (
        new.id,
        new.empresa_id,
        new.auth_user_id,
        1,
        'acesso_configurado',
        now()
      )
      on conflict (acesso_id, auth_user_id)
      do update set
        empresa_id = excluded.empresa_id,
        versao = public.imperium_funcionario_realtime_sinais.versao + 1,
        evento = excluded.evento,
        atualizado_em = excluded.atualizado_em;
    end if;

    return new;
  end if;

  if old.auth_user_id is not null then
    insert into public.imperium_funcionario_realtime_sinais (
      acesso_id,
      empresa_id,
      auth_user_id,
      versao,
      evento,
      atualizado_em
    ) values (
      new.id,
      new.empresa_id,
      old.auth_user_id,
      1,
      v_evento,
      now()
    )
    on conflict (acesso_id, auth_user_id)
    do update set
      empresa_id = excluded.empresa_id,
      versao = public.imperium_funcionario_realtime_sinais.versao + 1,
      evento = excluded.evento,
      atualizado_em = excluded.atualizado_em;
  end if;

  if new.auth_user_id is not null
     and new.auth_user_id is distinct from old.auth_user_id then
    insert into public.imperium_funcionario_realtime_sinais (
      acesso_id,
      empresa_id,
      auth_user_id,
      versao,
      evento,
      atualizado_em
    ) values (
      new.id,
      new.empresa_id,
      new.auth_user_id,
      1,
      v_evento,
      now()
    )
    on conflict (acesso_id, auth_user_id)
    do update set
      empresa_id = excluded.empresa_id,
      versao = public.imperium_funcionario_realtime_sinais.versao + 1,
      evento = excluded.evento,
      atualizado_em = excluded.atualizado_em;
  end if;

  return new;
end;
$$;

revoke all on function private.imperium_funcionario_realtime_sinalizar()
  from public;

drop trigger if exists trg_imperium_funcionario_realtime_sinal
  on public.imperium_funcionario_acessos;

create trigger trg_imperium_funcionario_realtime_sinal
after insert or update of
  permissoes,
  ativo,
  auth_user_id,
  permitir_novo_dispositivo,
  email,
  login
on public.imperium_funcionario_acessos
for each row
execute function private.imperium_funcionario_realtime_sinalizar();

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'imperium_funcionario_realtime_sinais'
  ) then
    alter publication supabase_realtime
      add table public.imperium_funcionario_realtime_sinais;
  end if;
end
$$;
