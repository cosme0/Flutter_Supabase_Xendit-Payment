-- =============================================================================
-- BMC Finals Project - student_shop
-- Database schema of the Student Shop (Supabase project: kfvxqsxycpmawgbwugyr)
--
-- Two tables:
--   products  the catalogue that the app shows
--   orders    one row per checkout attempt, updated by the Xendit webhook
--
-- The script is idempotent: running it again does not break anything.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- products
-- -----------------------------------------------------------------------------
create table if not exists public.products (
    id         serial primary key,
    name       text        not null unique,
    price      numeric(12, 2) not null check (price > 0),
    image_url  text,
    created_at timestamptz not null default now()
);

comment on table public.products is 'Catalogue of the items sold in the student shop.';

-- -----------------------------------------------------------------------------
-- orders
-- -----------------------------------------------------------------------------
create table if not exists public.orders (
    id           serial primary key,
    external_id  text        not null unique,
    status       text        not null default 'PENDING',
    product_name text        not null,
    amount       numeric(12, 2) not null check (amount > 0),
    created_at   timestamptz not null default now(),
    constraint orders_status_valid check (
        status in ('PENDING', 'PAID', 'EXPIRED', 'FAILED', 'CANCELLED')
    )
);

comment on table public.orders is
    'One row per checkout. Only the edge functions (service role) may write it.';

create index if not exists orders_created_at_idx on public.orders (created_at desc);
create index if not exists orders_external_id_idx on public.orders (external_id);

-- -----------------------------------------------------------------------------
-- Row Level Security
--
-- The Flutter app talks to the database with the *public* anon key, therefore
-- it may READ the catalogue and the order history.
--
-- It may NOT write: there is deliberately no insert/update/delete policy for
-- `orders`. Only the edge functions - which run with the service role key -
-- can create an order and can flip it to PAID after Xendit confirmed the
-- payment. A client can therefore never mark its own order as paid.
-- -----------------------------------------------------------------------------
alter table public.products enable row level security;
alter table public.orders   enable row level security;

drop policy if exists "products are readable by everybody" on public.products;
create policy "products are readable by everybody"
    on public.products
    for select
    using (true);

drop policy if exists "orders are readable by everybody" on public.orders;
create policy "orders are readable by everybody"
    on public.orders
    for select
    using (true);
