-- Columnas nuevas para la pantalla de Inventario (rediseño Abako, 2026-08-15).
-- Correr en el SQL Editor de Supabase.

alter table productos
  add column if not exists categoria text not null default 'Otros';

alter table productos
  add column if not exists stock_minimo numeric not null default 0;

-- Nota: no hace falta tocar la publicación de PowerSync ("powersync") ni las
-- políticas RLS existentes de `productos` — ya cubre "for all using (true)
-- with check (true)" para el rol authenticated, que alcanza para estas
-- columnas nuevas también.
