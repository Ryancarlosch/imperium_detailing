-- Hardening final do roadmap: Ponto / RLS / índices.
-- Aplicada no projeto tiztkfiqkrpfzuwswmfz em 2026-09-30.

create index if not exists idx_ponto_ajustes_executado_por
  on public.ponto_ajustes (executado_por);

create index if not exists idx_ponto_fechamento_historico_executado_por
  on public.ponto_fechamento_historico (executado_por);

create index if not exists idx_ponto_fechamentos_colaborador_fk
  on public.ponto_fechamentos (colaborador_id);

create index if not exists idx_ponto_solicitacoes_decidido_por
  on public.ponto_solicitacoes_ajuste (decidido_por);

create index if not exists idx_ponto_solicitacoes_solicitado_por
  on public.ponto_solicitacoes_ajuste (solicitado_por);

create index if not exists idx_ponto_sync_estado_migracao_por
  on public.ponto_sync_estado (migracao_concluida_por);

drop policy if exists ponto_solicitacoes_select
  on public.ponto_solicitacoes_ajuste;

create policy ponto_solicitacoes_select
on public.ponto_solicitacoes_ajuste
for select
to authenticated
using (
  private.usuario_admin_empresa(empresa_id)
  or exists (
    select 1
    from public.ponto_colaboradores pc
    where pc.id = ponto_solicitacoes_ajuste.colaborador_id
      and pc.empresa_id = ponto_solicitacoes_ajuste.empresa_id
      and pc.auth_user_id = (select auth.uid())
      and pc.ativo = true
  )
);

-- O índice *_key é backing index de constraint UNIQUE equivalente.
drop index if exists public.imperium_ordens_servico_empresa_id_id_uidx;
