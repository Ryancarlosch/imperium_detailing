create table if not exists public.imperium_estoque_reservas_os (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null,
  ordem_servico_id uuid not null,
  item_estoque_id uuid not null,
  quantidade numeric(18,6) not null check (quantidade > 0),
  status text not null default 'Ativa'
    check (status in ('Ativa','Consumida','Liberada')),
  origem_dispositivo text,
  origem_os_local_id bigint,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  consumida_em timestamptz,
  liberada_em timestamptz,
  constraint imperium_estoque_reservas_os_uq
    unique (empresa_id, ordem_servico_id, item_estoque_id),
  constraint imperium_estoque_reservas_os_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico (empresa_id, id),
  constraint imperium_estoque_reservas_os_item_fk
    foreign key (empresa_id, item_estoque_id)
    references public.imperium_estoque_itens (empresa_id, id)
);

create index if not exists imperium_estoque_reservas_os_ativas_idx
  on public.imperium_estoque_reservas_os
  (empresa_id, item_estoque_id, status);

create table if not exists public.imperium_estoque_alertas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null,
  item_estoque_id uuid not null,
  tipo text not null default 'Estoque baixo',
  status text not null default 'Ativo'
    check (status in ('Ativo','Resolvido')),
  mensagem text not null default '',
  saldo_atual numeric(18,6) not null default 0,
  limite numeric(18,6) not null default 0,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  resolvido_em timestamptz,
  constraint imperium_estoque_alertas_uq
    unique (empresa_id, item_estoque_id, tipo),
  constraint imperium_estoque_alertas_item_fk
    foreign key (empresa_id, item_estoque_id)
    references public.imperium_estoque_itens (empresa_id, id)
);

alter table public.imperium_estoque_reservas_os enable row level security;
alter table public.imperium_estoque_alertas enable row level security;

revoke all on public.imperium_estoque_reservas_os from anon, authenticated;
revoke all on public.imperium_estoque_alertas from anon, authenticated;
grant select on public.imperium_estoque_reservas_os to authenticated;
grant select on public.imperium_estoque_alertas to authenticated;

create policy imperium_estoque_reservas_os_select
on public.imperium_estoque_reservas_os
for select
to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'estoque')));

create policy imperium_estoque_alertas_select
on public.imperium_estoque_alertas
for select
to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'estoque')));

create or replace function private.imperium_estoque_atualizar_alerta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.excluido_em is null
     and new.ativo
     and new.quantidade <= new.quantidade_minima then
    insert into public.imperium_estoque_alertas (
      empresa_id, item_estoque_id, tipo, status, mensagem,
      saldo_atual, limite, criado_em, atualizado_em, resolvido_em
    ) values (
      new.empresa_id,
      new.id,
      'Estoque baixo',
      'Ativo',
      'Estoque baixo: ' || new.nome || ' (' || new.quantidade::text ||
        ' / minimo ' || new.quantidade_minima::text || ')',
      new.quantidade,
      new.quantidade_minima,
      now(),
      now(),
      null
    )
    on conflict (empresa_id, item_estoque_id, tipo)
    do update set
      status = 'Ativo',
      mensagem = excluded.mensagem,
      saldo_atual = excluded.saldo_atual,
      limite = excluded.limite,
      atualizado_em = now(),
      resolvido_em = null;
  else
    update public.imperium_estoque_alertas
    set status = 'Resolvido',
        saldo_atual = new.quantidade,
        limite = new.quantidade_minima,
        atualizado_em = now(),
        resolvido_em = coalesce(resolvido_em, now())
    where empresa_id = new.empresa_id
      and item_estoque_id = new.id
      and tipo = 'Estoque baixo'
      and status <> 'Resolvido';
  end if;

  return new;
end;
$$;

revoke execute on function private.imperium_estoque_atualizar_alerta()
from public, anon, authenticated;

drop trigger if exists imperium_estoque_itens_alerta_trg
on public.imperium_estoque_itens;

create trigger imperium_estoque_itens_alerta_trg
after insert or update of quantidade, quantidade_minima, ativo, excluido_em
on public.imperium_estoque_itens
for each row
execute function private.imperium_estoque_atualizar_alerta();

insert into public.imperium_estoque_alertas (
  empresa_id, item_estoque_id, tipo, status, mensagem,
  saldo_atual, limite, criado_em, atualizado_em, resolvido_em
)
select
  i.empresa_id,
  i.id,
  'Estoque baixo',
  'Ativo',
  'Estoque baixo: ' || i.nome || ' (' || i.quantidade::text ||
    ' / minimo ' || i.quantidade_minima::text || ')',
  i.quantidade,
  i.quantidade_minima,
  now(),
  now(),
  null
from public.imperium_estoque_itens i
where i.excluido_em is null
  and i.ativo
  and i.quantidade <= i.quantidade_minima
on conflict (empresa_id, item_estoque_id, tipo)
do update set
  status = 'Ativo',
  mensagem = excluded.mensagem,
  saldo_atual = excluded.saldo_atual,
  limite = excluded.limite,
  atualizado_em = now(),
  resolvido_em = null;

create or replace function public.imperium_estoque_reservar_os(
  p_empresa_id uuid,
  p_ordem_servico_id uuid,
  p_reservas jsonb,
  p_origem_dispositivo text default null,
  p_origem_os_local_id bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_saldo numeric;
  v_reservado numeric;
  v_result jsonb := '[]'::jsonb;
begin
  if (select auth.uid()) is null
     or not private.imperium_pode_modulo(p_empresa_id, 'estoque') then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para reservar estoque.';
  end if;

  if not exists (
    select 1
    from public.imperium_ordens_servico os
    where os.empresa_id = p_empresa_id
      and os.id = p_ordem_servico_id
      and os.excluido_em is null
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'Ordem de Servico remota nao encontrada.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('imperium_estoque:' || p_empresa_id::text)::bigint
  );

  if exists (
    select 1
    from public.imperium_estoque_reservas_os r0
    where r0.empresa_id = p_empresa_id
      and r0.ordem_servico_id = p_ordem_servico_id
      and r0.status = 'Consumida'
  ) then
    return jsonb_build_object(
      'status', 'ja_consumida',
      'reservas', '[]'::jsonb
    );
  end if;

  update public.imperium_estoque_reservas_os
  set status = 'Liberada',
      liberada_em = now(),
      atualizado_em = now()
  where empresa_id = p_empresa_id
    and ordem_servico_id = p_ordem_servico_id
    and status = 'Ativa';

  for r in
    select x.item_estoque_id, sum(x.quantidade)::numeric as quantidade
    from jsonb_to_recordset(coalesce(p_reservas, '[]'::jsonb))
      as x(item_estoque_id uuid, quantidade numeric)
    where x.item_estoque_id is not null
      and x.quantidade > 0
    group by x.item_estoque_id
    order by x.item_estoque_id
  loop
    select i.quantidade
      into v_saldo
    from public.imperium_estoque_itens i
    where i.empresa_id = p_empresa_id
      and i.id = r.item_estoque_id
      and i.excluido_em is null
      and i.ativo
    for update;

    if v_saldo is null then
      raise exception using
        errcode = 'P0001',
        message = 'Item remoto de estoque nao encontrado ou inativo.';
    end if;

    select coalesce(sum(ro.quantidade), 0)
      into v_reservado
    from public.imperium_estoque_reservas_os ro
    where ro.empresa_id = p_empresa_id
      and ro.item_estoque_id = r.item_estoque_id
      and ro.status = 'Ativa';

    if r.quantidade > (v_saldo - v_reservado) + 0.000001 then
      raise exception using
        errcode = 'P0001',
        message = 'Estoque remoto insuficiente para reservar item ' ||
          r.item_estoque_id::text || '. Disponivel: ' ||
          greatest(v_saldo - v_reservado, 0)::text ||
          '. Necessario: ' || r.quantidade::text || '.';
    end if;

    insert into public.imperium_estoque_reservas_os (
      empresa_id, ordem_servico_id, item_estoque_id, quantidade,
      status, origem_dispositivo, origem_os_local_id,
      criado_em, atualizado_em, consumida_em, liberada_em
    ) values (
      p_empresa_id, p_ordem_servico_id, r.item_estoque_id, r.quantidade,
      'Ativa', nullif(trim(coalesce(p_origem_dispositivo, '')), ''),
      p_origem_os_local_id, now(), now(), null, null
    )
    on conflict (empresa_id, ordem_servico_id, item_estoque_id)
    do update set
      quantidade = excluded.quantidade,
      status = 'Ativa',
      origem_dispositivo = excluded.origem_dispositivo,
      origem_os_local_id = excluded.origem_os_local_id,
      atualizado_em = now(),
      consumida_em = null,
      liberada_em = null;

    v_result := v_result || jsonb_build_array(
      jsonb_build_object(
        'item_estoque_id', r.item_estoque_id,
        'quantidade', r.quantidade,
        'saldo_remoto', v_saldo,
        'reservado_outros', v_reservado
      )
    );
  end loop;

  return jsonb_build_object('status', 'reservada', 'reservas', v_result);
end;
$$;

create or replace function public.imperium_estoque_consumir_reserva_os(
  p_empresa_id uuid,
  p_ordem_servico_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_novo_saldo numeric;
  v_atualizado_em timestamptz;
  v_result jsonb := '[]'::jsonb;
begin
  if (select auth.uid()) is null
     or not private.imperium_pode_modulo(p_empresa_id, 'estoque') then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para consumir reserva de estoque.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('imperium_estoque:' || p_empresa_id::text)::bigint
  );

  if not exists (
    select 1
    from public.imperium_estoque_reservas_os ro
    where ro.empresa_id = p_empresa_id
      and ro.ordem_servico_id = p_ordem_servico_id
      and ro.status = 'Ativa'
  ) then
    if exists (
      select 1
      from public.imperium_estoque_reservas_os ro
      where ro.empresa_id = p_empresa_id
        and ro.ordem_servico_id = p_ordem_servico_id
        and ro.status = 'Consumida'
    ) then
      return jsonb_build_object(
        'status', 'ja_consumida',
        'itens', '[]'::jsonb
      );
    end if;

    return jsonb_build_object('status', 'sem_reserva', 'itens', '[]'::jsonb);
  end if;

  for r in
    select ro.id, ro.item_estoque_id, ro.quantidade
    from public.imperium_estoque_reservas_os ro
    where ro.empresa_id = p_empresa_id
      and ro.ordem_servico_id = p_ordem_servico_id
      and ro.status = 'Ativa'
    order by ro.item_estoque_id
  loop
    select i.quantidade
      into v_novo_saldo
    from public.imperium_estoque_itens i
    where i.empresa_id = p_empresa_id
      and i.id = r.item_estoque_id
      and i.excluido_em is null
      and i.ativo
    for update;

    if v_novo_saldo is null then
      raise exception using
        errcode = 'P0001',
        message = 'Item remoto reservado nao existe mais ou esta inativo.';
    end if;

    if r.quantidade > v_novo_saldo + 0.000001 then
      raise exception using
        errcode = 'P0001',
        message = 'Saldo remoto ficou insuficiente antes do consumo da reserva.';
    end if;

    update public.imperium_estoque_itens
    set quantidade = greatest(quantidade - r.quantidade, 0),
        atualizado_em = now()
    where empresa_id = p_empresa_id
      and id = r.item_estoque_id
    returning quantidade, atualizado_em
      into v_novo_saldo, v_atualizado_em;

    update public.imperium_estoque_reservas_os
    set status = 'Consumida',
        consumida_em = now(),
        atualizado_em = now(),
        liberada_em = null
    where id = r.id;

    v_result := v_result || jsonb_build_array(
      jsonb_build_object(
        'item_estoque_id', r.item_estoque_id,
        'quantidade_consumida', r.quantidade,
        'quantidade_posterior', v_novo_saldo,
        'atualizado_em', v_atualizado_em
      )
    );
  end loop;

  return jsonb_build_object('status', 'consumida', 'itens', v_result);
end;
$$;

create or replace function public.imperium_estoque_liberar_reserva_os(
  p_empresa_id uuid,
  p_ordem_servico_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_total integer;
begin
  if (select auth.uid()) is null
     or not private.imperium_pode_modulo(p_empresa_id, 'estoque') then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para liberar reserva de estoque.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('imperium_estoque:' || p_empresa_id::text)::bigint
  );

  update public.imperium_estoque_reservas_os
  set status = 'Liberada',
      liberada_em = now(),
      atualizado_em = now()
  where empresa_id = p_empresa_id
    and ordem_servico_id = p_ordem_servico_id
    and status = 'Ativa';

  get diagnostics v_total = row_count;

  return jsonb_build_object('status', 'liberada', 'quantidade', v_total);
end;
$$;

revoke execute on function public.imperium_estoque_reservar_os(
  uuid, uuid, jsonb, text, bigint
) from public, anon;
revoke execute on function public.imperium_estoque_consumir_reserva_os(
  uuid, uuid
) from public, anon;
revoke execute on function public.imperium_estoque_liberar_reserva_os(
  uuid, uuid
) from public, anon;

grant execute on function public.imperium_estoque_reservar_os(
  uuid, uuid, jsonb, text, bigint
) to authenticated;
grant execute on function public.imperium_estoque_consumir_reserva_os(
  uuid, uuid
) to authenticated;
grant execute on function public.imperium_estoque_liberar_reserva_os(
  uuid, uuid
) to authenticated;
