-- Snapshot seguro para CRM / Pós-venda / Marketing.
-- Expõe somente dados operacionais mínimos necessários aos módulos comerciais.

create or replace function public.imperium_growth_snapshot(
  p_empresa_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_resultado jsonb;
begin
  if not private.imperium_pode_modulo(p_empresa_id, 'crm') then
    raise exception 'Sem permissão para CRM/Pós-venda/Marketing.'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'clientes',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'nome', c.nome,
          'telefone', c.telefone,
          'email', c.email
        )
        order by c.nome
      )
      from public.imperium_clientes c
      where c.empresa_id = p_empresa_id
        and c.excluido_em is null
        and c.ativo = true
    ), '[]'::jsonb),
    'ordens',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', o.id,
          'cliente_id', o.cliente_id,
          'veiculo_id', o.veiculo_id,
          'numero', o.numero,
          'status', o.status,
          'data_finalizacao', o.data_finalizacao,
          'data_abertura', o.data_abertura,
          'valor_total', o.valor_total,
          'desconto', o.desconto,
          'desconto_negociacao', o.desconto_negociacao,
          'acrescimo_negociacao', o.acrescimo_negociacao,
          'juros_parcelamento', o.juros_parcelamento
        )
      )
      from public.imperium_ordens_servico o
      where o.empresa_id = p_empresa_id
        and o.excluido_em is null
        and lower(coalesce(o.status, '')) = 'finalizada'
    ), '[]'::jsonb),
    'agendamentos',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', a.id,
          'cliente_id', a.cliente_id,
          'veiculo_id', a.veiculo_id,
          'servico', a.servico,
          'data', a.data,
          'hora', a.hora,
          'status', a.status
        )
      )
      from public.imperium_agendamentos a
      where a.empresa_id = p_empresa_id
        and a.excluido_em is null
        and lower(coalesce(a.status, '')) not in (
          'cancelado', 'cancelada', 'concluído', 'concluido', 'finalizado',
          'finalizada'
        )
    ), '[]'::jsonb)
  )
  into v_resultado;

  return v_resultado;
end;
$$;

revoke all on function public.imperium_growth_snapshot(uuid) from public;
grant execute on function public.imperium_growth_snapshot(uuid) to authenticated;
