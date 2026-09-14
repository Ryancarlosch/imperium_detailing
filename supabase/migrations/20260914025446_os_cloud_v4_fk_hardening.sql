-- OS Cloud V4 - hardening dos FKs opcionais multiempresa.
alter table public.imperium_financeiro_os_mao_obra
  drop constraint if exists imperium_fin_os_mao_colab_fk;
alter table public.imperium_financeiro_os_mao_obra
  add constraint imperium_fin_os_mao_colab_fk
  foreign key (empresa_id, colaborador_custo_id)
  references public.imperium_precificacao_colaboradores_custo(empresa_id, id)
  on delete set null (colaborador_custo_id);

alter table public.imperium_ordem_servico_ajustes_financeiros
  drop constraint if exists imperium_os_ajuste_regra_fk;
alter table public.imperium_ordem_servico_ajustes_financeiros
  add constraint imperium_os_ajuste_regra_fk
  foreign key (empresa_id, regra_taxa_id)
  references public.imperium_financeiro_regras_taxa(empresa_id, id)
  on delete set null (regra_taxa_id);

alter table public.imperium_ordem_servico_ajustes_financeiros
  drop constraint if exists imperium_os_ajuste_pag_fk;
alter table public.imperium_ordem_servico_ajustes_financeiros
  add constraint imperium_os_ajuste_pag_fk
  foreign key (empresa_id, pagamento_id)
  references public.imperium_financeiro_pagamentos_os(empresa_id, id)
  on delete set null (pagamento_id);
