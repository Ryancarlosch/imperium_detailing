-- OS Cloud V5 - cancelamento Web transacional
-- Espelho da migration aplicada no Supabase em 2026-09-17.
-- Cancela apenas OS Aberta/Em andamento, com CAS, idempotencia,
-- liberacao de reserva, cancelamento de pendencias e agenda na mesma transacao.

create table if not exists public.imperium_os_cancelamentos_web (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  ordem_servico_id uuid not null,
  idempotency_key text not null,
  request_hash text not null,
  motivo text not null default '',
  origem_dispositivo text not null,
  origem_base bigint not null,
  resultado_json jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  constraint imperium_os_cancel_web_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico(empresa_id, id)
    on delete cascade,
  constraint imperium_os_cancel_web_os_uq
    unique (empresa_id, ordem_servico_id),
  constraint imperium_os_cancel_web_key_uq
    unique (empresa_id, idempotency_key),
  constraint imperium_os_cancel_web_origem_ck check (
    length(trim(origem_dispositivo)) > 0 and origem_base > 0
  )
);

alter table public.imperium_os_cancelamentos_web enable row level security;

revoke all on table public.imperium_os_cancelamentos_web from public, anon;
grant select, insert on table public.imperium_os_cancelamentos_web to authenticated;

drop policy if exists imperium_os_cancel_web_select
  on public.imperium_os_cancelamentos_web;
drop policy if exists imperium_os_cancel_web_insert
  on public.imperium_os_cancelamentos_web;

create policy imperium_os_cancel_web_select
on public.imperium_os_cancelamentos_web
for select to authenticated
using (
  private.imperium_pode_modulo(empresa_id, 'ordens_servico')
  and private.imperium_pode_modulo(empresa_id, 'estoque')
  and private.imperium_pode_modulo(empresa_id, 'financeiro')
);

create policy imperium_os_cancel_web_insert
on public.imperium_os_cancelamentos_web
for insert to authenticated
with check (
  private.imperium_pode_modulo(empresa_id, 'ordens_servico')
  and private.imperium_pode_modulo(empresa_id, 'estoque')
  and private.imperium_pode_modulo(empresa_id, 'financeiro')
);

create or replace function public.imperium_os_cancelar_web_v5(
  p_empresa_id uuid,
  p_ordem_id uuid,
  p_os_atualizado_em timestamptz,
  p_idempotency_key text,
  p_origem_dispositivo text,
  p_origem_base bigint,
  p_motivo text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_os public.imperium_ordens_servico%rowtype;
  v_exist public.imperium_os_cancelamentos_web%rowtype;
  v_request_hash text;
  v_result jsonb;
  v_estoque_result jsonb;
  v_pagamentos_cancelados integer := 0;
  v_agendamento_atualizado boolean := false;
  v_agora timestamptz := clock_timestamp();
begin
  if (select auth.uid()) is null then
    raise exception 'Sessao autenticada obrigatoria para cancelar OS.'
      using errcode = '42501';
  end if;

  if not private.imperium_pode_modulo(p_empresa_id, 'ordens_servico')
     or not private.imperium_pode_modulo(p_empresa_id, 'estoque')
     or not private.imperium_pode_modulo(p_empresa_id, 'financeiro') then
    raise exception
      'Cancelamento Web exige acesso a OS, Estoque e Financeiro.'
      using errcode = '42501';
  end if;

  if trim(coalesce(p_idempotency_key, '')) = ''
     or trim(coalesce(p_origem_dispositivo, '')) = ''
     or coalesce(p_origem_base, 0) <= 0 then
    raise exception 'Chave de idempotencia e origem Web sao obrigatorias.'
      using errcode = '22023';
  end if;

  if length(trim(coalesce(p_motivo, ''))) < 3 then
    raise exception 'Informe o motivo do cancelamento.'
      using errcode = '22023';
  end if;

  v_request_hash := md5(jsonb_build_object(
    'empresa', p_empresa_id,
    'os', p_ordem_id,
    'os_ts', p_os_atualizado_em,
    'motivo', trim(p_motivo)
  )::text);

  perform pg_advisory_xact_lock(
    hashtextextended(
      'imperium_os_cancelar:' || p_empresa_id::text || ':' || p_ordem_id::text,
      0
    )
  );

  select * into v_exist
  from public.imperium_os_cancelamentos_web
  where empresa_id = p_empresa_id
    and idempotency_key = p_idempotency_key;

  if found then
    if v_exist.request_hash <> v_request_hash then
      raise exception
        'Chave de idempotencia reutilizada com dados diferentes.'
        using errcode = '40001';
    end if;
    return v_exist.resultado_json;
  end if;

  select * into v_os
  from public.imperium_ordens_servico
  where empresa_id = p_empresa_id
    and id = p_ordem_id
    and excluido_em is null
  for update;

  if not found then
    raise exception 'OS nao encontrada.' using errcode = 'P0002';
  end if;

  if v_os.status = 'Cancelada' then
    return jsonb_build_object(
      'ordem_id', p_ordem_id,
      'status', 'Cancelada',
      'ja_cancelada', true,
      'pagamentos_cancelados', 0,
      'reserva', jsonb_build_object('status', 'sem_alteracao', 'quantidade', 0),
      'agendamento_atualizado', false
    );
  end if;

  if v_os.status = 'Finalizada' then
    raise exception
      'OS finalizada nao pode ser cancelada por este fluxo. Use estorno/correcao.'
      using errcode = '22023';
  end if;

  if v_os.status not in ('Aberta', 'Em andamento') then
    raise exception 'Somente OS Aberta ou Em andamento pode ser cancelada.'
      using errcode = '22023';
  end if;

  if p_os_atualizado_em is null
     or v_os.atualizado_em is distinct from p_os_atualizado_em then
    raise exception
      'A OS mudou em outro dispositivo. Atualize antes de cancelar.'
      using errcode = '40001';
  end if;

  if coalesce(v_os.valor_recebido, 0) > 0.000001
     or exists (
       select 1
       from public.imperium_financeiro_pagamentos_os p
       where p.empresa_id = p_empresa_id
         and p.ordem_servico_id = p_ordem_id
         and p.excluido_em is null
         and p.status = 'Pago'
     ) then
    raise exception
      'Estorne os pagamentos recebidos antes de cancelar esta OS.'
      using errcode = '22023';
  end if;

  if v_os.agendamento_id is not null
     and not private.imperium_pode_modulo(p_empresa_id, 'agenda') then
    raise exception
      'Esta OS possui agendamento vinculado; o cancelamento exige acesso a Agenda.'
      using errcode = '42501';
  end if;

  update public.imperium_financeiro_pagamentos_os
  set status = 'Cancelado',
      observacoes = case
        when trim(coalesce(observacoes, '')) = ''
          then 'Cancelado junto com a OS pelo Web.'
        else observacoes || ' | Cancelado junto com a OS pelo Web.'
      end,
      origem_atualizado_em = v_agora::text,
      atualizado_em = v_agora
  where empresa_id = p_empresa_id
    and ordem_servico_id = p_ordem_id
    and excluido_em is null
    and status = 'Pendente';

  get diagnostics v_pagamentos_cancelados = row_count;

  v_estoque_result := public.imperium_estoque_liberar_reserva_os(
    p_empresa_id,
    p_ordem_id
  );

  update public.imperium_ordens_servico
  set status = 'Cancelada',
      status_pagamento = 'Cancelado',
      vencimento_pagamento = null,
      pagamento_atualizado_em = v_agora,
      atualizado_em = v_agora
  where empresa_id = p_empresa_id
    and id = p_ordem_id
  returning * into v_os;

  if v_os.agendamento_id is not null then
    update public.imperium_agendamentos
    set status = 'Cancelado',
        atualizado_em = v_agora
    where empresa_id = p_empresa_id
      and id = v_os.agendamento_id
      and excluido_em is null;
    v_agendamento_atualizado := found;
  end if;

  v_result := jsonb_build_object(
    'ordem_id', p_ordem_id,
    'status', 'Cancelada',
    'ja_cancelada', false,
    'motivo', trim(p_motivo),
    'pagamentos_cancelados', v_pagamentos_cancelados,
    'reserva', v_estoque_result,
    'agendamento_atualizado', v_agendamento_atualizado,
    'atualizado_em', v_os.atualizado_em
  );

  insert into public.imperium_os_cancelamentos_web(
    empresa_id,
    ordem_servico_id,
    idempotency_key,
    request_hash,
    motivo,
    origem_dispositivo,
    origem_base,
    resultado_json
  ) values (
    p_empresa_id,
    p_ordem_id,
    p_idempotency_key,
    v_request_hash,
    trim(p_motivo),
    p_origem_dispositivo,
    p_origem_base,
    v_result
  );

  return v_result;
end;
$$;

revoke all on function public.imperium_os_cancelar_web_v5(
  uuid, uuid, timestamptz, text, text, bigint, text
) from public, anon;

grant execute on function public.imperium_os_cancelar_web_v5(
  uuid, uuid, timestamptz, text, text, bigint, text
) to authenticated;
