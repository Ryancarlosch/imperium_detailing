create or replace function public.imperium_confirmar_pagamento_infinitepay(
  p_order_nsu text,
  p_transaction_nsu text,
  p_invoice_slug text,
  p_amount_centavos integer,
  p_paid_amount_centavos integer,
  p_installments integer,
  p_capture_method text,
  p_receipt_url text,
  p_payload jsonb default '{}'::jsonb
)
returns table(
  empresa_id uuid,
  plano_codigo text,
  vencimento date,
  ja_processado boolean
)
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_cobranca record;
  v_licenca record;
  v_base date;
  v_novo_vencimento date;
  v_valor_mensal numeric;
begin
  if coalesce(trim(p_order_nsu), '') = '' then
    raise exception 'order_nsu ausente.' using errcode = 'P0001';
  end if;

  if coalesce(trim(p_transaction_nsu), '') = '' then
    raise exception 'transaction_nsu ausente.' using errcode = 'P0001';
  end if;

  select c.*
  into v_cobranca
  from public.imperium_assinatura_cobrancas as c
  where c.order_nsu = trim(p_order_nsu)
  for update;

  if not found then
    raise exception 'Cobranca nao encontrada.' using errcode = 'P0001';
  end if;

  if v_cobranca.valor_centavos <> p_amount_centavos then
    raise exception 'Valor do pagamento nao confere com a cobranca.' using errcode = 'P0001';
  end if;

  if v_cobranca.status = 'pago' then
    if v_cobranca.transaction_nsu is distinct from trim(p_transaction_nsu) then
      raise exception 'Cobranca ja processada por outra transacao.' using errcode = 'P0001';
    end if;

    return query
    select
      v_cobranca.empresa_id,
      v_cobranca.plano_codigo,
      l.vencimento,
      true
    from public.empresa_licencas as l
    where l.empresa_id = v_cobranca.empresa_id;
    return;
  end if;

  if exists (
    select 1
    from public.imperium_assinatura_cobrancas as c
    where c.transaction_nsu = trim(p_transaction_nsu)
      and c.order_nsu <> trim(p_order_nsu)
  ) then
    raise exception 'Transacao ja vinculada a outra cobranca.' using errcode = 'P0001';
  end if;

  select l.*
  into v_licenca
  from public.empresa_licencas as l
  where l.empresa_id = v_cobranca.empresa_id
  for update;

  if not found then
    raise exception 'Licenca da empresa nao encontrada.' using errcode = 'P0001';
  end if;

  -- Dias gratuitos nunca viram saldo pago. Se a empresa ainda esta no teste,
  -- o primeiro plano pago comeca no dia do pagamento. Renovacoes de um plano
  -- pago ativo preservam somente o saldo pago que ainda nao venceu.
  if lower(coalesce(v_licenca.status_base, '')) = 'teste' then
    v_base := current_date;
  elsif lower(coalesce(v_licenca.status_base, '')) = 'ativa'
    and v_licenca.teste_ate is null
    and v_licenca.vencimento is not null
    and v_licenca.vencimento >= current_date then
    v_base := v_licenca.vencimento;
  else
    v_base := current_date;
  end if;

  v_novo_vencimento := (
    v_base + pg_catalog.make_interval(months => v_cobranca.plano_meses)
  )::date;

  v_valor_mensal := round(
    (v_cobranca.valor_centavos::numeric / 100) / v_cobranca.plano_meses,
    2
  );

  update public.imperium_assinatura_cobrancas as c
  set
    status = 'pago',
    invoice_slug = nullif(trim(p_invoice_slug), ''),
    transaction_nsu = trim(p_transaction_nsu),
    capture_method = nullif(trim(p_capture_method), ''),
    installments = p_installments,
    amount_centavos = p_amount_centavos,
    paid_amount_centavos = p_paid_amount_centavos,
    receipt_url = nullif(trim(p_receipt_url), ''),
    provider_payload = coalesce(p_payload, '{}'::jsonb),
    erro = '',
    pago_em = coalesce(c.pago_em, now()),
    atualizado_em = now()
  where c.order_nsu = trim(p_order_nsu);

  update public.empresa_licencas as l
  set
    plano = v_cobranca.plano_nome,
    status_base = 'ativa',
    teste_ate = null,
    vencimento = v_novo_vencimento,
    tolerancia_dias = greatest(coalesce(l.tolerancia_dias, 0), 3),
    valor_mensal = v_valor_mensal,
    ultimo_pagamento_em = now(),
    motivo_bloqueio = '',
    observacoes = trim(both from concat_ws(
      E'\n',
      nullif(l.observacoes, ''),
      'Pagamento InfinitePay confirmado. Pedido ' || v_cobranca.order_nsu || '.'
    )),
    atualizado_em = now()
  where l.empresa_id = v_cobranca.empresa_id;

  insert into public.imperium_licenca_historico(
    empresa_id,
    acao,
    plano_antes,
    status_antes,
    vencimento_antes,
    plano_depois,
    status_depois,
    vencimento_depois,
    detalhes,
    executado_por
  ) values (
    v_cobranca.empresa_id,
    'pagamento_infinitepay_confirmado',
    v_licenca.plano,
    v_licenca.status_base,
    v_licenca.vencimento,
    v_cobranca.plano_nome,
    'ativa',
    v_novo_vencimento,
    'Pagamento confirmado pela InfinitePay. Pedido ' || v_cobranca.order_nsu || ', transacao ' || trim(p_transaction_nsu) || '.',
    null
  );

  return query
  select
    v_cobranca.empresa_id,
    v_cobranca.plano_codigo,
    v_novo_vencimento,
    false;
end;
$$;
