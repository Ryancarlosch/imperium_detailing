alter table public.imperium_crm_cupons
  add column if not exists geracao_tipo text
  generated always as (
    case
      when split_part(chave_geracao, ':', 1) in ('aniversario', 'reativacao')
        then split_part(chave_geracao, ':', 1)
      else null
    end
  ) stored;

alter table public.imperium_crm_cupons
  add column if not exists geracao_periodo text
  generated always as (
    case
      when split_part(chave_geracao, ':', 1) in ('aniversario', 'reativacao')
        then nullif(split_part(chave_geracao, ':', 4), '')
      else null
    end
  ) stored;

create unique index if not exists imperium_crm_cupons_geracao_negocio_uq
  on public.imperium_crm_cupons(
    empresa_id,
    campanha_id,
    cliente_id,
    geracao_tipo,
    geracao_periodo
  )
  where geracao_tipo is not null
    and geracao_periodo is not null
    and campanha_id is not null
    and cliente_id is not null;

create or replace function public.imperium_crm_gerar_beneficios_web(
  p_empresa_id uuid,
  p_referencia date,
  p_origem_dispositivo text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_ref date := coalesce(p_referencia, current_date);
  v_camp public.imperium_crm_campanhas%rowtype;
  v_cliente record;
  v_inicio date;
  v_fim date;
  v_chave text;
  v_codigo text;
  v_periodo text;
  v_origem_local_id bigint;
  v_aniversario integer := 0;
  v_reativacao integer := 0;
  v_expirados integer := 0;
  v_agora timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;

  if not private.imperium_pode_modulo(p_empresa_id, 'crm') then
    raise exception 'Sem permissão para gerar benefícios do CRM.';
  end if;

  if trim(coalesce(p_origem_dispositivo, '')) = '' then
    raise exception 'Origem Web inválida.';
  end if;

  update public.imperium_crm_cupons
  set status = 'Expirado',
      atualizado_em = v_agora
  where empresa_id = p_empresa_id
    and status = 'Ativo'
    and validade_fim ~ '^\d{4}-\d{2}-\d{2}'
    and left(validade_fim, 10)::date < v_ref;

  get diagnostics v_expirados = row_count;

  for v_camp in
    select *
    from public.imperium_crm_campanhas
    where empresa_id = p_empresa_id
      and ativo = true
      and excluido_em is null
      and tipo in ('Aniversário', 'Reativação')
    order by criado_em, id
  loop
    if v_camp.tipo = 'Aniversário' then
      for v_cliente in
        select c.id, c.data_nascimento
        from public.imperium_clientes c
        where c.empresa_id = p_empresa_id
          and c.ativo = true
          and c.excluido_em is null
          and c.data_nascimento ~ '^\d{4}-\d{2}-\d{2}'
          and substring(c.data_nascimento from 6 for 2)::integer =
              extract(month from v_ref)::integer
      loop
        begin
          v_inicio := make_date(
            extract(year from v_ref)::integer,
            substring(v_cliente.data_nascimento from 6 for 2)::integer,
            case
              when substring(v_cliente.data_nascimento from 6 for 5) = '02-29'
                   and extract(day from (
                     make_date(extract(year from v_ref)::integer, 3, 1)
                     - interval '1 day'
                   ))::integer = 28
                then 28
              else substring(v_cliente.data_nascimento from 9 for 2)::integer
            end
          );
        exception when others then
          continue;
        end;

        v_periodo := extract(year from v_ref)::integer::text;

        if exists (
          select 1
          from public.imperium_crm_cupons cp
          where cp.empresa_id = p_empresa_id
            and cp.campanha_id = v_camp.id
            and cp.cliente_id = v_cliente.id
            and cp.geracao_tipo = 'aniversario'
            and cp.geracao_periodo = v_periodo
        ) then
          continue;
        end if;

        v_chave :=
          'aniversario:' || v_camp.id::text || ':' ||
          v_cliente.id::text || ':' || v_periodo;
        v_codigo := 'NIVER-' || upper(substr(md5(v_chave), 1, 8));
        v_fim := v_inicio + greatest(v_camp.dias_validade, 1)::integer;
        v_origem_local_id := abs(hashtextextended(v_chave, 0));

        insert into public.imperium_crm_cupons (
          empresa_id,
          origem_dispositivo,
          origem_local_id,
          codigo,
          campanha_id,
          cliente_id,
          lead_id,
          beneficio_tipo,
          beneficio_valor,
          beneficio_descricao,
          valor_minimo,
          validade_inicio,
          validade_fim,
          status,
          usado_em,
          ordem_servico_id,
          chave_geracao,
          origem_criado_em,
          excluido_em,
          criado_em,
          atualizado_em
        ) values (
          p_empresa_id,
          trim(p_origem_dispositivo) || ':beneficios',
          v_origem_local_id,
          v_codigo,
          v_camp.id,
          v_cliente.id,
          null,
          v_camp.beneficio_tipo,
          v_camp.beneficio_valor,
          v_camp.beneficio_descricao,
          v_camp.valor_minimo,
          to_char(v_inicio, 'YYYY-MM-DD'),
          to_char(v_fim, 'YYYY-MM-DD'),
          'Ativo',
          null,
          null,
          v_chave,
          v_agora::text,
          null,
          v_agora,
          v_agora
        )
        on conflict do nothing;

        if found then
          v_aniversario := v_aniversario + 1;
        end if;
      end loop;
    elsif v_camp.tipo = 'Reativação' then
      v_periodo :=
        extract(year from v_ref)::integer::text || '-' ||
        lpad(extract(month from v_ref)::integer::text, 2, '0');

      for v_cliente in
        select c.id
        from public.imperium_clientes c
        join lateral (
          select max(
            left(
              coalesce(os.data_finalizacao, os.data_inicio, os.data_abertura),
              10
            )::date
          ) as ultimo_servico
          from public.imperium_ordens_servico os
          where os.empresa_id = p_empresa_id
            and os.cliente_id = c.id
            and lower(trim(os.status)) = 'finalizada'
            and os.excluido_em is null
            and coalesce(
              os.data_finalizacao,
              os.data_inicio,
              os.data_abertura
            ) ~ '^\d{4}-\d{2}-\d{2}'
        ) u on u.ultimo_servico is not null
        where c.empresa_id = p_empresa_id
          and c.ativo = true
          and c.excluido_em is null
          and u.ultimo_servico <
              (v_ref - greatest(v_camp.dias_sem_retorno, 0)::integer)
      loop
        if exists (
          select 1
          from public.imperium_crm_cupons cp
          where cp.empresa_id = p_empresa_id
            and cp.campanha_id = v_camp.id
            and cp.cliente_id = v_cliente.id
            and cp.geracao_tipo = 'reativacao'
            and cp.geracao_periodo = v_periodo
        ) then
          continue;
        end if;

        v_inicio := v_ref;
        v_chave :=
          'reativacao:' || v_camp.id::text || ':' ||
          v_cliente.id::text || ':' || v_periodo;
        v_codigo := 'VOLTA-' || upper(substr(md5(v_chave), 1, 8));
        v_fim := v_inicio + greatest(v_camp.dias_validade, 1)::integer;
        v_origem_local_id := abs(hashtextextended(v_chave, 0));

        insert into public.imperium_crm_cupons (
          empresa_id,
          origem_dispositivo,
          origem_local_id,
          codigo,
          campanha_id,
          cliente_id,
          lead_id,
          beneficio_tipo,
          beneficio_valor,
          beneficio_descricao,
          valor_minimo,
          validade_inicio,
          validade_fim,
          status,
          usado_em,
          ordem_servico_id,
          chave_geracao,
          origem_criado_em,
          excluido_em,
          criado_em,
          atualizado_em
        ) values (
          p_empresa_id,
          trim(p_origem_dispositivo) || ':beneficios',
          v_origem_local_id,
          v_codigo,
          v_camp.id,
          v_cliente.id,
          null,
          v_camp.beneficio_tipo,
          v_camp.beneficio_valor,
          v_camp.beneficio_descricao,
          v_camp.valor_minimo,
          to_char(v_inicio, 'YYYY-MM-DD'),
          to_char(v_fim, 'YYYY-MM-DD'),
          'Ativo',
          null,
          null,
          v_chave,
          v_agora::text,
          null,
          v_agora,
          v_agora
        )
        on conflict do nothing;

        if found then
          v_reativacao := v_reativacao + 1;
        end if;
      end loop;
    end if;
  end loop;

  return jsonb_build_object(
    'aniversario', v_aniversario,
    'reativacao', v_reativacao,
    'expirados', v_expirados,
    'total_criados', v_aniversario + v_reativacao
  );
end;
$$;

revoke all on function public.imperium_crm_gerar_beneficios_web(
  uuid, date, text
) from public, anon;

grant execute on function public.imperium_crm_gerar_beneficios_web(
  uuid, date, text
) to authenticated;
