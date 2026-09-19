create or replace function public.imperium_financeiro_transferir_web(
  p_empresa_id uuid,
  p_conta_origem_id uuid,
  p_conta_destino_id uuid,
  p_valor numeric,
  p_data text,
  p_origem_dispositivo text,
  p_origem_local_id bigint,
  p_saida_local_id bigint,
  p_entrada_local_id bigint,
  p_descricao text default 'Transferência entre contas',
  p_observacoes text default ''
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_transferencia_id uuid;
  v_plano_conta_id uuid;
  v_natureza text := 'Transferência';
  v_descricao text;
  v_agora text := now()::text;
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;

  if p_conta_origem_id = p_conta_destino_id then
    raise exception 'Selecione contas diferentes para a transferência.';
  end if;

  if coalesce(p_valor, 0) <= 0 then
    raise exception 'O valor da transferência deve ser maior que zero.';
  end if;

  if nullif(trim(coalesce(p_origem_dispositivo, '')), '') is null then
    raise exception 'Origem do dispositivo inválida.';
  end if;

  perform 1
  from public.imperium_financeiro_contas
  where empresa_id = p_empresa_id
    and id = p_conta_origem_id
    and ativo = true
    and excluido_em is null;

  if not found then
    raise exception 'Conta de origem inválida ou sem acesso.';
  end if;

  perform 1
  from public.imperium_financeiro_contas
  where empresa_id = p_empresa_id
    and id = p_conta_destino_id
    and ativo = true
    and excluido_em is null;

  if not found then
    raise exception 'Conta de destino inválida ou sem acesso.';
  end if;

  select id, natureza
  into v_plano_conta_id, v_natureza
  from public.imperium_financeiro_plano_contas
  where empresa_id = p_empresa_id
    and codigo = '9.01'
    and ativo = true
    and excluido_em is null
  limit 1;

  v_natureza := coalesce(nullif(trim(v_natureza), ''), 'Transferência');
  v_descricao := coalesce(
    nullif(trim(coalesce(p_descricao, '')), ''),
    'Transferência entre contas'
  );

  insert into public.imperium_financeiro_transferencias (
    empresa_id, origem_dispositivo, origem_local_id, conta_origem_id,
    conta_destino_id, valor, data, descricao, observacoes, origem_criado_em,
    criado_em, atualizado_em
  ) values (
    p_empresa_id, p_origem_dispositivo, p_origem_local_id, p_conta_origem_id,
    p_conta_destino_id, p_valor, p_data, v_descricao,
    trim(coalesce(p_observacoes, '')), v_agora, now(), now()
  )
  returning id into v_transferencia_id;

  insert into public.imperium_financeiro_movimentos (
    empresa_id, origem_dispositivo, origem_local_id, tipo, descricao, valor,
    forma_pagamento, data, plano_conta_id, conta_id, transferencia_id,
    origem_plano_conta_local_id, origem_conta_local_id,
    origem_transferencia_local_id, total_parcelas, natureza, origem, status,
    data_competencia, data_pagamento, numero_documento, observacoes,
    impacta_dre, criado_em, atualizado_em
  ) values (
    p_empresa_id, p_origem_dispositivo, p_saida_local_id, 'Saída', v_descricao,
    p_valor, 'Transferência', p_data, v_plano_conta_id, p_conta_origem_id,
    v_transferencia_id, null, null, p_origem_local_id, 1, v_natureza,
    'Transferência', 'Realizado', p_data, p_data, '',
    trim(coalesce(p_observacoes, '')), false, now(), now()
  );

  insert into public.imperium_financeiro_movimentos (
    empresa_id, origem_dispositivo, origem_local_id, tipo, descricao, valor,
    forma_pagamento, data, plano_conta_id, conta_id, transferencia_id,
    origem_plano_conta_local_id, origem_conta_local_id,
    origem_transferencia_local_id, total_parcelas, natureza, origem, status,
    data_competencia, data_pagamento, numero_documento, observacoes,
    impacta_dre, criado_em, atualizado_em
  ) values (
    p_empresa_id, p_origem_dispositivo, p_entrada_local_id, 'Entrada',
    v_descricao, p_valor, 'Transferência', p_data, v_plano_conta_id,
    p_conta_destino_id, v_transferencia_id, null, null, p_origem_local_id, 1,
    v_natureza, 'Transferência', 'Realizado', p_data, p_data, '',
    trim(coalesce(p_observacoes, '')), false, now(), now()
  );

  return v_transferencia_id;
end;
$$;

revoke all on function public.imperium_financeiro_transferir_web(
  uuid, uuid, uuid, numeric, text, text, bigint, bigint, bigint, text, text
) from public, anon;

grant execute on function public.imperium_financeiro_transferir_web(
  uuid, uuid, uuid, numeric, text, text, bigint, bigint, bigint, text, text
) to authenticated;
