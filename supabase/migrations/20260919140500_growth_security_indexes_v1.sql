-- Hardening Pós-venda / Marketing V1

revoke execute on function public.imperium_growth_snapshot(uuid) from public;
revoke execute on function public.imperium_growth_snapshot(uuid) from anon;
grant execute on function public.imperium_growth_snapshot(uuid) to authenticated;

create index if not exists idx_imperium_pos_venda_interacoes_os
  on public.imperium_pos_venda_interacoes
  (empresa_id, ordem_servico_id)
  where ordem_servico_id is not null;

create index if not exists idx_imperium_marketing_publicacoes_campanha
  on public.imperium_marketing_publicacoes
  (empresa_id, campanha_id)
  where campanha_id is not null;

create index if not exists idx_imperium_marketing_atribuicoes_lead
  on public.imperium_marketing_atribuicoes
  (empresa_id, lead_id)
  where lead_id is not null;

create index if not exists idx_imperium_marketing_atribuicoes_cliente
  on public.imperium_marketing_atribuicoes
  (empresa_id, cliente_id)
  where cliente_id is not null;

create index if not exists idx_imperium_marketing_atribuicoes_os
  on public.imperium_marketing_atribuicoes
  (empresa_id, ordem_servico_id)
  where ordem_servico_id is not null;
