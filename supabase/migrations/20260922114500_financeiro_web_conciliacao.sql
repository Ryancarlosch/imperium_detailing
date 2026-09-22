create or replace function public.imperium_financeiro_conciliar_web(
  p_empresa_id uuid,
  p_conta_id uuid,
  p_data text,
  p_saldo_informado numeric,
  p_criar_ajuste boolean,
  p_observacoes text,
  p_origem_dispositivo text,
  p_conciliacao_local_id bigint,
  p_movimento_local_id bigint
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_nome_conta text;
  v_conta_ativa boolean;
  v_saldo_inicial numeric := 0;
  v_data_saldo text;
  v_movimentos numeric := 0;
  v_saldo_calculado numeric := 0;
  v_diferenca numeric := 0;
  v_status text := 'Conciliado';
  v_plano_conta_id uuid;
  v_natureza text := 'Ajuste de caixa';
  v_movimento_id uuid;
  v_conciliacao_id uuid;
  v_tipo text;
  v_valor numeric;
  v_data timestamp;
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;

  if nullif(trim(coalesce(p_origem_dispositivo, '')), '') is null then
    raise exception 'Origem do dispositivo inválida.';
  end if;

  if coalesce(p_conciliacao_local_id, 0) <= 0 then
    raise exception 'Origem local da conciliação inválida.';
  end if;

  begin
    v_data := p_data::timestamp;
  exception when others then
    raise exception 'Data de conciliação inválida.';
  end;

  select nome, ativo, saldo_inicial, data_saldo_inicial
  into v_nome_conta, v_conta_ativa, v_saldo_inicial, v_data_saldo
  from public.imperium_financeiro_contas
  where empresa_id = p_empresa_id
    and id = p_conta_id
    and excluido_em is null;

  if not found then
    raise exception 'Conta financeira não encontrada ou sem acesso.';
  end if;

  if v_data_saldo is not null
     and nullif(trim(v_data_saldo), '') is not null
     and date(v_data) < date(v_data_saldo::timestamp) then
    v_saldo_calculado := 0;
  else
    select coalesce(sum(
      case
        when lower(tipo) = 'entrada' then valor
        when lower(tipo) in ('saída', 'saida') then -valor
        else 0
      end
    ), 0)
    into v_movimentos
    from public.imperium_financeiro_movimentos
    where empresa_id = p_empresa_id
      and conta_id = p_conta_id
      and status = 'Realizado'
      and excluido_em is null
      and date(coalesce(nullif(data_pagamento, ''), data)::timestamp) <= date(v_data)
      and (
        v_data_saldo is null
        or nullif(trim(v_data_saldo), '') is null
        or date(coalesce(nullif(data_pagamento, ''), data)::timestamp)
          >= date(v_data_saldo::timestamp)
      );

    v_saldo_calculado := coalesce(v_saldo_inicial, 0) + coalesce(v_movimentos, 0);
  end if;

  v_diferenca := coalesce(p_saldo_informado, 0) - v_saldo_calculado;
  if abs(v_diferenca) < 0.005 then
    v_diferenca := 0;
  end if;

  if coalesce(p_criar_ajuste, false) and v_diferenca <> 0 then
    if not coalesce(v_conta_ativa, false) then
      raise exception 'Não é possível criar ajuste em uma conta financeira inativa.';
    end if;

    if coalesce(p_movimento_local_id, 0) <= 0 then
      raise exception 'Origem local do ajuste financeiro inválida.';
    end if;

    select id, natureza
    into v_plano_conta_id, v_natureza
    from public.imperium_financeiro_plano_contas
    where empresa_id = p_empresa_id
      and codigo = '9.05'
      and ativo = true
      and excluido_em is null
    limit 1;

    if v_plano_conta_id is null then
      raise exception 'A categoria Correção de caixa (9.05) não foi encontrada.';
    end if;

    v_tipo := case when v_diferenca > 0 then 'Entrada' else 'Saída' end;
    v_valor := abs(v_diferenca);

    insert into public.imperium_financeiro_movimentos (
      empresa_id,
      origem_dispositivo,
      origem_local_id,
      tipo,
      descricao,
      valor,
      forma_pagamento,
      data,
      plano_conta_id,
      conta_id,
      total_parcelas,
      natureza,
      origem,
      status,
      data_competencia,
      data_pagamento,
      numero_documento,
      observacoes,
      impacta_dre,
      criado_em,
      atualizado_em
    ) values (
      p_empresa_id,
      p_origem_dispositivo,
      p_movimento_local_id,
      v_tipo,
      'Ajuste de conciliação - ' || coalesce(nullif(trim(v_nome_conta), ''), 'Conta'),
      v_valor,
      'Ajuste',
      p_data,
      v_plano_conta_id,
      p_conta_id,
      1,
      coalesce(nullif(trim(v_natureza), ''), 'Ajuste de caixa'),
      'Conciliação de conta',
      'Realizado',
      p_data,
      p_data,
      '',
      case
        when nullif(trim(coalesce(p_observacoes, '')), '') is null
          then 'Ajuste criado pela conciliação da conta.'
        else trim(p_observacoes)
      end,
      false,
      now(),
      now()
    )
    returning id into v_movimento_id;

    v_status := 'Ajustado';
  elsif v_diferenca <> 0 then
    v_status := 'Divergente';
  end if;

  insert into public.imperium_financeiro_conciliacoes (
    empresa_id,
    origem_dispositivo,
    origem_local_id,
    conta_id,
    data_conciliacao,
    saldo_calculado,
    saldo_informado,
    diferenca,
    status,
    movimento_ajuste_id,
    observacoes,
    origem_criado_em,
    excluido_em,
    criado_em,
    atualizado_em
  ) values (
    p_empresa_id,
    p_origem_dispositivo,
    p_conciliacao_local_id,
    p_conta_id,
    p_data,
    v_saldo_calculado,
    coalesce(p_saldo_informado, 0),
    v_diferenca,
    v_status,
    v_movimento_id,
    trim(coalesce(p_observacoes, '')),
    now()::text,
    null,
    now(),
    now()
  )
  returning id into v_conciliacao_id;

  return jsonb_build_object(
    'conciliacao_id', v_conciliacao_id,
    'movimento_ajuste_id', v_movimento_id,
    'saldo_calculado', v_saldo_calculado,
    'saldo_informado', coalesce(p_saldo_informado, 0),
    'diferenca', v_diferenca,
    'status', v_status
  );
end;
$$;

revoke all on function public.imperium_financeiro_conciliar_web(
  uuid, uuid, text, numeric, boolean, text, text, bigint, bigint
) from public, anon;

grant execute on function public.imperium_financeiro_conciliar_web(
  uuid, uuid, text, numeric, boolean, text, text, bigint, bigint
) to authenticated;
