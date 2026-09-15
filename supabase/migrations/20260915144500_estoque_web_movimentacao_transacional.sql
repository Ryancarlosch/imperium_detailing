-- Imperium Manager - Estoque Web movimentacao transacional
-- Entrada, saida e ajuste usam o mesmo saldo Cloud consumido pelo Android.
-- Saidas e ajustes para baixo respeitam reservas ativas e consomem lotes FIFO.

create or replace function public.imperium_estoque_movimentar_web(
  p_empresa_id uuid,
  p_item_estoque_id uuid,
  p_tipo text,
  p_quantidade numeric,
  p_origem_dispositivo text,
  p_origem_local_id bigint,
  p_observacoes text default '',
  p_motivo text default '',
  p_valor_total_pago numeric default null,
  p_quantidade_original numeric default null,
  p_unidade_original text default null,
  p_fornecedor text default null,
  p_data timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.imperium_estoque_itens%rowtype;
  v_existente public.imperium_estoque_movimentacoes%rowtype;
  v_tipo text;
  v_anterior numeric;
  v_posterior numeric;
  v_movimentada numeric;
  v_reservado numeric := 0;
  v_restante numeric := 0;
  v_consumo numeric := 0;
  v_custo_total numeric := 0;
  v_custo_unitario numeric := 0;
  v_lote record;
  v_lote_id uuid;
  v_movimento_id uuid;
begin
  if (select auth.uid()) is null
     or not private.imperium_pode_modulo(p_empresa_id, 'estoque') then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para movimentar estoque.';
  end if;

  if trim(coalesce(p_origem_dispositivo, '')) = ''
     or coalesce(p_origem_local_id, 0) <= 0 then
    raise exception using
      errcode = '22023',
      message = 'Origem Web invalida para movimentacao de estoque.';
  end if;

  v_tipo := upper(trim(coalesce(p_tipo, '')));
  if v_tipo not in ('ENTRADA', 'SAIDA', 'AJUSTE') then
    raise exception using
      errcode = '22023',
      message = 'Tipo de movimentacao de estoque invalido.';
  end if;

  if p_quantidade is null or p_quantidade < 0 then
    raise exception using
      errcode = '22023',
      message = 'Quantidade de estoque invalida.';
  end if;

  select * into v_existente
  from public.imperium_estoque_movimentacoes m
  where m.empresa_id = p_empresa_id
    and m.origem_dispositivo = trim(p_origem_dispositivo)
    and m.origem_local_id = p_origem_local_id;

  if found then
    return jsonb_build_object(
      'status', 'ja_aplicada',
      'movimento_id', v_existente.id,
      'item_estoque_id', v_existente.item_estoque_id,
      'tipo', v_existente.tipo,
      'quantidade_anterior', v_existente.quantidade_anterior,
      'quantidade_posterior', v_existente.quantidade_posterior,
      'custo_unitario', v_existente.custo_unitario
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('imperium_estoque:' || p_empresa_id::text, 0)
  );

  select * into v_existente
  from public.imperium_estoque_movimentacoes m
  where m.empresa_id = p_empresa_id
    and m.origem_dispositivo = trim(p_origem_dispositivo)
    and m.origem_local_id = p_origem_local_id;

  if found then
    return jsonb_build_object(
      'status', 'ja_aplicada',
      'movimento_id', v_existente.id,
      'item_estoque_id', v_existente.item_estoque_id,
      'tipo', v_existente.tipo,
      'quantidade_anterior', v_existente.quantidade_anterior,
      'quantidade_posterior', v_existente.quantidade_posterior,
      'custo_unitario', v_existente.custo_unitario
    );
  end if;

  select * into v_item
  from public.imperium_estoque_itens i
  where i.empresa_id = p_empresa_id
    and i.id = p_item_estoque_id
    and i.excluido_em is null
    and i.ativo
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Produto de estoque nao encontrado ou inativo.';
  end if;

  v_anterior := coalesce(v_item.quantidade, 0);

  select coalesce(sum(r.quantidade), 0)
    into v_reservado
  from public.imperium_estoque_reservas_os r
  where r.empresa_id = p_empresa_id
    and r.item_estoque_id = p_item_estoque_id
    and r.status = 'Ativa';

  if v_tipo = 'ENTRADA' then
    if p_quantidade <= 0 then
      raise exception using
        errcode = '22023',
        message = 'A quantidade de entrada deve ser maior que zero.';
    end if;

    if p_valor_total_pago is null or p_valor_total_pago <= 0 then
      raise exception using
        errcode = '22023',
        message = 'Informe o valor total pago da entrada.';
    end if;

    v_custo_unitario := p_valor_total_pago / p_quantidade;
    v_posterior := v_anterior + p_quantidade;
    v_movimentada := p_quantidade;

    insert into public.imperium_estoque_lotes (
      empresa_id,
      item_estoque_id,
      origem_dispositivo,
      origem_local_id,
      data_compra,
      quantidade_original,
      quantidade_normalizada,
      quantidade_disponivel,
      unidade_original,
      unidade_base,
      valor_total_pago,
      custo_unitario,
      fornecedor,
      observacao,
      ativo,
      origem_criado_em,
      excluido_em,
      criado_em,
      atualizado_em
    ) values (
      p_empresa_id,
      p_item_estoque_id,
      trim(p_origem_dispositivo),
      p_origem_local_id,
      p_data::text,
      coalesce(nullif(p_quantidade_original, 0), p_quantidade),
      p_quantidade,
      p_quantidade,
      coalesce(nullif(trim(coalesce(p_unidade_original, '')), ''), v_item.unidade),
      v_item.unidade,
      p_valor_total_pago,
      v_custo_unitario,
      coalesce(nullif(trim(coalesce(p_fornecedor, '')), ''), v_item.fornecedor),
      trim(coalesce(p_observacoes, '')),
      true,
      p_data::text,
      null,
      now(),
      now()
    )
    returning id into v_lote_id;

    update public.imperium_estoque_itens
    set quantidade = v_posterior,
        valor_total_pago = p_valor_total_pago,
        quantidade_total = p_quantidade,
        custo_unitario = v_custo_unitario,
        custo_unitario_calculado = v_custo_unitario,
        fornecedor = coalesce(
          nullif(trim(coalesce(p_fornecedor, '')), ''),
          fornecedor
        ),
        origem_atualizado_em = p_data::text
    where empresa_id = p_empresa_id
      and id = p_item_estoque_id;

  elsif v_tipo = 'SAIDA' then
    if p_quantidade <= 0 then
      raise exception using
        errcode = '22023',
        message = 'A quantidade de saida deve ser maior que zero.';
    end if;

    v_posterior := v_anterior - p_quantidade;
    if v_posterior < -0.000001 then
      raise exception using
        errcode = 'P0001',
        message = 'Quantidade de saida maior que o estoque atual.';
    end if;

    if v_posterior + 0.000001 < v_reservado then
      raise exception using
        errcode = 'P0001',
        message = 'A saida consumiria saldo reservado para Ordens de Servico.';
    end if;

    v_restante := p_quantidade;

    for v_lote in
      select l.id, l.quantidade_disponivel, l.custo_unitario
      from public.imperium_estoque_lotes l
      where l.empresa_id = p_empresa_id
        and l.item_estoque_id = p_item_estoque_id
        and l.excluido_em is null
        and l.ativo
        and l.quantidade_disponivel > 0
      order by l.data_compra asc, l.criado_em asc, l.id asc
      for update
    loop
      exit when v_restante <= 0.000001;
      v_consumo := least(v_restante, v_lote.quantidade_disponivel);

      update public.imperium_estoque_lotes
      set quantidade_disponivel = greatest(quantidade_disponivel - v_consumo, 0)
      where empresa_id = p_empresa_id
        and id = v_lote.id;

      v_custo_total := v_custo_total + (v_consumo * v_lote.custo_unitario);
      v_restante := v_restante - v_consumo;
    end loop;

    if v_restante > 0.000001 then
      raise exception using
        errcode = 'P0001',
        message = 'Lotes FIFO insuficientes para concluir a saida.';
    end if;

    v_custo_unitario := case
      when p_quantidade > 0 then v_custo_total / p_quantidade
      else 0
    end;
    v_movimentada := p_quantidade;

    update public.imperium_estoque_itens
    set quantidade = greatest(v_posterior, 0),
        origem_atualizado_em = p_data::text
    where empresa_id = p_empresa_id
      and id = p_item_estoque_id;

  else
    if trim(coalesce(p_motivo, '')) = '' then
      raise exception using
        errcode = '22023',
        message = 'Informe o motivo do ajuste manual.';
    end if;

    v_posterior := p_quantidade;
    v_movimentada := abs(v_posterior - v_anterior);

    if v_movimentada <= 0.000001 then
      raise exception using
        errcode = '22023',
        message = 'O ajuste nao altera a quantidade atual.';
    end if;

    if v_posterior + 0.000001 < v_reservado then
      raise exception using
        errcode = 'P0001',
        message = 'O ajuste deixaria saldo menor que o estoque reservado para OS.';
    end if;

    if v_posterior > v_anterior then
      v_custo_unitario := case
        when coalesce(v_item.custo_unitario_calculado, 0) > 0
          then v_item.custo_unitario_calculado
        else coalesce(v_item.custo_unitario, 0)
      end;

      insert into public.imperium_estoque_lotes (
        empresa_id,
        item_estoque_id,
        origem_dispositivo,
        origem_local_id,
        data_compra,
        quantidade_original,
        quantidade_normalizada,
        quantidade_disponivel,
        unidade_original,
        unidade_base,
        valor_total_pago,
        custo_unitario,
        fornecedor,
        observacao,
        ativo,
        origem_criado_em,
        excluido_em,
        criado_em,
        atualizado_em
      ) values (
        p_empresa_id,
        p_item_estoque_id,
        trim(p_origem_dispositivo),
        p_origem_local_id,
        p_data::text,
        v_movimentada,
        v_movimentada,
        v_movimentada,
        v_item.unidade,
        v_item.unidade,
        v_movimentada * v_custo_unitario,
        v_custo_unitario,
        v_item.fornecedor,
        'Lote tecnico criado por ajuste manual: ' || trim(p_motivo),
        true,
        p_data::text,
        null,
        now(),
        now()
      )
      returning id into v_lote_id;
    else
      v_restante := v_anterior - v_posterior;

      for v_lote in
        select l.id, l.quantidade_disponivel, l.custo_unitario
        from public.imperium_estoque_lotes l
        where l.empresa_id = p_empresa_id
          and l.item_estoque_id = p_item_estoque_id
          and l.excluido_em is null
          and l.ativo
          and l.quantidade_disponivel > 0
        order by l.data_compra asc, l.criado_em asc, l.id asc
        for update
      loop
        exit when v_restante <= 0.000001;
        v_consumo := least(v_restante, v_lote.quantidade_disponivel);

        update public.imperium_estoque_lotes
        set quantidade_disponivel = greatest(quantidade_disponivel - v_consumo, 0)
        where empresa_id = p_empresa_id
          and id = v_lote.id;

        v_custo_total := v_custo_total + (v_consumo * v_lote.custo_unitario);
        v_restante := v_restante - v_consumo;
      end loop;

      if v_restante > 0.000001 then
        raise exception using
          errcode = 'P0001',
          message = 'Lotes FIFO insuficientes para concluir o ajuste.';
      end if;

      v_custo_unitario := case
        when v_movimentada > 0 then v_custo_total / v_movimentada
        else 0
      end;
    end if;

    update public.imperium_estoque_itens
    set quantidade = v_posterior,
        origem_atualizado_em = p_data::text
    where empresa_id = p_empresa_id
      and id = p_item_estoque_id;
  end if;

  insert into public.imperium_estoque_movimentacoes (
    empresa_id,
    item_estoque_id,
    lote_id,
    ordem_servico_id,
    origem_dispositivo,
    origem_local_id,
    tipo,
    quantidade,
    quantidade_anterior,
    quantidade_posterior,
    custo_unitario,
    observacoes,
    motivo,
    origem,
    origem_ordem_servico_local_id,
    origem_nota_fiscal_local_id,
    origem_nota_fiscal_item_local_id,
    data,
    origem_criado_em,
    criado_em
  ) values (
    p_empresa_id,
    p_item_estoque_id,
    v_lote_id,
    null,
    trim(p_origem_dispositivo),
    p_origem_local_id,
    v_tipo,
    v_movimentada,
    v_anterior,
    v_posterior,
    v_custo_unitario,
    trim(coalesce(p_observacoes, '')),
    trim(coalesce(p_motivo, '')),
    case when v_tipo = 'AJUSTE' then 'Ajuste manual Web' else 'Web' end,
    null,
    null,
    null,
    p_data::text,
    p_data::text,
    now()
  )
  returning id into v_movimento_id;

  return jsonb_build_object(
    'status', 'aplicada',
    'movimento_id', v_movimento_id,
    'item_estoque_id', p_item_estoque_id,
    'tipo', v_tipo,
    'quantidade', v_movimentada,
    'quantidade_anterior', v_anterior,
    'quantidade_posterior', v_posterior,
    'reservado_ativo', v_reservado,
    'custo_unitario', v_custo_unitario,
    'lote_id', v_lote_id
  );
end;
$$;

revoke all on function public.imperium_estoque_movimentar_web(
  uuid, uuid, text, numeric, text, bigint, text, text,
  numeric, numeric, text, text, timestamptz
) from public, anon;

grant execute on function public.imperium_estoque_movimentar_web(
  uuid, uuid, text, numeric, text, bigint, text, text,
  numeric, numeric, text, text, timestamptz
) to authenticated;

comment on function public.imperium_estoque_movimentar_web(
  uuid, uuid, text, numeric, text, bigint, text, text,
  numeric, numeric, text, text, timestamptz
) is
  'Movimentacao manual Web idempotente, serializada, com reservas e FIFO.';
