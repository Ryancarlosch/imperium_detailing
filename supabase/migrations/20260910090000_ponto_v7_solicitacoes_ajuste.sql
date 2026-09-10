
-- Imperium Manager - Ponto V7
-- Solicitações de ajuste de ponto com aprovação administrativa e auditoria.

create table if not exists public.ponto_solicitacoes_ajuste (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  colaborador_id uuid not null references public.ponto_colaboradores(id) on delete cascade,
  data date not null,
  situacao_solicitada text not null default 'Trabalhado'
    check (situacao_solicitada in ('Trabalhado', 'Falta', 'Atestado', 'Folga')),
  entrada_solicitada time,
  intervalo_inicio_solicitado time,
  intervalo_fim_solicitado time,
  saida_solicitada time,
  observacoes_solicitadas text not null default '',
  motivo text not null,
  registro_atual_json jsonb,
  status text not null default 'Pendente'
    check (status in ('Pendente', 'Aprovada', 'Rejeitada', 'Cancelada')),
  solicitado_por uuid not null default auth.uid()
    references auth.users(id) on delete cascade,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  decidido_em timestamptz,
  decidido_por uuid references auth.users(id) on delete set null,
  decisao_motivo text not null default ''
);

create unique index if not exists uq_ponto_solicitacao_pendente_dia
  on public.ponto_solicitacoes_ajuste (empresa_id, colaborador_id, data)
  where status = 'Pendente';

create index if not exists idx_ponto_solicitacoes_empresa_status
  on public.ponto_solicitacoes_ajuste (empresa_id, status, criado_em desc);

create index if not exists idx_ponto_solicitacoes_colaborador
  on public.ponto_solicitacoes_ajuste (colaborador_id, criado_em desc);

alter table public.ponto_solicitacoes_ajuste enable row level security;

drop policy if exists ponto_solicitacoes_select on public.ponto_solicitacoes_ajuste;
create policy ponto_solicitacoes_select
on public.ponto_solicitacoes_ajuste
for select
to authenticated
using (
  private.usuario_admin_empresa(empresa_id)
  or exists (
    select 1
    from public.ponto_colaboradores pc
    where pc.id = ponto_solicitacoes_ajuste.colaborador_id
      and pc.empresa_id = ponto_solicitacoes_ajuste.empresa_id
      and pc.auth_user_id = auth.uid()
      and pc.ativo = true
  )
);

revoke insert, update, delete on public.ponto_solicitacoes_ajuste
  from anon, authenticated;
grant select on public.ponto_solicitacoes_ajuste to authenticated;

create or replace function public.ponto_solicitar_ajuste(
  p_empresa_id uuid,
  p_colaborador_id uuid,
  p_data date,
  p_situacao text,
  p_entrada time default null,
  p_intervalo_inicio time default null,
  p_intervalo_fim time default null,
  p_saida time default null,
  p_observacoes text default '',
  p_motivo text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth uuid := auth.uid();
  v_existente uuid;
  v_registro jsonb;
  v_resultado jsonb;
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_obs text := btrim(coalesce(p_observacoes, ''));
begin
  if v_auth is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not exists (
    select 1
    from public.ponto_colaboradores pc
    where pc.id = p_colaborador_id
      and pc.empresa_id = p_empresa_id
      and pc.auth_user_id = v_auth
      and pc.ativo = true
  ) then
    raise exception 'Este usuário não está vinculado ao funcionário informado.';
  end if;

  if p_data is null or p_data > current_date then
    raise exception 'A correção só pode ser solicitada para hoje ou data anterior.';
  end if;

  if p_situacao not in ('Trabalhado', 'Falta', 'Atestado', 'Folga') then
    raise exception 'Situação do ponto inválida.';
  end if;

  if char_length(v_motivo) < 5 then
    raise exception 'Informe o motivo da correção com pelo menos 5 caracteres.';
  end if;

  if p_situacao = 'Trabalhado' then
    if p_entrada is null or p_saida is null then
      raise exception 'Para dia trabalhado, informe entrada e saída.';
    end if;

    if p_saida <= p_entrada then
      raise exception 'A saída precisa ser posterior à entrada.';
    end if;

    if (p_intervalo_inicio is null) <> (p_intervalo_fim is null) then
      raise exception 'Informe início e fim do intervalo juntos.';
    end if;

    if p_intervalo_inicio is not null then
      if p_intervalo_inicio <= p_entrada
         or p_intervalo_fim <= p_intervalo_inicio
         or p_saida <= p_intervalo_fim then
        raise exception 'Os horários do intervalo estão fora da ordem esperada.';
      end if;
    end if;
  end if;

  select to_jsonb(pr)
    into v_registro
  from public.ponto_registros pr
  where pr.empresa_id = p_empresa_id
    and pr.colaborador_id = p_colaborador_id
    and pr.data = p_data
  limit 1;

  select s.id
    into v_existente
  from public.ponto_solicitacoes_ajuste s
  where s.empresa_id = p_empresa_id
    and s.colaborador_id = p_colaborador_id
    and s.data = p_data
    and s.status = 'Pendente'
  order by s.criado_em desc
  limit 1
  for update;

  if v_existente is null then
    insert into public.ponto_solicitacoes_ajuste (
      empresa_id,
      colaborador_id,
      data,
      situacao_solicitada,
      entrada_solicitada,
      intervalo_inicio_solicitado,
      intervalo_fim_solicitado,
      saida_solicitada,
      observacoes_solicitadas,
      motivo,
      registro_atual_json,
      status,
      solicitado_por
    ) values (
      p_empresa_id,
      p_colaborador_id,
      p_data,
      p_situacao,
      case when p_situacao = 'Trabalhado' then p_entrada else null end,
      case when p_situacao = 'Trabalhado' then p_intervalo_inicio else null end,
      case when p_situacao = 'Trabalhado' then p_intervalo_fim else null end,
      case when p_situacao = 'Trabalhado' then p_saida else null end,
      v_obs,
      v_motivo,
      v_registro,
      'Pendente',
      v_auth
    )
    returning id into v_existente;
  else
    update public.ponto_solicitacoes_ajuste
    set
      situacao_solicitada = p_situacao,
      entrada_solicitada = case when p_situacao = 'Trabalhado' then p_entrada else null end,
      intervalo_inicio_solicitado = case when p_situacao = 'Trabalhado' then p_intervalo_inicio else null end,
      intervalo_fim_solicitado = case when p_situacao = 'Trabalhado' then p_intervalo_fim else null end,
      saida_solicitada = case when p_situacao = 'Trabalhado' then p_saida else null end,
      observacoes_solicitadas = v_obs,
      motivo = v_motivo,
      registro_atual_json = v_registro,
      atualizado_em = now()
    where id = v_existente;
  end if;

  select to_jsonb(s)
    into v_resultado
  from public.ponto_solicitacoes_ajuste s
  where s.id = v_existente;

  return v_resultado;
end;
$$;

create or replace function public.ponto_minhas_solicitacoes_ajuste(
  p_empresa_id uuid,
  p_colaborador_id uuid,
  p_limite integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth uuid := auth.uid();
  v_resultado jsonb;
begin
  if v_auth is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not exists (
    select 1
    from public.ponto_colaboradores pc
    where pc.id = p_colaborador_id
      and pc.empresa_id = p_empresa_id
      and pc.auth_user_id = v_auth
      and pc.ativo = true
  ) then
    raise exception 'Acesso ao funcionário não autorizado.';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.criado_em desc),
    '[]'::jsonb
  )
  into v_resultado
  from (
    select
      s.id,
      s.data,
      s.situacao_solicitada,
      s.entrada_solicitada,
      s.intervalo_inicio_solicitado,
      s.intervalo_fim_solicitado,
      s.saida_solicitada,
      s.observacoes_solicitadas,
      s.motivo,
      s.registro_atual_json,
      s.status,
      s.criado_em,
      s.atualizado_em,
      s.decidido_em,
      s.decisao_motivo
    from public.ponto_solicitacoes_ajuste s
    where s.empresa_id = p_empresa_id
      and s.colaborador_id = p_colaborador_id
    order by s.criado_em desc
    limit greatest(1, least(coalesce(p_limite, 50), 200))
  ) x;

  return v_resultado;
end;
$$;

create or replace function public.ponto_listar_solicitacoes_ajuste_admin(
  p_empresa_id uuid,
  p_status text default 'Pendente',
  p_limite integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resultado jsonb;
begin
  if auth.uid() is null or not private.usuario_admin_empresa(p_empresa_id) then
    raise exception 'Somente administradores da empresa podem revisar solicitações.';
  end if;

  if p_status not in ('Pendente', 'Aprovada', 'Rejeitada', 'Cancelada', 'Todos') then
    raise exception 'Status de solicitação inválido.';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.criado_em desc),
    '[]'::jsonb
  )
  into v_resultado
  from (
    select
      s.id,
      s.empresa_id,
      s.colaborador_id,
      pc.nome as colaborador_nome,
      pc.funcao as colaborador_funcao,
      s.data,
      s.situacao_solicitada,
      s.entrada_solicitada,
      s.intervalo_inicio_solicitado,
      s.intervalo_fim_solicitado,
      s.saida_solicitada,
      s.observacoes_solicitadas,
      s.motivo,
      s.registro_atual_json,
      s.status,
      s.criado_em,
      s.atualizado_em,
      s.decidido_em,
      s.decisao_motivo
    from public.ponto_solicitacoes_ajuste s
    join public.ponto_colaboradores pc
      on pc.id = s.colaborador_id
     and pc.empresa_id = s.empresa_id
    where s.empresa_id = p_empresa_id
      and (p_status = 'Todos' or s.status = p_status)
    order by
      case when s.status = 'Pendente' then 0 else 1 end,
      s.criado_em desc
    limit greatest(1, least(coalesce(p_limite, 100), 300))
  ) x;

  return v_resultado;
end;
$$;

create or replace function public.ponto_cancelar_solicitacao_ajuste(
  p_solicitacao_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth uuid := auth.uid();
  v_solicitacao public.ponto_solicitacoes_ajuste%rowtype;
begin
  if v_auth is null then
    raise exception 'Usuário não autenticado.';
  end if;

  select *
    into v_solicitacao
  from public.ponto_solicitacoes_ajuste s
  where s.id = p_solicitacao_id
  for update;

  if not found then
    raise exception 'Solicitação não encontrada.';
  end if;

  if v_solicitacao.status <> 'Pendente' then
    raise exception 'Somente solicitação pendente pode ser cancelada.';
  end if;

  if not exists (
    select 1
    from public.ponto_colaboradores pc
    where pc.id = v_solicitacao.colaborador_id
      and pc.empresa_id = v_solicitacao.empresa_id
      and pc.auth_user_id = v_auth
      and pc.ativo = true
  ) then
    raise exception 'Você não pode cancelar esta solicitação.';
  end if;

  update public.ponto_solicitacoes_ajuste
  set
    status = 'Cancelada',
    atualizado_em = now(),
    decidido_em = now(),
    decidido_por = v_auth,
    decisao_motivo = 'Cancelada pelo funcionário'
  where id = p_solicitacao_id
  returning * into v_solicitacao;

  return to_jsonb(v_solicitacao);
end;
$$;

create or replace function public.ponto_decidir_solicitacao_ajuste(
  p_solicitacao_id uuid,
  p_aprovar boolean,
  p_motivo text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_solicitacao public.ponto_solicitacoes_ajuste%rowtype;
  v_motivo text := btrim(coalesce(p_motivo, ''));
  v_ajuste jsonb;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado.';
  end if;

  select *
    into v_solicitacao
  from public.ponto_solicitacoes_ajuste s
  where s.id = p_solicitacao_id
  for update;

  if not found then
    raise exception 'Solicitação não encontrada.';
  end if;

  if not private.usuario_admin_empresa(v_solicitacao.empresa_id) then
    raise exception 'Somente administradores da empresa podem decidir solicitações.';
  end if;

  if v_solicitacao.status <> 'Pendente' then
    raise exception 'Esta solicitação já foi decidida.';
  end if;

  if not p_aprovar and char_length(v_motivo) < 5 then
    raise exception 'Informe o motivo da rejeição com pelo menos 5 caracteres.';
  end if;

  if p_aprovar then
    v_ajuste := public.ponto_salvar_registro_admin(
      v_solicitacao.empresa_id,
      v_solicitacao.colaborador_id,
      v_solicitacao.data,
      v_solicitacao.situacao_solicitada,
      v_solicitacao.entrada_solicitada,
      v_solicitacao.intervalo_inicio_solicitado,
      v_solicitacao.intervalo_fim_solicitado,
      v_solicitacao.saida_solicitada,
      v_solicitacao.observacoes_solicitadas,
      concat(
        'Solicitação do funcionário: ',
        v_solicitacao.motivo,
        case when v_motivo = '' then '' else concat(' | Aprovação: ', v_motivo) end
      )
    );
  end if;

  update public.ponto_solicitacoes_ajuste
  set
    status = case when p_aprovar then 'Aprovada' else 'Rejeitada' end,
    atualizado_em = now(),
    decidido_em = now(),
    decidido_por = auth.uid(),
    decisao_motivo = case
      when p_aprovar and v_motivo = '' then 'Aprovada pelo administrador'
      else v_motivo
    end
  where id = p_solicitacao_id
  returning * into v_solicitacao;

  return jsonb_build_object(
    'solicitacao', to_jsonb(v_solicitacao),
    'registro', v_ajuste
  );
end;
$$;

revoke all on function public.ponto_solicitar_ajuste(uuid, uuid, date, text, time, time, time, time, text, text)
  from public, anon;
revoke all on function public.ponto_minhas_solicitacoes_ajuste(uuid, uuid, integer)
  from public, anon;
revoke all on function public.ponto_listar_solicitacoes_ajuste_admin(uuid, text, integer)
  from public, anon;
revoke all on function public.ponto_cancelar_solicitacao_ajuste(uuid)
  from public, anon;
revoke all on function public.ponto_decidir_solicitacao_ajuste(uuid, boolean, text)
  from public, anon;

grant execute on function public.ponto_solicitar_ajuste(uuid, uuid, date, text, time, time, time, time, text, text)
  to authenticated;
grant execute on function public.ponto_minhas_solicitacoes_ajuste(uuid, uuid, integer)
  to authenticated;
grant execute on function public.ponto_listar_solicitacoes_ajuste_admin(uuid, text, integer)
  to authenticated;
grant execute on function public.ponto_cancelar_solicitacao_ajuste(uuid)
  to authenticated;
grant execute on function public.ponto_decidir_solicitacao_ajuste(uuid, boolean, text)
  to authenticated;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'ponto_solicitacoes_ajuste'
  ) then
    execute 'alter publication supabase_realtime add table public.ponto_solicitacoes_ajuste';
  end if;
end;
$$;
