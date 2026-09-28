alter table public.imperium_clientes
  add column if not exists data_nascimento text;

create index if not exists idx_imperium_clientes_nascimento
  on public.imperium_clientes(empresa_id, data_nascimento)
  where data_nascimento is not null
    and btrim(data_nascimento) <> '';
