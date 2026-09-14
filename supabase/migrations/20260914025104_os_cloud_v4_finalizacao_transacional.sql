-- OS Cloud V4 - finalizacao transacional
-- Espelho local da migration aplicada no projeto Supabase em 2026-09-14.
-- Mantem RLS, idempotencia, FIFO, financeiro e mao de obra no mesmo contrato.

create table if not exists public.imperium_ordem_servico_produtos_estado (
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  ordem_servico_id uuid not null,
  contrato_hash text not null default '',
  pronto boolean not null default false,
  origem_dispositivo text,
  origem_os_local_id bigint,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  primary key (empresa_id, ordem_servico_id),
  constraint imperium_os_prod_estado_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico(empresa_id, id)
    on delete cascade
);

create table if not exists public.imperium_ordem_servico_produtos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  ordem_servico_id uuid not null,
  item_estoque_id uuid,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  produto_nome text not null,
  quantidade numeric not null default 0,
  unidade text not null default '',
  custo_unitario numeric not null default 0,
  custo_unitario_no_momento numeric not null default 0,
  custo_total_no_momento numeric not null default 0,
  composicao_lotes_json jsonb not null default '[]'::jsonb,
  baixado_estoque boolean not null default false,
  excluido_em timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_os_prod_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico(empresa_id, id)
    on delete cascade,
  constraint imperium_os_prod_item_fk
    foreign key (empresa_id, item_estoque_id)
    references public.imperium_estoque_itens(empresa_id, id)
    on delete restrict,
  constraint imperium_os_prod_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_os_prod_empresa_id_uq unique (empresa_id, id),
  constraint imperium_os_prod_quantidade_ck check (quantidade >= 0),
  constraint imperium_os_prod_origem_ck check (
    length(trim(origem_dispositivo)) > 0 and origem_local_id > 0
  )
);

create index if not exists idx_imperium_os_produtos_os
  on public.imperium_ordem_servico_produtos(empresa_id, ordem_servico_id)
  where excluido_em is null;

create table if not exists public.imperium_ordem_servico_produto_lotes (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  ordem_servico_produto_id uuid not null,
  ordem_servico_id uuid not null,
  item_estoque_id uuid not null,
  lote_id uuid not null,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  quantidade numeric not null,
  custo_unitario numeric not null default 0,
  custo_total numeric not null default 0,
  criado_em timestamptz not null default now(),
  constraint imperium_os_prod_lote_prod_fk
    foreign key (empresa_id, ordem_servico_produto_id)
    references public.imperium_ordem_servico_produtos(empresa_id, id)
    on delete cascade,
  constraint imperium_os_prod_lote_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico(empresa_id, id)
    on delete cascade,
  constraint imperium_os_prod_lote_item_fk
    foreign key (empresa_id, item_estoque_id)
    references public.imperium_estoque_itens(empresa_id, id)
    on delete restrict,
  constraint imperium_os_prod_lote_lote_fk
    foreign key (empresa_id, lote_id)
    references public.imperium_estoque_lotes(empresa_id, id)
    on delete restrict,
  constraint imperium_os_prod_lote_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_os_prod_lote_comp_uq
    unique (empresa_id, ordem_servico_produto_id, lote_id),
  constraint imperium_os_prod_lote_qtd_ck check (quantidade > 0)
);

create index if not exists idx_imperium_os_prod_lotes_os
  on public.imperium_ordem_servico_produto_lotes(empresa_id, ordem_servico_id);

create table if not exists public.imperium_financeiro_os_mao_obra (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  ordem_servico_id uuid not null,
  colaborador_custo_id uuid,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  descricao text not null default '',
  horas numeric not null default 0,
  custo_hora_snapshot numeric not null default 0,
  custo_total numeric not null default 0,
  data text not null,
  observacoes text not null default '',
  ativo boolean not null default true,
  cancelado_em text,
  origem_criado_em text,
  origem_atualizado_em text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_fin_os_mao_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico(empresa_id, id)
    on delete cascade,
  constraint imperium_fin_os_mao_colab_fk
    foreign key (empresa_id, colaborador_custo_id)
    references public.imperium_precificacao_colaboradores_custo(empresa_id, id)
    on delete set null (colaborador_custo_id),
  constraint imperium_fin_os_mao_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_fin_os_mao_empresa_id_uq unique (empresa_id, id),
  constraint imperium_fin_os_mao_valores_ck check (
    horas >= 0 and custo_hora_snapshot >= 0 and custo_total >= 0
  )
);

create index if not exists idx_imperium_fin_os_mao_os
  on public.imperium_financeiro_os_mao_obra(empresa_id, ordem_servico_id);

create table if not exists public.imperium_ordem_servico_ajustes_financeiros (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  ordem_servico_id uuid not null,
  regra_taxa_id uuid,
  pagamento_id uuid,
  origem_dispositivo text not null,
  origem_local_id bigint not null,
  tipo text not null,
  valor numeric not null,
  motivo text not null,
  status text not null default 'Ativo',
  origem text not null default 'Manual',
  cancelado_em text,
  motivo_cancelamento text not null default '',
  origem_criado_em text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_os_ajuste_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico(empresa_id, id)
    on delete cascade,
  constraint imperium_os_ajuste_regra_fk
    foreign key (empresa_id, regra_taxa_id)
    references public.imperium_financeiro_regras_taxa(empresa_id, id)
    on delete set null (regra_taxa_id),
  constraint imperium_os_ajuste_pag_fk
    foreign key (empresa_id, pagamento_id)
    references public.imperium_financeiro_pagamentos_os(empresa_id, id)
    on delete set null (pagamento_id),
  constraint imperium_os_ajuste_origem_uq
    unique (empresa_id, origem_dispositivo, origem_local_id),
  constraint imperium_os_ajuste_empresa_id_uq unique (empresa_id, id),
  constraint imperium_os_ajuste_valor_ck check (valor > 0)
);

create index if not exists idx_imperium_os_ajuste_os
  on public.imperium_ordem_servico_ajustes_financeiros(empresa_id, ordem_servico_id);

create table if not exists public.imperium_os_finalizacoes_web (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  ordem_servico_id uuid not null,
  idempotency_key text not null,
  request_hash text not null,
  origem_dispositivo text not null,
  origem_base bigint not null,
  resultado_json jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  constraint imperium_os_final_web_os_fk
    foreign key (empresa_id, ordem_servico_id)
    references public.imperium_ordens_servico(empresa_id, id)
    on delete cascade,
  constraint imperium_os_final_web_os_uq unique (empresa_id, ordem_servico_id),
  constraint imperium_os_final_web_key_uq unique (empresa_id, idempotency_key),
  constraint imperium_os_final_web_origem_ck check (
    length(trim(origem_dispositivo)) > 0 and origem_base > 0
  )
);

alter table public.imperium_ordem_servico_produtos_estado enable row level security;
alter table public.imperium_ordem_servico_produtos enable row level security;
alter table public.imperium_ordem_servico_produto_lotes enable row level security;
alter table public.imperium_financeiro_os_mao_obra enable row level security;
alter table public.imperium_ordem_servico_ajustes_financeiros enable row level security;
alter table public.imperium_os_finalizacoes_web enable row level security;

revoke all on table public.imperium_ordem_servico_produtos_estado from public, anon;
revoke all on table public.imperium_ordem_servico_produtos from public, anon;
revoke all on table public.imperium_ordem_servico_produto_lotes from public, anon;
revoke all on table public.imperium_financeiro_os_mao_obra from public, anon;
revoke all on table public.imperium_ordem_servico_ajustes_financeiros from public, anon;
revoke all on table public.imperium_os_finalizacoes_web from public, anon;

grant select, insert, update on table public.imperium_ordem_servico_produtos_estado to authenticated;
grant select, insert, update on table public.imperium_ordem_servico_produtos to authenticated;
grant select, insert on table public.imperium_ordem_servico_produto_lotes to authenticated;
grant select, insert, update on table public.imperium_financeiro_os_mao_obra to authenticated;
grant select, insert, update on table public.imperium_ordem_servico_ajustes_financeiros to authenticated;
grant select, insert on table public.imperium_os_finalizacoes_web to authenticated;

drop policy if exists imperium_os_prod_estado_select on public.imperium_ordem_servico_produtos_estado;
drop policy if exists imperium_os_prod_estado_insert on public.imperium_ordem_servico_produtos_estado;
drop policy if exists imperium_os_prod_estado_update on public.imperium_ordem_servico_produtos_estado;
create policy imperium_os_prod_estado_select on public.imperium_ordem_servico_produtos_estado
for select to authenticated
using (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'estoque')
);
create policy imperium_os_prod_estado_insert on public.imperium_ordem_servico_produtos_estado
for insert to authenticated
with check (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'estoque')
);
create policy imperium_os_prod_estado_update on public.imperium_ordem_servico_produtos_estado
for update to authenticated
using (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'estoque')
)
with check (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'estoque')
);

drop policy if exists imperium_os_prod_select on public.imperium_ordem_servico_produtos;
drop policy if exists imperium_os_prod_insert on public.imperium_ordem_servico_produtos;
drop policy if exists imperium_os_prod_update on public.imperium_ordem_servico_produtos;
create policy imperium_os_prod_select on public.imperium_ordem_servico_produtos
for select to authenticated
using (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'estoque')
);
create policy imperium_os_prod_insert on public.imperium_ordem_servico_produtos
for insert to authenticated
with check (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'estoque')
);
create policy imperium_os_prod_update on public.imperium_ordem_servico_produtos
for update to authenticated
using (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'estoque')
)
with check (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'estoque')
);

drop policy if exists imperium_os_prod_lote_select on public.imperium_ordem_servico_produto_lotes;
drop policy if exists imperium_os_prod_lote_insert on public.imperium_ordem_servico_produto_lotes;
create policy imperium_os_prod_lote_select on public.imperium_ordem_servico_produto_lotes
for select to authenticated
using (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'estoque')
);
create policy imperium_os_prod_lote_insert on public.imperium_ordem_servico_produto_lotes
for insert to authenticated
with check (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'estoque')
);

drop policy if exists imperium_fin_os_mao_select on public.imperium_financeiro_os_mao_obra;
drop policy if exists imperium_fin_os_mao_insert on public.imperium_financeiro_os_mao_obra;
drop policy if exists imperium_fin_os_mao_update on public.imperium_financeiro_os_mao_obra;
create policy imperium_fin_os_mao_select on public.imperium_financeiro_os_mao_obra
for select to authenticated
using (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'precificacao')
);
create policy imperium_fin_os_mao_insert on public.imperium_financeiro_os_mao_obra
for insert to authenticated
with check (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'precificacao')
);
create policy imperium_fin_os_mao_update on public.imperium_financeiro_os_mao_obra
for update to authenticated
using (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'precificacao')
)
with check (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'precificacao')
);

drop policy if exists imperium_os_ajuste_select on public.imperium_ordem_servico_ajustes_financeiros;
drop policy if exists imperium_os_ajuste_insert on public.imperium_ordem_servico_ajustes_financeiros;
drop policy if exists imperium_os_ajuste_update on public.imperium_ordem_servico_ajustes_financeiros;
create policy imperium_os_ajuste_select on public.imperium_ordem_servico_ajustes_financeiros
for select to authenticated
using (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'financeiro')
);
create policy imperium_os_ajuste_insert on public.imperium_ordem_servico_ajustes_financeiros
for insert to authenticated
with check (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'financeiro')
);
create policy imperium_os_ajuste_update on public.imperium_ordem_servico_ajustes_financeiros
for update to authenticated
using (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'financeiro')
)
with check (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'financeiro')
);

drop policy if exists imperium_os_final_web_select on public.imperium_os_finalizacoes_web;
drop policy if exists imperium_os_final_web_insert on public.imperium_os_finalizacoes_web;
create policy imperium_os_final_web_select on public.imperium_os_finalizacoes_web
for select to authenticated
using (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'financeiro')
);
create policy imperium_os_final_web_insert on public.imperium_os_finalizacoes_web
for insert to authenticated
with check (
  private.imperium_pode_modulo(empresa_id,'ordens_servico')
  and private.imperium_pode_modulo(empresa_id,'financeiro')
);

drop trigger if exists trg_imperium_os_prod_estado_touch
  on public.imperium_ordem_servico_produtos_estado;
create trigger trg_imperium_os_prod_estado_touch
before update on public.imperium_ordem_servico_produtos_estado
for each row execute function private.imperium_touch_atualizado_em();

drop trigger if exists trg_imperium_os_prod_touch
  on public.imperium_ordem_servico_produtos;
create trigger trg_imperium_os_prod_touch
before update on public.imperium_ordem_servico_produtos
for each row execute function private.imperium_touch_atualizado_em();

drop trigger if exists trg_imperium_fin_os_mao_touch
  on public.imperium_financeiro_os_mao_obra;
create trigger trg_imperium_fin_os_mao_touch
before update on public.imperium_financeiro_os_mao_obra
for each row execute function private.imperium_touch_atualizado_em();

drop trigger if exists trg_imperium_os_ajuste_touch
  on public.imperium_ordem_servico_ajustes_financeiros;
create trigger trg_imperium_os_ajuste_touch
before update on public.imperium_ordem_servico_ajustes_financeiros
for each row execute function private.imperium_touch_atualizado_em();

-- Resolve produto FIFO por ID remoto ou origem local. Essa forma permite
-- interoperabilidade Web -> Android -> Web.
create or replace function public.imperium_os_produto_resolver_v4(
  p_empresa_id uuid,
  p_ordem_servico_id uuid,
  p_produto_id uuid,
  p_origem_dispositivo text,
  p_origem_local_id bigint
)
returns uuid
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if p_produto_id is not null then
    select p.id into v_id
    from public.imperium_ordem_servico_produtos p
    where p.empresa_id = p_empresa_id
      and p.ordem_servico_id = p_ordem_servico_id
      and p.id = p_produto_id
      and p.excluido_em is null;
    if v_id is not null then return v_id; end if;
  end if;

  if trim(coalesce(p_origem_dispositivo,'')) <> ''
     and coalesce(p_origem_local_id,0) > 0 then
    select p.id into v_id
    from public.imperium_ordem_servico_produtos p
    where p.empresa_id = p_empresa_id
      and p.ordem_servico_id = p_ordem_servico_id
      and p.origem_dispositivo = p_origem_dispositivo
      and p.origem_local_id = p_origem_local_id
      and p.excluido_em is null;
  end if;

  return v_id;
end;
$$;

revoke all on function public.imperium_os_produto_resolver_v4(
  uuid,uuid,uuid,text,bigint
) from public, anon;
grant execute on function public.imperium_os_produto_resolver_v4(
  uuid,uuid,uuid,text,bigint
) to authenticated;

create or replace function public.imperium_os_produtos_publicar_v4(
  p_empresa_id uuid,
  p_ordem_servico_id uuid,
  p_estado_atualizado_em timestamptz,
  p_contrato_hash text,
  p_produtos jsonb,
  p_lotes jsonb,
  p_origem_dispositivo text,
  p_origem_os_local_id bigint default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_os public.imperium_ordens_servico%rowtype;
  v_estado public.imperium_ordem_servico_produtos_estado%rowtype;
  v_item jsonb;
  v_lote jsonb;
  v_id uuid;
  v_produto_id uuid;
  v_origem_local_id bigint;
  v_ids uuid[] := array[]::uuid[];
  v_estado_existe boolean := false;
begin
  if not private.imperium_pode_modulo(p_empresa_id,'ordens_servico')
     or not private.imperium_pode_modulo(p_empresa_id,'estoque') then
    raise exception 'Sem permissao para publicar produtos da OS.'
      using errcode='42501';
  end if;

  if trim(coalesce(p_origem_dispositivo,''))='' then
    raise exception 'Origem do dispositivo e obrigatoria.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_produtos,'[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_lotes,'[]'::jsonb)) <> 'array' then
    raise exception 'Contrato de produtos invalido.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'imperium_os_produtos:'||p_empresa_id::text||':'||
      p_ordem_servico_id::text,
      0
    )
  );

  select * into v_os
  from public.imperium_ordens_servico
  where empresa_id=p_empresa_id
    and id=p_ordem_servico_id
    and excluido_em is null
  for update;

  if not found then
    raise exception 'OS nao encontrada.' using errcode='P0002';
  end if;

  if v_os.status='Cancelada' then
    raise exception 'OS cancelada nao aceita contrato de produtos.'
      using errcode='22023';
  end if;

  if v_os.status='Finalizada' and exists(
    select 1
    from public.imperium_os_finalizacoes_web f
    where f.empresa_id=p_empresa_id
      and f.ordem_servico_id=p_ordem_servico_id
  ) then
    raise exception 'Produtos de uma OS finalizada pelo Web sao imutaveis.'
      using errcode='40001';
  end if;

  select * into v_estado
  from public.imperium_ordem_servico_produtos_estado
  where empresa_id=p_empresa_id
    and ordem_servico_id=p_ordem_servico_id
  for update;

  v_estado_existe := found;

  if v_estado_existe then
    if p_estado_atualizado_em is null
       or v_estado.atualizado_em is distinct from p_estado_atualizado_em then
      raise exception
        'Produtos da OS mudaram em outro dispositivo. Atualize antes de salvar.'
        using errcode='40001';
    end if;

    update public.imperium_ordem_servico_produtos_estado
    set pronto=false
    where empresa_id=p_empresa_id
      and ordem_servico_id=p_ordem_servico_id;
  else
    if p_estado_atualizado_em is not null then
      raise exception 'Estado de produtos foi criado em outro dispositivo.'
        using errcode='40001';
    end if;

    insert into public.imperium_ordem_servico_produtos_estado(
      empresa_id,
      ordem_servico_id,
      contrato_hash,
      pronto,
      origem_dispositivo,
      origem_os_local_id
    ) values (
      p_empresa_id,
      p_ordem_servico_id,
      coalesce(p_contrato_hash,''),
      false,
      p_origem_dispositivo,
      p_origem_os_local_id
    );
  end if;

  for v_item in
    select value
    from jsonb_array_elements(coalesce(p_produtos,'[]'::jsonb))
  loop
    v_id := null;

    if nullif(v_item->>'id','') is not null then
      begin
        v_id := (v_item->>'id')::uuid;
      exception when others then
        raise exception 'ID de produto invalido.' using errcode='22023';
      end;
    end if;

    begin
      v_origem_local_id := (v_item->>'origem_local_id')::bigint;
    exception when others then
      v_origem_local_id := null;
    end;

    if coalesce((v_item->>'quantidade')::numeric,0) < 0 then
      raise exception 'Quantidade de produto invalida.' using errcode='22023';
    end if;

    if v_id is not null then
      update public.imperium_ordem_servico_produtos p
      set item_estoque_id=nullif(v_item->>'item_estoque_id','')::uuid,
          produto_nome=coalesce(v_item->>'produto_nome','Produto'),
          quantidade=coalesce((v_item->>'quantidade')::numeric,0),
          unidade=coalesce(v_item->>'unidade',''),
          custo_unitario=coalesce((v_item->>'custo_unitario')::numeric,0),
          custo_unitario_no_momento=
            coalesce((v_item->>'custo_unitario_no_momento')::numeric,0),
          custo_total_no_momento=
            coalesce((v_item->>'custo_total_no_momento')::numeric,0),
          composicao_lotes_json=
            coalesce(v_item->'composicao_lotes_json','[]'::jsonb),
          baixado_estoque=
            coalesce((v_item->>'baixado_estoque')::boolean,false),
          excluido_em=null
      where p.empresa_id=p_empresa_id
        and p.ordem_servico_id=p_ordem_servico_id
        and p.id=v_id
      returning p.id into v_produto_id;

      if v_produto_id is null then
        raise exception 'Produto remoto nao pertence a OS.'
          using errcode='40001';
      end if;
    else
      if v_origem_local_id is null or v_origem_local_id <= 0 then
        raise exception 'Origem local do produto e obrigatoria.'
          using errcode='22023';
      end if;

      select p.id into v_produto_id
      from public.imperium_ordem_servico_produtos p
      where p.empresa_id=p_empresa_id
        and p.origem_dispositivo=p_origem_dispositivo
        and p.origem_local_id=v_origem_local_id
      for update;

      if found then
        update public.imperium_ordem_servico_produtos p
        set ordem_servico_id=p_ordem_servico_id,
            item_estoque_id=nullif(v_item->>'item_estoque_id','')::uuid,
            produto_nome=coalesce(v_item->>'produto_nome','Produto'),
            quantidade=coalesce((v_item->>'quantidade')::numeric,0),
            unidade=coalesce(v_item->>'unidade',''),
            custo_unitario=coalesce((v_item->>'custo_unitario')::numeric,0),
            custo_unitario_no_momento=
              coalesce((v_item->>'custo_unitario_no_momento')::numeric,0),
            custo_total_no_momento=
              coalesce((v_item->>'custo_total_no_momento')::numeric,0),
            composicao_lotes_json=
              coalesce(v_item->'composicao_lotes_json','[]'::jsonb),
            baixado_estoque=
              coalesce((v_item->>'baixado_estoque')::boolean,false),
            excluido_em=null
        where p.id=v_produto_id;
      else
        insert into public.imperium_ordem_servico_produtos(
          empresa_id,
          ordem_servico_id,
          item_estoque_id,
          origem_dispositivo,
          origem_local_id,
          produto_nome,
          quantidade,
          unidade,
          custo_unitario,
          custo_unitario_no_momento,
          custo_total_no_momento,
          composicao_lotes_json,
          baixado_estoque
        ) values (
          p_empresa_id,
          p_ordem_servico_id,
          nullif(v_item->>'item_estoque_id','')::uuid,
          p_origem_dispositivo,
          v_origem_local_id,
          coalesce(v_item->>'produto_nome','Produto'),
          coalesce((v_item->>'quantidade')::numeric,0),
          coalesce(v_item->>'unidade',''),
          coalesce((v_item->>'custo_unitario')::numeric,0),
          coalesce((v_item->>'custo_unitario_no_momento')::numeric,0),
          coalesce((v_item->>'custo_total_no_momento')::numeric,0),
          coalesce(v_item->'composicao_lotes_json','[]'::jsonb),
          coalesce((v_item->>'baixado_estoque')::boolean,false)
        )
        returning id into v_produto_id;
      end if;
    end if;

    v_ids := array_append(v_ids,v_produto_id);
  end loop;

  update public.imperium_ordem_servico_produtos p
  set excluido_em=now()
  where p.empresa_id=p_empresa_id
    and p.ordem_servico_id=p_ordem_servico_id
    and p.excluido_em is null
    and not (p.id = any(v_ids));

  for v_lote in
    select value
    from jsonb_array_elements(coalesce(p_lotes,'[]'::jsonb))
  loop
    begin
      v_origem_local_id :=
        (v_lote->>'produto_origem_local_id')::bigint;
    exception when others then
      v_origem_local_id := null;
    end;

    v_produto_id := public.imperium_os_produto_resolver_v4(
      p_empresa_id,
      p_ordem_servico_id,
      nullif(v_lote->>'produto_id','')::uuid,
      p_origem_dispositivo,
      v_origem_local_id
    );

    if v_produto_id is null then
      raise exception 'Produto da composicao FIFO nao encontrado.'
        using errcode='22023';
    end if;

    insert into public.imperium_ordem_servico_produto_lotes(
      empresa_id,
      ordem_servico_produto_id,
      ordem_servico_id,
      item_estoque_id,
      lote_id,
      origem_dispositivo,
      origem_local_id,
      quantidade,
      custo_unitario,
      custo_total
    ) values (
      p_empresa_id,
      v_produto_id,
      p_ordem_servico_id,
      (v_lote->>'item_estoque_id')::uuid,
      (v_lote->>'lote_id')::uuid,
      p_origem_dispositivo,
      (v_lote->>'origem_local_id')::bigint,
      (v_lote->>'quantidade')::numeric,
      coalesce((v_lote->>'custo_unitario')::numeric,0),
      coalesce((v_lote->>'custo_total')::numeric,0)
    )
    on conflict (empresa_id,origem_dispositivo,origem_local_id)
    do update set
      quantidade=excluded.quantidade,
      custo_unitario=excluded.custo_unitario,
      custo_total=excluded.custo_total;
  end loop;

  update public.imperium_ordem_servico_produtos_estado
  set contrato_hash=coalesce(p_contrato_hash,''),
      pronto=true,
      origem_dispositivo=p_origem_dispositivo,
      origem_os_local_id=p_origem_os_local_id
  where empresa_id=p_empresa_id
    and ordem_servico_id=p_ordem_servico_id
  returning * into v_estado;

  return jsonb_build_object(
    'estado',
    to_jsonb(v_estado),
    'produtos',
    (
      select coalesce(
        jsonb_agg(to_jsonb(p) order by p.id),
        '[]'::jsonb
      )
      from public.imperium_ordem_servico_produtos p
      where p.empresa_id=p_empresa_id
        and p.ordem_servico_id=p_ordem_servico_id
        and p.excluido_em is null
    )
  );
end;
$$;

revoke all on function public.imperium_os_produtos_publicar_v4(
  uuid,uuid,timestamptz,text,jsonb,jsonb,text,bigint
) from public, anon;
grant execute on function public.imperium_os_produtos_publicar_v4(
  uuid,uuid,timestamptz,text,jsonb,jsonb,text,bigint
) to authenticated;

-- Evita segunda baixa quando o FIFO ja foi executado pela finalizacao Web.
create or replace function public.imperium_estoque_consumir_reserva_os(
  p_empresa_id uuid,
  p_ordem_servico_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_novo_saldo numeric;
  v_atualizado_em timestamptz;
  v_result jsonb := '[]'::jsonb;
  v_fifo_web boolean := false;
begin
  if (select auth.uid()) is null
     or not private.imperium_pode_modulo(p_empresa_id, 'estoque') then
    raise exception
      using errcode = '42501',
      message = 'Sem permissao para consumir reserva de estoque.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('imperium_estoque:' || p_empresa_id::text)::bigint
  );

  select exists(
    select 1
    from public.imperium_ordens_servico os
    join public.imperium_ordem_servico_produtos_estado pe
      on pe.empresa_id=os.empresa_id
     and pe.ordem_servico_id=os.id
     and pe.pronto
    where os.empresa_id=p_empresa_id
      and os.id=p_ordem_servico_id
      and os.status='Finalizada'
      and not exists (
        select 1
        from public.imperium_ordem_servico_produtos p
        where p.empresa_id=p_empresa_id
          and p.ordem_servico_id=p_ordem_servico_id
          and p.excluido_em is null
          and not p.baixado_estoque
      )
  ) into v_fifo_web;

  if v_fifo_web then
    update public.imperium_estoque_reservas_os
    set status='Consumida',
        consumida_em=now(),
        atualizado_em=now(),
        liberada_em=null
    where empresa_id=p_empresa_id
      and ordem_servico_id=p_ordem_servico_id
      and status='Ativa';

    return jsonb_build_object(
      'status','ja_consumida',
      'origem','fifo_web',
      'itens','[]'::jsonb
    );
  end if;

  if not exists (
    select 1
    from public.imperium_estoque_reservas_os ro
    where ro.empresa_id=p_empresa_id
      and ro.ordem_servico_id=p_ordem_servico_id
      and ro.status='Ativa'
  ) then
    if exists (
      select 1
      from public.imperium_estoque_reservas_os ro
      where ro.empresa_id=p_empresa_id
        and ro.ordem_servico_id=p_ordem_servico_id
        and ro.status='Consumida'
    ) then
      return jsonb_build_object(
        'status','ja_consumida',
        'itens','[]'::jsonb
      );
    end if;

    return jsonb_build_object(
      'status','sem_reserva',
      'itens','[]'::jsonb
    );
  end if;

  for r in
    select ro.id,ro.item_estoque_id,ro.quantidade
    from public.imperium_estoque_reservas_os ro
    where ro.empresa_id=p_empresa_id
      and ro.ordem_servico_id=p_ordem_servico_id
      and ro.status='Ativa'
    order by ro.item_estoque_id
  loop
    select i.quantidade
    into v_novo_saldo
    from public.imperium_estoque_itens i
    where i.empresa_id=p_empresa_id
      and i.id=r.item_estoque_id
      and i.excluido_em is null
      and i.ativo
    for update;

    if v_novo_saldo is null then
      raise exception
        using errcode='P0001',
        message='Item remoto reservado nao existe mais ou esta inativo.';
    end if;

    if r.quantidade > v_novo_saldo + 0.000001 then
      raise exception
        using errcode='P0001',
        message='Saldo remoto ficou insuficiente antes do consumo da reserva.';
    end if;

    update public.imperium_estoque_itens
    set quantidade=greatest(quantidade-r.quantidade,0),
        atualizado_em=now()
    where empresa_id=p_empresa_id
      and id=r.item_estoque_id
    returning quantidade,atualizado_em
    into v_novo_saldo,v_atualizado_em;

    update public.imperium_estoque_reservas_os
    set status='Consumida',
        consumida_em=now(),
        atualizado_em=now(),
        liberada_em=null
    where id=r.id;

    v_result:=v_result||jsonb_build_array(
      jsonb_build_object(
        'item_estoque_id',r.item_estoque_id,
        'quantidade_consumida',r.quantidade,
        'quantidade_posterior',v_novo_saldo,
        'atualizado_em',v_atualizado_em
      )
    );
  end loop;

  return jsonb_build_object(
    'status','consumida',
    'itens',v_result
  );
end;
$$;

-- Finalizacao Web exactly-once.
create or replace function public.imperium_os_finalizar_web_v4(
  p_empresa_id uuid,
  p_ordem_id uuid,
  p_os_atualizado_em timestamptz,
  p_produtos_atualizado_em timestamptz,
  p_idempotency_key text,
  p_origem_dispositivo text,
  p_origem_base bigint,
  p_entrada timestamptz,
  p_saida timestamptz,
  p_forma_pagamento text default null,
  p_valor_pagamento numeric default null,
  p_data_pagamento timestamptz default null,
  p_vencimento_pagamento text default null,
  p_conta_id uuid default null,
  p_parcelas_taxa bigint default 1,
  p_timezone text default 'America/Sao_Paulo'
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_os public.imperium_ordens_servico%rowtype;
  v_estado public.imperium_ordem_servico_produtos_estado%rowtype;
  v_exist public.imperium_os_finalizacoes_web%rowtype;
  v_prod record;
  v_lote record;
  v_item record;
  v_colab record;
  v_regra record;
  v_pagamento_id uuid;
  v_plano_receita uuid;
  v_plano_taxa uuid;
  v_conta_recebimento uuid;
  v_valor_inicial numeric;
  v_pagamento_base numeric;
  v_valor_cobrado numeric;
  v_taxa numeric:=0;
  v_taxa_percentual numeric:=null;
  v_repasse numeric:=0;
  v_regra_id uuid:=null;
  v_regra_origem_local bigint:=null;
  v_recebido numeric:=0;
  v_saldo numeric:=0;
  v_status_pagamento text;
  v_data_entrada text;
  v_hora_entrada text;
  v_data_saida text;
  v_hora_saida text;
  v_data_pagamento text;
  v_saida_local text;
  v_horas numeric:=0;
  v_custo_hora numeric:=0;
  v_custo_mensal numeric:=0;
  v_horas_mes numeric:=220;
  v_reservado_outros numeric;
  v_disponivel_lotes numeric;
  v_restante numeric;
  v_usar numeric;
  v_saldo_item numeric;
  v_saldo_lote numeric;
  v_custo_total_prod numeric;
  v_composicao jsonb;
  v_seq bigint:=0;
  v_request_hash text;
  v_result jsonb;
  v_estoque_result jsonb;
  v_forma text:=trim(coalesce(p_forma_pagamento,''));
  v_parcelas bigint:=greatest(1,least(coalesce(p_parcelas_taxa,1),12));
  v_ajuste_id uuid:=null;
  v_agora timestamptz:=clock_timestamp();
begin
  if not private.imperium_pode_modulo(p_empresa_id,'ordens_servico')
     or not private.imperium_pode_modulo(p_empresa_id,'estoque')
     or not private.imperium_pode_modulo(p_empresa_id,'financeiro')
     or not private.imperium_pode_modulo(p_empresa_id,'precificacao') then
    raise exception
      'Finalizacao Web exige acesso a OS, Estoque, Financeiro e Precificacao.'
      using errcode='42501';
  end if;

  if trim(coalesce(p_idempotency_key,''))=''
     or trim(coalesce(p_origem_dispositivo,''))=''
     or coalesce(p_origem_base,0)<=0 then
    raise exception 'Chave de idempotencia e origem Web sao obrigatorias.'
      using errcode='22023';
  end if;

  if p_entrada is null or p_saida is null or p_saida < p_entrada then
    raise exception 'Periodo operacional invalido.' using errcode='22023';
  end if;

  if not exists(
    select 1 from pg_timezone_names where name=p_timezone
  ) then
    raise exception 'Timezone invalido.' using errcode='22023';
  end if;

  v_request_hash:=md5(
    jsonb_build_object(
      'empresa',p_empresa_id,
      'os',p_ordem_id,
      'os_ts',p_os_atualizado_em,
      'prod_ts',p_produtos_atualizado_em,
      'entrada',p_entrada,
      'saida',p_saida,
      'forma',v_forma,
      'valor',p_valor_pagamento,
      'pagamento_em',p_data_pagamento,
      'vencimento',p_vencimento_pagamento,
      'conta',p_conta_id,
      'parcelas',v_parcelas,
      'timezone',p_timezone
    )::text
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      'imperium_os_finalizar:'||p_empresa_id::text||':'||p_ordem_id::text,
      0
    )
  );

  select * into v_exist
  from public.imperium_os_finalizacoes_web
  where empresa_id=p_empresa_id
    and idempotency_key=p_idempotency_key;

  if found then
    if v_exist.request_hash<>v_request_hash then
      raise exception
        'Chave de idempotencia reutilizada com dados diferentes.'
        using errcode='40001';
    end if;
    return v_exist.resultado_json;
  end if;

  select * into v_exist
  from public.imperium_os_finalizacoes_web
  where empresa_id=p_empresa_id
    and ordem_servico_id=p_ordem_id;

  if found then
    if v_exist.request_hash=v_request_hash then
      return v_exist.resultado_json;
    end if;
    raise exception 'Esta OS ja possui uma finalizacao Web registrada.'
      using errcode='40001';
  end if;

  select * into v_os
  from public.imperium_ordens_servico
  where empresa_id=p_empresa_id
    and id=p_ordem_id
    and excluido_em is null
  for update;

  if not found then
    raise exception 'OS nao encontrada.' using errcode='P0002';
  end if;

  if v_os.status<>'Em andamento' then
    raise exception 'A OS precisa estar Em andamento para finalizar.'
      using errcode='22023';
  end if;

  if p_os_atualizado_em is null
     or v_os.atualizado_em is distinct from p_os_atualizado_em then
    raise exception
      'A OS mudou em outro dispositivo. Atualize antes de finalizar.'
      using errcode='40001';
  end if;

  select * into v_estado
  from public.imperium_ordem_servico_produtos_estado
  where empresa_id=p_empresa_id
    and ordem_servico_id=p_ordem_id
  for update;

  if not found or not v_estado.pronto then
    raise exception 'Contrato de produtos da OS ainda nao esta pronto.'
      using errcode='22023';
  end if;

  if p_produtos_atualizado_em is null
     or v_estado.atualizado_em is distinct from p_produtos_atualizado_em then
    raise exception
      'Produtos da OS mudaram em outro dispositivo. Atualize antes de finalizar.'
      using errcode='40001';
  end if;

  if exists(
    select 1
    from public.imperium_ordem_servico_produtos p
    where p.empresa_id=p_empresa_id
      and p.ordem_servico_id=p_ordem_id
      and p.excluido_em is null
      and p.baixado_estoque
  ) then
    raise exception
      'A OS ja possui produto marcado como baixado antes da finalizacao.'
      using errcode='40001';
  end if;

  v_valor_inicial:=greatest(
    greatest(
      coalesce(v_os.valor_total,0)-coalesce(v_os.desconto,0),
      0
    )
    -coalesce(v_os.desconto_negociacao,0)
    +coalesce(v_os.acrescimo_negociacao,0)
    +coalesce(v_os.juros_parcelamento,0),
    0
  );

  v_pagamento_base:=coalesce(
    p_valor_pagamento,
    case when v_forma<>'' then v_valor_inicial else 0 end
  );

  if v_pagamento_base<0
     or v_pagamento_base>v_valor_inicial+0.000001 then
    raise exception 'Valor recebido invalido para esta OS.'
      using errcode='22023';
  end if;

  if v_pagamento_base>0.000001 and v_forma='' then
    raise exception 'Informe a forma de pagamento.' using errcode='22023';
  end if;

  v_valor_cobrado:=v_pagamento_base;
  v_conta_recebimento:=p_conta_id;

  if v_pagamento_base>0.000001
     and v_forma in ('Cartão de crédito','Cartão de débito') then
    select r.* into v_regra
    from public.imperium_financeiro_regras_taxa r
    where r.empresa_id=p_empresa_id
      and r.ativo
      and r.excluido_em is null
      and r.forma_pagamento=v_forma
      and r.parcelas=v_parcelas
      and (
        p_conta_id is null
        or r.conta_id=p_conta_id
        or r.conta_id is null
      )
    order by
      case
        when p_conta_id is not null and r.conta_id=p_conta_id then 0
        when r.conta_id is not null then 1
        else 2
      end,
      r.prioridade desc,
      r.id desc
    limit 1;

    if found then
      v_regra_id:=v_regra.id;
      v_regra_origem_local:=v_regra.origem_local_id;
      v_taxa_percentual:=coalesce(v_regra.taxa_percentual,0);
      v_conta_recebimento:=coalesce(v_regra.conta_id,p_conta_id);

      if coalesce(v_regra.repassar_cliente,false) then
        if v_taxa_percentual>=100 then
          raise exception 'Taxa de cartao invalida.' using errcode='22023';
        end if;

        v_valor_cobrado:=ceil(
          (
            (v_pagamento_base+coalesce(v_regra.taxa_fixa,0))
            /(1-v_taxa_percentual/100)
          )*100
        )/100;

        v_repasse:=greatest(v_valor_cobrado-v_pagamento_base,0);
      end if;

      v_taxa:=least(
        round(
          v_valor_cobrado*v_taxa_percentual/100+
          coalesce(v_regra.taxa_fixa,0),
          2
        ),
        v_valor_cobrado
      );
    end if;
  end if;

  if v_valor_cobrado>0.000001 then
    if v_conta_recebimento is null then
      raise exception 'Informe a conta financeira do recebimento.'
        using errcode='22023';
    end if;

    perform 1
    from public.imperium_financeiro_contas c
    where c.empresa_id=p_empresa_id
      and c.id=v_conta_recebimento
      and c.ativo
      and c.excluido_em is null;

    if not found then
      raise exception 'Conta financeira invalida ou inativa.'
        using errcode='22023';
    end if;
  end if;

  perform pg_advisory_xact_lock(
    hashtext('imperium_estoque:'||p_empresa_id::text)::bigint
  );

  for v_item in
    select p.item_estoque_id,sum(p.quantidade) quantidade
    from public.imperium_ordem_servico_produtos p
    where p.empresa_id=p_empresa_id
      and p.ordem_servico_id=p_ordem_id
      and p.excluido_em is null
      and p.item_estoque_id is not null
      and p.quantidade>0
    group by p.item_estoque_id
    order by p.item_estoque_id
  loop
    perform 1
    from public.imperium_estoque_itens i
    where i.empresa_id=p_empresa_id
      and i.id=v_item.item_estoque_id
      and i.ativo
      and i.excluido_em is null
    for update;

    if not found then
      raise exception 'Produto da OS nao existe mais no estoque.'
        using errcode='P0001';
    end if;

    select i.quantidade into v_saldo_item
    from public.imperium_estoque_itens i
    where i.empresa_id=p_empresa_id
      and i.id=v_item.item_estoque_id;

    select coalesce(sum(r.quantidade),0)
    into v_reservado_outros
    from public.imperium_estoque_reservas_os r
    where r.empresa_id=p_empresa_id
      and r.item_estoque_id=v_item.item_estoque_id
      and r.status='Ativa'
      and r.ordem_servico_id<>p_ordem_id;

    if v_item.quantidade >
       greatest(v_saldo_item-v_reservado_outros,0)+0.000001 then
      raise exception
        'Estoque insuficiente considerando reservas de outras OS.'
        using errcode='P0001';
    end if;

    perform 1
    from public.imperium_estoque_lotes l
    where l.empresa_id=p_empresa_id
      and l.item_estoque_id=v_item.item_estoque_id
      and l.ativo
      and l.excluido_em is null
      and l.quantidade_disponivel>0
    order by l.data_compra,l.id
    for update;

    select coalesce(sum(l.quantidade_disponivel),0)
    into v_disponivel_lotes
    from public.imperium_estoque_lotes l
    where l.empresa_id=p_empresa_id
      and l.item_estoque_id=v_item.item_estoque_id
      and l.ativo
      and l.excluido_em is null
      and l.quantidade_disponivel>0;

    if v_item.quantidade > v_disponivel_lotes+0.000001 then
      raise exception 'Lotes insuficientes para baixa FIFO.'
        using errcode='P0001';
    end if;
  end loop;

  v_data_entrada:=to_char(
    p_entrada at time zone p_timezone,
    'YYYY-MM-DD'
  );
  v_hora_entrada:=to_char(
    p_entrada at time zone p_timezone,
    'HH24:MI'
  );
  v_data_saida:=to_char(
    p_saida at time zone p_timezone,
    'YYYY-MM-DD'
  );
  v_hora_saida:=to_char(
    p_saida at time zone p_timezone,
    'HH24:MI'
  );
  v_saida_local:=to_char(
    p_saida at time zone p_timezone,
    'YYYY-MM-DD"T"HH24:MI:SS'
  );
  v_data_pagamento:=to_char(
    coalesce(p_data_pagamento,p_saida) at time zone p_timezone,
    'YYYY-MM-DD"T"HH24:MI:SS'
  );

  for v_prod in
    select *
    from public.imperium_ordem_servico_produtos p
    where p.empresa_id=p_empresa_id
      and p.ordem_servico_id=p_ordem_id
      and p.excluido_em is null
    order by p.id
    for update
  loop
    if v_prod.item_estoque_id is null or v_prod.quantidade<=0 then
      update public.imperium_ordem_servico_produtos
      set baixado_estoque=true,
          composicao_lotes_json='[]'::jsonb
      where id=v_prod.id;
      continue;
    end if;

    v_restante:=v_prod.quantidade;
    v_custo_total_prod:=0;
    v_composicao:='[]'::jsonb;

    while v_restante>0.000001 loop
      select * into v_lote
      from public.imperium_estoque_lotes l
      where l.empresa_id=p_empresa_id
        and l.item_estoque_id=v_prod.item_estoque_id
        and l.ativo
        and l.excluido_em is null
        and l.quantidade_disponivel>0
      order by l.data_compra,l.id
      limit 1
      for update;

      if not found then
        raise exception 'Falha na baixa FIFO da OS.' using errcode='P0001';
      end if;

      v_usar:=least(v_restante,v_lote.quantidade_disponivel);

      select quantidade into v_saldo_item
      from public.imperium_estoque_itens
      where empresa_id=p_empresa_id
        and id=v_prod.item_estoque_id
      for update;

      v_saldo_lote:=greatest(v_lote.quantidade_disponivel-v_usar,0);

      update public.imperium_estoque_lotes
      set quantidade_disponivel=v_saldo_lote
      where empresa_id=p_empresa_id
        and id=v_lote.id;

      update public.imperium_estoque_itens
      set quantidade=greatest(quantidade-v_usar,0),
          atualizado_em=clock_timestamp()
      where empresa_id=p_empresa_id
        and id=v_prod.item_estoque_id;

      v_seq:=v_seq+1;

      insert into public.imperium_ordem_servico_produto_lotes(
        empresa_id,
        ordem_servico_produto_id,
        ordem_servico_id,
        item_estoque_id,
        lote_id,
        origem_dispositivo,
        origem_local_id,
        quantidade,
        custo_unitario,
        custo_total
      ) values (
        p_empresa_id,
        v_prod.id,
        p_ordem_id,
        v_prod.item_estoque_id,
        v_lote.id,
        p_origem_dispositivo,
        p_origem_base+100000+v_seq,
        v_usar,
        v_lote.custo_unitario,
        v_usar*v_lote.custo_unitario
      )
      on conflict (empresa_id,ordem_servico_produto_id,lote_id)
      do nothing;

      insert into public.imperium_estoque_movimentacoes(
        empresa_id,
        item_estoque_id,
        lote_id,
        ordem_servico_id,
        origem_dispositivo,
        origem_local_id,
        tipo,
        quantidade,
        quantidade_anterior,
        quantidade_posterior,
        custo_unitario,
        observacoes,
        motivo,
        origem,
        origem_ordem_servico_local_id,
        data,
        origem_criado_em
      ) values (
        p_empresa_id,
        v_prod.item_estoque_id,
        v_lote.id,
        p_ordem_id,
        p_origem_dispositivo,
        p_origem_base+200000+v_seq,
        'SAIDA',
        v_usar,
        v_saldo_item,
        greatest(v_saldo_item-v_usar,0),
        v_lote.custo_unitario,
        'Baixa automatica FIFO da Ordem de Servico '||v_os.numero,
        '',
        'Ordem de Serviço',
        v_os.origem_local_id,
        v_saida_local,
        v_agora::text
      );

      v_custo_total_prod:=
        v_custo_total_prod+v_usar*v_lote.custo_unitario;

      v_composicao:=v_composicao||jsonb_build_array(
        jsonb_build_object(
          'lote_id',v_lote.id,
          'quantidade',v_usar,
          'custo_unitario',v_lote.custo_unitario,
          'custo_total',v_usar*v_lote.custo_unitario
        )
      );

      v_restante:=v_restante-v_usar;
    end loop;

    update public.imperium_ordem_servico_produtos
    set custo_unitario_no_momento=
          case
            when v_prod.quantidade>0
              then v_custo_total_prod/v_prod.quantidade
            else 0
          end,
        custo_total_no_momento=v_custo_total_prod,
        composicao_lotes_json=v_composicao,
        baixado_estoque=true
    where id=v_prod.id;
  end loop;

  if v_repasse>0.000001 then
    update public.imperium_ordens_servico
    set acrescimo_negociacao=
      coalesce(acrescimo_negociacao,0)+v_repasse
    where empresa_id=p_empresa_id
      and id=p_ordem_id
    returning * into v_os;
  end if;

  v_valor_inicial:=greatest(
    greatest(
      coalesce(v_os.valor_total,0)-coalesce(v_os.desconto,0),
      0
    )
    -coalesce(v_os.desconto_negociacao,0)
    +coalesce(v_os.acrescimo_negociacao,0)
    +coalesce(v_os.juros_parcelamento,0),
    0
  );

  v_recebido:=
    case when v_valor_cobrado>0 then v_valor_cobrado else 0 end;
  v_saldo:=greatest(v_valor_inicial-v_recebido,0);

  if v_valor_inicial<=0.000001 or v_saldo<=0.000001 then
    v_status_pagamento:='Pago';
  elsif v_recebido>0.000001 then
    v_status_pagamento:='Parcialmente pago';
  else
    v_status_pagamento:='Pendente';
  end if;

  update public.imperium_ordens_servico
  set status='Finalizada',
      data_inicio=v_data_entrada,
      hora_entrada=v_hora_entrada,
      data_finalizacao=v_data_saida,
      hora_saida=v_hora_saida,
      status_pagamento=v_status_pagamento,
      valor_recebido=v_recebido,
      vencimento_pagamento=
        nullif(trim(coalesce(p_vencimento_pagamento,'')),''),
      pagamento_atualizado_em=v_agora,
      forma_pagamento=
        case when v_valor_cobrado>0 then v_forma else null end
  where empresa_id=p_empresa_id
    and id=p_ordem_id
  returning * into v_os;

  update public.imperium_ordem_servico_produtos_estado
  set contrato_hash=
        md5(
          coalesce(contrato_hash,'')||
          ':finalizado:'||
          p_idempotency_key
        ),
      pronto=true
  where empresa_id=p_empresa_id
    and ordem_servico_id=p_ordem_id
  returning * into v_estado;

  if v_os.agendamento_id is not null
     and private.imperium_pode_modulo(p_empresa_id,'agenda') then
    update public.imperium_agendamentos
    set status='Finalizado'
    where empresa_id=p_empresa_id
      and id=v_os.agendamento_id
      and excluido_em is null;
  end if;

  v_horas:=extract(epoch from (p_saida-p_entrada))/3600.0;

  if v_horas>0.000001 then
    select coalesce(
      sum(
        remuneracao_mensal+
        encargos_mensais+
        outros_custos_mensais
      ),
      0
    )
    into v_custo_mensal
    from public.imperium_precificacao_colaboradores_custo c
    where c.empresa_id=p_empresa_id
      and c.ativo
      and c.excluido_em is null;

    select coalesce(nullif(horas_produtivas_mes,0),220)
    into v_horas_mes
    from public.imperium_precificacao_config pc
    where pc.empresa_id=p_empresa_id;

    v_horas_mes:=coalesce(nullif(v_horas_mes,0),220);
    v_custo_hora:=
      case when v_horas_mes>0 then v_custo_mensal/v_horas_mes else 0 end;

    select c.* into v_colab
    from public.imperium_precificacao_colaboradores_custo c
    where c.empresa_id=p_empresa_id
      and c.ativo
      and c.excluido_em is null
      and lower(trim(c.nome))=
          lower(trim(v_os.funcionario_responsavel))
    order by c.id
    limit 1;

    insert into public.imperium_financeiro_os_mao_obra(
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
      origem_criado_em,
      origem_atualizado_em
    ) values (
      p_empresa_id,
      p_ordem_id,
      case when found then v_colab.id else null end,
      p_origem_dispositivo,
      p_origem_base+300001,
      case
        when trim(coalesce(v_os.funcionario_responsavel,''))=''
          then 'Responsável não informado'
        else trim(v_os.funcionario_responsavel)
      end,
      v_horas,
      v_custo_hora,
      v_horas*v_custo_hora,
      v_saida_local,
      'AUTO_OS_FINALIZACAO',
      true,
      v_agora::text,
      v_agora::text
    );
  end if;

  v_estoque_result:=
    public.imperium_estoque_consumir_reserva_os(
      p_empresa_id,
      p_ordem_id
    );

  if v_valor_cobrado>0.000001 then
    select id into v_plano_receita
    from public.imperium_financeiro_plano_contas
    where empresa_id=p_empresa_id
      and codigo='1.01'
      and ativo
      and excluido_em is null
    limit 1;

    select id into v_plano_taxa
    from public.imperium_financeiro_plano_contas
    where empresa_id=p_empresa_id
      and codigo='2.02.01'
      and ativo
      and excluido_em is null
    limit 1;

    insert into public.imperium_financeiro_pagamentos_os(
      empresa_id,
      ordem_servico_id,
      origem_dispositivo,
      origem_local_id,
      status,
      valor,
      forma_pagamento,
      data_pagamento,
      observacoes,
      taxa_percentual,
      taxa_operacao,
      valor_liquido,
      regra_taxa_id,
      origem_regra_taxa_local_id,
      parcelas_taxa,
      origem_criado_em,
      origem_atualizado_em
    ) values (
      p_empresa_id,
      p_ordem_id,
      p_origem_dispositivo,
      p_origem_base+400001,
      'Pago',
      v_valor_cobrado,
      v_forma,
      v_data_pagamento,
      'Finalizacao Web',
      v_taxa_percentual,
      v_taxa,
      v_valor_cobrado-v_taxa,
      v_regra_id,
      v_regra_origem_local,
      v_parcelas,
      v_agora::text,
      v_agora::text
    )
    returning id into v_pagamento_id;

    if v_repasse>0.000001 then
      insert into public.imperium_ordem_servico_ajustes_financeiros(
        empresa_id,
        ordem_servico_id,
        regra_taxa_id,
        pagamento_id,
        origem_dispositivo,
        origem_local_id,
        tipo,
        valor,
        motivo,
        status,
        origem,
        origem_criado_em
      ) values (
        p_empresa_id,
        p_ordem_id,
        v_regra_id,
        v_pagamento_id,
        p_origem_dispositivo,
        p_origem_base+410001,
        'Acréscimo',
        v_repasse,
        'Repasse automático da taxa da maquininha: '||
          coalesce(v_regra.nome,'Regra automática')||'.',
        'Ativo',
        'Taxa de maquininha',
        v_agora::text
      )
      returning id into v_ajuste_id;
    end if;

    insert into public.imperium_financeiro_movimentos(
      empresa_id,
      origem_dispositivo,
      origem_local_id,
      tipo,
      descricao,
      valor,
      forma_pagamento,
      data,
      ordem_servico_id,
      pagamento_id,
      plano_conta_id,
      conta_id,
      origem_ordem_servico_local_id,
      origem_pagamento_local_id,
      natureza,
      origem,
      status,
      data_competencia,
      data_pagamento,
      numero_documento,
      observacoes,
      impacta_dre
    ) values (
      p_empresa_id,
      p_origem_dispositivo,
      p_origem_base+400002,
      'entrada',
      'Pagamento da OS '||v_os.numero,
      v_valor_cobrado,
      v_forma,
      v_data_pagamento,
      p_ordem_id,
      v_pagamento_id,
      v_plano_receita,
      v_conta_recebimento,
      v_os.origem_local_id,
      p_origem_base+400001,
      'Receita operacional',
      'Pagamento de OS',
      'Realizado',
      v_data_pagamento,
      v_data_pagamento,
      '',
      '',
      false
    );

    if v_taxa>0.000001 then
      insert into public.imperium_financeiro_movimentos(
        empresa_id,
        origem_dispositivo,
        origem_local_id,
        tipo,
        descricao,
        valor,
        forma_pagamento,
        data,
        ordem_servico_id,
        pagamento_id,
        plano_conta_id,
        conta_id,
        origem_ordem_servico_local_id,
        origem_pagamento_local_id,
        natureza,
        origem,
        status,
        data_competencia,
        data_pagamento,
        numero_documento,
        observacoes,
        impacta_dre
      ) values (
        p_empresa_id,
        p_origem_dispositivo,
        p_origem_base+400003,
        'saída',
        'Taxa da maquininha - OS '||v_os.numero,
        v_taxa,
        v_forma,
        v_data_pagamento,
        p_ordem_id,
        v_pagamento_id,
        v_plano_taxa,
        v_conta_recebimento,
        v_os.origem_local_id,
        p_origem_base+400001,
        'Custo variável',
        'Taxa de pagamento',
        'Realizado',
        v_data_pagamento,
        v_data_pagamento,
        '',
        '',
        true
      );
    end if;
  end if;

  v_result:=jsonb_build_object(
    'ordem_id',p_ordem_id,
    'status','Finalizada',
    'valor_negociado',v_valor_inicial,
    'valor_recebido',v_recebido,
    'status_pagamento',v_status_pagamento,
    'taxa_operacao',v_taxa,
    'repasse_cliente',v_repasse,
    'pagamento_id',v_pagamento_id,
    'ajuste_id',v_ajuste_id,
    'estoque',v_estoque_result,
    'produtos_estado_atualizado_em',v_estado.atualizado_em
  );

  insert into public.imperium_os_finalizacoes_web(
    empresa_id,
    ordem_servico_id,
    idempotency_key,
    request_hash,
    origem_dispositivo,
    origem_base,
    resultado_json
  ) values (
    p_empresa_id,
    p_ordem_id,
    p_idempotency_key,
    v_request_hash,
    p_origem_dispositivo,
    p_origem_base,
    v_result
  );

  return v_result;
end;
$$;

revoke all on function public.imperium_os_finalizar_web_v4(
  uuid,uuid,timestamptz,timestamptz,text,text,bigint,
  timestamptz,timestamptz,text,numeric,timestamptz,text,uuid,bigint,text
) from public, anon;

grant execute on function public.imperium_os_finalizar_web_v4(
  uuid,uuid,timestamptz,timestamptz,text,text,bigint,
  timestamptz,timestamptz,text,numeric,timestamptz,text,uuid,bigint,text
) to authenticated;

-- Regra financeira oficial: recebimento e caixa, nao nova receita na DRE.
create or replace function private.imperium_fin_pagamento_os_sem_dre()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.origem = 'Pagamento de OS' then
    new.impacta_dre := false;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_imperium_fin_pagamento_os_sem_dre
  on public.imperium_financeiro_movimentos;

create trigger trg_imperium_fin_pagamento_os_sem_dre
before insert or update of origem, impacta_dre
on public.imperium_financeiro_movimentos
for each row
execute function private.imperium_fin_pagamento_os_sem_dre();

update public.imperium_financeiro_movimentos
set impacta_dre = false
where origem = 'Pagamento de OS'
  and impacta_dre is distinct from false;
