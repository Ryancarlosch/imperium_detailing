create or replace function public.imperium_crm_converter_lead_web(
  p_empresa_id uuid,
  p_lead_id uuid,
  p_atualizado_em_base timestamptz,
  p_origem_dispositivo text,
  p_cliente_origem_local_id bigint,
  p_interacao_origem_local_id bigint
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_lead public.imperium_crm_leads%rowtype;
  v_cliente public.imperium_clientes%rowtype;
  v_agora timestamptz := now();
  v_telefone text;
  v_email text;
  v_criado boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;

  if not private.imperium_pode_modulo(p_empresa_id, 'crm') then
    raise exception 'Sem permissão para operar o CRM.';
  end if;

  if not private.imperium_pode_modulo(p_empresa_id, 'clientes') then
    raise exception 'Sem permissão para converter lead em cliente.';
  end if;

  if trim(coalesce(p_origem_dispositivo, '')) = ''
     or coalesce(p_cliente_origem_local_id, 0) <= 0
     or coalesce(p_interacao_origem_local_id, 0) <= 0 then
    raise exception 'Origem Web inválida.';
  end if;

  select *
    into v_lead
  from public.imperium_crm_leads
  where empresa_id = p_empresa_id
    and id = p_lead_id
    and excluido_em is null
  for update;

  if not found then
    raise exception 'Lead não encontrado.';
  end if;

  if p_atualizado_em_base is not null
     and v_lead.atualizado_em <> p_atualizado_em_base then
    raise exception 'O lead foi alterado em outro dispositivo. Atualize e tente novamente.';
  end if;

  if v_lead.cliente_id is not null then
    select *
      into v_cliente
    from public.imperium_clientes
    where empresa_id = p_empresa_id
      and id = v_lead.cliente_id
      and excluido_em is null
    limit 1;

    if found then
      return jsonb_build_object(
        'criado', false,
        'cliente', to_jsonb(v_cliente),
        'lead', to_jsonb(v_lead)
      );
    end if;
  end if;

  v_telefone := regexp_replace(coalesce(v_lead.telefone, ''), '\D', '', 'g');
  v_email := lower(trim(coalesce(v_lead.email, '')));

  select *
    into v_cliente
  from public.imperium_clientes c
  where c.empresa_id = p_empresa_id
    and c.excluido_em is null
    and c.ativo = true
    and (
      (
        v_telefone <> ''
        and regexp_replace(coalesce(c.telefone, ''), '\D', '', 'g') = v_telefone
      )
      or (
        v_email <> ''
        and lower(trim(coalesce(c.email, ''))) = v_email
      )
    )
  order by c.criado_em, c.id
  limit 1;

  if not found then
    insert into public.imperium_clientes (
      empresa_id,
      origem_dispositivo,
      origem_local_id,
      nome,
      telefone,
      email,
      endereco,
      observacoes,
      ativo,
      arquivado_em,
      excluido_em,
      criado_em,
      atualizado_em
    ) values (
      p_empresa_id,
      trim(p_origem_dispositivo),
      p_cliente_origem_local_id,
      trim(v_lead.nome),
      trim(coalesce(v_lead.telefone, '')),
      trim(coalesce(v_lead.email, '')),
      '',
      case
        when trim(coalesce(v_lead.observacoes, '')) = ''
          then 'Cliente convertido pelo CRM.'
        else 'CRM: ' || trim(v_lead.observacoes)
      end,
      true,
      null,
      null,
      v_agora,
      v_agora
    )
    returning * into v_cliente;

    v_criado := true;
  end if;

  update public.imperium_crm_leads
  set cliente_id = v_cliente.id,
      origem_atualizado_em = v_agora::text,
      atualizado_em = v_agora
  where empresa_id = p_empresa_id
    and id = p_lead_id
  returning * into v_lead;

  insert into public.imperium_crm_interacoes (
    empresa_id,
    origem_dispositivo,
    origem_local_id,
    lead_id,
    tipo,
    descricao,
    data_interacao,
    origem_criado_em,
    excluido_em,
    criado_em,
    atualizado_em
  ) values (
    p_empresa_id,
    trim(p_origem_dispositivo),
    p_interacao_origem_local_id,
    p_lead_id,
    'Conversão de cadastro',
    'Contato convertido/vinculado a um cliente do cadastro.',
    v_agora::text,
    v_agora::text,
    null,
    v_agora,
    v_agora
  );

  return jsonb_build_object(
    'criado', v_criado,
    'cliente', to_jsonb(v_cliente),
    'lead', to_jsonb(v_lead)
  );
end;
$$;

revoke all on function public.imperium_crm_converter_lead_web(
  uuid, uuid, timestamptz, text, bigint, bigint
) from public, anon;

grant execute on function public.imperium_crm_converter_lead_web(
  uuid, uuid, timestamptz, text, bigint, bigint
) to authenticated;


create or replace function public.imperium_crm_agendar_lead_web(
  p_empresa_id uuid,
  p_lead_id uuid,
  p_atualizado_em_base timestamptz,
  p_veiculo_id uuid,
  p_data text,
  p_hora text,
  p_servico text,
  p_valor numeric,
  p_observacoes text,
  p_origem_dispositivo text,
  p_agendamento_origem_local_id bigint,
  p_interacao_origem_local_id bigint
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_lead public.imperium_crm_leads%rowtype;
  v_agendamento public.imperium_agendamentos%rowtype;
  v_agora timestamptz := now();
  v_servico text := trim(coalesce(p_servico, ''));
  v_hora text := trim(coalesce(p_hora, ''));
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;

  if not private.imperium_pode_modulo(p_empresa_id, 'crm') then
    raise exception 'Sem permissão para operar o CRM.';
  end if;

  if not private.imperium_pode_modulo(p_empresa_id, 'agenda') then
    raise exception 'Sem permissão para criar agendamentos.';
  end if;

  if trim(coalesce(p_origem_dispositivo, '')) = ''
     or coalesce(p_agendamento_origem_local_id, 0) <= 0
     or coalesce(p_interacao_origem_local_id, 0) <= 0 then
    raise exception 'Origem Web inválida.';
  end if;

  if v_servico = '' then
    raise exception 'Informe o serviço.';
  end if;

  if v_hora = '' then
    raise exception 'Informe o horário.';
  end if;

  if trim(coalesce(p_data, '')) = '' then
    raise exception 'Informe a data do agendamento.';
  end if;

  select *
    into v_lead
  from public.imperium_crm_leads
  where empresa_id = p_empresa_id
    and id = p_lead_id
    and excluido_em is null
  for update;

  if not found then
    raise exception 'Lead não encontrado.';
  end if;

  if p_atualizado_em_base is not null
     and v_lead.atualizado_em <> p_atualizado_em_base then
    raise exception 'O lead foi alterado em outro dispositivo. Atualize e tente novamente.';
  end if;

  if v_lead.cliente_id is null then
    raise exception 'Converta ou vincule o lead a um cliente antes de agendar.';
  end if;

  if v_lead.agendamento_id is not null then
    select *
      into v_agendamento
    from public.imperium_agendamentos a
    where a.empresa_id = p_empresa_id
      and a.id = v_lead.agendamento_id
      and a.excluido_em is null
    limit 1;

    if found then
      return jsonb_build_object(
        'criado', false,
        'agendamento', to_jsonb(v_agendamento),
        'lead', to_jsonb(v_lead)
      );
    end if;
  end if;

  if not exists (
    select 1
    from public.imperium_veiculos v
    where v.empresa_id = p_empresa_id
      and v.id = p_veiculo_id
      and v.cliente_id = v_lead.cliente_id
      and v.excluido_em is null
  ) then
    raise exception 'O veículo selecionado não pertence ao cliente.';
  end if;

  insert into public.imperium_agendamentos (
    empresa_id,
    cliente_id,
    veiculo_id,
    origem_dispositivo,
    origem_local_id,
    servico,
    data,
    hora,
    valor,
    status,
    observacoes,
    excluido_em,
    criado_em,
    atualizado_em
  ) values (
    p_empresa_id,
    v_lead.cliente_id,
    p_veiculo_id,
    trim(p_origem_dispositivo),
    p_agendamento_origem_local_id,
    v_servico,
    trim(p_data),
    v_hora,
    greatest(coalesce(p_valor, 0), 0),
    'Agendado',
    trim(coalesce(p_observacoes, '')),
    null,
    v_agora,
    v_agora
  )
  returning * into v_agendamento;

  update public.imperium_crm_leads
  set veiculo_id = p_veiculo_id,
      agendamento_id = v_agendamento.id,
      etapa = 'Agendado',
      proximo_contato = null,
      origem_atualizado_em = v_agora::text,
      atualizado_em = v_agora
  where empresa_id = p_empresa_id
    and id = p_lead_id
  returning * into v_lead;

  insert into public.imperium_crm_interacoes (
    empresa_id,
    origem_dispositivo,
    origem_local_id,
    lead_id,
    tipo,
    descricao,
    data_interacao,
    origem_criado_em,
    excluido_em,
    criado_em,
    atualizado_em
  ) values (
    p_empresa_id,
    trim(p_origem_dispositivo),
    p_interacao_origem_local_id,
    p_lead_id,
    'Agendamento',
    'Agendamento criado para ' || v_servico || '.',
    v_agora::text,
    v_agora::text,
    null,
    v_agora,
    v_agora
  );

  return jsonb_build_object(
    'criado', true,
    'agendamento', to_jsonb(v_agendamento),
    'lead', to_jsonb(v_lead)
  );
end;
$$;

revoke all on function public.imperium_crm_agendar_lead_web(
  uuid, uuid, timestamptz, uuid, text, text, text, numeric, text,
  text, bigint, bigint
) from public, anon;

grant execute on function public.imperium_crm_agendar_lead_web(
  uuid, uuid, timestamptz, uuid, text, text, text, numeric, text,
  text, bigint, bigint
) to authenticated;
