-- Agrega costo por producto (para poder calcular margen/rentabilidad más
-- adelante en Reportes, y para no perder el dato de costo al migrar el
-- historial de la app vieja). No hace falta tocar la publicación de
-- PowerSync ni el stream (columna nueva en tabla ya publicada, se replica
-- sola) ni las políticas RLS existentes.
alter table productos add column if not exists costo numeric not null default 0;
