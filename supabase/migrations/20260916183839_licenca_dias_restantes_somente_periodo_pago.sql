create or replace function private.imperium_status_licenca_empresa(p_empresa_id uuid)
returns table(
  status_efetivo text,
  acesso_liberado boolean,
  valido_ate date,
  dias_restantes integer,
  motivo text
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with b as (
    select
      l.status_base,
      l.teste_ate,
      l.vencimento,
      coalesce(l.tolerancia_dias, 0) as tolerancia_dias,
      coalesce(l.motivo_bloqueio, '') as motivo_bloqueio,
      current_date as hoje
    from public.empresa_licencas l
    where l.empresa_id = p_empresa_id
  )
  select
    case
      when b.status_base = 'vitalicia' then 'vitalicia'
      when b.status_base = 'cortesia' then 'cortesia'
      when b.status_base = 'suspensa' then 'suspensa'
      when b.status_base = 'cancelada' then 'cancelada'
      when b.status_base = 'teste'
        and b.teste_ate is not null
        and b.hoje <= b.teste_ate then 'teste'
      when b.status_base = 'teste' then 'vencida'
      when b.status_base = 'ativa'
        and b.vencimento is not null
        and b.hoje <= b.vencimento then 'ativa'
      when b.status_base = 'ativa'
        and b.vencimento is not null
        and b.hoje <= (b.vencimento + b.tolerancia_dias) then 'tolerancia'
      when b.status_base = 'ativa' then 'vencida'
      else 'vencida'
    end,
    case
      when b.status_base in ('vitalicia', 'cortesia') then true
      when b.status_base = 'teste'
        and b.teste_ate is not null
        and b.hoje <= b.teste_ate then true
      when b.status_base = 'ativa'
        and b.vencimento is not null
        and b.hoje <= (b.vencimento + b.tolerancia_dias) then true
      else false
    end,
    case
      when b.status_base in ('vitalicia', 'cortesia') then null
      when b.status_base = 'teste' then b.teste_ate
      when b.status_base = 'ativa' and b.vencimento is not null
        then b.vencimento
      else coalesce(b.vencimento, b.teste_ate)
    end,
    case
      when b.status_base in ('vitalicia', 'cortesia') then null
      when b.status_base = 'teste' and b.teste_ate is not null
        then (b.teste_ate - b.hoje)
      when b.status_base = 'ativa' and b.vencimento is not null
        then (b.vencimento - b.hoje)
      else null
    end::integer,
    case
      when b.status_base = 'suspensa' then
        case when b.motivo_bloqueio <> ''
          then b.motivo_bloqueio else 'Licenca suspensa.' end
      when b.status_base = 'cancelada' then
        case when b.motivo_bloqueio <> ''
          then b.motivo_bloqueio else 'Licenca cancelada.' end
      when b.status_base = 'teste'
        and (b.teste_ate is null or b.hoje > b.teste_ate)
        then 'Periodo de teste encerrado.'
      when b.status_base = 'ativa'
        and (b.vencimento is null
          or b.hoje > (b.vencimento + b.tolerancia_dias))
        then 'Licenca vencida.'
      when b.status_base = 'ativa'
        and b.vencimento is not null
        and b.hoje > b.vencimento
        then 'Licenca em periodo de tolerancia.'
      else ''
    end
  from b;
$$;
