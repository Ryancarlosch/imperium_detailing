create or replace function public.imperium_status_licenca_empresa(p_empresa_id uuid)
returns table(
  empresa_id uuid,
  empresa_nome text,
  papel text,
  plano text,
  status_base text,
  status_efetivo text,
  acesso_liberado boolean,
  hoje date,
  valido_ate date,
  dias_restantes integer,
  tolerancia_dias integer,
  valor_mensal numeric,
  motivo text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    e.id as empresa_id,
    e.nome as empresa_nome,
    eu.papel,
    coalesce(l.plano, 'Sem plano')::text as plano,
    coalesce(l.status_base, 'sem_licenca')::text as status_base,
    coalesce(s.status_efetivo, 'sem_licenca')::text as status_efetivo,
    coalesce(s.acesso_liberado, false) as acesso_liberado,
    current_date as hoje,
    s.valido_ate,
    s.dias_restantes,
    coalesce(l.tolerancia_dias, 0) as tolerancia_dias,
    l.valor_mensal,
    coalesce(
      s.motivo,
      case
        when l.empresa_id is null then 'Empresa sem licenca cadastrada.'
        else ''
      end
    )::text as motivo
  from public.empresa_usuarios eu
  join public.empresas e
    on e.id = eu.empresa_id
   and e.ativo = true
  left join public.empresa_licencas l
    on l.empresa_id = e.id
  left join lateral private.imperium_status_licenca_empresa(e.id) s
    on true
  where eu.empresa_id = p_empresa_id
    and eu.user_id = (select auth.uid())
    and eu.ativo = true
    and lower(trim(eu.papel)) in ('admin', 'proprietario');
$$;

revoke all on function public.imperium_status_licenca_empresa(uuid) from public;
revoke all on function public.imperium_status_licenca_empresa(uuid) from anon;
grant execute on function public.imperium_status_licenca_empresa(uuid) to authenticated;
