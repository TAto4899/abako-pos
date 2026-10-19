-- Feature "Caja registradora": apertura/cierre de caja diario.
-- No es append-only como movimientos_stock/pagos_venta: una fila de caja
-- vive un ciclo abierta -> cerrada y se actualiza al cerrar (mismo criterio
-- que ventas/configuracion_tienda, que sí permiten UPDATE).
create table if not exists cajas (
  id uuid primary key,
  deposito_id uuid not null references depositos(id),
  monto_apertura numeric not null,
  abierta_por text,
  cerrada_en timestamptz,
  monto_cierre_esperado numeric,
  monto_cierre_real numeric,
  diferencia numeric,
  cerrada_por text,
  estado text not null default 'abierta',
  notas text,
  creado_en timestamptz not null default now()
);

alter table cajas enable row level security;

create policy cajas_select on cajas for select to authenticated using (true);
create policy cajas_insert on cajas for insert to authenticated with check (true);
create policy cajas_update on cajas for update to authenticated using (true) with check (true);
-- Sin policy de delete: una caja cerrada queda como registro histórico, no se borra.

-- IMPORTANTE: además de este script, hay que agregar "select * from cajas" al
-- stream "global" en el dashboard de PowerSync (Client Auth → Sync Streams) y
-- volver a deployarlo — una tabla nueva agregada solo acá a la publicación NO
-- alcanza para que sincronice (mismo gotcha documentado en la sesión de
-- Ajustes 2026-08-27: sin el segundo paso, la tabla queda vacía en el
-- cliente sin ningún error visible).
alter publication powersync add table cajas;
