create table if not exists public.imperium_planos_assinatura (
  codigo text primary key,
  nome text not null,
  meses integer not null check (meses > 0),
  valor_centavos integer not null check (valor_centavos > 0),
  moeda text not null default 'BRL',
  ativo boolean not null default true,
  ordem integer not null default 0,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

insert into public.imperium_planos_assinatura(codigo, nome, meses, valor_centavos, moeda, ativo, ordem)
values
  ('mensal', 'Mensal', 1, 2000, 'BRL', true, 10),
  ('trimestral', 'Trimestral', 3, 5000, 'BRL', true, 20),
  ('anual', 'Anual', 12, 20000, 'BRL', true, 30)
on conflict (codigo) do update set
  nome = excluded.nome,
  meses = excluded.meses,
  valor_centavos = excluded.valor_centavos,
  moeda = excluded.moeda,
  ativo = excluded.ativo,
  ordem = excluded.ordem,
  atualizado_em = now();

alter table public.imperium_planos_assinatura enable row level security;

revoke all on table public.imperium_planos_assinatura from anon;
revoke all on table public.imperium_planos_assinatura from authenticated;

create or replace function public.imperium_planos_disponiveis()
returns table(
  codigo text,
  nome text,
  meses integer,
  valor_centavos integer,
  moeda text
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.codigo, p.nome, p.meses, p.valor_centavos, p.moeda
  from public.imperium_planos_assinatura p
  where p.ativo = true
  order by p.ordem, p.meses, p.codigo;
$$;

revoke all on function public.imperium_planos_disponiveis() from public;
revoke all on function public.imperium_planos_disponiveis() from anon;
grant execute on function public.imperium_planos_disponiveis() to authenticated;

create table if not exists public.imperium_assinatura_cobrancas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  user_id uuid,
  plano_codigo text not null references public.imperium_planos_assinatura(codigo),
  plano_nome text not null,
  valor_centavos integer not null check (valor_centavos > 0),
  moeda text not null default 'BRL',
  order_nsu text not null unique,
  checkout_url text,
  status text not null default 'pendente' check (status in ('pendente', 'pago', 'falhou', 'cancelado')),
  invoice_slug text,
  transaction_nsu text unique,
  capture_method text,
  installments integer,
  amount_centavos integer,
  paid_amount_centavos integer,
  receipt_url text,
  provider_payload jsonb not null default '{}'::jsonb,
  erro text not null default '',
  pago_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists imperium_assinatura_cobrancas_empresa_idx
  on public.imperium_assinatura_cobrancas(empresa_id, criado_em desc);

create index if not exists imperium_assinatura_cobrancas_status_idx
  on public.imperium_assinatura_cobrancas(status, criado_em desc);

alter table public.imperium_assinatura_cobrancas enable row level security;

revoke all on table public.imperium_assinatura_cobrancas from anon;
revoke insert, update, delete on table public.imperium_assinatura_cobrancas from authenticated;
grant select on table public.imperium_assinatura_cobrancas to authenticated;

drop policy if exists imperium_cobrancas_admin_select on public.imperium_assinatura_cobrancas;
create policy imperium_cobrancas_admin_select
on public.imperium_assinatura_cobrancas
for select
to authenticated
using (
  exists (
    select 1
    from public.empresa_usuarios eu
    join public.empresas e on e.id = eu.empresa_id and e.ativo = true
    where eu.empresa_id = imperium_assinatura_cobrancas.empresa_id
      and eu.user_id = (select auth.uid())
      and eu.ativo = true
      and lower(trim(eu.papel)) in ('admin', 'proprietario')
  )
);

create or replace function public.imperium_confirmar_pagamento_infinitepay(
  p_order_nsu text,
  p_transaction_nsu text,
  p_invoice_slug text,
  p_amount_centavos integer,
  p_paid_amount_centavos integer,
  p_installments integer,
  p_capture_method text,
  p_receipt_url text,
  p_payload jsonb default '{}'::jsonb
)
returns table(
  empresa_id uuid,
  plano_codigo text,
  vencimento date,
  ja_processado boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cobranca record;
  v_licenca record;
  v_base date;
  v_novo_vencimento date;
  v_valor_mensal numeric;
begin
  if coalesce(trim(p_order_nsu), '') = '' then
    raise exception 'order_nsu ausente.' using errcode = 'P0001';
  end if;

  if coalesce(trim(p_transaction_nsu), '') = '' then
    raise exception 'transaction_nsu ausente.' using errcode = 'P0001';
  end if;

  select
    c.*,
    p.meses as plano_meses
  into v_cobranca
  from public.imperium_assinatura_cobrancas c
  join public.imperium_planos_assinatura p on p.codigo = c.plano_codigo
  where c.order_nsu = trim(p_order_nsu)
  for update of c;

  if not found then
    raise exception 'Cobranca nao encontrada.' using errcode = 'P0001';
  end if;

  if v_cobranca.valor_centavos <> p_amount_centavos then
    raise exception 'Valor do pagamento nao confere com a cobranca.' using errcode = 'P0001';
  end if;

  if v_cobranca.status = 'pago' then
    if v_cobranca.transaction_nsu is distinct from trim(p_transaction_nsu) then
      raise exception 'Cobranca ja processada por outra transacao.' using errcode = 'P0001';
    end if;

    return query
    select
      v_cobranca.empresa_id,
      v_cobranca.plano_codigo,
      l.vencimento,
      true
    from public.empresa_licencas l
    where l.empresa_id = v_cobranca.empresa_id;
    return;
  end if;

  if exists (
    select 1
    from public.imperium_assinatura_cobrancas c
    where c.transaction_nsu = trim(p_transaction_nsu)
      and c.order_nsu <> trim(p_order_nsu)
  ) then
    raise exception 'Transacao ja vinculada a outra cobranca.' using errcode = 'P0001';
  end if;

  select *
  into v_licenca
  from public.empresa_licencas l
  where l.empresa_id = v_cobranca.empresa_id
  for update;

  if not found then
    raise exception 'Licenca da empresa nao encontrada.' using errcode = 'P0001';
  end if;

  v_base := greatest(
    current_date,
    coalesce(v_licenca.vencimento, current_date),
    coalesce(v_licenca.teste_ate, current_date)
  );

  v_novo_vencimento := (
    v_base + pg_catalog.make_interval(months => v_cobranca.plano_meses)
  )::date;

  v_valor_mensal := round(
    (v_cobranca.valor_centavos::numeric / 100) / v_cobranca.plano_meses,
    2
  );

  update public.imperium_assinatura_cobrancas
  set
    status = 'pago',
    invoice_slug = nullif(trim(p_invoice_slug), ''),
    transaction_nsu = trim(p_transaction_nsu),
    capture_method = nullif(trim(p_capture_method), ''),
    installments = p_installments,
    amount_centavos = p_amount_centavos,
    paid_amount_centavos = p_paid_amount_centavos,
    receipt_url = nullif(trim(p_receipt_url), ''),
    provider_payload = coalesce(p_payload, '{}'::jsonb),
    erro = '',
    pago_em = coalesce(pago_em, now()),
    atualizado_em = now()
  where order_nsu = trim(p_order_nsu);

  update public.empresa_licencas
  set
    plano = v_cobranca.plano_nome,
    status_base = 'ativa',
    teste_ate = null,
    vencimento = v_novo_vencimento,
    tolerancia_dias = greatest(coalesce(tolerancia_dias, 0), 3),
    valor_mensal = v_valor_mensal,
    ultimo_pagamento_em = now(),
    motivo_bloqueio = '',
    observacoes = trim(both from concat_ws(
      E'\n',
      nullif(observacoes, ''),
      'Pagamento InfinitePay confirmado. Pedido ' || v_cobranca.order_nsu || '.'
    )),
    atualizado_em = now()
  where empresa_id = v_cobranca.empresa_id;

  insert into public.imperium_licenca_historico(
    empresa_id,
    acao,
    plano_antes,
    status_antes,
    vencimento_antes,
    plano_depois,
    status_depois,
    vencimento_depois,
    detalhes,
    executado_por
  ) values (
    v_cobranca.empresa_id,
    'pagamento_infinitepay_confirmado',
    v_licenca.plano,
    v_licenca.status_base,
    v_licenca.vencimento,
    v_cobranca.plano_nome,
    'ativa',
    v_novo_vencimento,
    'Pagamento confirmado pela InfinitePay. Pedido ' || v_cobranca.order_nsu || ', transacao ' || trim(p_transaction_nsu) || '.',
    null
  );

  return query
  select
    v_cobranca.empresa_id,
    v_cobranca.plano_codigo,
    v_novo_vencimento,
    false;
end;
$$;

revoke all on function public.imperium_confirmar_pagamento_infinitepay(text, text, text, integer, integer, integer, text, text, jsonb) from public;
revoke all on function public.imperium_confirmar_pagamento_infinitepay(text, text, text, integer, integer, integer, text, text, jsonb) from anon;
revoke all on function public.imperium_confirmar_pagamento_infinitepay(text, text, text, integer, integer, integer, text, text, jsonb) from authenticated;
grant execute on function public.imperium_confirmar_pagamento_infinitepay(text, text, text, integer, integer, integer, text, text, jsonb) to service_role;
