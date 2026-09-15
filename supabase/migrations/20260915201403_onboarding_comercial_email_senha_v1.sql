-- Onboarding comercial por e-mail e senha.
-- A venda/licenca e criada pelo painel comercial e gera um convite para o
-- e-mail do proprietario. No primeiro login confirmado, esta RPC transforma
-- o convite em vinculo administrativo da empresa de forma idempotente.

create or replace function public.imperium_resgatar_convite()
returns table(
  resgatado boolean,
  empresa_id uuid,
  empresa_nome text,
  papel text,
  plano text,
  status_efetivo text,
  acesso_liberado boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_email text;
  v_convite_id uuid;
  v_empresa_id uuid;
  v_empresa_nome text;
  v_papel text;
  v_plano text;
  v_status text;
  v_liberado boolean;
begin
  if v_uid is null then
    raise exception 'Sessao Supabase nao autenticada.';
  end if;

  select lower(trim(coalesce(u.email, '')))
  into v_email
  from auth.users as u
  where u.id = v_uid;

  if coalesce(v_email, '') = '' then
    raise exception 'A conta autenticada nao possui e-mail.';
  end if;

  -- Convite pendente tem prioridade. Assim, um administrador que ja possui
  -- uma empresa tambem consegue ativar outra assinatura vinculada ao e-mail.
  select
    c.id,
    c.empresa_id,
    c.papel
  into
    v_convite_id,
    v_empresa_id,
    v_papel
  from public.imperium_convites_empresa as c
  join public.empresas as e
    on e.id = c.empresa_id
   and e.ativo = true
  where lower(trim(c.email)) = v_email
    and c.ativo = true
    and c.aceito_em is null
    and (c.expira_em is null or c.expira_em > now())
    and lower(trim(c.papel)) in ('admin', 'proprietario')
  order by c.criado_em desc, c.id desc
  limit 1;

  if v_convite_id is not null then
    insert into public.empresa_usuarios(
      empresa_id,
      user_id,
      papel,
      ativo
    )
    values (
      v_empresa_id,
      v_uid,
      lower(trim(v_papel)),
      true
    )
    on conflict (empresa_id, user_id)
    do update set
      papel = excluded.papel,
      ativo = true;

    update public.empresas as e
    set
      owner_id = v_uid,
      atualizado_em = now()
    where e.id = v_empresa_id;

    update public.imperium_convites_empresa as c
    set
      ativo = false,
      aceito_em = now(),
      aceito_por = v_uid
    where c.id = v_convite_id
      and c.ativo = true
      and c.aceito_em is null;

    update public.imperium_empresa_perfis as ep
    set
      proprietario_email = v_email,
      onboarding_status = 'ativo',
      ativado_em = coalesce(ep.ativado_em, now()),
      atualizado_em = now()
    where ep.empresa_id = v_empresa_id;
  else
    -- Idempotencia: se a assinatura ja foi ativada, reutiliza o vinculo.
    select
      eu.empresa_id,
      e.nome,
      eu.papel
    into
      v_empresa_id,
      v_empresa_nome,
      v_papel
    from public.empresa_usuarios as eu
    join public.empresas as e
      on e.id = eu.empresa_id
    where eu.user_id = v_uid
      and eu.ativo = true
      and e.ativo = true
      and lower(trim(eu.papel)) in ('admin', 'proprietario')
    order by
      case when lower(trim(eu.papel)) = 'proprietario' then 0 else 1 end,
      eu.empresa_id
    limit 1;

    if v_empresa_id is null then
      raise exception 'Nao encontramos uma assinatura pendente para este e-mail. Use o mesmo e-mail informado na assinatura do Imperium.';
    end if;
  end if;

  select
    e.nome,
    eu.papel,
    l.plano
  into
    v_empresa_nome,
    v_papel,
    v_plano
  from public.empresas as e
  join public.empresa_usuarios as eu
    on eu.empresa_id = e.id
   and eu.user_id = v_uid
   and eu.ativo = true
  left join public.empresa_licencas as l
    on l.empresa_id = e.id
  where e.id = v_empresa_id;

  select
    s.status_efetivo,
    s.acesso_liberado
  into
    v_status,
    v_liberado
  from private.imperium_status_licenca_empresa(v_empresa_id) as s;

  return query
  select
    true,
    v_empresa_id,
    v_empresa_nome,
    v_papel,
    coalesce(v_plano, 'Sem plano')::text,
    coalesce(v_status, 'sem_licenca')::text,
    coalesce(v_liberado, false);
end;
$$;

revoke all on function public.imperium_resgatar_convite() from public;
revoke all on function public.imperium_resgatar_convite() from anon;
grant execute on function public.imperium_resgatar_convite() to authenticated;

-- As rotinas do painel comercial tambem ficam explicitamente restritas a
-- usuarios autenticados; internamente elas validam o admin comercial.
revoke all on function public.imperium_admin_criar_cliente(text, text, text, integer, numeric) from public;
revoke all on function public.imperium_admin_criar_cliente(text, text, text, integer, numeric) from anon;
grant execute on function public.imperium_admin_criar_cliente(text, text, text, integer, numeric) to authenticated;

revoke all on function public.imperium_admin_criar_empresa_beta(text, text, text, text, text, integer, numeric, integer) from public;
revoke all on function public.imperium_admin_criar_empresa_beta(text, text, text, text, text, integer, numeric, integer) from anon;
grant execute on function public.imperium_admin_criar_empresa_beta(text, text, text, text, text, integer, numeric, integer) to authenticated;
