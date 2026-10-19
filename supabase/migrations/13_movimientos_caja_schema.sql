-- Feature "Movimientos de caja" (retiros/ingresos manuales de efectivo).
-- Append-only, mismo criterio que movimientos_stock/pagos_venta: un retiro o
-- ingreso no se corrige ni se borra, si se cargó mal se compensa con otro
-- movimiento nuevo. Esto es lo que faltaba para que el "esperado en caja" sea
-- confiable cuando sale/entra plata de la caja que no es una venta (pagarle a
-- un proveedor en efectivo, agregar cambio, etc.).
create table if not exists movimientos_caja (
  id uuid primary key,
  caja_id uuid not null references cajas(id),
  tipo text not null, -- 'ingreso' | 'retiro'
  monto numeric not null,
  motivo text,
  creado_por text,
  creado_en timestamptz not null default now()
);

alter table movimientos_caja enable row level security;

create policy movimientos_caja_select on movimientos_caja for select to authenticated using (true);
create policy movimientos_caja_insert on movimientos_caja for insert to authenticated with check (true);
-- Sin policy de update/delete: append-only.

-- IMPORTANTE: además de este script, agregar "select * from movimientos_caja"
-- al stream "global" en el dashboard de PowerSync (Client Auth → Sync
-- Streams) y volver a deployarlo — si no, la tabla queda vacía en el cliente
-- sin ningún error visible (mismo gotcha ya documentado varias veces en este
-- proyecto).
alter publication powersync add table movimientos_caja;
