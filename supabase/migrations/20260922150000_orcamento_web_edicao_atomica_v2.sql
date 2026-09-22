create or replace function public.imperium_orcamento_web_editar_v2(
  p_empresa_id uuid,
  p_orcamento_id uuid,
  p_atualizado_em_base timestamptz,
  p_validade text,
  p_observacoes text,
  p_desconto numeric,
  p_perfil_preco text,
  p_itens jsonb,
  p_origem_dispositivo text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_orc public.imperium_orcamentos%rowtype;
  v_item jsonb;
  v_primeiro jsonb;
  v_ids uuid[] := array[]::uuid[];
  v_id uuid;
  v_esperado timestamptz;
  v_subtotal numeric := 0;
  v_desconto numeric := 0;
  v_quantidade numeric;
  v_unitario numeric;
  v_ordem bigint := 0;
  v_agora timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;

  if not private.imperium_pode_modulo(p_empresa_id, 'orcamentos') then
    raise exception 'Sem permissão para editar orçamentos.';
  end if;

  select *
    into v_orc
  from public.imperium_orcamentos
  where empresa_id = p_empresa_id
    and id = p_orcamento_id
    and excluido_em is null
  for update;

  if not found then
    raise exception 'Orçamento não encontrado.';
  end if;

  if p_atualizado_em_base is not null
     and v_orc.atualizado_em <> p_atualizado_em_base then
    raise exception 'O orçamento foi alterado em outro dispositivo. Atualize e tente novamente.';
  end if;

  if p_itens is null
     or jsonb_typeof(p_itens) <> 'array'
     or jsonb_array_length(p_itens) = 0 then
    raise exception 'Adicione pelo menos um serviço ao orçamento.';
  end if;

  if coalesce(trim(p_perfil_preco), '') not in (
    'informado',
    'cliente',
    'parceiro_1_4',
    'parceiro_5_9',
    'parceiro_10_mais'
  ) then
    raise exception 'Perfil de preço inválido.';
  end if;

  v_primeiro := p_itens->0;

  for v_item in
    select value
    from jsonb_array_elements(p_itens)
  loop
    if length(trim(coalesce(v_item->>'servico', ''))) = 0 then
      raise exception 'Todo serviço precisa ter nome.';
    end if;

    begin
      v_quantidade := coalesce((v_item->>'quantidade')::numeric, 0);
      v_unitario := coalesce((v_item->>'valor_unitario')::numeric, 0);
    exception when others then
      raise exception 'Quantidade ou valor inválido no orçamento.';
    end;

    if v_quantidade <= 0 or v_unitario < 0 then
      raise exception 'Quantidade deve ser positiva e valor não pode ser negativo.';
    end if;

    v_subtotal := v_subtotal + (v_quantidade * v_unitario);
  end loop;

  v_desconto := least(greatest(coalesce(p_desconto, 0), 0), v_subtotal);

  update public.imperium_orcamentos
  set servico = trim(coalesce(v_primeiro->>'servico', '')),
      descricao = trim(coalesce(v_primeiro->>'descricao', '')),
      valor = greatest(v_subtotal - v_desconto, 0),
      validade = trim(coalesce(p_validade, '')),
      observacoes = trim(coalesce(p_observacoes, '')),
      desconto = v_desconto,
      perfil_preco = trim(p_perfil_preco),
      origem_atualizado_em = v_agora::text,
      atualizado_em = v_agora
  where empresa_id = p_empresa_id
    and id = p_orcamento_id
  returning * into v_orc;

  for v_item in
    select value
    from jsonb_array_elements(p_itens)
  loop
    v_quantidade := (v_item->>'quantidade')::numeric;
    v_unitario := (v_item->>'valor_unitario')::numeric;
    v_id := nullif(trim(coalesce(v_item->>'id', '')), '')::uuid;

    if v_id is null then
      if coalesce((v_item->>'origem_local_id')::bigint, 0) <= 0 then
        raise exception 'Origem do novo item do orçamento é inválida.';
      end if;

      insert into public.imperium_orcamento_itens (
        empresa_id,
        origem_dispositivo,
        origem_local_id,
        orcamento_id,
        servico_catalogo_id,
        origem_servico_catalogo_local_id,
        servico,
        descricao,
        quantidade,
        valor_unitario,
        ordem,
        excluido_em,
        criado_em,
        atualizado_em
      ) values (
        p_empresa_id,
        trim(p_origem_dispositivo),
        (v_item->>'origem_local_id')::bigint,
        p_orcamento_id,
        nullif(trim(coalesce(v_item->>'servico_catalogo_id', '')), '')::uuid,
        nullif(
          trim(coalesce(v_item->>'origem_servico_catalogo_local_id', '')),
          ''
        )::bigint,
        trim(v_item->>'servico'),
        trim(coalesce(v_item->>'descricao', '')),
        v_quantidade,
        v_unitario,
        v_ordem,
        null,
        v_agora,
        v_agora
      )
      returning id into v_id;
    else
      select nullif(
        trim(coalesce(v_item->>'atualizado_em', '')),
        ''
      )::timestamptz
      into v_esperado;

      update public.imperium_orcamento_itens
      set servico_catalogo_id =
            nullif(
              trim(coalesce(v_item->>'servico_catalogo_id', '')),
              ''
            )::uuid,
          servico = trim(v_item->>'servico'),
          descricao = trim(coalesce(v_item->>'descricao', '')),
          quantidade = v_quantidade,
          valor_unitario = v_unitario,
          ordem = v_ordem,
          excluido_em = null,
          atualizado_em = v_agora
      where empresa_id = p_empresa_id
        and id = v_id
        and orcamento_id = p_orcamento_id
        and excluido_em is null
        and (v_esperado is null or atualizado_em = v_esperado);

      if not found then
        raise exception 'Um item do orçamento foi alterado em outro dispositivo. Atualize e tente novamente.';
      end if;
    end if;

    v_ids := array_append(v_ids, v_id);
    v_ordem := v_ordem + 1;
  end loop;

  update public.imperium_orcamento_itens
  set excluido_em = v_agora,
      atualizado_em = v_agora
  where empresa_id = p_empresa_id
    and orcamento_id = p_orcamento_id
    and excluido_em is null
    and not (id = any(v_ids));

  return jsonb_build_object(
    'orcamento', to_jsonb(v_orc),
    'itens', coalesce(
      (
        select jsonb_agg(to_jsonb(i) order by i.ordem)
        from public.imperium_orcamento_itens i
        where i.empresa_id = p_empresa_id
          and i.orcamento_id = p_orcamento_id
          and i.excluido_em is null
      ),
      '[]'::jsonb
    )
  );
end;
$$;

revoke all on function public.imperium_orcamento_web_editar_v2(
  uuid, uuid, timestamptz, text, text, numeric, text, jsonb, text
) from public, anon;

grant execute on function public.imperium_orcamento_web_editar_v2(
  uuid, uuid, timestamptz, text, text, numeric, text, jsonb, text
) to authenticated;
