-- Central Cloud de relacionamento do CRM.
-- Registrada no repositorio apos aplicacao validada no Supabase em 2026-09-28.
-- Fontes: follow-up de lead, follow-up de orcamento, pos-venda de OS e beneficio/cupom.

create table if not exists public.imperium_crm_acoes_relacionamento (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  chave text not null,
  tipo text not null,
  entidade_tipo text not null,
  entidade_id uuid not null,
  cliente_id uuid,
  lead_id uuid,
  titulo text not null,
  nome_contato text not null default '',
  telefone text not null default '',
  mensagem_sugerida text not null default '',
  vencimento text not null,
  prioridade text not null default 'Normal',
  status text not null default 'Pendente',
  concluida_em text,
  adiada_para text,
  observacoes text not null default '',
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_crm_acoes_chave_uq unique (empresa_id, chave),
  constraint imperium_crm_acoes_entidade_ck check (entidade_tipo in ('lead','orcamento','ordem_servico','cupom')),
  constraint imperium_crm_acoes_prioridade_ck check (prioridade in ('Baixa','Normal','Alta')),
  constraint imperium_crm_acoes_status_ck check (status in ('Pendente','Concluida','Adiada','Ignorada'))
);

create index if not exists idx_imperium_crm_acoes_entidade
  on public.imperium_crm_acoes_relacionamento (empresa_id, entidade_tipo, entidade_id);
create index if not exists idx_imperium_crm_acoes_status_vencimento
  on public.imperium_crm_acoes_relacionamento (empresa_id, status, vencimento);

alter table public.imperium_crm_acoes_relacionamento enable row level security;

drop policy if exists imperium_crm_acoes_select on public.imperium_crm_acoes_relacionamento;
create policy imperium_crm_acoes_select on public.imperium_crm_acoes_relacionamento
  for select to authenticated
  using ((select private.imperium_pode_modulo(empresa_id, 'crm')));

drop policy if exists imperium_crm_acoes_insert on public.imperium_crm_acoes_relacionamento;
create policy imperium_crm_acoes_insert on public.imperium_crm_acoes_relacionamento
  for insert to authenticated
  with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

drop policy if exists imperium_crm_acoes_update on public.imperium_crm_acoes_relacionamento;
create policy imperium_crm_acoes_update on public.imperium_crm_acoes_relacionamento
  for update to authenticated
  using ((select private.imperium_pode_modulo(empresa_id, 'crm')))
  with check ((select private.imperium_pode_modulo(empresa_id, 'crm')));

grant select, insert, update on public.imperium_crm_acoes_relacionamento to authenticated;

CREATE OR REPLACE FUNCTION public.imperium_crm_adiar_acao_web(p_empresa_id uuid, p_acao_id uuid, p_atualizado_em_base timestamp with time zone, p_nova_data date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_acao public.imperium_crm_acoes_relacionamento%rowtype;
  v_agora timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;
  if not private.imperium_pode_modulo(p_empresa_id, 'crm') then
    raise exception 'Sem permissão para adiar ação do CRM.';
  end if;
  if p_nova_data < current_date then
    raise exception 'A nova data não pode ficar no passado.';
  end if;

  select * into v_acao
  from public.imperium_crm_acoes_relacionamento
  where empresa_id = p_empresa_id and id = p_acao_id
  for update;

  if not found then
    raise exception 'Ação de relacionamento não encontrada.';
  end if;
  if p_atualizado_em_base is not null
     and v_acao.atualizado_em <> p_atualizado_em_base then
    raise exception 'A ação foi alterada em outro dispositivo. Atualize e tente novamente.';
  end if;
  if v_acao.status not in ('Pendente', 'Adiada') then
    raise exception 'Ação não está disponível para adiamento.';
  end if;

  update public.imperium_crm_acoes_relacionamento
  set status = 'Pendente',
      vencimento = to_char(p_nova_data, 'YYYY-MM-DD'),
      adiada_para = to_char(p_nova_data, 'YYYY-MM-DD'),
      atualizado_em = v_agora
  where empresa_id = p_empresa_id and id = p_acao_id
  returning * into v_acao;

  return to_jsonb(v_acao);
end;
$function$


CREATE OR REPLACE FUNCTION public.imperium_crm_concluir_acao_web(p_empresa_id uuid, p_acao_id uuid, p_atualizado_em_base timestamp with time zone, p_observacoes text, p_proximo_contato text, p_origem_dispositivo text, p_interacao_origem_local_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_acao public.imperium_crm_acoes_relacionamento%rowtype;
  v_agora timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;
  if not private.imperium_pode_modulo(p_empresa_id, 'crm') then
    raise exception 'Sem permissão para concluir ação do CRM.';
  end if;

  select * into v_acao
  from public.imperium_crm_acoes_relacionamento
  where empresa_id = p_empresa_id and id = p_acao_id
  for update;

  if not found then
    raise exception 'Ação de relacionamento não encontrada.';
  end if;
  if p_atualizado_em_base is not null
     and v_acao.atualizado_em <> p_atualizado_em_base then
    raise exception 'A ação foi alterada em outro dispositivo. Atualize e tente novamente.';
  end if;
  if v_acao.status = 'Concluida' then
    return to_jsonb(v_acao);
  end if;

  update public.imperium_crm_acoes_relacionamento
  set status = 'Concluida',
      concluida_em = v_agora::text,
      observacoes = btrim(coalesce(p_observacoes, '')),
      atualizado_em = v_agora
  where empresa_id = p_empresa_id and id = p_acao_id
  returning * into v_acao;

  if v_acao.lead_id is not null then
    if btrim(coalesce(p_origem_dispositivo, '')) = ''
       or coalesce(p_interacao_origem_local_id, 0) <= 0 then
      raise exception 'Origem da interação é inválida.';
    end if;

    insert into public.imperium_crm_interacoes (
      empresa_id, origem_dispositivo, origem_local_id, lead_id,
      tipo, descricao, data_interacao, origem_criado_em,
      excluido_em, criado_em, atualizado_em
    ) values (
      p_empresa_id, btrim(p_origem_dispositivo),
      p_interacao_origem_local_id, v_acao.lead_id,
      v_acao.tipo,
      case
        when btrim(coalesce(p_observacoes, '')) = ''
          then 'Ação de relacionamento concluída: ' || v_acao.titulo || '.'
        else btrim(p_observacoes)
      end,
      v_agora::text, v_agora::text, null, v_agora, v_agora
    );

    if v_acao.tipo = 'Follow-up lead' then
      update public.imperium_crm_leads
      set proximo_contato = nullif(btrim(coalesce(p_proximo_contato, '')), ''),
          origem_atualizado_em = v_agora::text,
          atualizado_em = v_agora
      where empresa_id = p_empresa_id
        and id = v_acao.lead_id
        and excluido_em is null;
    end if;
  end if;

  return to_jsonb(v_acao);
end;
$function$


CREATE OR REPLACE FUNCTION public.imperium_crm_ignorar_acao_web(p_empresa_id uuid, p_acao_id uuid, p_atualizado_em_base timestamp with time zone, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_acao public.imperium_crm_acoes_relacionamento%rowtype;
  v_agora timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;
  if not private.imperium_pode_modulo(p_empresa_id, 'crm') then
    raise exception 'Sem permissão para ignorar ação do CRM.';
  end if;

  select * into v_acao
  from public.imperium_crm_acoes_relacionamento
  where empresa_id = p_empresa_id and id = p_acao_id
  for update;

  if not found then
    raise exception 'Ação de relacionamento não encontrada.';
  end if;
  if p_atualizado_em_base is not null
     and v_acao.atualizado_em <> p_atualizado_em_base then
    raise exception 'A ação foi alterada em outro dispositivo. Atualize e tente novamente.';
  end if;
  if v_acao.status = 'Concluida' then
    raise exception 'Ação concluída não pode ser ignorada.';
  end if;

  update public.imperium_crm_acoes_relacionamento
  set status = 'Ignorada',
      observacoes = btrim(coalesce(p_motivo, '')),
      atualizado_em = v_agora
  where empresa_id = p_empresa_id and id = p_acao_id
  returning * into v_acao;

  return to_jsonb(v_acao);
end;
$function$


CREATE OR REPLACE FUNCTION public.imperium_crm_sincronizar_acoes_web(p_empresa_id uuid, p_referencia date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_ref date := coalesce(p_referencia, current_date);
  v_agora timestamptz := now();
  v_criadas integer := 0;
  v_rows integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;

  if not private.imperium_pode_modulo(p_empresa_id, 'crm') then
    raise exception 'Sem permissão para sincronizar ações do CRM.';
  end if;

  update public.imperium_crm_acoes_relacionamento a
  set status = 'Ignorada',
      observacoes = case
        when btrim(a.observacoes) = ''
          then 'Lead encerrado ou follow-up removido.'
        else a.observacoes
      end,
      atualizado_em = v_agora
  where a.empresa_id = p_empresa_id
    and a.tipo = 'Follow-up lead'
    and a.status in ('Pendente', 'Adiada')
    and not exists (
      select 1
      from public.imperium_crm_leads l
      where l.empresa_id = p_empresa_id
        and l.id = a.entidade_id
        and l.excluido_em is null
        and l.etapa not in ('Ganho', 'Perdido')
        and btrim(coalesce(l.proximo_contato, '')) <> ''
    );

  update public.imperium_crm_acoes_relacionamento a
  set status = 'Ignorada',
      observacoes = case
        when btrim(a.observacoes) = ''
          then 'Orçamento não está mais pendente.'
        else a.observacoes
      end,
      atualizado_em = v_agora
  where a.empresa_id = p_empresa_id
    and a.tipo = 'Follow-up orçamento'
    and a.status in ('Pendente', 'Adiada')
    and not exists (
      select 1
      from public.imperium_orcamentos o
      where o.empresa_id = p_empresa_id
        and o.id = a.entidade_id
        and o.excluido_em is null
        and lower(btrim(o.status)) = 'pendente'
    );

  update public.imperium_crm_acoes_relacionamento a
  set status = 'Ignorada',
      observacoes = case
        when btrim(a.observacoes) = ''
          then 'A Ordem de Serviço não está mais finalizada.'
        else a.observacoes
      end,
      atualizado_em = v_agora
  where a.empresa_id = p_empresa_id
    and a.tipo = 'Pós-venda'
    and a.status in ('Pendente', 'Adiada')
    and not exists (
      select 1
      from public.imperium_ordens_servico os
      where os.empresa_id = p_empresa_id
        and os.id = a.entidade_id
        and os.excluido_em is null
        and lower(btrim(os.status)) = 'finalizada'
    );

  update public.imperium_crm_acoes_relacionamento a
  set status = 'Ignorada',
      observacoes = case
        when btrim(a.observacoes) = ''
          then 'Cupom não está mais ativo.'
        else a.observacoes
      end,
      atualizado_em = v_agora
  where a.empresa_id = p_empresa_id
    and a.tipo = 'Benefício/cupom'
    and a.status in ('Pendente', 'Adiada')
    and not exists (
      select 1
      from public.imperium_crm_cupons cp
      where cp.empresa_id = p_empresa_id
        and cp.id = a.entidade_id
        and cp.excluido_em is null
        and cp.status = 'Ativo'
    );

  insert into public.imperium_crm_acoes_relacionamento (
    empresa_id, chave, tipo, entidade_tipo, entidade_id,
    cliente_id, lead_id, titulo, nome_contato, telefone,
    mensagem_sugerida, vencimento, prioridade, status,
    concluida_em, adiada_para, observacoes, criado_em, atualizado_em
  )
  select
    p_empresa_id,
    'lead:' || l.id::text || ':' || left(l.proximo_contato, 10),
    'Follow-up lead',
    'lead',
    l.id,
    l.cliente_id,
    l.id,
    case
      when btrim(coalesce(l.etapa, '')) = '' then 'Retomar contato'
      else 'Retomar contato • ' || l.etapa
    end,
    l.nome,
    coalesce(l.telefone, ''),
    case
      when btrim(coalesce(l.servico_interesse, '')) = ''
        then 'Olá, ' || split_part(btrim(l.nome), ' ', 1) ||
             '! Tudo bem? Estou entrando em contato para dar continuidade ao seu atendimento na Imperium Detailing. Posso te ajudar em algo?'
      else 'Olá, ' || split_part(btrim(l.nome), ' ', 1) ||
           '! Tudo bem? Estou entrando em contato para dar continuidade ao atendimento sobre ' ||
           l.servico_interesse || '. Posso te ajudar a avançar?'
    end,
    left(l.proximo_contato, 10),
    case
      when left(l.proximo_contato, 10)::date < v_ref then 'Alta'
      else 'Normal'
    end,
    'Pendente', null, null, '', v_agora, v_agora
  from public.imperium_crm_leads l
  where l.empresa_id = p_empresa_id
    and l.excluido_em is null
    and l.etapa not in ('Ganho', 'Perdido')
    and l.proximo_contato ~ '^\d{4}-\d{2}-\d{2}'
    and left(l.proximo_contato, 10)::date <= v_ref + 30
  on conflict (empresa_id, chave) do nothing;
  get diagnostics v_rows = row_count;
  v_criadas := v_criadas + v_rows;

  update public.imperium_crm_acoes_relacionamento a
  set status = 'Ignorada',
      observacoes = 'Substituída por uma nova data de follow-up.',
      atualizado_em = v_agora
  where a.empresa_id = p_empresa_id
    and a.tipo = 'Follow-up lead'
    and a.status in ('Pendente', 'Adiada')
    and exists (
      select 1
      from public.imperium_crm_leads l
      where l.empresa_id = p_empresa_id
        and l.id = a.entidade_id
        and l.excluido_em is null
        and l.etapa not in ('Ganho', 'Perdido')
        and l.proximo_contato ~ '^\d{4}-\d{2}-\d{2}'
        and a.chave <> (
          'lead:' || l.id::text || ':' || left(l.proximo_contato, 10)
        )
    );

  insert into public.imperium_crm_acoes_relacionamento (
    empresa_id, chave, tipo, entidade_tipo, entidade_id,
    cliente_id, lead_id, titulo, nome_contato, telefone,
    mensagem_sugerida, vencimento, prioridade, status,
    concluida_em, adiada_para, observacoes, criado_em, atualizado_em
  )
  select
    p_empresa_id,
    'orcamento:' || o.id::text,
    'Follow-up orçamento',
    'orcamento',
    o.id,
    o.cliente_id,
    null,
    'Retomar orçamento #' ||
      coalesce(o.origem_local_id::text, left(o.id::text, 8)),
    c.nome,
    coalesce(c.telefone, ''),
    'Olá, ' || split_part(btrim(c.nome), ' ', 1) ||
    '! Tudo bem? Passando para saber se conseguiu analisar o orçamento para ' ||
    coalesce(
      nullif((
        select string_agg(nullif(btrim(i.servico), ''), ', ' order by i.ordem)
        from public.imperium_orcamento_itens i
        where i.empresa_id = p_empresa_id
          and i.orcamento_id = o.id
          and i.excluido_em is null
      ), ''),
      nullif(btrim(o.servico), ''),
      'os serviços solicitados'
    ) ||
    ', no valor de R$ ' || to_char(coalesce(o.valor, 0), 'FM999999990D00') ||
    '. Se quiser, posso tirar qualquer dúvida e ajustar os detalhes com você.',
    to_char(left(o.data_emissao, 10)::date + 2, 'YYYY-MM-DD'),
    case
      when left(o.data_emissao, 10)::date + 2 < v_ref then 'Alta'
      else 'Normal'
    end,
    'Pendente', null, null, '', v_agora, v_agora
  from public.imperium_orcamentos o
  join public.imperium_clientes c
    on c.empresa_id = o.empresa_id
   and c.id = o.cliente_id
   and c.excluido_em is null
   and c.ativo = true
  where o.empresa_id = p_empresa_id
    and o.excluido_em is null
    and lower(btrim(o.status)) = 'pendente'
    and o.data_emissao ~ '^\d{4}-\d{2}-\d{2}'
    and (
      o.validade is null
      or btrim(o.validade) = ''
      or o.validade !~ '^\d{4}-\d{2}-\d{2}'
      or left(o.validade, 10)::date >= v_ref
    )
    and left(o.data_emissao, 10)::date + 2 <= v_ref + 30
  on conflict (empresa_id, chave) do nothing;
  get diagnostics v_rows = row_count;
  v_criadas := v_criadas + v_rows;

  update public.imperium_crm_acoes_relacionamento a
  set status = 'Ignorada',
      observacoes = case
        when btrim(a.observacoes) = ''
          then 'Orçamento venceu antes do follow-up ser concluído.'
        else a.observacoes
      end,
      atualizado_em = v_agora
  where a.empresa_id = p_empresa_id
    and a.tipo = 'Follow-up orçamento'
    and a.status in ('Pendente', 'Adiada')
    and exists (
      select 1
      from public.imperium_orcamentos o
      where o.empresa_id = p_empresa_id
        and o.id = a.entidade_id
        and o.validade ~ '^\d{4}-\d{2}-\d{2}'
        and left(o.validade, 10)::date < v_ref
    );

  insert into public.imperium_crm_acoes_relacionamento (
    empresa_id, chave, tipo, entidade_tipo, entidade_id,
    cliente_id, lead_id, titulo, nome_contato, telefone,
    mensagem_sugerida, vencimento, prioridade, status,
    concluida_em, adiada_para, observacoes, criado_em, atualizado_em
  )
  select
    p_empresa_id,
    'posvenda:' || os.id::text,
    'Pós-venda',
    'ordem_servico',
    os.id,
    os.cliente_id,
    null,
    'Pós-venda • OS ' || coalesce(os.numero, left(os.id::text, 8)),
    c.nome,
    coalesce(c.telefone, ''),
    'Olá, ' || split_part(btrim(c.nome), ' ', 1) ||
    '! Passando para agradecer novamente pela confiança na Imperium Detailing. Como ficou o veículo depois do serviço da OS ' ||
    coalesce(os.numero, left(os.id::text, 8)) ||
    '? Se puder, conta pra gente como foi sua experiência. 🙌',
    to_char(
      left(
        coalesce(os.data_finalizacao, os.data_inicio, os.data_abertura),
        10
      )::date + 1,
      'YYYY-MM-DD'
    ),
    case
      when left(
        coalesce(os.data_finalizacao, os.data_inicio, os.data_abertura),
        10
      )::date + 1 < v_ref then 'Alta'
      else 'Normal'
    end,
    'Pendente', null, null, '', v_agora, v_agora
  from public.imperium_ordens_servico os
  join public.imperium_clientes c
    on c.empresa_id = os.empresa_id
   and c.id = os.cliente_id
   and c.excluido_em is null
   and c.ativo = true
  where os.empresa_id = p_empresa_id
    and os.excluido_em is null
    and lower(btrim(os.status)) = 'finalizada'
    and coalesce(
      os.data_finalizacao, os.data_inicio, os.data_abertura
    ) ~ '^\d{4}-\d{2}-\d{2}'
    and left(
      coalesce(os.data_finalizacao, os.data_inicio, os.data_abertura),
      10
    )::date between v_ref - 60 and v_ref
  on conflict (empresa_id, chave) do nothing;
  get diagnostics v_rows = row_count;
  v_criadas := v_criadas + v_rows;

  insert into public.imperium_crm_acoes_relacionamento (
    empresa_id, chave, tipo, entidade_tipo, entidade_id,
    cliente_id, lead_id, titulo, nome_contato, telefone,
    mensagem_sugerida, vencimento, prioridade, status,
    concluida_em, adiada_para, observacoes, criado_em, atualizado_em
  )
  select
    p_empresa_id,
    'cupom:' || cp.id::text,
    'Benefício/cupom',
    'cupom',
    cp.id,
    cp.cliente_id,
    cp.lead_id,
    'Enviar benefício • ' || cp.codigo,
    c.nome,
    coalesce(c.telefone, ''),
    'Olá, ' || split_part(btrim(c.nome), ' ', 1) ||
    '! Temos um benefício da Imperium Detailing para você: ' ||
    case
      when btrim(coalesce(cp.beneficio_descricao, '')) <> ''
        then cp.beneficio_descricao
      when cp.beneficio_tipo = 'Percentual'
        then trim(to_char(cp.beneficio_valor, 'FM999990D99')) || '% de benefício'
      when cp.beneficio_tipo in ('Valor', 'Crédito')
        then 'R$ ' || to_char(cp.beneficio_valor, 'FM999999990D00') || ' de benefício'
      else 'um benefício especial'
    end ||
    '. Código: ' || cp.codigo ||
    '. Válido até ' || cp.validade_fim || '.',
    case
      when cp.validade_inicio ~ '^\d{4}-\d{2}-\d{2}'
           and left(cp.validade_inicio, 10)::date > v_ref
        then left(cp.validade_inicio, 10)
      else to_char(v_ref, 'YYYY-MM-DD')
    end,
    case
      when cp.validade_fim ~ '^\d{4}-\d{2}-\d{2}'
           and left(cp.validade_fim, 10)::date - v_ref <= 3
        then 'Alta'
      else 'Normal'
    end,
    'Pendente', null, null, '', v_agora, v_agora
  from public.imperium_crm_cupons cp
  join public.imperium_clientes c
    on c.empresa_id = cp.empresa_id
   and c.id = cp.cliente_id
   and c.excluido_em is null
   and c.ativo = true
  where cp.empresa_id = p_empresa_id
    and cp.excluido_em is null
    and cp.status = 'Ativo'
    and cp.validade_fim ~ '^\d{4}-\d{2}-\d{2}'
    and left(cp.validade_fim, 10)::date >= v_ref
  on conflict (empresa_id, chave) do nothing;
  get diagnostics v_rows = row_count;
  v_criadas := v_criadas + v_rows;

  return jsonb_build_object('criadas', v_criadas);
end;
$function$


revoke all on function public.imperium_crm_sincronizar_acoes_web(uuid,date) from public;
revoke all on function public.imperium_crm_concluir_acao_web(uuid,uuid,timestamptz,text,text,text,bigint) from public;
revoke all on function public.imperium_crm_adiar_acao_web(uuid,uuid,timestamptz,date) from public;
revoke all on function public.imperium_crm_ignorar_acao_web(uuid,uuid,timestamptz,text) from public;

grant execute on function public.imperium_crm_sincronizar_acoes_web(uuid,date) to authenticated;
grant execute on function public.imperium_crm_concluir_acao_web(uuid,uuid,timestamptz,text,text,text,bigint) to authenticated;
grant execute on function public.imperium_crm_adiar_acao_web(uuid,uuid,timestamptz,date) to authenticated;
grant execute on function public.imperium_crm_ignorar_acao_web(uuid,uuid,timestamptz,text) to authenticated;
