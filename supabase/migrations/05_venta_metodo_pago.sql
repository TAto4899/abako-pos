-- Agrega método de pago a las ventas, para la pantalla de cobro del rediseño
-- Abako de Punto de Venta (Efectivo / Tarjeta / Transferencia).
alter table ventas add column if not exists metodo_pago text;
