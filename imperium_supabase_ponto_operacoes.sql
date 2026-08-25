-- IMPERIUM MANAGER
-- PONTO HÍBRIDO COMPLETO - Operações seguras na nuvem
--
-- Pré-requisitos já aplicados:
--   empresas / empresa_usuarios / RLS
--   ponto_colaboradores / ponto_jornada / ponto_config
--   ponto_registros / ponto_ajustes / ponto_fechamentos
--   ponto_fechamento_historico
--
-- Escritas continuam bloqueadas diretamente nas tabelas.
-- O app grava por RPCs SECURITY DEFINER com validação explícita de empresa/papel.

begin;

-- ============================================================
-- VÍNCULO ENTRE FUNCIONÁRIO E USUÁRIO SUPABASE
-- ============================================================

create or replace function public.ponto_vincular_usuario_colaborador(
  p_empresa_id uuid,
  p_colaborador_id uuid,
  p_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_email text;
  v_colaborador_nome text;
begin
  if (select auth.uid()) is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not private.usuario_admin_empresa(p_empresa_id) then
    raise exception 'Somente proprietário ou administrador pode vincular funcionários.';
  end if;

  v_email := lower(trim(coalesce(p_email, '')));

  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'Informe um e-mail válido.';
  end if;

  select u.id
    into v_user_id
  from auth.users u
  where lower(u.email) = v_email
    and u.email_confirmed_at is not null
  order by u.created_at
  limit 1;

  if v_user_id is null then
    raise exception
      'Usuário confirmado não encontrado no Supabase Auth. Envie/aceite o convite primeiro.';
  end if;

  select pc.nome
    into v_colaborador_nome
  from public.ponto_colaboradores pc
  where pc.id = p_colaborador_id
    and pc.empresa_id = p_empresa_id
  for update;

  if v_colaborador_nome is null then
    raise exception 'Funcionário remoto não encontrado.';
  end if;

  -- Garante que o usuário não esteja ligado a outro colaborador da mesma empresa.
  if exists (
    select 1
    from public.ponto_colaboradores pc
    where pc.empresa_id = p_empresa_id
      and pc.auth_user_id = v_user_id
      and pc.id <> p_colaborador_id
  ) then
    raise exception 'Este usuário já está vinculado a outro funcionário.';
  end if;

  update public.ponto_colaboradores
  set
    auth_user_id = v_user_id,
    atualizado_em = now()
  where id = p_colaborador_id
    and empresa_id = p_empresa_id;

  insert into public.empresa_usuarios (
    empresa_id,
    user_id,
    papel,
    ativo,
    atualizado_em
  )
  values (
    p_empresa_id,
    v_user_id,
    'funcionario',
    true,
    now()
  )
  on conflict (empresa_id, user_id)
  do update set
    papel = case
      when public.empresa_usuarios.papel in ('proprietario', 'admin')
        then public.empresa_usuarios.papel
      else 'funcionario'
    end,
    ativo = true,
    atualizado_em = now();

  return jsonb_build_object(
    'colaborador_id', p_colaborador_id,
    'colaborador_nome', v_colaborador_nome,
    'user_id', v_user_id,
    'email', v_email
  );
end;
$$;

revoke all on function public.ponto_vincular_usuario_colaborador(
  uuid, uuid, text
) from public, anon;

grant execute on function public.ponto_vincular_usuario_colaborador(
  uuid, uuid, text
) to authenticated;

-- ============================================================
-- BATIDA DE PONTO
-- Horário oficial vem do PostgreSQL/Supabase.
-- Advisory lock impede duas batidas simultâneas do mesmo funcionário/dia.
-- ============================================================

create or replace function public.ponto_registrar_batida(
  p_empresa_id uuid,
  p_colaborador_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_user uuid := (select auth.uid());
  v_timezone text := 'America/Sao_Paulo';
  v_agora timestamptz := now();
  v_local timestamp;
  v_data date;
  v_hora time(0);

  v_admin boolean := false;
  v_colaborador public.ponto_colaboradores%rowtype;
  v_jornada public.ponto_jornada%rowtype;
  v_registro public.ponto_registros%rowtype;

  v_tem_intervalo boolean := false;
  v_acao text;
  v_competencia date;
begin
  if v_auth_user is null then
    raise exception 'Usuário não autenticado.';
  end if;

  select *
    into v_colaborador
  from public.ponto_colaboradores
  where id = p_colaborador_id
    and empresa_id = p_empresa_id
  limit 1;

  if not found then
    raise exception 'Funcionário não encontrado na nuvem.';
  end if;

  if not v_colaborador.ativo then
    raise exception 'O funcionário está inativo.';
  end if;

  v_admin := private.usuario_admin_empresa(p_empresa_id);

  if not v_admin and v_colaborador.auth_user_id is distinct from v_auth_user then
    raise exception 'Você só pode registrar o próprio ponto.';
  end if;

  select coalesce(pc.timezone, 'America/Sao_Paulo')
    into v_timezone
  from public.ponto_config pc
  where pc.empresa_id = p_empresa_id;

  v_timezone := coalesce(v_timezone, 'America/Sao_Paulo');
  v_local := v_agora at time zone v_timezone;
  v_data := v_local::date;
  v_hora := date_trunc('minute', v_local)::time;
  v_competencia := date_trunc('month', v_data)::date;

  if exists (
    select 1
    from public.ponto_fechamentos pf
    where pf.empresa_id = p_empresa_id
      and pf.colaborador_id = p_colaborador_id
      and pf.competencia = v_competencia
      and pf.status = 'Fechado'
  ) then
    raise exception 'O ponto desta competência está fechado.';
  end if;

  select *
    into v_jornada
  from public.ponto_jornada
  where empresa_id = p_empresa_id
    and dia_semana = extract(isodow from v_data)::int
  limit 1;

  if not found or not v_jornada.ativo then
    raise exception 'Hoje não existe jornada ativa para este funcionário.';
  end if;

  v_tem_intervalo :=
    v_jornada.intervalo_inicio is not null
    and v_jornada.intervalo_fim is not null;

  -- Serializa operações para o mesmo funcionário/dia.
  perform pg_advisory_xact_lock(
    hashtext(p_colaborador_id::text),
    (v_data - date '2000-01-01')::int
  );

  select *
    into v_registro
  from public.ponto_registros
  where empresa_id = p_empresa_id
    and colaborador_id = p_colaborador_id
    and data = v_data
  for update;

  -- Proteção multiaparelho V5:
  -- duas batidas online no mesmo minuto representam a mesma ação.
  if found then
    if v_registro.saida is not null
       and v_registro.saida = v_hora then
      v_acao := 'Saída';
    elsif v_registro.intervalo_fim is not null
       and v_registro.intervalo_fim = v_hora then
      v_acao := 'Fim do intervalo';
    elsif v_registro.intervalo_inicio is not null
       and v_registro.intervalo_inicio = v_hora then
      v_acao := 'Início do intervalo';
    elsif v_registro.entrada is not null
       and v_registro.entrada = v_hora then
      v_acao := 'Entrada';
    end if;

    if v_acao is not null then
      return jsonb_build_object(
        'acao', v_acao,
        'hora', to_char(v_hora, 'HH24:MI'),
        'data', v_data,
        'registro', to_jsonb(v_registro),
        'repetida', true
      );
    end if;
  end if;


  if not found then
    insert into public.ponto_registros (
      empresa_id,
      colaborador_id,
      data,
      situacao,
      entrada,
      origem,
      criado_em,
      atualizado_em
    )
    values (
      p_empresa_id,
      p_colaborador_id,
      v_data,
      'Trabalhado',
      v_hora,
      'batida_nuvem',
      v_agora,
      v_agora
    )
    returning * into v_registro;

    v_acao := 'Entrada';
  else
    if v_registro.situacao <> 'Trabalhado' then
      raise exception 'O dia está marcado como %.', v_registro.situacao;
    end if;

    if v_registro.saida is not null then
      raise exception 'O ponto de hoje já foi concluído.';
    end if;

    if v_registro.entrada is null then
      update public.ponto_registros
      set
        entrada = v_hora,
        atualizado_em = v_agora
      where id = v_registro.id
      returning * into v_registro;

      v_acao := 'Entrada';

    elsif not v_tem_intervalo then
      update public.ponto_registros
      set
        saida = v_hora,
        atualizado_em = v_agora
      where id = v_registro.id
      returning * into v_registro;

      v_acao := 'Saída';

    elsif v_registro.intervalo_inicio is null then
      update public.ponto_registros
      set
        intervalo_inicio = v_hora,
        atualizado_em = v_agora
      where id = v_registro.id
      returning * into v_registro;

      v_acao := 'Início do intervalo';

    elsif v_registro.intervalo_fim is null then
      update public.ponto_registros
      set
        intervalo_fim = v_hora,
        atualizado_em = v_agora
      where id = v_registro.id
      returning * into v_registro;

      v_acao := 'Fim do intervalo';

    else
      update public.ponto_registros
      set
        saida = v_hora,
        atualizado_em = v_agora
      where id = v_registro.id
      returning * into v_registro;

      v_acao := 'Saída';
    end if;
  end if;

  return jsonb_build_object(
    'acao', v_acao,
    'hora', to_char(v_hora, 'HH24:MI'),
    'data', v_data,
    'registro', to_jsonb(v_registro)
  );
end;
$$;

revoke all on function public.ponto_registrar_batida(
  uuid, uuid
) from public, anon;

grant execute on function public.ponto_registrar_batida(
  uuid, uuid
) to authenticated;

-- ============================================================
-- PONTO OFFLINE IDEMPOTENTE V5
-- Fonte oficial da RPC usada pelo aplicativo quando uma batida
-- é registrada sem conexão e enviada posteriormente.
-- ============================================================

create table if not exists public.ponto_batidas_idempotencia (
  empresa_id uuid not null
    references public.empresas(id) on delete cascade,
  chave text not null,
  colaborador_id uuid not null,
  ocorrido_em timestamptz not null,
  resultado_json jsonb not null,
  criado_em timestamptz not null default now(),
  primary key (empresa_id, chave)
);

alter table public.ponto_batidas_idempotencia enable row level security;

revoke all on public.ponto_batidas_idempotencia
  from public, anon, authenticated;

create index if not exists idx_ponto_batidas_idempotencia_colaborador
  on public.ponto_batidas_idempotencia (
    empresa_id,
    colaborador_id,
    criado_em desc
  );

create or replace function public.ponto_registrar_batida_offline(
  p_empresa_id uuid,
  p_colaborador_id uuid,
  p_ocorrido_em timestamptz,
  p_chave text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_user uuid := (select auth.uid());
  v_timezone text := 'America/Sao_Paulo';
  v_chave text := trim(coalesce(p_chave, ''));
  v_local timestamp;
  v_data date;
  v_hora time(0);
  v_competencia date;

  v_admin boolean := false;
  v_repetida boolean := false;
  v_acao text;
  v_resultado jsonb;

  v_colaborador public.ponto_colaboradores%rowtype;
  v_jornada public.ponto_jornada%rowtype;
  v_registro public.ponto_registros%rowtype;
  v_existente public.ponto_batidas_idempotencia%rowtype;

  v_tem_intervalo boolean := false;
begin
  if v_auth_user is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not private.usuario_tem_acesso_empresa(p_empresa_id) then
    raise exception 'Sem acesso à empresa informada.';
  end if;

  if p_ocorrido_em is null then
    raise exception 'Horário da batida offline não informado.';
  end if;

  if p_ocorrido_em > now() + interval '5 minutes' then
    raise exception 'A batida offline está no futuro.';
  end if;

  if char_length(v_chave) < 12 or char_length(v_chave) > 200 then
    raise exception 'Chave de idempotência inválida.';
  end if;

  -- Serializa tentativas com a mesma chave antes de tocar no ponto.
  perform pg_advisory_xact_lock(
    hashtext(p_empresa_id::text),
    hashtext(v_chave)
  );

  select *
    into v_existente
  from public.ponto_batidas_idempotencia
  where empresa_id = p_empresa_id
    and chave = v_chave
  limit 1;

  if found then
    if v_existente.colaborador_id is distinct from p_colaborador_id
       or v_existente.ocorrido_em is distinct from p_ocorrido_em then
      raise exception
        'A chave de idempotência já foi usada com outro conteúdo.';
    end if;

    return v_existente.resultado_json
      || jsonb_build_object('idempotente_replay', true);
  end if;

  select *
    into v_colaborador
  from public.ponto_colaboradores
  where id = p_colaborador_id
    and empresa_id = p_empresa_id
  limit 1;

  if not found then
    raise exception 'Funcionário não encontrado na nuvem.';
  end if;

  if not v_colaborador.ativo then
    raise exception 'O funcionário está inativo.';
  end if;

  v_admin := private.usuario_admin_empresa(p_empresa_id);

  if not v_admin
     and v_colaborador.auth_user_id is distinct from v_auth_user then
    raise exception 'Você só pode registrar o próprio ponto.';
  end if;

  select coalesce(pc.timezone, 'America/Sao_Paulo')
    into v_timezone
  from public.ponto_config pc
  where pc.empresa_id = p_empresa_id;

  v_timezone := coalesce(v_timezone, 'America/Sao_Paulo');
  v_local := p_ocorrido_em at time zone v_timezone;
  v_data := v_local::date;
  v_hora := date_trunc('minute', v_local)::time;
  v_competencia := date_trunc('month', v_data)::date;

  if exists (
    select 1
    from public.ponto_fechamentos pf
    where pf.empresa_id = p_empresa_id
      and pf.colaborador_id = p_colaborador_id
      and pf.competencia = v_competencia
      and pf.status = 'Fechado'
  ) then
    raise exception 'O ponto desta competência está fechado.';
  end if;

  select *
    into v_jornada
  from public.ponto_jornada
  where empresa_id = p_empresa_id
    and dia_semana = extract(isodow from v_data)::int
  limit 1;

  if not found or not v_jornada.ativo then
    raise exception 'Não existe jornada ativa para a data desta batida.';
  end if;

  v_tem_intervalo :=
    v_jornada.intervalo_inicio is not null
    and v_jornada.intervalo_fim is not null;

  -- Serializa qualquer origem (online/offline) no mesmo funcionário/dia.
  perform pg_advisory_xact_lock(
    hashtext(p_colaborador_id::text),
    (v_data - date '2000-01-01')::int
  );

  select *
    into v_registro
  from public.ponto_registros
  where empresa_id = p_empresa_id
    and colaborador_id = p_colaborador_id
    and data = v_data
  for update;

  -- Dois aparelhos podem ter registrado a mesma ação no mesmo minuto.
  -- Nesse caso a segunda chave é aceita como repetição, sem avançar
  -- Entrada -> Intervalo -> Saída por engano.
  if found then
    if v_registro.saida is not null
       and v_registro.saida = v_hora then
      v_acao := 'Saída';
      v_repetida := true;
    elsif v_registro.intervalo_fim is not null
       and v_registro.intervalo_fim = v_hora then
      v_acao := 'Fim do intervalo';
      v_repetida := true;
    elsif v_registro.intervalo_inicio is not null
       and v_registro.intervalo_inicio = v_hora then
      v_acao := 'Início do intervalo';
      v_repetida := true;
    elsif v_registro.entrada is not null
       and v_registro.entrada = v_hora then
      v_acao := 'Entrada';
      v_repetida := true;
    end if;
  end if;

  if not v_repetida then
    if not found then
      insert into public.ponto_registros (
        empresa_id,
        colaborador_id,
        data,
        situacao,
        entrada,
        origem,
        criado_em,
        atualizado_em
      )
      values (
        p_empresa_id,
        p_colaborador_id,
        v_data,
        'Trabalhado',
        v_hora,
        'batida_offline',
        now(),
        now()
      )
      returning * into v_registro;

      v_acao := 'Entrada';
    else
      if v_registro.situacao <> 'Trabalhado' then
        raise exception 'O dia está marcado como %.', v_registro.situacao;
      end if;

      if v_registro.saida is not null then
        raise exception 'O ponto deste dia já foi concluído.';
      end if;

      if v_registro.entrada is null then
        update public.ponto_registros
        set
          entrada = v_hora,
          atualizado_em = now()
        where id = v_registro.id
        returning * into v_registro;

        v_acao := 'Entrada';

      elsif not v_tem_intervalo then
        update public.ponto_registros
        set
          saida = v_hora,
          atualizado_em = now()
        where id = v_registro.id
        returning * into v_registro;

        v_acao := 'Saída';

      elsif v_registro.intervalo_inicio is null then
        update public.ponto_registros
        set
          intervalo_inicio = v_hora,
          atualizado_em = now()
        where id = v_registro.id
        returning * into v_registro;

        v_acao := 'Início do intervalo';

      elsif v_registro.intervalo_fim is null then
        update public.ponto_registros
        set
          intervalo_fim = v_hora,
          atualizado_em = now()
        where id = v_registro.id
        returning * into v_registro;

        v_acao := 'Fim do intervalo';

      else
        update public.ponto_registros
        set
          saida = v_hora,
          atualizado_em = now()
        where id = v_registro.id
        returning * into v_registro;

        v_acao := 'Saída';
      end if;
    end if;
  end if;

  v_resultado := jsonb_build_object(
    'acao', v_acao,
    'hora', to_char(v_hora, 'HH24:MI'),
    'data', v_data,
    'registro', to_jsonb(v_registro),
    'offline', true,
    'repetida', v_repetida
  );

  insert into public.ponto_batidas_idempotencia (
    empresa_id,
    chave,
    colaborador_id,
    ocorrido_em,
    resultado_json
  )
  values (
    p_empresa_id,
    v_chave,
    p_colaborador_id,
    p_ocorrido_em,
    v_resultado
  );

  return v_resultado;
end;
$$;

revoke all on function public.ponto_registrar_batida_offline(
  uuid, uuid, timestamptz, text
) from public, anon;

grant execute on function public.ponto_registrar_batida_offline(
  uuid, uuid, timestamptz, text
) to authenticated;

-- ============================================================
-- LANÇAMENTO / EDIÇÃO ADMINISTRATIVA
-- ============================================================

create or replace function public.ponto_salvar_registro_admin(
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
  v_anterior public.ponto_registros%rowtype;
  v_depois public.ponto_registros%rowtype;
  v_acao text;
  v_motivo text := trim(coalesce(p_motivo, ''));
  v_competencia date := date_trunc('month', p_data)::date;
begin
  if (select auth.uid()) is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not private.usuario_admin_empresa(p_empresa_id) then
    raise exception 'Somente proprietário ou administrador pode corrigir o ponto.';
  end if;

  if p_situacao not in ('Trabalhado', 'Falta', 'Atestado', 'Folga') then
    raise exception 'Situação do ponto inválida.';
  end if;

  if not exists (
    select 1
    from public.ponto_colaboradores pc
    where pc.id = p_colaborador_id
      and pc.empresa_id = p_empresa_id
  ) then
    raise exception 'Funcionário não encontrado.';
  end if;

  if exists (
    select 1
    from public.ponto_fechamentos pf
    where pf.empresa_id = p_empresa_id
      and pf.colaborador_id = p_colaborador_id
      and pf.competencia = v_competencia
      and pf.status = 'Fechado'
  ) then
    raise exception 'A competência está fechada. Reabra o mês antes de alterar.';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(p_colaborador_id::text),
    (p_data - date '2000-01-01')::int
  );

  select *
    into v_anterior
  from public.ponto_registros
  where empresa_id = p_empresa_id
    and colaborador_id = p_colaborador_id
    and data = p_data
  for update;

  if found then
    if char_length(v_motivo) < 5 then
      raise exception 'Informe o motivo da alteração com pelo menos 5 caracteres.';
    end if;
    v_acao := 'Edicao';
  else
    v_acao := 'Criacao';
    if v_motivo = '' then
      v_motivo := 'Lançamento manual pelo administrador';
    end if;
  end if;

  if p_situacao = 'Trabalhado' then
    if p_entrada is null or p_saida is null then
      raise exception 'Informe entrada e saída para um dia trabalhado.';
    end if;

    if p_saida <= p_entrada then
      raise exception 'A saída deve ser posterior à entrada.';
    end if;

    if (p_intervalo_inicio is null) <> (p_intervalo_fim is null) then
      raise exception 'Informe início e fim do intervalo juntos.';
    end if;

    if p_intervalo_inicio is not null then
      if not (
        p_entrada < p_intervalo_inicio
        and p_intervalo_inicio < p_intervalo_fim
        and p_intervalo_fim < p_saida
      ) then
        raise exception 'Os horários do intervalo são inválidos.';
      end if;
    end if;
  end if;

  insert into public.ponto_registros (
    empresa_id,
    colaborador_id,
    data,
    situacao,
    entrada,
    intervalo_inicio,
    intervalo_fim,
    saida,
    observacoes,
    origem,
    atualizado_em
  )
  values (
    p_empresa_id,
    p_colaborador_id,
    p_data,
    p_situacao,
    case when p_situacao = 'Trabalhado' then p_entrada else null end,
    case when p_situacao = 'Trabalhado' then p_intervalo_inicio else null end,
    case when p_situacao = 'Trabalhado' then p_intervalo_fim else null end,
    case when p_situacao = 'Trabalhado' then p_saida else null end,
    trim(coalesce(p_observacoes, '')),
    'ajuste_admin_nuvem',
    now()
  )
  on conflict (empresa_id, colaborador_id, data)
  do update set
    situacao = excluded.situacao,
    entrada = excluded.entrada,
    intervalo_inicio = excluded.intervalo_inicio,
    intervalo_fim = excluded.intervalo_fim,
    saida = excluded.saida,
    observacoes = excluded.observacoes,
    origem = excluded.origem,
    atualizado_em = now()
  returning * into v_depois;

  insert into public.ponto_ajustes (
    empresa_id,
    colaborador_id,
    registro_id,
    data,
    acao,
    motivo,
    antes_json,
    depois_json,
    executado_por
  )
  values (
    p_empresa_id,
    p_colaborador_id,
    v_depois.id,
    p_data,
    v_acao,
    v_motivo,
    case
      when v_anterior.id is null then null
      else to_jsonb(v_anterior)
    end,
    to_jsonb(v_depois),
    (select auth.uid())
  );

  return to_jsonb(v_depois);
end;
$$;

revoke all on function public.ponto_salvar_registro_admin(
  uuid, uuid, date, text, time, time, time, time, text, text
) from public, anon;

grant execute on function public.ponto_salvar_registro_admin(
  uuid, uuid, date, text, time, time, time, time, text, text
) to authenticated;

-- ============================================================
-- EXCLUSÃO ADMINISTRATIVA
-- ============================================================

create or replace function public.ponto_remover_registro_admin(
  p_empresa_id uuid,
  p_registro_id uuid,
  p_motivo text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anterior public.ponto_registros%rowtype;
  v_motivo text := trim(coalesce(p_motivo, ''));
  v_competencia date;
begin
  if (select auth.uid()) is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not private.usuario_admin_empresa(p_empresa_id) then
    raise exception 'Somente proprietário ou administrador pode excluir registros.';
  end if;

  if char_length(v_motivo) < 5 then
    raise exception 'Informe o motivo da exclusão com pelo menos 5 caracteres.';
  end if;

  select *
    into v_anterior
  from public.ponto_registros
  where id = p_registro_id
    and empresa_id = p_empresa_id
  for update;

  if not found then
    raise exception 'Registro de ponto não encontrado.';
  end if;

  v_competencia := date_trunc('month', v_anterior.data)::date;

  if exists (
    select 1
    from public.ponto_fechamentos pf
    where pf.empresa_id = p_empresa_id
      and pf.colaborador_id = v_anterior.colaborador_id
      and pf.competencia = v_competencia
      and pf.status = 'Fechado'
  ) then
    raise exception 'A competência está fechada. Reabra o mês antes de excluir.';
  end if;

  delete from public.ponto_registros
  where id = p_registro_id
    and empresa_id = p_empresa_id;

  insert into public.ponto_ajustes (
    empresa_id,
    colaborador_id,
    registro_id,
    data,
    acao,
    motivo,
    antes_json,
    depois_json,
    executado_por
  )
  values (
    p_empresa_id,
    v_anterior.colaborador_id,
    null,
    v_anterior.data,
    'Exclusao',
    v_motivo,
    to_jsonb(v_anterior),
    null,
    (select auth.uid())
  );

  return true;
end;
$$;

revoke all on function public.ponto_remover_registro_admin(
  uuid, uuid, text
) from public, anon;

grant execute on function public.ponto_remover_registro_admin(
  uuid, uuid, text
) to authenticated;

-- ============================================================
-- JORNADA / CONFIG
-- ============================================================

create or replace function public.ponto_salvar_jornada_admin(
  p_empresa_id uuid,
  p_dia_semana smallint,
  p_ativo boolean,
  p_entrada time default null,
  p_intervalo_inicio time default null,
  p_intervalo_fim time default null,
  p_saida time default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_linha public.ponto_jornada%rowtype;
begin
  if (select auth.uid()) is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not private.usuario_admin_empresa(p_empresa_id) then
    raise exception 'Somente proprietário ou administrador pode alterar a jornada.';
  end if;

  if p_dia_semana < 1 or p_dia_semana > 7 then
    raise exception 'Dia da semana inválido.';
  end if;

  if p_ativo then
    if p_entrada is null or p_saida is null then
      raise exception 'Informe entrada e saída da jornada.';
    end if;

    if p_saida <= p_entrada then
      raise exception 'A saída deve ser posterior à entrada.';
    end if;

    if (p_intervalo_inicio is null) <> (p_intervalo_fim is null) then
      raise exception 'Informe início e fim do intervalo juntos.';
    end if;

    if p_intervalo_inicio is not null and not (
      p_entrada < p_intervalo_inicio
      and p_intervalo_inicio < p_intervalo_fim
      and p_intervalo_fim < p_saida
    ) then
      raise exception 'Intervalo inválido.';
    end if;
  end if;

  insert into public.ponto_jornada (
    empresa_id,
    dia_semana,
    ativo,
    entrada,
    intervalo_inicio,
    intervalo_fim,
    saida,
    atualizado_em
  )
  values (
    p_empresa_id,
    p_dia_semana,
    p_ativo,
    case when p_ativo then p_entrada else null end,
    case when p_ativo then p_intervalo_inicio else null end,
    case when p_ativo then p_intervalo_fim else null end,
    case when p_ativo then p_saida else null end,
    now()
  )
  on conflict (empresa_id, dia_semana)
  do update set
    ativo = excluded.ativo,
    entrada = excluded.entrada,
    intervalo_inicio = excluded.intervalo_inicio,
    intervalo_fim = excluded.intervalo_fim,
    saida = excluded.saida,
    atualizado_em = now()
  returning * into v_linha;

  return to_jsonb(v_linha);
end;
$$;

revoke all on function public.ponto_salvar_jornada_admin(
  uuid, smallint, boolean, time, time, time, time
) from public, anon;

grant execute on function public.ponto_salvar_jornada_admin(
  uuid, smallint, boolean, time, time, time, time
) to authenticated;

create or replace function public.ponto_salvar_config_admin(
  p_empresa_id uuid,
  p_adicional_hora_extra numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_linha public.ponto_config%rowtype;
begin
  if (select auth.uid()) is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not private.usuario_admin_empresa(p_empresa_id) then
    raise exception 'Somente proprietário ou administrador pode alterar a configuração.';
  end if;

  if p_adicional_hora_extra < 0 or p_adicional_hora_extra > 500 then
    raise exception 'O adicional de hora extra deve ficar entre 0%% e 500%%.';
  end if;

  insert into public.ponto_config (
    empresa_id,
    adicional_hora_extra,
    timezone,
    atualizado_em
  )
  values (
    p_empresa_id,
    p_adicional_hora_extra,
    'America/Sao_Paulo',
    now()
  )
  on conflict (empresa_id)
  do update set
    adicional_hora_extra = excluded.adicional_hora_extra,
    atualizado_em = now()
  returning * into v_linha;

  return to_jsonb(v_linha);
end;
$$;

revoke all on function public.ponto_salvar_config_admin(
  uuid, numeric
) from public, anon;

grant execute on function public.ponto_salvar_config_admin(
  uuid, numeric
) to authenticated;

-- ============================================================
-- FECHAMENTO / REABERTURA
-- A validação detalhada de pendências continua no app.
-- A nuvem garante papel, competência e auditoria central.
-- ============================================================

create or replace function public.ponto_fechar_competencia_admin(
  p_empresa_id uuid,
  p_colaborador_id uuid,
  p_competencia date,
  p_snapshot jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_competencia date := date_trunc('month', p_competencia)::date;
  v_linha public.ponto_fechamentos%rowtype;
begin
  if (select auth.uid()) is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not private.usuario_admin_empresa(p_empresa_id) then
    raise exception 'Somente proprietário ou administrador pode fechar competências.';
  end if;

  if not exists (
    select 1
    from public.ponto_colaboradores pc
    where pc.id = p_colaborador_id
      and pc.empresa_id = p_empresa_id
  ) then
    raise exception 'Funcionário não encontrado.';
  end if;

  if current_date <= (v_competencia + interval '1 month - 1 day')::date then
    raise exception 'O mês só pode ser fechado depois que a competência terminar.';
  end if;

  insert into public.ponto_fechamentos (
    empresa_id,
    colaborador_id,
    competencia,
    status,
    snapshot_json,
    fechado_em,
    reaberto_em,
    motivo_reabertura,
    atualizado_em
  )
  values (
    p_empresa_id,
    p_colaborador_id,
    v_competencia,
    'Fechado',
    p_snapshot,
    now(),
    null,
    '',
    now()
  )
  on conflict (empresa_id, colaborador_id, competencia)
  do update set
    status = 'Fechado',
    snapshot_json = excluded.snapshot_json,
    fechado_em = now(),
    reaberto_em = null,
    motivo_reabertura = '',
    atualizado_em = now()
  returning * into v_linha;

  insert into public.ponto_fechamento_historico (
    empresa_id,
    colaborador_id,
    competencia,
    acao,
    motivo,
    snapshot_json,
    executado_por
  )
  values (
    p_empresa_id,
    p_colaborador_id,
    v_competencia,
    'Fechamento',
    'Competência aprovada pelo administrador',
    p_snapshot,
    (select auth.uid())
  );

  return to_jsonb(v_linha);
end;
$$;

revoke all on function public.ponto_fechar_competencia_admin(
  uuid, uuid, date, jsonb
) from public, anon;

grant execute on function public.ponto_fechar_competencia_admin(
  uuid, uuid, date, jsonb
) to authenticated;

create or replace function public.ponto_reabrir_competencia_admin(
  p_empresa_id uuid,
  p_colaborador_id uuid,
  p_competencia date,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_competencia date := date_trunc('month', p_competencia)::date;
  v_motivo text := trim(coalesce(p_motivo, ''));
  v_anterior public.ponto_fechamentos%rowtype;
  v_linha public.ponto_fechamentos%rowtype;
begin
  if (select auth.uid()) is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not private.usuario_admin_empresa(p_empresa_id) then
    raise exception 'Somente proprietário ou administrador pode reabrir competências.';
  end if;

  if char_length(v_motivo) < 5 then
    raise exception 'Informe o motivo da reabertura com pelo menos 5 caracteres.';
  end if;

  select *
    into v_anterior
  from public.ponto_fechamentos
  where empresa_id = p_empresa_id
    and colaborador_id = p_colaborador_id
    and competencia = v_competencia
    and status = 'Fechado'
  for update;

  if not found then
    raise exception 'Esta competência não está fechada.';
  end if;

  update public.ponto_fechamentos
  set
    status = 'Aberto',
    reaberto_em = now(),
    motivo_reabertura = v_motivo,
    atualizado_em = now()
  where id = v_anterior.id
  returning * into v_linha;

  insert into public.ponto_fechamento_historico (
    empresa_id,
    colaborador_id,
    competencia,
    acao,
    motivo,
    snapshot_json,
    executado_por
  )
  values (
    p_empresa_id,
    p_colaborador_id,
    v_competencia,
    'Reabertura',
    v_motivo,
    v_anterior.snapshot_json,
    (select auth.uid())
  );

  return to_jsonb(v_linha);
end;
$$;

revoke all on function public.ponto_reabrir_competencia_admin(
  uuid, uuid, date, text
) from public, anon;

grant execute on function public.ponto_reabrir_competencia_admin(
  uuid, uuid, date, text
) to authenticated;

-- ============================================================
-- ESTADO DA MIGRAÇÃO
-- Impede que qualquer aparelho trate a nuvem como fonte principal
-- antes da importação inicial do histórico estar concluída.
-- ============================================================

create table if not exists public.ponto_sync_estado (
  empresa_id uuid primary key
    references public.empresas(id) on delete cascade,
  migracao_concluida boolean not null default false,
  migracao_concluida_em timestamptz,
  migracao_concluida_por uuid
    references auth.users(id) on delete set null,
  atualizado_em timestamptz not null default now()
);

alter table public.ponto_sync_estado enable row level security;

revoke all on public.ponto_sync_estado from anon, authenticated;
grant select on public.ponto_sync_estado to authenticated;

drop policy if exists "ponto_sync_estado_select"
  on public.ponto_sync_estado;

create policy "ponto_sync_estado_select"
on public.ponto_sync_estado
for select
to authenticated
using (
  (select private.usuario_tem_acesso_empresa(empresa_id))
);

insert into public.ponto_sync_estado (
  empresa_id,
  migracao_concluida
)
select e.id, false
from public.empresas e
where e.slug = 'imperium-detailing'
on conflict (empresa_id) do nothing;

create or replace function public.ponto_concluir_migracao(
  p_empresa_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not private.usuario_admin_empresa(p_empresa_id) then
    raise exception 'Somente proprietário ou administrador pode concluir a migração.';
  end if;

  insert into public.ponto_sync_estado (
    empresa_id,
    migracao_concluida,
    migracao_concluida_em,
    migracao_concluida_por,
    atualizado_em
  )
  values (
    p_empresa_id,
    true,
    now(),
    (select auth.uid()),
    now()
  )
  on conflict (empresa_id)
  do update set
    migracao_concluida = true,
    migracao_concluida_em = now(),
    migracao_concluida_por = (select auth.uid()),
    atualizado_em = now();

  return true;
end;
$$;

revoke all on function public.ponto_concluir_migracao(uuid)
  from public, anon;
grant execute on function public.ponto_concluir_migracao(uuid)
  to authenticated;

-- Preserva auditoria antiga do SQLite durante a migração inicial.
create or replace function public.ponto_importar_ajuste_historico(
  p_empresa_id uuid,
  p_colaborador_id uuid,
  p_data date,
  p_acao text,
  p_motivo text,
  p_antes_json jsonb default null,
  p_depois_json jsonb default null,
  p_criado_em timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not private.usuario_admin_empresa(p_empresa_id) then
    raise exception 'Sem permissão para importar histórico.';
  end if;

  insert into public.ponto_ajustes (
    empresa_id,
    colaborador_id,
    registro_id,
    data,
    acao,
    motivo,
    antes_json,
    depois_json,
    executado_por,
    criado_em
  )
  values (
    p_empresa_id,
    p_colaborador_id,
    null,
    p_data,
    trim(coalesce(p_acao, 'Importacao')),
    trim(coalesce(p_motivo, 'Migração do SQLite')),
    p_antes_json,
    p_depois_json,
    (select auth.uid()),
    coalesce(p_criado_em, now())
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.ponto_importar_ajuste_historico(
  uuid, uuid, date, text, text, jsonb, jsonb, timestamptz
) from public, anon;

grant execute on function public.ponto_importar_ajuste_historico(
  uuid, uuid, date, text, text, jsonb, jsonb, timestamptz
) to authenticated;


-- ============================================================
-- DIAGNÓSTICO DE SAÚDE DO PONTO V6
-- Somente leitura. Permite ao aplicativo confirmar que o tenant
-- e os recursos críticos do backend estão realmente disponíveis.
-- ============================================================

create or replace function public.ponto_diagnostico(
  p_empresa_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_user uuid := (select auth.uid());
  v_migracao boolean := false;
  v_rpc_online boolean := false;
  v_rpc_offline boolean := false;
  v_idempotencia boolean := false;
  v_sync_estado boolean := false;
  v_realtime boolean := false;
begin
  if v_auth_user is null then
    raise exception 'Usuário não autenticado.';
  end if;

  if not private.usuario_tem_acesso_empresa(p_empresa_id) then
    raise exception 'Sem acesso à empresa informada.';
  end if;

  select exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'ponto_registrar_batida'
  )
  into v_rpc_online;

  select exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'ponto_registrar_batida_offline'
  )
  into v_rpc_offline;

  v_idempotencia :=
    to_regclass('public.ponto_batidas_idempotencia') is not null;

  v_sync_estado :=
    to_regclass('public.ponto_sync_estado') is not null;

  if v_sync_estado then
    select coalesce(pse.migracao_concluida, false)
      into v_migracao
    from public.ponto_sync_estado pse
    where pse.empresa_id = p_empresa_id
    limit 1;

    v_migracao := coalesce(v_migracao, false);
  end if;

  select exists (
    select 1
    from pg_catalog.pg_publication_tables ppt
    where ppt.pubname = 'supabase_realtime'
      and ppt.schemaname = 'public'
      and ppt.tablename = 'ponto_registros'
  )
  into v_realtime;

  return jsonb_build_object(
    'backend_version', 6,
    'empresa_id', p_empresa_id,
    'usuario_id', v_auth_user,
    'rpc_batida_online', v_rpc_online,
    'rpc_batida_offline', v_rpc_offline,
    'tabela_idempotencia', v_idempotencia,
    'sync_estado_disponivel', v_sync_estado,
    'migracao_concluida', v_migracao,
    'realtime_ponto_registros', v_realtime,
    'verificado_em', now()
  );
end;
$$;

revoke all on function public.ponto_diagnostico(uuid)
  from public, anon;

grant execute on function public.ponto_diagnostico(uuid)
  to authenticated;

-- ============================================================
-- REALTIME
-- ============================================================

alter table public.ponto_registros replica identity full;
alter table public.ponto_colaboradores replica identity full;
alter table public.ponto_fechamentos replica identity full;

do $$
begin
  if exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'ponto_registros'
    ) then
      execute 'alter publication supabase_realtime add table public.ponto_registros';
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'ponto_colaboradores'
    ) then
      execute 'alter publication supabase_realtime add table public.ponto_colaboradores';
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'ponto_fechamentos'
    ) then
      execute 'alter publication supabase_realtime add table public.ponto_fechamentos';
    end if;
  end if;
end
$$;

commit;

-- VERIFICAÇÃO
select
  p.proname as funcao
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'ponto_vincular_usuario_colaborador',
    'ponto_registrar_batida',
    'ponto_registrar_batida_offline',
    'ponto_salvar_registro_admin',
    'ponto_remover_registro_admin',
    'ponto_salvar_jornada_admin',
    'ponto_salvar_config_admin',
    'ponto_fechar_competencia_admin',
    'ponto_reabrir_competencia_admin',
    'ponto_concluir_migracao',
    'ponto_importar_ajuste_historico',
    'ponto_diagnostico'
  )
order by p.proname;
