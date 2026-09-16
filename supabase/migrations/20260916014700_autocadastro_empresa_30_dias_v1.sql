create or replace function public.imperium_autocadastro_empresa()
returns table(
  criado boolean,
  empresa_id uuid,
  empresa_nome text,
  papel text,
  plano text,
  status_efetivo text,
  teste_ate date,
  acesso_liberado boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_email text;
  v_email_confirmado_em timestamptz;
  v_empresa_id uuid;
  v_empresa_nome text;
  v_papel text;
  v_vinculo_ativo boolean;
  v_empresa_ativa boolean;
  v_slug_base text;
  v_slug text;
  v_identificador text;
begin
  if v_user_id is null then
    raise exception 'Entre com e-mail e senha para continuar.' using errcode = 'P0001';
  end if;

  select
    lower(trim(coalesce(u.email, ''))),
    coalesce(u.email_confirmed_at, u.confirmed_at)
  into v_email, v_email_confirmado_em
  from auth.users u
  where u.id = v_user_id;

  if v_email is null or v_email = '' or position('@' in v_email) = 0 then
    raise exception 'Sua conta não possui um e-mail válido.' using errcode = 'P0001';
  end if;

  if v_email_confirmado_em is null then
    raise exception 'Confirme seu e-mail antes de criar sua empresa.' using errcode = 'P0001';
  end if;

  -- Impede duas empresas se Web e Mobile prepararem o primeiro acesso juntos.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_user_id::text, 0)
  );

  select
    eu.empresa_id,
    e.nome,
    lower(trim(eu.papel)),
    eu.ativo,
    e.ativo
  into
    v_empresa_id,
    v_empresa_nome,
    v_papel,
    v_vinculo_ativo,
    v_empresa_ativa
  from public.empresa_usuarios eu
  join public.empresas e on e.id = eu.empresa_id
  where eu.user_id = v_user_id
    and lower(trim(eu.papel)) in ('admin', 'proprietario')
  order by
    case when eu.ativo and e.ativo then 0 else 1 end,
    eu.criado_em asc
  limit 1;

  if found then
    if not coalesce(v_vinculo_ativo, false)
       or not coalesce(v_empresa_ativa, false) then
      raise exception
        'Sua conta empresarial está desativada. Fale com o suporte do Imperium.'
        using errcode = 'P0001';
    end if;

    return query
    select
      false,
      e.id,
      e.nome::text,
      eu.papel::text,
      coalesce(l.plano, 'Sem plano')::text,
      coalesce(s.status_efetivo, 'sem_licenca')::text,
      l.teste_ate,
      coalesce(s.acesso_liberado, false)
    from public.empresas e
    join public.empresa_usuarios eu
      on eu.empresa_id = e.id
     and eu.user_id = v_user_id
     and eu.ativo = true
    left join public.empresa_licencas l on l.empresa_id = e.id
    left join lateral private.imperium_status_licenca_empresa(e.id) s on true
    where e.id = v_empresa_id
    limit 1;

    return;
  end if;

  v_empresa_id := gen_random_uuid();
  v_identificador := split_part(v_email, '@', 1);
  v_identificador := regexp_replace(v_identificador, '[^a-z0-9_-]+', '-', 'g');
  v_identificador := trim(both '-' from v_identificador);

  if v_identificador = '' then
    v_identificador := 'empresa';
  end if;

  v_empresa_nome := 'Empresa ' || v_identificador;
  v_slug_base := regexp_replace(v_identificador, '[^a-z0-9]+', '-', 'g');
  v_slug_base := trim(both '-' from v_slug_base);

  if v_slug_base = '' then
    v_slug_base := 'empresa';
  end if;

  v_slug := v_slug_base || '-' || substr(replace(v_empresa_id::text, '-', ''), 1, 8);

  insert into public.empresas(
    id,
    nome,
    slug,
    owner_id,
    ativo
  ) values (
    v_empresa_id,
    v_empresa_nome,
    v_slug,
    v_user_id,
    true
  );

  insert into public.empresa_usuarios(
    empresa_id,
    user_id,
    papel,
    ativo
  ) values (
    v_empresa_id,
    v_user_id,
    'proprietario',
    true
  );

  insert into public.imperium_empresa_perfis(
    empresa_id,
    proprietario_nome,
    proprietario_email,
    telefone,
    onboarding_status,
    ativado_em,
    atualizado_em
  ) values (
    v_empresa_id,
    '',
    v_email,
    '',
    'ativo',
    now(),
    now()
  );

  insert into public.empresa_licencas(
    empresa_id,
    plano,
    status_base,
    teste_ate,
    vencimento,
    tolerancia_dias,
    valor_mensal,
    motivo_bloqueio,
    observacoes,
    atualizado_em
  ) values (
    v_empresa_id,
    'Teste 30 dias',
    'teste',
    current_date + 30,
    null,
    0,
    null,
    '',
    'Autocadastro: 30 dias grátis a partir do primeiro acesso confirmado.',
    now()
  );

  insert into public.imperium_licenca_historico(
    empresa_id,
    acao,
    plano_depois,
    status_depois,
    vencimento_depois,
    detalhes,
    executado_por
  ) values (
    v_empresa_id,
    'autocadastro_teste_30_dias',
    'Teste 30 dias',
    'teste',
    null,
    'Empresa criada automaticamente após confirmação do e-mail. Teste gratuito por 30 dias.',
    v_user_id
  );

  return query
  select
    true,
    e.id,
    e.nome::text,
    eu.papel::text,
    l.plano::text,
    coalesce(s.status_efetivo, 'teste')::text,
    l.teste_ate,
    coalesce(s.acesso_liberado, true)
  from public.empresas e
  join public.empresa_usuarios eu
    on eu.empresa_id = e.id
   and eu.user_id = v_user_id
  join public.empresa_licencas l on l.empresa_id = e.id
  left join lateral private.imperium_status_licenca_empresa(e.id) s on true
  where e.id = v_empresa_id;
end;
$$;

revoke all on function public.imperium_autocadastro_empresa() from public;
revoke all on function public.imperium_autocadastro_empresa() from anon;
grant execute on function public.imperium_autocadastro_empresa() to authenticated;

comment on function public.imperium_autocadastro_empresa() is
  'Cria de forma idempotente a primeira empresa do usuário autenticado após confirmação do e-mail e concede 30 dias grátis.';
