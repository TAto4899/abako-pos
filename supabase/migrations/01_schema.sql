-- Schema inicial: software de ventas y stock
-- Modelo append-only para movimientos_stock (ver decisión de arquitectura)

create extension if not exists pgcrypto;

-- Depósitos / sucursales / ubicaciones de stock
create table depositos (
    id uuid primary key default gen_random_uuid(),
    nombre text not null,
    creado_en timestamptz not null default now()
);

-- Catálogo de productos
create table productos (
    id uuid primary key default gen_random_uuid(),
    nombre text not null,
    sku text unique,
    precio numeric(12,2) not null default 0,
    creado_en timestamptz not null default now()
);

-- Movimientos de stock: APPEND-ONLY. Nunca UPDATE ni DELETE sobre esta tabla.
-- El stock actual siempre se calcula, nunca se guarda como campo editable.
create table movimientos_stock (
    id uuid primary key default gen_random_uuid(),
    producto_id uuid not null references productos(id),
    deposito_id uuid not null references depositos(id),
    cantidad numeric(12,2) not null, -- positivo = entrada, negativo = salida
    motivo text not null,            -- 'venta', 'compra', 'ajuste', etc.
    venta_id uuid,                   -- referencia opcional a la venta que originó el movimiento
    creado_en timestamptz not null default now()
);

-- Ventas
create table ventas (
    id uuid primary key default gen_random_uuid(),
    deposito_id uuid not null references depositos(id),
    total numeric(12,2) not null default 0,
    estado text not null default 'confirmada', -- 'confirmada' | 'pendiente_revision'
    creado_en timestamptz not null default now()
);

-- Vista: stock actual por producto y depósito, calculado como SUM de movimientos
create view stock_actual as
select
    producto_id,
    deposito_id,
    sum(cantidad) as cantidad_actual
from movimientos_stock
group by producto_id, deposito_id;

-- La vista hereda los permisos de quien la creó por defecto (bypassa RLS de las tablas).
-- security_invoker hace que respete los permisos de quien consulta, igual que las tablas.
alter view stock_actual set (security_invoker = on);

-- RLS: se habilita sin políticas por ahora (bloquea acceso vía API pública anon/authenticated).
-- Todavía no hay autenticación en la app, así que no hay políticas que definir.
-- Cuando se agregue login, acá se suman policies específicas por tabla.
alter table depositos enable row level security;
alter table productos enable row level security;
alter table movimientos_stock enable row level security;
alter table ventas enable row level security;
