create table if not exists public.imperium_financeiro_pagamentos_colaboradores (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  colaborador_id uuid not null,
  origem_colaborador_local_id bigint,
  movimento_financeiro_id uuid,
  origem_movimento_local_id bigint,
  valor numeric(18,2) not null default 0,
  conta_id uuid not null,
  origem_conta_local_id bigint,
  data_pagamento text not null,
  forma_pagamento text not null default '',
  observacoes text not null default '',
  origem_criado_em text,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_fin_pag_colab_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_fin_pag_colab_empresa_id_id_uq
    unique (empresa_id, id),
  constraint imperium_fin_pag_colab_colaborador_fk
    foreign key (empresa_id, colaborador_id)
    references public.imperium_precificacao_colaboradores_custo(empresa_id, id)
    on delete restrict,
  constraint imperium_fin_pag_colab_movimento_fk
    foreign key (empresa_id, movimento_financeiro_id)
    references public.imperium_financeiro_movimentos(empresa_id, id)
    on delete set null,
  constraint imperium_fin_pag_colab_conta_fk
    foreign key (empresa_id, conta_id)
    references public.imperium_financeiro_contas(empresa_id, id)
    on delete restrict,
  constraint imperium_fin_pag_colab_valor_ck check (valor > 0)
);

create index if not exists idx_imperium_fin_pag_colab_empresa_data
  on public.imperium_financeiro_pagamentos_colaboradores
  (empresa_id, data_pagamento desc);

create index if not exists idx_imperium_fin_pag_colab_colaborador
  on public.imperium_financeiro_pagamentos_colaboradores
  (empresa_id, colaborador_id, data_pagamento desc);

alter table public.imperium_financeiro_pagamentos_colaboradores
  enable row level security;

revoke all on public.imperium_financeiro_pagamentos_colaboradores
  from anon, authenticated;

grant select, insert, update
  on public.imperium_financeiro_pagamentos_colaboradores
  to authenticated;

drop policy if exists imperium_fin_pag_colab_select
  on public.imperium_financeiro_pagamentos_colaboradores;
create policy imperium_fin_pag_colab_select
  on public.imperium_financeiro_pagamentos_colaboradores
  for select to authenticated
  using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

drop policy if exists imperium_fin_pag_colab_insert
  on public.imperium_financeiro_pagamentos_colaboradores;
create policy imperium_fin_pag_colab_insert
  on public.imperium_financeiro_pagamentos_colaboradores
  for insert to authenticated
  with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

drop policy if exists imperium_fin_pag_colab_update
  on public.imperium_financeiro_pagamentos_colaboradores;
create policy imperium_fin_pag_colab_update
  on public.imperium_financeiro_pagamentos_colaboradores
  for update to authenticated
  using ((select private.imperium_pode_modulo(empresa_id, 'financeiro')))
  with check ((select private.imperium_pode_modulo(empresa_id, 'financeiro')));

drop trigger if exists imperium_fin_pag_colab_touch
  on public.imperium_financeiro_pagamentos_colaboradores;
create trigger imperium_fin_pag_colab_touch
  before update on public.imperium_financeiro_pagamentos_colaboradores
  for each row execute function private.imperium_touch_atualizado_em();

create or replace function public.imperium_financeiro_pagar_colaborador_web(
  p_empresa_id uuid,
  p_colaborador_id uuid,
  p_conta_id uuid,
  p_valor numeric,
  p_data_pagamento text,
  p_forma_pagamento text,
  p_observacoes text,
  p_origem_dispositivo text,
  p_pagamento_local_id bigint,
  p_movimento_local_id bigint
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_nome text;
  v_conta_ativa boolean;
  v_plano_id uuid;
  v_natureza text := 'Mão de obra';
  v_movimento_id uuid;
  v_pagamento_id uuid;
  v_data timestamp;
  v_forma text;
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;

  if coalesce(p_valor, 0) <= 0 then
    raise exception 'O valor do pagamento deve ser maior que zero.';
  end if;

  if nullif(trim(coalesce(p_origem_dispositivo, '')), '') is null
     or coalesce(p_pagamento_local_id, 0) <= 0
     or coalesce(p_movimento_local_id, 0) <= 0 then
    raise exception 'Origem do pagamento inválida.';
  end if;

  begin
    v_data := p_data_pagamento::timestamp;
  exception when others then
    raise exception 'Data de pagamento inválida.';
  end;

  select nome
  into v_nome
  from public.imperium_precificacao_colaboradores_custo
  where empresa_id = p_empresa_id
    and id = p_colaborador_id
    and excluido_em is null;

  if not found then
    raise exception 'Funcionário não encontrado ou sem acesso.';
  end if;

  select ativo
  into v_conta_ativa
  from public.imperium_financeiro_contas
  where empresa_id = p_empresa_id
    and id = p_conta_id
    and excluido_em is null;

  if not found then
    raise exception 'Conta financeira não encontrada ou sem acesso.';
  end if;

  if not coalesce(v_conta_ativa, false) then
    raise exception 'A conta financeira selecionada está inativa.';
  end if;

  select id, natureza
  into v_plano_id, v_natureza
  from public.imperium_financeiro_plano_contas
  where empresa_id = p_empresa_id
    and codigo = '2.01.01'
    and ativo = true
    and excluido_em is null
  limit 1;

  v_natureza := coalesce(nullif(trim(v_natureza), ''), 'Mão de obra');
  v_forma := coalesce(
    nullif(trim(coalesce(p_forma_pagamento, '')), ''),
    'Não informado'
  );

  insert into public.imperium_financeiro_movimentos (
    empresa_id,
    origem_dispositivo,
    origem_local_id,
    tipo,
    descricao,
    valor,
    forma_pagamento,
    data,
    plano_conta_id,
    conta_id,
    total_parcelas,
    natureza,
    origem,
    status,
    data_competencia,
    data_pagamento,
    numero_documento,
    observacoes,
    impacta_dre,
    criado_em,
    atualizado_em
  ) values (
    p_empresa_id,
    p_origem_dispositivo,
    p_movimento_local_id,
    'Saída',
    'Pagamento de funcionário - ' ||
      coalesce(nullif(trim(v_nome), ''), 'Funcionário'),
    p_valor,
    v_forma,
    p_data_pagamento,
    v_plano_id,
    p_conta_id,
    1,
    v_natureza,
    'Pagamento de funcionário',
    'Realizado',
    p_data_pagamento,
    p_data_pagamento,
    '',
    trim(coalesce(p_observacoes, '')),
    true,
    now(),
    now()
  )
  returning id into v_movimento_id;

  insert into public.imperium_financeiro_pagamentos_colaboradores (
    empresa_id,
    origem_dispositivo,
    origem_local_id,
    colaborador_id,
    movimento_financeiro_id,
    valor,
    conta_id,
    data_pagamento,
    forma_pagamento,
    observacoes,
    origem_criado_em,
    excluido_em,
    criado_em,
    atualizado_em
  ) values (
    p_empresa_id,
    p_origem_dispositivo,
    p_pagamento_local_id,
    p_colaborador_id,
    v_movimento_id,
    p_valor,
    p_conta_id,
    p_data_pagamento,
    v_forma,
    trim(coalesce(p_observacoes, '')),
    now()::text,
    null,
    now(),
    now()
  )
  returning id into v_pagamento_id;

  return jsonb_build_object(
    'pagamento_id', v_pagamento_id,
    'movimento_id', v_movimento_id
  );
end;
$$;

revoke all on function public.imperium_financeiro_pagar_colaborador_web(
  uuid, uuid, uuid, numeric, text, text, text, text, bigint, bigint
) from public, anon;

grant execute on function public.imperium_financeiro_pagar_colaborador_web(
  uuid, uuid, uuid, numeric, text, text, text, text, bigint, bigint
) to authenticated;
