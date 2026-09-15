-- Imperium Manager - Estoque Web cadastro e edicao CAS
-- Cadastro pode incluir entrada inicial no mesmo commit transacional.
-- Edicao cadastral nunca altera saldo diretamente e usa CAS por atualizado_em.

create or replace function public.imperium_estoque_criar_item_web(
  p_empresa_id uuid,
  p_origem_dispositivo text,
  p_origem_local_id bigint,
  p_nome text,
  p_categoria text default '',
  p_quantidade_minima numeric default 0,
  p_unidade text default 'unidade',
  p_ean text default '',
  p_fornecedor text default '',
  p_observacoes text default '',
  p_quantidade_inicial numeric default 0,
  p_quantidade_original numeric default null,
  p_unidade_original text default null,
  p_valor_total_pago numeric default null,
  p_data timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.imperium_estoque_itens%rowtype;
  v_nome text;
  v_unidade text;
begin
  if (select auth.uid()) is null
     or not private.imperium_pode_modulo(p_empresa_id, 'estoque') then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para cadastrar produto de estoque.';
  end if;

  if trim(coalesce(p_origem_dispositivo, '')) = ''
     or coalesce(p_origem_local_id, 0) <= 0 then
    raise exception using
      errcode = '22023',
      message = 'Origem Web invalida para cadastro de produto.';
  end if;

  v_nome := trim(coalesce(p_nome, ''));
  if length(v_nome) < 2 then
    raise exception using
      errcode = '22023',
      message = 'Informe o nome do produto.';
  end if;

  v_unidade := lower(trim(coalesce(p_unidade, '')));
  if v_unidade not in ('ml', 'g', 'metro', 'unidade') then
    raise exception using
      errcode = '22023',
      message = 'Unidade base invalida para o produto.';
  end if;

  if coalesce(p_quantidade_minima, 0) < 0
     or coalesce(p_quantidade_inicial, 0) < 0 then
    raise exception using
      errcode = '22023',
      message = 'Quantidades do produto nao podem ser negativas.';
  end if;

  if coalesce(p_quantidade_inicial, 0) > 0
     and coalesce(p_valor_total_pago, 0) <= 0 then
    raise exception using
      errcode = '22023',
      message = 'Informe o valor total pago para a entrada inicial.';
  end if;

  select * into v_item
  from public.imperium_estoque_itens i
  where i.empresa_id = p_empresa_id
    and i.origem_dispositivo = trim(p_origem_dispositivo)
    and i.origem_local_id = p_origem_local_id;

  if found then
    return jsonb_build_object(
      'status', 'ja_cadastrado',
      'id', v_item.id,
      'nome', v_item.nome,
      'quantidade', v_item.quantidade,
      'unidade', v_item.unidade,
      'atualizado_em', v_item.atualizado_em
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('imperium_estoque:' || p_empresa_id::text, 0)
  );

  select * into v_item
  from public.imperium_estoque_itens i
  where i.empresa_id = p_empresa_id
    and i.origem_dispositivo = trim(p_origem_dispositivo)
    and i.origem_local_id = p_origem_local_id;

  if found then
    return jsonb_build_object(
      'status', 'ja_cadastrado',
      'id', v_item.id,
      'nome', v_item.nome,
      'quantidade', v_item.quantidade,
      'unidade', v_item.unidade,
      'atualizado_em', v_item.atualizado_em
    );
  end if;

  insert into public.imperium_estoque_itens (
    empresa_id,
    origem_dispositivo,
    origem_local_id,
    nome,
    categoria,
    quantidade,
    quantidade_minima,
    unidade,
    valor_total_pago,
    quantidade_total,
    ean,
    custo_unitario,
    custo_unitario_calculado,
    fornecedor,
    observacoes,
    ativo,
    origem_atualizado_em,
    excluido_em,
    criado_em,
    atualizado_em
  ) values (
    p_empresa_id,
    trim(p_origem_dispositivo),
    p_origem_local_id,
    v_nome,
    trim(coalesce(p_categoria, '')),
    0,
    coalesce(p_quantidade_minima, 0),
    v_unidade,
    0,
    0,
    trim(coalesce(p_ean, '')),
    0,
    0,
    trim(coalesce(p_fornecedor, '')),
    trim(coalesce(p_observacoes, '')),
    true,
    p_data::text,
    null,
    now(),
    now()
  )
  returning * into v_item;

  if coalesce(p_quantidade_inicial, 0) > 0 then
    perform public.imperium_estoque_movimentar_web(
      p_empresa_id => p_empresa_id,
      p_item_estoque_id => v_item.id,
      p_tipo => 'ENTRADA',
      p_quantidade => p_quantidade_inicial,
      p_origem_dispositivo => trim(p_origem_dispositivo),
      p_origem_local_id => p_origem_local_id,
      p_observacoes => case
        when trim(coalesce(p_observacoes, '')) = '' then 'Entrada inicial do cadastro Web'
        else trim(p_observacoes)
      end,
      p_motivo => 'Cadastro de produto Web',
      p_valor_total_pago => p_valor_total_pago,
      p_quantidade_original => coalesce(
        nullif(p_quantidade_original, 0),
        p_quantidade_inicial
      ),
      p_unidade_original => coalesce(
        nullif(trim(coalesce(p_unidade_original, '')), ''),
        v_unidade
      ),
      p_fornecedor => trim(coalesce(p_fornecedor, '')),
      p_data => p_data
    );
  end if;

  select * into v_item
  from public.imperium_estoque_itens i
  where i.empresa_id = p_empresa_id
    and i.id = v_item.id;

  return jsonb_build_object(
    'status', 'cadastrado',
    'id', v_item.id,
    'nome', v_item.nome,
    'quantidade', v_item.quantidade,
    'unidade', v_item.unidade,
    'atualizado_em', v_item.atualizado_em
  );
end;
$$;

create or replace function public.imperium_estoque_atualizar_item_web(
  p_empresa_id uuid,
  p_item_estoque_id uuid,
  p_atualizado_em timestamptz,
  p_nome text,
  p_categoria text,
  p_quantidade_minima numeric,
  p_unidade text,
  p_ean text,
  p_fornecedor text,
  p_observacoes text,
  p_ativo boolean,
  p_data timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.imperium_estoque_itens%rowtype;
  v_nome text;
  v_unidade text;
begin
  if (select auth.uid()) is null
     or not private.imperium_pode_modulo(p_empresa_id, 'estoque') then
    raise exception using
      errcode = '42501',
      message = 'Sem permissao para editar produto de estoque.';
  end if;

  v_nome := trim(coalesce(p_nome, ''));
  if length(v_nome) < 2 then
    raise exception using
      errcode = '22023',
      message = 'Informe o nome do produto.';
  end if;

  v_unidade := lower(trim(coalesce(p_unidade, '')));
  if v_unidade not in ('ml', 'g', 'metro', 'unidade') then
    raise exception using
      errcode = '22023',
      message = 'Unidade base invalida para o produto.';
  end if;

  if coalesce(p_quantidade_minima, 0) < 0 then
    raise exception using
      errcode = '22023',
      message = 'A quantidade minima nao pode ser negativa.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('imperium_estoque:' || p_empresa_id::text, 0)
  );

  select * into v_item
  from public.imperium_estoque_itens i
  where i.empresa_id = p_empresa_id
    and i.id = p_item_estoque_id
    and i.excluido_em is null
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Produto de estoque nao encontrado.';
  end if;

  if p_atualizado_em is null
     or v_item.atualizado_em is distinct from p_atualizado_em then
    raise exception using
      errcode = '40001',
      message = 'O produto mudou em outro dispositivo. Atualize a pagina antes de salvar.';
  end if;

  if v_item.unidade <> v_unidade
     and abs(coalesce(v_item.quantidade, 0)) > 0.000001 then
    raise exception using
      errcode = '22023',
      message = 'A unidade base so pode ser alterada quando o saldo estiver zerado.';
  end if;

  if coalesce(p_ativo, false) = false then
    if exists (
      select 1
      from public.imperium_estoque_reservas_os r
      where r.empresa_id = p_empresa_id
        and r.item_estoque_id = p_item_estoque_id
        and r.status = 'Ativa'
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'O produto possui saldo reservado para Ordem de Servico e nao pode ser inativado.';
    end if;

    if exists (
      select 1
      from public.imperium_ordem_servico_produtos p
      join public.imperium_ordens_servico os
        on os.empresa_id = p.empresa_id
       and os.id = p.ordem_servico_id
      where p.empresa_id = p_empresa_id
        and p.item_estoque_id = p_item_estoque_id
        and p.excluido_em is null
        and os.excluido_em is null
        and os.status not in ('Finalizada', 'Cancelada')
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'O produto esta vinculado a uma Ordem de Servico ativa e nao pode ser inativado.';
    end if;
  end if;

  update public.imperium_estoque_itens
  set nome = v_nome,
      categoria = trim(coalesce(p_categoria, '')),
      quantidade_minima = coalesce(p_quantidade_minima, 0),
      unidade = v_unidade,
      ean = trim(coalesce(p_ean, '')),
      fornecedor = trim(coalesce(p_fornecedor, '')),
      observacoes = trim(coalesce(p_observacoes, '')),
      ativo = coalesce(p_ativo, true),
      origem_atualizado_em = p_data::text
  where empresa_id = p_empresa_id
    and id = p_item_estoque_id
  returning * into v_item;

  return jsonb_build_object(
    'status', 'atualizado',
    'id', v_item.id,
    'nome', v_item.nome,
    'quantidade', v_item.quantidade,
    'quantidade_minima', v_item.quantidade_minima,
    'unidade', v_item.unidade,
    'ativo', v_item.ativo,
    'atualizado_em', v_item.atualizado_em
  );
end;
$$;

revoke all on function public.imperium_estoque_criar_item_web(
  uuid, text, bigint, text, text, numeric, text, text, text, text,
  numeric, numeric, text, numeric, timestamptz
) from public, anon;
revoke all on function public.imperium_estoque_atualizar_item_web(
  uuid, uuid, timestamptz, text, text, numeric, text, text, text, text,
  boolean, timestamptz
) from public, anon;

grant execute on function public.imperium_estoque_criar_item_web(
  uuid, text, bigint, text, text, numeric, text, text, text, text,
  numeric, numeric, text, numeric, timestamptz
) to authenticated;
grant execute on function public.imperium_estoque_atualizar_item_web(
  uuid, uuid, timestamptz, text, text, numeric, text, text, text, text,
  boolean, timestamptz
) to authenticated;
