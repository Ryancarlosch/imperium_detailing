alter table public.imperium_financeiro_pagamentos_os
  add column if not exists estorno_web_modo text,
  add column if not exists estorno_web_idempotency_key text,
  add column if not exists estorno_web_request_hash text,
  add column if not exists estorno_web_resultado jsonb;

create unique index if not exists idx_imperium_fin_pag_estorno_web_key
  on public.imperium_financeiro_pagamentos_os(
    empresa_id,
    estorno_web_idempotency_key
  )
  where estorno_web_idempotency_key is not null;

create or replace function private.imperium_ajuste_taxa_estorno_guard()
returns trigger
language plpgsql
security invoker
set search_path = public, private, pg_temp
as $$
declare
  v_estornado_em text;
begin
  if new.pagamento_id is null
     or trim(coalesce(new.origem,'')) <> 'Taxa de maquininha' then
    return new;
  end if;

  select p.estornado_em
    into v_estornado_em
  from public.imperium_financeiro_pagamentos_os p
  where p.empresa_id = new.empresa_id
    and p.id = new.pagamento_id
    and p.status = 'Estornado'
    and p.excluido_em is null;

  if found then
    new.status := 'Cancelado';
    new.cancelado_em := coalesce(
      nullif(trim(coalesce(new.cancelado_em,'')),''),
      nullif(trim(coalesce(v_estornado_em,'')),''),
      clock_timestamp()::text
    );

    if trim(coalesce(new.motivo_cancelamento,'')) = '' then
      new.motivo_cancelamento :=
        'Cancelado automaticamente porque o pagamento vinculado foi estornado.';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.imperium_ajuste_taxa_estorno_guard()
  from public, anon;
grant execute on function private.imperium_ajuste_taxa_estorno_guard()
  to authenticated;

drop trigger if exists trg_imperium_os_ajuste_taxa_estorno_guard
  on public.imperium_ordem_servico_ajustes_financeiros;
create trigger trg_imperium_os_ajuste_taxa_estorno_guard
before insert or update
on public.imperium_ordem_servico_ajustes_financeiros
for each row
execute function private.imperium_ajuste_taxa_estorno_guard();

create or replace function public.imperium_financeiro_estornar_pagamento_web_v1(
  p_empresa_id uuid,
  p_pagamento_id uuid,
  p_pagamento_atualizado_em timestamptz,
  p_modo text,
  p_motivo text,
  p_idempotency_key text,
  p_origem_dispositivo text,
  p_origem_base bigint,
  p_timezone text default 'America/Sao_Paulo'
)
returns jsonb
language plpgsql
security invoker
set search_path = public, private, pg_temp
as $$
declare
  v_pagamento public.imperium_financeiro_pagamentos_os%rowtype;
  v_os public.imperium_ordens_servico%rowtype;
  v_modo text := lower(trim(coalesce(p_modo,'')));
  v_motivo text := trim(coalesce(p_motivo,''));
  v_agora timestamptz := clock_timestamp();
  v_agora_local text;
  v_request_hash text;
  v_repasse numeric := 0;
  v_desconto numeric := 0;
  v_acrescimo numeric := 0;
  v_juros numeric := 0;
  v_total numeric := 0;
  v_recebido numeric := 0;
  v_saldo numeric := 0;
  v_valor_reaberto numeric := 0;
  v_status_pagamento text;
  v_vencimento text;
  v_forma_resumo text;
  v_formas_count bigint := 0;
  v_forma_unica text;
  v_conta_id uuid;
  v_plano_estorno_id uuid;
  v_movimento_estorno_id uuid;
  v_pagamento_reaberto_id uuid;
  v_ajustes_cancelados bigint := 0;
  v_movimentos_cancelados bigint := 0;
  v_result jsonb;
begin
  if not private.imperium_pode_modulo(p_empresa_id,'financeiro')
     or not private.imperium_pode_modulo(p_empresa_id,'ordens_servico') then
    raise exception
      'Estorno Web exige acesso a Financeiro e Ordens de Serviço.'
      using errcode='42501';
  end if;

  if v_modo not in ('correcao','devolucao') then
    raise exception 'Modo de estorno inválido.' using errcode='22023';
  end if;

  if length(v_motivo) < 5 then
    raise exception 'Informe um motivo com pelo menos 5 caracteres.'
      using errcode='22023';
  end if;

  if trim(coalesce(p_idempotency_key,'')) = ''
     or trim(coalesce(p_origem_dispositivo,'')) = ''
     or coalesce(p_origem_base,0) <= 0 then
    raise exception 'Chave de idempotência e origem Web são obrigatórias.'
      using errcode='22023';
  end if;

  if not exists(
    select 1 from pg_timezone_names where name = p_timezone
  ) then
    raise exception 'Timezone inválido.' using errcode='22023';
  end if;

  v_request_hash := md5(
    jsonb_build_object(
      'empresa', p_empresa_id,
      'pagamento', p_pagamento_id,
      'pagamento_ts', p_pagamento_atualizado_em,
      'modo', v_modo,
      'motivo', v_motivo
    )::text
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      'imperium_fin_estorno:' || p_empresa_id::text || ':' ||
      p_pagamento_id::text,
      0
    )
  );

  select * into v_pagamento
  from public.imperium_financeiro_pagamentos_os p
  where p.empresa_id = p_empresa_id
    and p.id = p_pagamento_id
    and p.excluido_em is null
  for update;

  if not found then
    raise exception 'Pagamento não encontrado.' using errcode='P0002';
  end if;

  if v_pagamento.estorno_web_idempotency_key = p_idempotency_key then
    if coalesce(v_pagamento.estorno_web_request_hash,'') <> v_request_hash then
      raise exception
        'Chave de idempotência reutilizada com dados diferentes.'
        using errcode='40001';
    end if;

    if v_pagamento.status = 'Estornado'
       and v_pagamento.estorno_web_resultado is not null then
      return v_pagamento.estorno_web_resultado;
    end if;
  end if;

  if v_pagamento.status <> 'Pago' then
    raise exception 'Somente pagamentos confirmados podem ser estornados.'
      using errcode='22023';
  end if;

  if p_pagamento_atualizado_em is null
     or v_pagamento.atualizado_em is distinct from p_pagamento_atualizado_em then
    raise exception
      'O pagamento mudou em outro dispositivo. Atualize antes de estornar.'
      using errcode='40001';
  end if;

  select * into v_os
  from public.imperium_ordens_servico os
  where os.empresa_id = p_empresa_id
    and os.id = v_pagamento.ordem_servico_id
    and os.excluido_em is null
  for update;

  if not found then
    raise exception 'Ordem de Serviço do pagamento não encontrada.'
      using errcode='P0002';
  end if;

  v_agora_local := to_char(
    v_agora at time zone p_timezone,
    'YYYY-MM-DD"T"HH24:MI:SS'
  );

  select coalesce(sum(a.valor),0)
    into v_repasse
  from public.imperium_ordem_servico_ajustes_financeiros a
  where a.empresa_id = p_empresa_id
    and a.pagamento_id = p_pagamento_id
    and a.status = 'Ativo'
    and a.origem = 'Taxa de maquininha';

  select m.conta_id
    into v_conta_id
  from public.imperium_financeiro_movimentos m
  where m.empresa_id = p_empresa_id
    and m.pagamento_id = p_pagamento_id
    and lower(trim(m.tipo)) = 'entrada'
    and m.status = 'Realizado'
    and m.excluido_em is null
  order by m.criado_em, m.id
  limit 1;

  update public.imperium_financeiro_pagamentos_os
  set status = 'Estornado',
      estornado_em = v_agora_local,
      motivo_estorno = case
        when v_modo = 'correcao' then 'Correção: ' || v_motivo
        else 'Devolução: ' || v_motivo
      end,
      estorno_web_modo = v_modo,
      estorno_web_idempotency_key = p_idempotency_key,
      estorno_web_request_hash = v_request_hash,
      estorno_web_resultado = null,
      origem_atualizado_em = v_agora_local
  where empresa_id = p_empresa_id
    and id = p_pagamento_id;

  if v_modo = 'correcao' then
    update public.imperium_financeiro_movimentos
    set status = 'Cancelado',
        observacoes = 'Correção de recebimento: ' || v_motivo
    where empresa_id = p_empresa_id
      and pagamento_id = p_pagamento_id
      and status = 'Realizado'
      and excluido_em is null;

    get diagnostics v_movimentos_cancelados = row_count;
  end if;

  update public.imperium_ordem_servico_ajustes_financeiros
  set status = 'Cancelado',
      cancelado_em = v_agora_local,
      motivo_cancelamento = case
        when v_modo = 'correcao'
          then 'Cancelado automaticamente pela correção do recebimento.'
        else 'Cancelado automaticamente pelo estorno do pagamento.'
      end
  where empresa_id = p_empresa_id
    and pagamento_id = p_pagamento_id
    and status = 'Ativo'
    and origem = 'Taxa de maquininha';

  get diagnostics v_ajustes_cancelados = row_count;

  if v_modo = 'devolucao' then
    select pc.id into v_plano_estorno_id
    from public.imperium_financeiro_plano_contas pc
    where pc.empresa_id = p_empresa_id
      and pc.codigo = '1.02.01'
      and pc.ativo
      and pc.excluido_em is null
    limit 1;

    insert into public.imperium_financeiro_movimentos(
      empresa_id,
      origem_dispositivo,
      origem_local_id,
      tipo,
      descricao,
      valor,
      forma_pagamento,
      data,
      cliente_id,
      agendamento_id,
      ordem_servico_id,
      pagamento_id,
      plano_conta_id,
      conta_id,
      origem_cliente_local_id,
      origem_agendamento_local_id,
      origem_ordem_servico_local_id,
      origem_pagamento_local_id,
      origem_plano_conta_local_id,
      origem_conta_local_id,
      natureza,
      origem,
      status,
      data_competencia,
      data_pagamento,
      numero_documento,
      observacoes,
      impacta_dre
    ) values (
      p_empresa_id,
      p_origem_dispositivo,
      p_origem_base + 2,
      'saída',
      'Devolução ao cliente - OS ' || v_os.numero,
      v_pagamento.valor,
      case
        when trim(coalesce(v_pagamento.forma_pagamento,'')) = ''
          then 'Não informado'
        else v_pagamento.forma_pagamento
      end,
      v_agora_local,
      v_os.cliente_id,
      null,
      v_os.id,
      v_pagamento.id,
      v_plano_estorno_id,
      v_conta_id,
      null,
      null,
      v_os.origem_local_id,
      v_pagamento.origem_local_id,
      null,
      null,
      'Dedução de receita',
      'Devolução ao cliente',
      'Realizado',
      v_agora_local,
      v_agora_local,
      '',
      v_motivo,
      true
    )
    returning id into v_movimento_estorno_id;
  end if;

  if v_pagamento.parcela_numero is not null
     and v_pagamento.total_parcelas is not null then
    v_valor_reaberto := greatest(v_pagamento.valor - v_repasse, 0);

    insert into public.imperium_financeiro_pagamentos_os(
      empresa_id,
      ordem_servico_id,
      origem_dispositivo,
      origem_local_id,
      status,
      valor,
      forma_pagamento,
      data_pagamento,
      parcela_numero,
      total_parcelas,
      vencimento,
      observacoes,
      taxa_percentual,
      taxa_operacao,
      valor_liquido,
      parcelas_taxa,
      estornado_em,
      motivo_estorno,
      origem_criado_em,
      origem_atualizado_em
    ) values (
      p_empresa_id,
      v_pagamento.ordem_servico_id,
      p_origem_dispositivo,
      p_origem_base + 1,
      'Pendente',
      v_valor_reaberto,
      '',
      null,
      v_pagamento.parcela_numero,
      v_pagamento.total_parcelas,
      v_pagamento.vencimento,
      case
        when v_modo = 'correcao'
          then 'Parcela reaberta após correção do pagamento ' || p_pagamento_id::text || '.'
        else 'Parcela reaberta após estorno do pagamento ' || p_pagamento_id::text || '.'
      end,
      null,
      0,
      0,
      1,
      null,
      '',
      v_agora_local,
      v_agora_local
    )
    returning id into v_pagamento_reaberto_id;
  end if;

  select
    coalesce(sum(case when a.tipo = 'Desconto' and a.status = 'Ativo' then a.valor else 0 end),0),
    coalesce(sum(case when a.tipo = 'Acréscimo' and a.status = 'Ativo' then a.valor else 0 end),0),
    coalesce(sum(case when a.tipo = 'Juros' and a.status = 'Ativo' then a.valor else 0 end),0)
  into v_desconto, v_acrescimo, v_juros
  from public.imperium_ordem_servico_ajustes_financeiros a
  where a.empresa_id = p_empresa_id
    and a.ordem_servico_id = v_os.id;

  v_total := greatest(
    greatest(coalesce(v_os.valor_total,0) - coalesce(v_os.desconto,0),0)
      - v_desconto + v_acrescimo + v_juros,
    0
  );

  select coalesce(sum(p.valor),0)
    into v_recebido
  from public.imperium_financeiro_pagamentos_os p
  where p.empresa_id = p_empresa_id
    and p.ordem_servico_id = v_os.id
    and p.status = 'Pago'
    and p.excluido_em is null;

  if v_total + 0.000001 < v_recebido then
    raise exception
      'O estorno deixaria o valor negociado abaixo do total ainda recebido.'
      using errcode='22023';
  end if;

  v_saldo := greatest(v_total - v_recebido, 0);

  select min(nullif(trim(p.vencimento),''))
    into v_vencimento
  from public.imperium_financeiro_pagamentos_os p
  where p.empresa_id = p_empresa_id
    and p.ordem_servico_id = v_os.id
    and p.status = 'Pendente'
    and p.vencimento is not null;

  v_vencimento := coalesce(
    v_vencimento,
    nullif(trim(coalesce(v_os.vencimento_pagamento,'')),'')
  );

  select
    count(distinct trim(p.forma_pagamento)),
    min(trim(p.forma_pagamento))
  into v_formas_count, v_forma_unica
  from public.imperium_financeiro_pagamentos_os p
  where p.empresa_id = p_empresa_id
    and p.ordem_servico_id = v_os.id
    and p.status = 'Pago'
    and trim(coalesce(p.forma_pagamento,'')) <> ''
    and p.excluido_em is null;

  v_forma_resumo := case
    when v_formas_count = 0 then null
    when v_formas_count = 1 then v_forma_unica
    else 'Múltiplas formas'
  end;

  v_status_pagamento := case
    when v_os.status = 'Cancelada' then 'Cancelado'
    when v_total <= 0.000001 or v_saldo <= 0.000001 then 'Pago'
    when v_vencimento is not null
      and substr(v_vencimento,1,10) < to_char(
        v_agora at time zone p_timezone,
        'YYYY-MM-DD'
      ) then 'Vencido'
    when v_recebido > 0.000001 then 'Parcialmente pago'
    else 'Pendente'
  end;

  update public.imperium_ordens_servico
  set desconto_negociacao = v_desconto,
      acrescimo_negociacao = v_acrescimo,
      juros_parcelamento = v_juros,
      status_pagamento = v_status_pagamento,
      valor_recebido = v_recebido,
      vencimento_pagamento = v_vencimento,
      pagamento_atualizado_em = v_agora,
      forma_pagamento = v_forma_resumo
  where empresa_id = p_empresa_id
    and id = v_os.id
  returning * into v_os;

  v_result := jsonb_build_object(
    'pagamento_id', p_pagamento_id,
    'ordem_id', v_os.id,
    'modo', v_modo,
    'status', 'Estornado',
    'valor_estornado', v_pagamento.valor,
    'repasse_cancelado', v_repasse,
    'ajustes_cancelados', v_ajustes_cancelados,
    'movimentos_cancelados', v_movimentos_cancelados,
    'movimento_devolucao_id', v_movimento_estorno_id,
    'pagamento_reaberto_id', v_pagamento_reaberto_id,
    'valor_recebido', v_recebido,
    'status_pagamento', v_status_pagamento,
    'vencimento_pagamento', v_vencimento
  );

  update public.imperium_financeiro_pagamentos_os
  set estorno_web_resultado = v_result,
      origem_atualizado_em = v_agora_local
  where empresa_id = p_empresa_id
    and id = p_pagamento_id;

  return v_result;
end;
$$;

revoke all on function public.imperium_financeiro_estornar_pagamento_web_v1(
  uuid,uuid,timestamptz,text,text,text,text,bigint,text
) from public, anon;
grant execute on function public.imperium_financeiro_estornar_pagamento_web_v1(
  uuid,uuid,timestamptz,text,text,text,text,bigint,text
) to authenticated;
