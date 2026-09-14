create or replace function public.imperium_os_web_editar_v3(
  p_empresa_id uuid,
  p_ordem_id uuid,
  p_os_atualizado_em timestamptz,
  p_header jsonb,
  p_itens_base jsonb,
  p_itens jsonb,
  p_origem_dispositivo text
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_os public.imperium_ordens_servico%rowtype;
  v_item jsonb;
  v_item_id uuid;
  v_item_ts timestamptz;
  v_count bigint;
  v_total numeric := 0;
  v_quantidade numeric;
  v_valor_unitario numeric;
  v_status text;
  v_origem_local_id bigint;
  v_resultado jsonb;
begin
  if p_empresa_id is null or p_ordem_id is null then
    raise exception 'Empresa e OS sao obrigatorias.' using errcode = '22023';
  end if;

  if p_os_atualizado_em is null then
    raise exception 'Versao da OS e obrigatoria.' using errcode = '22023';
  end if;

  if p_header is null or jsonb_typeof(p_header) <> 'object' then
    raise exception 'Cabecalho da OS invalido.' using errcode = '22023';
  end if;

  p_itens_base := coalesce(p_itens_base, '[]'::jsonb);
  p_itens := coalesce(p_itens, '[]'::jsonb);

  if jsonb_typeof(p_itens_base) <> 'array'
     or jsonb_typeof(p_itens) <> 'array' then
    raise exception 'Lista de itens invalida.' using errcode = '22023';
  end if;

  if jsonb_array_length(p_itens) = 0 then
    raise exception 'A OS precisa ter ao menos um servico.' using errcode = '22023';
  end if;

  select *
  into v_os
  from public.imperium_ordens_servico
  where empresa_id = p_empresa_id
    and id = p_ordem_id
    and excluido_em is null
  for update;

  if not found then
    raise exception 'OS nao encontrada ou sem permissao.' using errcode = 'P0002';
  end if;

  if v_os.atualizado_em is distinct from p_os_atualizado_em then
    raise exception
      'A OS foi alterada em outro dispositivo. Atualize a tela.'
      using errcode = '40001';
  end if;

  if v_os.status not in ('Aberta', 'Em andamento') then
    raise exception
      'Somente OS Aberta ou Em andamento pode ser editada pelo Web.'
      using errcode = '22023';
  end if;

  v_status := coalesce(
    nullif(trim(p_header ->> 'status'), ''),
    v_os.status
  );

  if v_status not in ('Aberta', 'Em andamento') then
    raise exception
      'O Web nao pode finalizar ou cancelar a OS neste fluxo.'
      using errcode = '22023';
  end if;

  perform 1
  from public.imperium_ordem_servico_itens
  where empresa_id = p_empresa_id
    and ordem_servico_id = p_ordem_id
    and excluido_em is null
  for update;

  select count(*)
  into v_count
  from public.imperium_ordem_servico_itens
  where empresa_id = p_empresa_id
    and ordem_servico_id = p_ordem_id
    and excluido_em is null;

  if v_count <> jsonb_array_length(p_itens_base) then
    raise exception
      'A lista de servicos mudou em outro dispositivo. Atualize a tela.'
      using errcode = '40001';
  end if;

  for v_item in
    select value from jsonb_array_elements(p_itens_base)
  loop
    begin
      v_item_id := (v_item ->> 'id')::uuid;
      v_item_ts := (v_item ->> 'atualizado_em')::timestamptz;
    exception when others then
      raise exception 'Versao base de item invalida.' using errcode = '22023';
    end;

    select atualizado_em
    into v_item_ts
    from public.imperium_ordem_servico_itens
    where empresa_id = p_empresa_id
      and ordem_servico_id = p_ordem_id
      and id = v_item_id
      and excluido_em is null
      and atualizado_em = (v_item ->> 'atualizado_em')::timestamptz
    for update;

    if not found then
      raise exception
        'Um servico foi alterado em outro dispositivo. Atualize a tela.'
        using errcode = '40001';
    end if;
  end loop;

  for v_item in
    select value from jsonb_array_elements(p_itens)
  loop
    if trim(coalesce(v_item ->> 'servico', '')) = '' then
      raise exception
        'Todo item precisa de um nome de servico.'
        using errcode = '22023';
    end if;

    begin
      v_quantidade := (v_item ->> 'quantidade')::numeric;
      v_valor_unitario := (v_item ->> 'valor_unitario')::numeric;
    exception when others then
      raise exception
        'Quantidade ou valor unitario invalido.'
        using errcode = '22023';
    end;

    if v_quantidade <= 0 or v_valor_unitario < 0 then
      raise exception
        'Quantidade deve ser positiva e valor nao pode ser negativo.'
        using errcode = '22023';
    end if;

    v_total := v_total + (v_quantidade * v_valor_unitario);

    if nullif(v_item ->> 'id', '') is not null then
      begin
        v_item_id := (v_item ->> 'id')::uuid;
      exception when others then
        raise exception 'ID de item invalido.' using errcode = '22023';
      end;

      if not exists (
        select 1
        from jsonb_array_elements(p_itens_base) base
        where base ->> 'id' = v_item_id::text
      ) then
        raise exception
          'Item existente nao pertence a versao carregada.'
          using errcode = '40001';
      end if;

      update public.imperium_ordem_servico_itens
      set servico = trim(v_item ->> 'servico'),
          descricao = coalesce(v_item ->> 'descricao', ''),
          quantidade = v_quantidade,
          valor_unitario = v_valor_unitario,
          concluido = coalesce((v_item ->> 'concluido')::boolean, false),
          ordem = coalesce((v_item ->> 'ordem')::bigint, 0),
          excluido_em = null
      where empresa_id = p_empresa_id
        and ordem_servico_id = p_ordem_id
        and id = v_item_id
        and excluido_em is null;

      if not found then
        raise exception
          'Item deixou de existir durante a edicao.'
          using errcode = '40001';
      end if;
    else
      if trim(coalesce(p_origem_dispositivo, '')) = '' then
        raise exception 'Origem Web invalida.' using errcode = '22023';
      end if;

      begin
        v_origem_local_id := (v_item ->> 'origem_local_id')::bigint;
      exception when others then
        raise exception
          'Origem local do novo item invalida.'
          using errcode = '22023';
      end;

      insert into public.imperium_ordem_servico_itens (
        empresa_id,
        ordem_servico_id,
        origem_dispositivo,
        origem_local_id,
        servico,
        descricao,
        quantidade,
        valor_unitario,
        concluido,
        ordem,
        excluido_em
      ) values (
        p_empresa_id,
        p_ordem_id,
        p_origem_dispositivo,
        v_origem_local_id,
        trim(v_item ->> 'servico'),
        coalesce(v_item ->> 'descricao', ''),
        v_quantidade,
        v_valor_unitario,
        coalesce((v_item ->> 'concluido')::boolean, false),
        coalesce((v_item ->> 'ordem')::bigint, 0),
        null
      );
    end if;
  end loop;

  update public.imperium_ordem_servico_itens item
  set excluido_em = clock_timestamp()
  where item.empresa_id = p_empresa_id
    and item.ordem_servico_id = p_ordem_id
    and item.excluido_em is null
    and not exists (
      select 1
      from jsonb_array_elements(p_itens) enviado
      where nullif(enviado ->> 'id', '') is not null
        and (enviado ->> 'id')::uuid = item.id
    );

  update public.imperium_ordens_servico
  set status = v_status,
      data_abertura = coalesce(
        nullif(p_header ->> 'data_abertura', ''),
        v_os.data_abertura
      ),
      data_inicio = nullif(p_header ->> 'data_inicio', ''),
      hora_entrada = nullif(p_header ->> 'hora_entrada', ''),
      hora_saida = nullif(p_header ->> 'hora_saida', ''),
      funcionario_responsavel =
        coalesce(p_header ->> 'funcionario_responsavel', ''),
      observacoes = coalesce(p_header ->> 'observacoes', ''),
      quilometragem_entrada =
        coalesce(p_header ->> 'quilometragem_entrada', ''),
      combustivel_entrada =
        coalesce(p_header ->> 'combustivel_entrada', ''),
      desconto = least(
        v_total,
        greatest(
          0,
          coalesce(
            nullif(p_header ->> 'desconto', '')::numeric,
            v_os.desconto
          )
        )
      ),
      valor_total = v_total,
      assinatura_desatualizada = case
        when assinatura_storage_path is not null
          or assinatura_sha256 is not null
        then true
        else assinatura_desatualizada
      end
  where empresa_id = p_empresa_id
    and id = p_ordem_id
  returning * into v_os;

  select jsonb_build_object(
    'ordem',
    to_jsonb(v_os),
    'itens',
    coalesce(
      jsonb_agg(to_jsonb(item) order by item.ordem, item.id)
        filter (where item.id is not null),
      '[]'::jsonb
    )
  )
  into v_resultado
  from public.imperium_ordem_servico_itens item
  where item.empresa_id = p_empresa_id
    and item.ordem_servico_id = p_ordem_id
    and item.excluido_em is null;

  return v_resultado;
end;
$$;

revoke all on function public.imperium_os_web_editar_v3(
  uuid,
  uuid,
  timestamptz,
  jsonb,
  jsonb,
  jsonb,
  text
) from public;

grant execute on function public.imperium_os_web_editar_v3(
  uuid,
  uuid,
  timestamptz,
  jsonb,
  jsonb,
  jsonb,
  text
) to authenticated;
