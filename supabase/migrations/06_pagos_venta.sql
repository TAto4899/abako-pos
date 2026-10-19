-- Reemplaza ventas.metodo_pago (un solo método por venta) por una tabla
-- pagos_venta que soporta pagos combinados (ej. mitad efectivo, mitad
-- tarjeta) y guarda efectivo recibido / vuelto para auditoría de caja.
-- Correr en el SQL Editor de Supabase.

create table if not exists pagos_venta (
  id uuid primary key,
  venta_id uuid not null references ventas(id),
  metodo text not null,
  monto numeric not null,
  efectivo_recibido numeric,
  vuelto numeric,
  creado_en timestamptz not null default now()
);

alter table ventas drop column if exists metodo_pago;

alter table pagos_venta enable row level security;

-- Mismo criterio que movimientos_stock: append-only, SOLO select + insert,
-- nunca update/delete (un pago de una venta no se corrige, se registra).
create policy pagos_venta_authenticated_select
    on pagos_venta
    for select
    to authenticated
    using (true);

create policy pagos_venta_authenticated_insert
    on pagos_venta
    for insert
    to authenticated
    with check (true);

alter publication powersync add table pagos_venta;
