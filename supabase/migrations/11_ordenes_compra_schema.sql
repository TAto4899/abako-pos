-- Feature "Órdenes de compra": pedido a proveedor, manual o auto-sugerido
-- por bajo stock, con recepción que repone stock solo.
create table if not exists ordenes_compra (
  id uuid primary key,
  proveedor text,
  estado text not null default 'pendiente', -- pendiente | recibida | cancelada
  notas text,
  creado_por text,
  recibida_en timestamptz,
  recibida_por text,
  creado_en timestamptz not null default now()
);

-- Líneas de una orden. Fijas al crear la orden (no se editan después de
-- creada — si hay que cambiar algo, se cancela y se hace de nuevo).
create table if not exists orden_compra_items (
  id uuid primary key,
  orden_id uuid not null references ordenes_compra(id),
  producto_id uuid not null references productos(id),
  cantidad numeric not null,
  creado_en timestamptz not null default now()
);

-- Trazabilidad: qué movimiento de stock vino de qué orden de compra.
alter table movimientos_stock add column if not exists orden_id uuid references ordenes_compra(id);

alter table ordenes_compra enable row level security;
create policy ordenes_compra_select on ordenes_compra for select to authenticated using (true);
create policy ordenes_compra_insert on ordenes_compra for insert to authenticated with check (true);
create policy ordenes_compra_update on ordenes_compra for update to authenticated using (true) with check (true);

alter table orden_compra_items enable row level security;
create policy orden_compra_items_select on orden_compra_items for select to authenticated using (true);
create policy orden_compra_items_insert on orden_compra_items for insert to authenticated with check (true);
-- Sin policy de update/delete en los items: son fijos desde que se crea la orden.

-- IMPORTANTE: además de este script, agregar "select * from ordenes_compra"
-- Y "select * from orden_compra_items" al stream "global" en el dashboard de
-- PowerSync (Client Auth → Sync Streams) y volver a deployarlo — son tablas
-- NUEVAS, no alcanza con la publicación sola (mismo gotcha de siempre; la
-- columna nueva en movimientos_stock sí se replica sola, esa parte no hace
-- falta tocarla en el stream).
alter publication powersync add table ordenes_compra, orden_compra_items;
