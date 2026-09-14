-- OS Cloud V4 - recebimento nao duplica DRE + resolver FIFO interoperavel.
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
