create table clientes (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  telefono text,
  email text,
  notas text,
  creado_en timestamptz not null default now()
);

alter table clientes enable row level security;
create policy "select clientes" on clientes for select to authenticated using (true);
create policy "insert clientes" on clientes for insert to authenticated with check (true);
create policy "update clientes" on clientes for update to authenticated
  using (true) with check (true);
-- Sin policy de delete, mismo criterio que el resto del proyecto (productos,
-- depositos, configuracion_tienda): no se borra, como mucho se deja de usar.

alter table ventas add column cliente_id uuid references clientes(id);

alter publication powersync add table clientes;
