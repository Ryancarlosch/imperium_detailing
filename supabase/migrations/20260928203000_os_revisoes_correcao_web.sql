create table if not exists public.imperium_ordem_servico_revisoes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  ordem_servico_id uuid not null,
  origem_dispositivo text,
  origem_local_id bigint,
  numero_revisao bigint not null check (numero_revisao > 0),
  tipo text not null,
  motivo text not null,
  dados_anteriores jsonb not null default '{}'::jsonb,
  dados_novos jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  constraint imperium_os_revisoes_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico(empresa_id, id)
    on delete cascade,
  constraint imperium_os_revisoes_numero_key
    unique (empresa_id, ordem_servico_id, numero_revisao),
  constraint imperium_os_revisoes_origem_key
    unique (empresa_id, origem_dispositivo, origem_local_id)
);

create index if not exists idx_imperium_os_revisoes_empresa_os
  on public.imperium_ordem_servico_revisoes(
    empresa_id,
    ordem_servico_id,
    numero_revisao
  );

alter table public.imperium_ordem_servico_revisoes enable row level security;

revoke all on public.imperium_ordem_servico_revisoes from anon, authenticated;
grant select, insert on public.imperium_ordem_servico_revisoes to authenticated;

drop policy if exists imperium_os_revisoes_select
  on public.imperium_ordem_servico_revisoes;
create policy imperium_os_revisoes_select
on public.imperium_ordem_servico_revisoes
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'ordens_servico')));

drop policy if exists imperium_os_revisoes_insert
  on public.imperium_ordem_servico_revisoes;
create policy imperium_os_revisoes_insert
on public.imperium_ordem_servico_revisoes
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'ordens_servico')));

-- A correção administrativa só pode ajustar a data da baixa existente.
grant update (data) on public.imperium_estoque_movimentacoes to authenticated;

drop policy if exists imperium_estoque_mov_update_data_os
  on public.imperium_estoque_movimentacoes;
create policy imperium_estoque_mov_update_data_os
on public.imperium_estoque_movimentacoes
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'estoque')))
with check ((select private.imperium_pode_modulo(empresa_id, 'estoque')));

create or replace function public.imperium_os_corrigir_finalizada_web(
  p_empresa_id uuid,
  p_ordem_servico_id uuid,
  p_atualizado_em_base timestamptz,
  p_motivo text,
  p_funcionario_responsavel text,
  p_observacoes text,
  p_quilometragem_entrada text,
  p_combustivel_entrada text,
  p_data_inicio text,
  p_data_finalizacao text,
  p_hora_entrada text,
  p_hora_saida text,
  p_origem_dispositivo text,
  p_origem_local_id bigint
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_os public.imperium_ordens_servico%rowtype;
  v_motivo text := trim(coalesce(p_motivo, ''));
  v_data_inicio text := nullif(trim(coalesce(p_data_inicio, '')), '');
  v_data_finalizacao text :=
    nullif(trim(coalesce(p_data_finalizacao, '')), '');
  v_hora_entrada text := nullif(trim(coalesce(p_hora_entrada, '')), '');
  v_hora_saida text := nullif(trim(coalesce(p_hora_saida, '')), '');
  v_entrada timestamp without time zone;
  v_saida timestamp without time zone;
  v_saida_iso text;
  v_anteriores jsonb;
  v_novos jsonb;
  v_numero bigint;
  v_agora timestamptz := now();
  v_assinatura_desatualizada boolean;
  v_horas numeric := 0;
  v_custo_mensal numeric := 0;
  v_horas_equipe numeric := 0;
  v_custo_hora numeric := 0;
  v_colaborador_id uuid;
  v_mao_id uuid;
  v_origem_mao text;
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;

  if not private.imperium_pode_modulo(p_empresa_id, 'ordens_servico') then
    raise exception 'Sem permissão para corrigir Ordens de Serviço.';
  end if;

  if length(v_motivo) < 5 then
    raise exception 'Informe um motivo de correção com pelo menos 5 caracteres.';
  end if;

  if trim(coalesce(p_origem_dispositivo, '')) = ''
     or coalesce(p_origem_local_id, 0) <= 0 then
    raise exception 'Origem da revisão inválida.';
  end if;

  select *
    into v_os
  from public.imperium_ordens_servico
  where empresa_id = p_empresa_id
    and id = p_ordem_servico_id
    and excluido_em is null
  for update;

  if not found then
    raise exception 'Ordem de Serviço não encontrada.';
  end if;

  if v_os.status <> 'Finalizada' then
    raise exception 'Somente Ordens de Serviço finalizadas podem ser corrigidas por este fluxo.';
  end if;

  if p_atualizado_em_base is not null
     and v_os.atualizado_em <> p_atualizado_em_base then
    raise exception 'A Ordem de Serviço foi alterada em outro dispositivo. Atualize e tente novamente.';
  end if;

  begin
    if v_data_inicio is not null then
      v_entrada :=
        left(v_data_inicio, 10)::date +
        coalesce(v_hora_entrada::time, time '00:00');
    end if;

    if v_data_finalizacao is not null then
      v_saida :=
        left(v_data_finalizacao, 10)::date +
        coalesce(v_hora_saida::time, time '00:00');
    end if;
  exception when others then
    raise exception 'Data ou horário inválido na correção da OS.';
  end;

  if v_entrada is not null
     and v_saida is not null
     and v_saida < v_entrada then
    raise exception 'A saída não pode ser anterior à entrada.';
  end if;

  v_anteriores := jsonb_build_object(
    'funcionario_responsavel', trim(coalesce(v_os.funcionario_responsavel, '')),
    'observacoes', trim(coalesce(v_os.observacoes, '')),
    'quilometragem_entrada', trim(coalesce(v_os.quilometragem_entrada, '')),
    'combustivel_entrada', trim(coalesce(v_os.combustivel_entrada, '')),
    'data_inicio', v_os.data_inicio,
    'data_finalizacao', v_os.data_finalizacao,
    'hora_entrada', v_os.hora_entrada,
    'hora_saida', v_os.hora_saida
  );

  v_novos := jsonb_build_object(
    'funcionario_responsavel',
      trim(coalesce(p_funcionario_responsavel, '')),
    'observacoes', trim(coalesce(p_observacoes, '')),
    'quilometragem_entrada', trim(coalesce(p_quilometragem_entrada, '')),
    'combustivel_entrada', trim(coalesce(p_combustivel_entrada, '')),
    'data_inicio', v_data_inicio,
    'data_finalizacao', v_data_finalizacao,
    'hora_entrada', v_hora_entrada,
    'hora_saida', v_hora_saida
  );

  if v_anteriores = v_novos then
    raise exception 'Nenhuma alteração foi identificada na Ordem de Serviço.';
  end if;

  v_numero := coalesce(v_os.quantidade_revisoes, 0) + 1;
  v_assinatura_desatualizada :=
    coalesce(v_os.assinatura_desatualizada, false)
    or nullif(trim(coalesce(v_os.assinatura_storage_path, '')), '') is not null;

  update public.imperium_ordens_servico
  set funcionario_responsavel =
        trim(coalesce(p_funcionario_responsavel, '')),
      observacoes = trim(coalesce(p_observacoes, '')),
      quilometragem_entrada = trim(coalesce(p_quilometragem_entrada, '')),
      combustivel_entrada = trim(coalesce(p_combustivel_entrada, '')),
      data_inicio = v_data_inicio,
      data_finalizacao = v_data_finalizacao,
      hora_entrada = v_hora_entrada,
      hora_saida = v_hora_saida,
      revisada_em = v_agora::text,
      motivo_ultima_revisao = v_motivo,
      quantidade_revisoes = v_numero,
      assinatura_desatualizada = v_assinatura_desatualizada,
      atualizado_em = v_agora
  where empresa_id = p_empresa_id
    and id = p_ordem_servico_id
  returning * into v_os;

  insert into public.imperium_ordem_servico_revisoes (
    empresa_id,
    ordem_servico_id,
    origem_dispositivo,
    origem_local_id,
    numero_revisao,
    tipo,
    motivo,
    dados_anteriores,
    dados_novos,
    criado_em
  ) values (
    p_empresa_id,
    p_ordem_servico_id,
    trim(p_origem_dispositivo),
    p_origem_local_id,
    v_numero,
    'Correcao administrativa',
    v_motivo,
    v_anteriores,
    v_novos,
    v_agora
  );

  if v_entrada is not null and v_saida is not null then
    v_horas := extract(epoch from (v_saida - v_entrada)) / 3600.0;

    if private.imperium_pode_modulo(p_empresa_id, 'precificacao') then
      select
        coalesce(sum(
          c.remuneracao_mensal +
          c.encargos_mensais +
          c.outros_custos_mensais
        ), 0),
        coalesce(max(c.horas_produtivas_mes), 0)
      into v_custo_mensal, v_horas_equipe
      from public.imperium_precificacao_colaboradores_custo c
      where c.empresa_id = p_empresa_id
        and c.ativo = true
        and c.excluido_em is null;

      select coalesce(cfg.horas_produtivas_mes, 0)
        into v_custo_hora
      from public.imperium_precificacao_config cfg
      where cfg.empresa_id = p_empresa_id
      limit 1;

      if coalesce(v_custo_hora, 0) > 0 then
        v_horas_equipe := v_custo_hora;
      end if;

      v_custo_hora :=
        case
          when coalesce(v_horas_equipe, 0) > 0
          then v_custo_mensal / v_horas_equipe
          else 0
        end;

      select c.id
        into v_colaborador_id
      from public.imperium_precificacao_colaboradores_custo c
      where c.empresa_id = p_empresa_id
        and c.ativo = true
        and c.excluido_em is null
        and lower(trim(c.nome)) =
            lower(trim(coalesce(p_funcionario_responsavel, '')))
      order by c.criado_em
      limit 1;

      select mo.id
        into v_mao_id
      from public.imperium_financeiro_os_mao_obra mo
      where mo.empresa_id = p_empresa_id
        and mo.ordem_servico_id = p_ordem_servico_id
        and mo.ativo = true
        and mo.observacoes = 'AUTO_OS_FINALIZACAO'
      order by mo.criado_em, mo.id
      limit 1;

      v_saida_iso :=
        to_char(v_saida, 'YYYY-MM-DD"T"HH24:MI:SS.MS');

      if v_horas <= 0 then
        update public.imperium_financeiro_os_mao_obra
        set ativo = false,
            cancelado_em = v_agora::text,
            origem_atualizado_em = v_agora::text,
            atualizado_em = v_agora
        where empresa_id = p_empresa_id
          and ordem_servico_id = p_ordem_servico_id
          and ativo = true
          and observacoes = 'AUTO_OS_FINALIZACAO';
      elsif v_mao_id is null then
        v_origem_mao := trim(p_origem_dispositivo) || ':revisao';

        insert into public.imperium_financeiro_os_mao_obra (
          empresa_id,
          ordem_servico_id,
          colaborador_custo_id,
          origem_dispositivo,
          origem_local_id,
          descricao,
          horas,
          custo_hora_snapshot,
          custo_total,
          data,
          observacoes,
          ativo,
          cancelado_em,
          origem_criado_em,
          origem_atualizado_em,
          criado_em,
          atualizado_em
        ) values (
          p_empresa_id,
          p_ordem_servico_id,
          v_colaborador_id,
          v_origem_mao,
          p_origem_local_id,
          case
            when trim(coalesce(p_funcionario_responsavel, '')) = ''
            then 'Responsável não informado'
            else trim(p_funcionario_responsavel)
          end,
          v_horas,
          v_custo_hora,
          v_horas * v_custo_hora,
          v_saida_iso,
          'AUTO_OS_FINALIZACAO',
          true,
          null,
          v_agora::text,
          v_agora::text,
          v_agora,
          v_agora
        );
      else
        update public.imperium_financeiro_os_mao_obra
        set colaborador_custo_id = v_colaborador_id,
            descricao = case
              when trim(coalesce(p_funcionario_responsavel, '')) = ''
              then 'Responsável não informado'
              else trim(p_funcionario_responsavel)
            end,
            horas = v_horas,
            custo_hora_snapshot = v_custo_hora,
            custo_total = v_horas * v_custo_hora,
            data = v_saida_iso,
            origem_atualizado_em = v_agora::text,
            atualizado_em = v_agora
        where empresa_id = p_empresa_id
          and id = v_mao_id;

        update public.imperium_financeiro_os_mao_obra
        set ativo = false,
            cancelado_em = v_agora::text,
            origem_atualizado_em = v_agora::text,
            atualizado_em = v_agora
        where empresa_id = p_empresa_id
          and ordem_servico_id = p_ordem_servico_id
          and ativo = true
          and observacoes = 'AUTO_OS_FINALIZACAO'
          and id <> v_mao_id;
      end if;
    end if;

    if private.imperium_pode_modulo(p_empresa_id, 'estoque') then
      v_saida_iso :=
        to_char(v_saida, 'YYYY-MM-DD"T"HH24:MI:SS.MS');

      update public.imperium_estoque_movimentacoes
      set data = v_saida_iso
      where empresa_id = p_empresa_id
        and ordem_servico_id = p_ordem_servico_id
        and upper(tipo) = 'SAIDA';
    end if;
  end if;

  return jsonb_build_object(
    'ordem', to_jsonb(v_os),
    'numero_revisao', v_numero
  );
end;
$$;

revoke all on function public.imperium_os_corrigir_finalizada_web(
  uuid, uuid, timestamptz, text, text, text, text, text,
  text, text, text, text, text, bigint
) from public, anon;

grant execute on function public.imperium_os_corrigir_finalizada_web(
  uuid, uuid, timestamptz, text, text, text, text, text,
  text, text, text, text, text, bigint
) to authenticated;
