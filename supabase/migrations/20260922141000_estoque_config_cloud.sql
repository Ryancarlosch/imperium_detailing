create table if not exists public.imperium_estoque_config (
  empresa_id uuid primary key references public.empresas(id) on delete cascade,
  controlar_estoque boolean not null default true,
  controlar_produtos_ordem_servico boolean not null default false,
  baixa_automatica boolean not null default false,
  exigir_quantidade boolean not null default false,
  alertar_estoque_baixo boolean not null default true,
  estoque_minimo_padrao numeric(18,4) not null default 1,
  origem_dispositivo text,
  origem_atualizado_em text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint imperium_estoque_config_minimo_ck
    check (estoque_minimo_padrao >= 0)
);

alter table public.imperium_estoque_config enable row level security;

revoke all on public.imperium_estoque_config from anon, authenticated;
grant select, insert, update on public.imperium_estoque_config to authenticated;

drop policy if exists imperium_estoque_config_select
  on public.imperium_estoque_config;
create policy imperium_estoque_config_select
  on public.imperium_estoque_config
  for select to authenticated
  using ((select private.imperium_pode_modulo(empresa_id, 'estoque')));

drop policy if exists imperium_estoque_config_insert
  on public.imperium_estoque_config;
create policy imperium_estoque_config_insert
  on public.imperium_estoque_config
  for insert to authenticated
  with check ((select private.imperium_pode_modulo(empresa_id, 'estoque')));

drop policy if exists imperium_estoque_config_update
  on public.imperium_estoque_config;
create policy imperium_estoque_config_update
  on public.imperium_estoque_config
  for update to authenticated
  using ((select private.imperium_pode_modulo(empresa_id, 'estoque')))
  with check ((select private.imperium_pode_modulo(empresa_id, 'estoque')));

create or replace function public.imperium_estoque_salvar_config(
  p_empresa_id uuid,
  p_controlar_estoque boolean,
  p_controlar_produtos_ordem_servico boolean,
  p_baixa_automatica boolean,
  p_exigir_quantidade boolean,
  p_alertar_estoque_baixo boolean,
  p_estoque_minimo_padrao numeric,
  p_origem_dispositivo text,
  p_origem_atualizado_em text,
  p_atualizado_em_base timestamptz default null
)
returns public.imperium_estoque_config
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_atual public.imperium_estoque_config%rowtype;
  v_resultado public.imperium_estoque_config%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Autenticação obrigatória.';
  end if;
  if not private.imperium_pode_modulo(p_empresa_id, 'estoque') then
    raise exception 'Sem permissão para alterar o estoque.';
  end if;
  if coalesce(p_estoque_minimo_padrao, -1) < 0 then
    raise exception 'Estoque mínimo padrão inválido.';
  end if;
  if not coalesce(p_controlar_estoque, false)
     and (
       coalesce(p_controlar_produtos_ordem_servico, false)
       or coalesce(p_baixa_automatica, false)
       or coalesce(p_exigir_quantidade, false)
     ) then
    raise exception 'Recursos de OS exigem controle de estoque ativo.';
  end if;
  if coalesce(p_baixa_automatica, false)
     and not coalesce(p_controlar_produtos_ordem_servico, false) then
    raise exception 'Baixa automática exige produtos nas Ordens de Serviço.';
  end if;
  if coalesce(p_exigir_quantidade, false)
     and not coalesce(p_controlar_produtos_ordem_servico, false) then
    raise exception 'Quantidade obrigatória exige produtos nas Ordens de Serviço.';
  end if;

  select *
    into v_atual
  from public.imperium_estoque_config
  where empresa_id = p_empresa_id
  for update;

  if found then
    if p_atualizado_em_base is not null
       and v_atual.atualizado_em <> p_atualizado_em_base then
      raise exception 'A configuração do estoque mudou em outro dispositivo. Atualize e tente novamente.';
    end if;

    update public.imperium_estoque_config
    set controlar_estoque = coalesce(p_controlar_estoque, true),
        controlar_produtos_ordem_servico =
          coalesce(p_controlar_produtos_ordem_servico, false),
        baixa_automatica = coalesce(p_baixa_automatica, false),
        exigir_quantidade = coalesce(p_exigir_quantidade, false),
        alertar_estoque_baixo = coalesce(p_alertar_estoque_baixo, true),
        estoque_minimo_padrao = p_estoque_minimo_padrao,
        origem_dispositivo =
          nullif(trim(coalesce(p_origem_dispositivo, '')), ''),
        origem_atualizado_em =
          nullif(trim(coalesce(p_origem_atualizado_em, '')), ''),
        atualizado_em = now()
    where empresa_id = p_empresa_id
    returning * into v_resultado;
  else
    insert into public.imperium_estoque_config (
      empresa_id,
      controlar_estoque,
      controlar_produtos_ordem_servico,
      baixa_automatica,
      exigir_quantidade,
      alertar_estoque_baixo,
      estoque_minimo_padrao,
      origem_dispositivo,
      origem_atualizado_em
    ) values (
      p_empresa_id,
      coalesce(p_controlar_estoque, true),
      coalesce(p_controlar_produtos_ordem_servico, false),
      coalesce(p_baixa_automatica, false),
      coalesce(p_exigir_quantidade, false),
      coalesce(p_alertar_estoque_baixo, true),
      p_estoque_minimo_padrao,
      nullif(trim(coalesce(p_origem_dispositivo, '')), ''),
      nullif(trim(coalesce(p_origem_atualizado_em, '')), '')
    )
    returning * into v_resultado;
  end if;

  return v_resultado;
end;
$$;

revoke all on function public.imperium_estoque_salvar_config(
  uuid, boolean, boolean, boolean, boolean, boolean, numeric, text, text,
  timestamptz
) from public, anon;

grant execute on function public.imperium_estoque_salvar_config(
  uuid, boolean, boolean, boolean, boolean, boolean, numeric, text, text,
  timestamptz
) to authenticated;
