create table if not exists public.imperium_configuracoes_empresa (
  empresa_id uuid primary key references public.empresas(id) on delete cascade,
  nome_fantasia text not null default '',
  razao_social text not null default '',
  cnpj text not null default '',
  inscricao_estadual text not null default '',
  telefone text not null default '',
  whatsapp text not null default '',
  email text not null default '',
  site text not null default '',
  instagram text not null default '',
  facebook text not null default '',
  endereco text not null default '',
  numero text not null default '',
  complemento text not null default '',
  bairro text not null default '',
  cidade text not null default '',
  estado text not null default '',
  cep text not null default '',
  nome_aplicativo text not null default 'Imperium Detailing',
  cor_principal bigint not null default 4292253771,
  cor_secundaria bigint not null default 4279900698,
  tema text not null default 'escuro',
  validade_orcamento_dias bigint not null default 15,
  rodape_documentos text not null default '',
  termos_orcamento text not null default '',
  termos_ordem_servico text not null default '',
  observacao_padrao text not null default '',
  mensagem_agradecimento text not null default '',
  mensagem_orcamento text not null default '',
  mensagem_confirmacao text not null default '',
  mensagem_entrega text not null default '',
  mensagem_cobranca text not null default '',
  origem_dispositivo text,
  origem_atualizado_em text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

alter table public.imperium_configuracoes_empresa enable row level security;

revoke all on public.imperium_configuracoes_empresa from anon, authenticated;
grant select, insert, update
on public.imperium_configuracoes_empresa to authenticated;

create policy imperium_config_empresa_select
on public.imperium_configuracoes_empresa
for select to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'configuracoes')));

create policy imperium_config_empresa_insert
on public.imperium_configuracoes_empresa
for insert to authenticated
with check ((select private.imperium_pode_modulo(empresa_id, 'configuracoes')));

create policy imperium_config_empresa_update
on public.imperium_configuracoes_empresa
for update to authenticated
using ((select private.imperium_pode_modulo(empresa_id, 'configuracoes')))
with check ((select private.imperium_pode_modulo(empresa_id, 'configuracoes')));

create trigger imperium_config_empresa_touch
before update on public.imperium_configuracoes_empresa
for each row execute function private.imperium_touch_atualizado_em();
