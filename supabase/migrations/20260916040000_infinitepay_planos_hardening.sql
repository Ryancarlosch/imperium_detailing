grant select on table public.imperium_planos_assinatura to authenticated;

drop policy if exists imperium_planos_authenticated_select on public.imperium_planos_assinatura;
create policy imperium_planos_authenticated_select
on public.imperium_planos_assinatura
for select
to authenticated
using (ativo = true);

create or replace function public.imperium_planos_disponiveis()
returns table(
  codigo text,
  nome text,
  meses integer,
  valor_centavos integer,
  moeda text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.codigo, p.nome, p.meses, p.valor_centavos, p.moeda
  from public.imperium_planos_assinatura p
  where p.ativo = true
  order by p.ordem, p.meses, p.codigo;
$$;

revoke all on function public.imperium_planos_disponiveis() from public;
revoke all on function public.imperium_planos_disponiveis() from anon;
grant execute on function public.imperium_planos_disponiveis() to authenticated;
