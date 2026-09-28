alter table public.imperium_ordens_servico
  add column if not exists orcamento_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'imperium_os_orcamento_fk'
      and conrelid = 'public.imperium_ordens_servico'::regclass
  ) then
    alter table public.imperium_ordens_servico
      add constraint imperium_os_orcamento_fk
      foreign key (orcamento_id)
      references public.imperium_orcamentos(id)
      on delete restrict;
  end if;
end
$$;

create unique index if not exists idx_imperium_os_orcamento_ativo_uq
  on public.imperium_ordens_servico(empresa_id, orcamento_id)
  where orcamento_id is not null and excluido_em is null;

create index if not exists idx_imperium_os_orcamento
  on public.imperium_ordens_servico(empresa_id, orcamento_id);

create or replace function public.imperium_orcamento_gerar_os_web(
  p_empresa_id uuid,
  p_orcamento_id uuid,
  p_atualizado_em_base timestamptz,
  p_funcionario_responsavel text default ''
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_orc public.imperium_orcamentos%rowtype;
  v_os public.imperium_ordens_servico%rowtype;
  v_existente public.imperium_ordens_servico%rowtype;
  v_agora timestamptz := now();
  v_numero text;
  v_subtotal numeric := 0;
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;

  if not private.imperium_pode_modulo(p_empresa_id, 'orcamentos') then
    raise exception 'Sem permissão para acessar orçamentos.';
  end if;

  if not private.imperium_pode_modulo(p_empresa_id, 'ordens_servico') then
    raise exception 'Sem permissão para criar Ordem de Serviço.';
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

  select *
    into v_existente
  from public.imperium_ordens_servico
  where empresa_id = p_empresa_id
    and orcamento_id = p_orcamento_id
    and excluido_em is null
  limit 1;

  if found then
    return jsonb_build_object(
      'criada', false,
      'ordem', to_jsonb(v_existente)
    );
  end if;

  if v_orc.status <> 'Aprovado' then
    raise exception 'A Ordem de Serviço só pode ser gerada a partir de orçamento aprovado.';
  end if;

  select coalesce(sum(i.quantidade * i.valor_unitario), 0)
    into v_subtotal
  from public.imperium_orcamento_itens i
  where i.empresa_id = p_empresa_id
    and i.orcamento_id = p_orcamento_id
    and i.excluido_em is null;

  if v_subtotal <= 0 then
    raise exception 'O orçamento não possui serviços válidos para gerar a OS.';
  end if;

  v_numero :=
    'WEB-' ||
    to_char(v_agora at time zone 'UTC', 'YYYYMMDD-HH24MISS') ||
    '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  insert into public.imperium_ordens_servico (
    empresa_id,
    cliente_id,
    veiculo_id,
    agendamento_id,
    orcamento_id,
    origem_dispositivo,
    origem_local_id,
    numero,
    status,
    data_abertura,
    data_inicio,
    data_finalizacao,
    hora_entrada,
    hora_saida,
    funcionario_responsavel,
    observacoes,
    valor_total,
    desconto,
    forma_pagamento,
    quilometragem_entrada,
    combustivel_entrada,
    revisada_em,
    motivo_ultima_revisao,
    quantidade_revisoes,
    assinatura_desatualizada,
    status_pagamento,
    valor_recebido,
    vencimento_pagamento,
    pagamento_atualizado_em,
    desconto_negociacao,
    acrescimo_negociacao,
    juros_parcelamento,
    excluido_em,
    criado_em,
    atualizado_em
  ) values (
    p_empresa_id,
    v_orc.cliente_id,
    v_orc.veiculo_id,
    null,
    p_orcamento_id,
    null,
    null,
    v_numero,
    'Aberta',
    to_char(v_agora at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    null,
    null,
    null,
    null,
    trim(coalesce(p_funcionario_responsavel, '')),
    v_orc.observacoes,
    v_subtotal,
    least(greatest(v_orc.desconto, 0), v_subtotal),
    null,
    '',
    '',
    null,
    '',
    0,
    false,
    'Pendente',
    0,
    null,
    null,
    0,
    0,
    0,
    null,
    v_agora,
    v_agora
  )
  returning * into v_os;

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
    excluido_em,
    criado_em,
    atualizado_em
  )
  select
    p_empresa_id,
    v_os.id,
    null,
    null,
    i.servico,
    i.descricao,
    i.quantidade,
    i.valor_unitario,
    false,
    i.ordem,
    null,
    v_agora,
    v_agora
  from public.imperium_orcamento_itens i
  where i.empresa_id = p_empresa_id
    and i.orcamento_id = p_orcamento_id
    and i.excluido_em is null
  order by i.ordem;

  return jsonb_build_object(
    'criada', true,
    'ordem', to_jsonb(v_os)
  );
end;
$$;

revoke all on function public.imperium_orcamento_gerar_os_web(
  uuid, uuid, timestamptz, text
) from public, anon;

grant execute on function public.imperium_orcamento_gerar_os_web(
  uuid, uuid, timestamptz, text
) to authenticated;
