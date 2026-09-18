create or replace function public.imperium_migracao_auditoria_v1(
  p_empresa_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = public, private, pg_temp
as $$
begin
  if p_empresa_id is null
     or not private.usuario_admin_empresa(p_empresa_id) then
    raise exception 'Auditoria de migracao restrita ao administrador da empresa.';
  end if;

  return jsonb_build_object(
    'empresa_id', p_empresa_id,
    'gerado_em', now(),

    'clientes_contagem', (
      select count(*)::bigint
      from public.imperium_clientes
      where empresa_id = p_empresa_id
        and excluido_em is null
    ),
    'veiculos_contagem', (
      select count(*)::bigint
      from public.imperium_veiculos
      where empresa_id = p_empresa_id
        and excluido_em is null
    ),
    'ordens_servico_contagem', (
      select count(*)::bigint
      from public.imperium_ordens_servico
      where empresa_id = p_empresa_id
        and excluido_em is null
    ),
    'estoque_itens_contagem', (
      select count(*)::bigint
      from public.imperium_estoque_itens
      where empresa_id = p_empresa_id
        and excluido_em is null
    ),
    'financeiro_movimentos_contagem', (
      select count(*)::bigint
      from public.imperium_financeiro_movimentos
      where empresa_id = p_empresa_id
        and excluido_em is null
    ),
    'pagamentos_os_contagem', (
      select count(*)::bigint
      from public.imperium_financeiro_pagamentos_os
      where empresa_id = p_empresa_id
        and excluido_em is null
    ),

    'estoque_quantidade_total', (
      select coalesce(sum(quantidade), 0)::numeric
      from public.imperium_estoque_itens
      where empresa_id = p_empresa_id
        and excluido_em is null
    ),
    'financeiro_entradas_realizadas', (
      select coalesce(sum(valor), 0)::numeric
      from public.imperium_financeiro_movimentos
      where empresa_id = p_empresa_id
        and excluido_em is null
        and lower(coalesce(status, '')) = 'realizado'
        and lower(coalesce(tipo, '')) = 'entrada'
    ),
    'financeiro_saidas_realizadas', (
      select coalesce(sum(valor), 0)::numeric
      from public.imperium_financeiro_movimentos
      where empresa_id = p_empresa_id
        and excluido_em is null
        and lower(coalesce(status, '')) = 'realizado'
        and lower(coalesce(tipo, '')) in ('saida', 'saída')
    ),
    'pagamentos_os_pagos_total', (
      select coalesce(sum(valor), 0)::numeric
      from public.imperium_financeiro_pagamentos_os
      where empresa_id = p_empresa_id
        and excluido_em is null
        and lower(coalesce(status, '')) = 'pago'
    )
  );
end;
$$;

revoke all on function public.imperium_migracao_auditoria_v1(uuid)
  from public, anon;
grant execute on function public.imperium_migracao_auditoria_v1(uuid)
  to authenticated;
