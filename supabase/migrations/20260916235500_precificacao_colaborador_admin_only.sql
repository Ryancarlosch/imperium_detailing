-- Precificação: custos financeiros de colaboradores são somente do administrador.
--
-- A regra geral `imperium_pode_modulo(..., 'financeiro')` também libera usuários
-- funcionários que receberam o módulo Financeiro. Isso é correto para contas e
-- operações autorizadas, mas não para remuneração/encargos/custo-hora da equipe.
-- Esta tabela contém dados salariais e, por regra de negócio, deve ser visível e
-- gravável apenas por admin/proprietário da própria empresa.

drop policy if exists imperium_prec_colab_select
  on public.imperium_precificacao_colaboradores_custo;
drop policy if exists imperium_prec_colab_insert
  on public.imperium_precificacao_colaboradores_custo;
drop policy if exists imperium_prec_colab_update
  on public.imperium_precificacao_colaboradores_custo;

create policy imperium_prec_colab_select
on public.imperium_precificacao_colaboradores_custo
for select
to authenticated
using ((select private.imperium_eh_admin_empresa(empresa_id)));

create policy imperium_prec_colab_insert
on public.imperium_precificacao_colaboradores_custo
for insert
to authenticated
with check ((select private.imperium_eh_admin_empresa(empresa_id)));

create policy imperium_prec_colab_update
on public.imperium_precificacao_colaboradores_custo
for update
to authenticated
using ((select private.imperium_eh_admin_empresa(empresa_id)))
with check ((select private.imperium_eh_admin_empresa(empresa_id)));
