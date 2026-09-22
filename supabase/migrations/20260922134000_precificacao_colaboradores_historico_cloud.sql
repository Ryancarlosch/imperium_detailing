create table if not exists public.imperium_precificacao_colaboradores_historico (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  colaborador_id uuid not null,
  origem_colaborador_local_id bigint,
  tipo text not null,
  remuneracao_anterior numeric(18,2) not null default 0,
  remuneracao_nova numeric(18,2) not null default 0,
  encargos_anteriores numeric(18,2) not null default 0,
  encargos_novos numeric(18,2) not null default 0,
  outros_custos_anteriores numeric(18,2) not null default 0,
  outros_custos_novos numeric(18,2) not null default 0,
  ativo_anterior boolean,
  ativo_novo boolean,
  motivo text not null default '',
  vigencia_em timestamptz not null,
  origem_criado_em text,
  criado_em timestamptz not null default now(),
  constraint imperium_prec_colab_hist_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_prec_colab_hist_empresa_id_id_uq
    unique (empresa_id, id),
  constraint imperium_prec_colab_hist_colaborador_fk
    foreign key (empresa_id, colaborador_id)
    references public.imperium_precificacao_colaboradores_custo(empresa_id, id)
    on delete cascade,
  constraint imperium_prec_colab_hist_tipo_ck check (
    tipo in (
      'Cadastro',
      'Reajuste salarial',
      'Atualização de custos',
      'Ativação',
      'Inativação'
    )
  ),
  constraint imperium_prec_colab_hist_valores_ck check (
    remuneracao_anterior >= 0 and remuneracao_nova >= 0 and
    encargos_anteriores >= 0 and encargos_novos >= 0 and
    outros_custos_anteriores >= 0 and outros_custos_novos >= 0
  )
);

create index if not exists idx_imperium_prec_colab_hist_colab_vigencia
  on public.imperium_precificacao_colaboradores_historico
  (empresa_id, colaborador_id, vigencia_em desc, criado_em desc);

alter table public.imperium_precificacao_colaboradores_historico
  enable row level security;

revoke all on public.imperium_precificacao_colaboradores_historico
  from anon, authenticated;

grant select, insert
  on public.imperium_precificacao_colaboradores_historico
  to authenticated;

drop policy if exists imperium_prec_colab_hist_select
  on public.imperium_precificacao_colaboradores_historico;
create policy imperium_prec_colab_hist_select
  on public.imperium_precificacao_colaboradores_historico
  for select to authenticated
  using ((select private.imperium_eh_admin_empresa(empresa_id)));

drop policy if exists imperium_prec_colab_hist_insert
  on public.imperium_precificacao_colaboradores_historico;
create policy imperium_prec_colab_hist_insert
  on public.imperium_precificacao_colaboradores_historico
  for insert to authenticated
  with check ((select private.imperium_eh_admin_empresa(empresa_id)));

create or replace function public.imperium_precificacao_salvar_colaborador_web(
  p_empresa_id uuid,
  p_colaborador_id uuid,
  p_nome text,
  p_funcao text,
  p_remuneracao_mensal numeric,
  p_encargos_mensais numeric,
  p_outros_custos_mensais numeric,
  p_horas_produtivas_mes numeric,
  p_observacoes text,
  p_ativo boolean,
  p_origem_dispositivo text,
  p_colaborador_local_id bigint,
  p_historico_local_id bigint,
  p_vigencia_em timestamptz,
  p_motivo text,
  p_atualizado_em_base timestamptz
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_atual public.imperium_precificacao_colaboradores_custo%rowtype;
  v_id uuid;
  v_tipo text;
  v_agora timestamptz := now();
  v_vigencia timestamptz := coalesce(p_vigencia_em, now());
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;
  if not private.imperium_eh_admin_empresa(p_empresa_id) then
    raise exception 'Somente administradores podem alterar funcionários.';
  end if;
  if length(trim(coalesce(p_nome, ''))) < 2 then
    raise exception 'Informe o nome do funcionário.';
  end if;
  if coalesce(p_remuneracao_mensal, -1) < 0
     or coalesce(p_encargos_mensais, -1) < 0
     or coalesce(p_outros_custos_mensais, -1) < 0
     or coalesce(p_horas_produtivas_mes, 0) <= 0 then
    raise exception 'Custos e horas do funcionário são inválidos.';
  end if;
  if v_vigencia::date > current_date then
    raise exception 'A vigência futura ainda não é suportada.';
  end if;
  if nullif(trim(coalesce(p_origem_dispositivo, '')), '') is null
     or coalesce(p_historico_local_id, 0) <= 0 then
    raise exception 'Origem do histórico inválida.';
  end if;

  if p_colaborador_id is null then
    if coalesce(p_colaborador_local_id, 0) <= 0 then
      raise exception 'Origem do funcionário inválida.';
    end if;

    insert into public.imperium_precificacao_colaboradores_custo (
      empresa_id, origem_dispositivo, origem_local_id, nome, funcao,
      remuneracao_mensal, encargos_mensais, outros_custos_mensais,
      horas_produtivas_mes, observacoes, ativo, origem_criado_em,
      origem_atualizado_em, excluido_em, criado_em, atualizado_em
    ) values (
      p_empresa_id, trim(p_origem_dispositivo), p_colaborador_local_id,
      trim(p_nome), trim(coalesce(p_funcao,'')), p_remuneracao_mensal,
      p_encargos_mensais, p_outros_custos_mensais, p_horas_produtivas_mes,
      trim(coalesce(p_observacoes,'')), coalesce(p_ativo,true),
      v_agora::text, v_agora::text, null, v_agora, v_agora
    ) returning id into v_id;

    insert into public.imperium_precificacao_colaboradores_historico (
      empresa_id, origem_dispositivo, origem_local_id, colaborador_id,
      origem_colaborador_local_id, tipo, remuneracao_anterior,
      remuneracao_nova, encargos_anteriores, encargos_novos,
      outros_custos_anteriores, outros_custos_novos,
      ativo_anterior, ativo_novo, motivo, vigencia_em, origem_criado_em
    ) values (
      p_empresa_id, trim(p_origem_dispositivo), p_historico_local_id, v_id,
      p_colaborador_local_id, 'Cadastro', 0, p_remuneracao_mensal, 0,
      p_encargos_mensais, 0, p_outros_custos_mensais, null,
      coalesce(p_ativo,true),
      coalesce(nullif(trim(coalesce(p_motivo,'')),''),'Cadastro inicial'),
      v_vigencia, v_agora::text
    );
  else
    select *
      into v_atual
    from public.imperium_precificacao_colaboradores_custo
    where empresa_id = p_empresa_id
      and id = p_colaborador_id
      and excluido_em is null
    for update;

    if not found then
      raise exception 'Funcionário não encontrado ou sem acesso.';
    end if;

    if p_atualizado_em_base is not null
       and v_atual.atualizado_em <> p_atualizado_em_base then
      raise exception 'O funcionário foi alterado em outro dispositivo. Atualize e tente novamente.';
    end if;

    update public.imperium_precificacao_colaboradores_custo
    set nome = trim(p_nome),
        funcao = trim(coalesce(p_funcao,'')),
        remuneracao_mensal = p_remuneracao_mensal,
        encargos_mensais = p_encargos_mensais,
        outros_custos_mensais = p_outros_custos_mensais,
        horas_produtivas_mes = p_horas_produtivas_mes,
        observacoes = trim(coalesce(p_observacoes,'')),
        ativo = coalesce(p_ativo,true),
        origem_atualizado_em = v_agora::text
    where empresa_id = p_empresa_id
      and id = p_colaborador_id
    returning id into v_id;

    if v_atual.ativo is distinct from coalesce(p_ativo,true) then
      v_tipo := case
        when coalesce(p_ativo,true) then 'Ativação'
        else 'Inativação'
      end;
    elsif v_atual.remuneracao_mensal is distinct from p_remuneracao_mensal then
      v_tipo := 'Reajuste salarial';
    elsif v_atual.encargos_mensais is distinct from p_encargos_mensais
       or v_atual.outros_custos_mensais is distinct from p_outros_custos_mensais then
      v_tipo := 'Atualização de custos';
    else
      v_tipo := null;
    end if;

    if v_tipo is not null then
      insert into public.imperium_precificacao_colaboradores_historico (
        empresa_id, origem_dispositivo, origem_local_id, colaborador_id,
        origem_colaborador_local_id, tipo, remuneracao_anterior,
        remuneracao_nova, encargos_anteriores, encargos_novos,
        outros_custos_anteriores, outros_custos_novos,
        ativo_anterior, ativo_novo, motivo, vigencia_em, origem_criado_em
      ) values (
        p_empresa_id, trim(p_origem_dispositivo), p_historico_local_id, v_id,
        v_atual.origem_local_id, v_tipo, v_atual.remuneracao_mensal,
        p_remuneracao_mensal, v_atual.encargos_mensais, p_encargos_mensais,
        v_atual.outros_custos_mensais, p_outros_custos_mensais,
        v_atual.ativo, coalesce(p_ativo,true),
        coalesce(
          nullif(trim(coalesce(p_motivo,'')),''),
          case v_tipo
            when 'Ativação' then 'Funcionário reativado'
            when 'Inativação' then 'Funcionário inativado'
            when 'Reajuste salarial' then 'Reajuste salarial'
            else 'Atualização de custos'
          end
        ),
        v_vigencia, v_agora::text
      );
    end if;
  end if;

  return (
    select to_jsonb(c)
    from public.imperium_precificacao_colaboradores_custo c
    where c.empresa_id = p_empresa_id and c.id = v_id
  );
end;
$$;

revoke all on function public.imperium_precificacao_salvar_colaborador_web(
  uuid, uuid, text, text, numeric, numeric, numeric, numeric, text, boolean,
  text, bigint, bigint, timestamptz, text, timestamptz
) from public, anon;

grant execute on function public.imperium_precificacao_salvar_colaborador_web(
  uuid, uuid, text, text, numeric, numeric, numeric, numeric, text, boolean,
  text, bigint, bigint, timestamptz, text, timestamptz
) to authenticated;
