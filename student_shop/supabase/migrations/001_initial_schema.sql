-- =============================================================================
-- BMC Finals Project - student_shop
-- Supabase organization : BMC
-- Supabase project      : BMC-ecom1
-- Currency             : PHP (Philippine Peso)
--
-- What this migration creates
--   tables    : products, orders, order_items, guest_sessions,
--               payment_webhook_events
--   functions : public.guest_token_hash(text)
--               public.create_order(...)          -- service_role only
--               public.cancel_order(...)          -- service_role only
--               public.apply_xendit_invoice_event(...)  -- service_role only
--               public.get_my_orders(text)        -- anon + authenticated
--   policies  : products are world readable, orders / order_items are readable
--               only by their owner, and NO client may ever write to them.
--
-- How to apply
--   1. Open the Supabase Dashboard -> SQL Editor -> New query
--   2. Paste this whole file and press "Run"
--   3. Then run 002_seed_demo_products.sql
--
-- The script is idempotent: it can safely be executed more than once.
-- =============================================================================

-- pgcrypto gives us digest() for hashing guest tokens. In Supabase the
-- extension lives in the "extensions" schema, but we keep a fallback for
-- installations where it lives in "public".
create extension if not exists pgcrypto with schema extensions;

-- =============================================================================
-- Upgrade of an installation that still contains the tables of an earlier
-- implementation (the reference project used `products.id integer` and an
-- `orders` table with the columns `amount`, `product_name` and `status`).
--
-- The block below makes the migration work on such a project as well:
--   * tables with a non uuid primary key are dropped (they only contain demo
--     data, the seed script recreates them)
--   * a missing column of the products / order_items table is repaired the
--     same way
--   * the orders table is extended with the columns of the new schema
-- =============================================================================
do $$
declare
    v_table       text;
    v_id_type     text;
    v_missing     boolean;
    v_column_name text;
begin
    -- 1) tables of the old implementation (integer ids) are dropped
    foreach v_table in array array['products', 'orders', 'order_items'] loop
        if to_regclass('public.' || v_table) is null then
            continue;
        end if;

        select data_type into v_id_type
          from information_schema.columns
         where table_schema = 'public'
           and table_name = v_table
           and column_name = 'id';

        if v_id_type is not null and v_id_type <> 'uuid' then
            execute format('drop table public.%I cascade', v_table);
        end if;
    end loop;

    -- 2) the old products table has no stock column
    if to_regclass('public.products') is not null then
        select not exists (
            select 1 from information_schema.columns
             where table_schema = 'public'
               and table_name = 'products'
               and column_name = 'stock_quantity'
        ) into v_missing;

        if v_missing then
            drop table public.products cascade;
        end if;
    end if;

    -- 3) the old order items table has a different structure
    if to_regclass('public.order_items') is not null then
        select not exists (
            select 1 from information_schema.columns
             where table_schema = 'public'
               and table_name = 'order_items'
               and column_name = 'subtotal'
        ) into v_missing;

        if v_missing then
            drop table public.order_items cascade;
        end if;
    end if;

    -- 4) extend an existing orders table with the new columns
    if to_regclass('public.orders') is not null then
        alter table public.orders add column if not exists external_id        text;
        alter table public.orders add column if not exists status             text not null default 'PENDING';
        alter table public.orders add column if not exists payment_status     text not null default 'PENDING';
        alter table public.orders add column if not exists currency           text not null default 'PHP';
        alter table public.orders add column if not exists total_amount       numeric(12, 2);
        alter table public.orders add column if not exists user_id            uuid;
        alter table public.orders add column if not exists guest_token_hash   text;
        alter table public.orders add column if not exists xendit_invoice_id  text;
        alter table public.orders add column if not exists xendit_invoice_url text;
        alter table public.orders add column if not exists idempotency_key    text;
        alter table public.orders add column if not exists payment_method     text;
        alter table public.orders add column if not exists failure_reason     text;
        alter table public.orders add column if not exists paid_at            timestamptz;
        alter table public.orders add column if not exists updated_at         timestamptz not null default now();

        -- the old table stored the amount in the column "amount"
        if exists (
            select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'orders' and column_name = 'amount'
        ) then
            update public.orders
               set total_amount = amount
             where total_amount is null and amount is not null;
        end if;

        -- columns of the old implementation that the new code does not fill
        for v_column_name in
            select column_name
              from information_schema.columns
             where table_schema = 'public'
               and table_name = 'orders'
               and is_nullable = 'NO'
               and column_default is null
               and column_name not in (
                   'external_id', 'status', 'payment_status', 'currency', 'total_amount'
               )
        loop
            execute format(
                'alter table public.orders alter column %I drop not null',
                v_column_name
            );
        end loop;

        -- the old orders have no owner: they are kept as archived guest orders
        update public.orders
           set guest_token_hash = 'legacy-' || id::text
         where user_id is null and guest_token_hash is null;

        -- the old orders may have duplicate or missing external ids
        update public.orders
           set external_id = 'legacy-' || id::text
         where external_id is null or external_id = '';
    end if;
end $$;

-- -----------------------------------------------------------------------------
-- products
-- -----------------------------------------------------------------------------
create table if not exists public.products (
    id             uuid primary key default gen_random_uuid(),
    name           text        not null,
    description    text,
    price          numeric(12, 2) not null,
    image_url      text,
    stock_quantity integer     not null default 0,
    is_active      boolean     not null default true,
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now(),
    constraint products_name_key        unique (name),
    constraint products_name_not_blank  check (char_length(btrim(name)) > 0),
    constraint products_price_positive  check (price > 0),
    constraint products_stock_nonneg    check (stock_quantity >= 0)
);

comment on table public.products is 'Catalogue of items sold by the student shop.';

-- -----------------------------------------------------------------------------
-- orders
--   * A pending order is created by the "create-invoice" edge function.
--   * It is only ever moved to PAID by the "xendit-webhook" edge function,
--     which calls public.apply_xendit_invoice_event(). There is deliberately
--     no client (Flutter) policy that allows INSERT/UPDATE on this table.
-- -----------------------------------------------------------------------------
create table if not exists public.orders (
    id                 uuid primary key default gen_random_uuid(),
    user_id            uuid references auth.users (id) on delete cascade,
    guest_token_hash   text,
    external_id        text        not null unique,
    status             text        not null default 'PENDING',
    payment_status     text        not null default 'PENDING',
    currency           text        not null default 'PHP',
    total_amount       numeric(12, 2) not null,
    xendit_invoice_id  text unique,
    xendit_invoice_url text,
    idempotency_key    text unique,
    payment_method     text,
    failure_reason     text,
    paid_at            timestamptz,
    created_at         timestamptz not null default now(),
    updated_at         timestamptz not null default now(),
    constraint orders_status_valid check (
        status in ('PENDING', 'PAID', 'EXPIRED', 'FAILED', 'CANCELLED')
    ),
    constraint orders_payment_status_valid check (
        payment_status in ('PENDING', 'PAID', 'EXPIRED', 'FAILED')
    ),
    constraint orders_currency_php check (currency = 'PHP'),
    constraint orders_total_positive check (total_amount > 0),
    -- exactly one owner: either a signed-in user or a guest device
    constraint orders_single_owner check (
        (user_id is not null) <> (guest_token_hash is not null)
    )
);

comment on table public.orders is 'Customer orders. Payment status is only written by trusted server code.';

-- -----------------------------------------------------------------------------
-- order_items  (product name / price are snapshotted so history never changes)
-- -----------------------------------------------------------------------------
create table if not exists public.order_items (
    id           uuid primary key default gen_random_uuid(),
    order_id     uuid not null references public.orders (id) on delete cascade,
    product_id   uuid references public.products (id) on delete set null,
    product_name text        not null,
    quantity     integer     not null,
    unit_price   numeric(12, 2) not null,
    subtotal     numeric(12, 2) not null,
    created_at   timestamptz not null default now(),
    constraint order_items_quantity_positive check (quantity > 0),
    constraint order_items_unit_price_positive check (unit_price > 0),
    constraint order_items_subtotal_valid check (subtotal = unit_price * quantity)
);

-- -----------------------------------------------------------------------------
-- guest_sessions
--   A guest checkout is identified by a high entropy random token that is
--   generated on the server and only ever stored hashed.
-- -----------------------------------------------------------------------------
create table if not exists public.guest_sessions (
    id           uuid primary key default gen_random_uuid(),
    token_hash   text        not null unique,
    created_at   timestamptz not null default now(),
    last_seen_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- payment_webhook_events
--   Every webhook delivery is recorded here. The unique event_key makes the
--   webhook processing idempotent (Xendit may deliver the same event twice).
-- -----------------------------------------------------------------------------
create table if not exists public.payment_webhook_events (
    id           uuid primary key default gen_random_uuid(),
    event_key    text        not null unique,
    invoice_id   text,
    external_id  text,
    event_type   text        not null,
    result       text,
    payload      jsonb,
    received_at  timestamptz not null default now(),
    processed_at timestamptz
);

-- -----------------------------------------------------------------------------
-- Indexes
-- -----------------------------------------------------------------------------
create index if not exists products_is_active_idx      on public.products (is_active);
create index if not exists orders_user_id_idx           on public.orders (user_id);
create index if not exists orders_guest_token_hash_idx  on public.orders (guest_token_hash);
create index if not exists orders_created_at_idx        on public.orders (created_at desc);
create index if not exists orders_xendit_invoice_idx    on public.orders (xendit_invoice_id);
create index if not exists order_items_order_id_idx     on public.order_items (order_id);
create index if not exists order_items_product_id_idx   on public.order_items (product_id);

-- The unique constraints of a freshly created orders table already exist.
-- An upgraded (legacy) table only has the plain indexes above, so the unique
-- indexes are created here - with a fallback for tables that contain
-- duplicates.
do $$
begin
    begin
        create unique index if not exists orders_external_id_uidx
            on public.orders (external_id);
    exception when others then
        create index if not exists orders_external_id_idx
            on public.orders (external_id);
    end;

    begin
        create unique index if not exists orders_xendit_invoice_id_uidx
            on public.orders (xendit_invoice_id);
    exception when others then
        create index if not exists orders_xendit_invoice_id_idx
            on public.orders (xendit_invoice_id);
    end;

    begin
        create unique index if not exists orders_idempotency_key_uidx
            on public.orders (idempotency_key);
    exception when others then
        create index if not exists orders_idempotency_key_idx
            on public.orders (idempotency_key);
    end;
end $$;

-- -----------------------------------------------------------------------------
-- updated_at trigger
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
    returns trigger
    language plpgsql
    security invoker
    set search_path = public
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at
    before update on public.products
    for each row execute function public.set_updated_at();

drop trigger if exists orders_set_updated_at on public.orders;
create trigger orders_set_updated_at
    before update on public.orders
    for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- guest_token_hash(text)
--   SHA-256 of a guest token. Used to link an order to a device without ever
--   storing the raw token in the database.
-- -----------------------------------------------------------------------------
create or replace function public.guest_token_hash(p_token text)
    returns text
    language plpgsql
    immutable
    strict
    security invoker
    set search_path = public, extensions
as $$
declare
    v_hash text;
begin
    if p_token is null or char_length(p_token) < 32 then
        raise exception 'INVALID_GUEST_TOKEN' using errcode = '22023';
    end if;

    begin
        v_hash := encode(extensions.digest(p_token, 'sha256'), 'hex');
    exception
        when undefined_function or undefined_table or invalid_schema_name then
            v_hash := encode(public.digest(p_token, 'sha256'), 'hex');
    end;

    return v_hash;
end;
$$;

comment on function public.guest_token_hash(text) is
    'SHA-256 hash of a guest checkout token (raw tokens are never stored).';

-- -----------------------------------------------------------------------------
-- create_order(...)
--   Server side order creation. Runs in a single transaction:
--     * locks the product row
--     * validates stock
--     * reserves (decrements) the stock
--     * inserts the order and its items
--   Only the service role (edge functions) may call it.
-- -----------------------------------------------------------------------------
create or replace function public.create_order(
    p_product_id       uuid,
    p_quantity         integer,
    p_user_id          uuid   default null,
    p_guest_token      text   default null,
    p_idempotency_key  text   default null,
    p_external_id      text   default null
)
    returns public.orders
    language plpgsql
    security definer
    set search_path = public, extensions
as $$
declare
    v_product   public.products%rowtype;
    v_order     public.orders%rowtype;
    v_total     numeric(12, 2);
    v_token_hash text;
    v_external  text;
begin
    if p_quantity is null or p_quantity < 1 or p_quantity > 50 then
        raise exception 'INVALID_QUANTITY' using errcode = '22023';
    end if;

    -- Idempotency: a retried request must not create a second order.
    if p_idempotency_key is not null then
        select * into v_order
          from public.orders
         where idempotency_key = p_idempotency_key;
        if found then
            return v_order;
        end if;
    end if;

    select * into v_product
      from public.products
     where id = p_product_id
     for update;

    if not found then
        raise exception 'PRODUCT_NOT_FOUND' using errcode = 'P0002';
    end if;

    if not v_product.is_active then
        raise exception 'PRODUCT_UNAVAILABLE' using errcode = 'P0001';
    end if;

    if v_product.stock_quantity < p_quantity then
        raise exception 'OUT_OF_STOCK' using errcode = 'P0001';
    end if;

    v_total := round(v_product.price * p_quantity, 2);

    if p_user_id is not null then
        v_token_hash := null;
    else
        if p_guest_token is null or char_length(p_guest_token) < 32 then
            raise exception 'INVALID_GUEST_TOKEN' using errcode = '22023';
        end if;
        v_token_hash := public.guest_token_hash(p_guest_token);
    end if;

    v_external := coalesce(p_external_id, gen_random_uuid()::text);

    begin
        insert into public.orders (
            user_id, guest_token_hash, external_id, status, payment_status,
            currency, total_amount, idempotency_key
        )
        values (
            p_user_id, v_token_hash, v_external, 'PENDING', 'PENDING',
            'PHP', v_total, p_idempotency_key
        )
        returning * into v_order;
    exception
        when unique_violation then
            -- Lost a race on the idempotency key: return the winning order.
            select * into v_order
              from public.orders
             where idempotency_key = p_idempotency_key;
            if not found then
                raise;
            end if;
            return v_order;
    end;

    insert into public.order_items (
        order_id, product_id, product_name, quantity, unit_price, subtotal
    )
    values (
        v_order.id, v_product.id, v_product.name, p_quantity,
        v_product.price, v_total
    );

    -- Reserve the stock for this order. It is given back if the invoice
    -- expires (public.apply_xendit_invoice_event) or the order is cancelled.
    update public.products
       set stock_quantity = stock_quantity - p_quantity
     where id = v_product.id;

    return v_order;
end;
$$;

-- -----------------------------------------------------------------------------
-- cancel_order(uuid, text)
--   Used when the Xendit API call fails after the order was created.
--   Releases the reserved stock and marks the order as FAILED.
-- -----------------------------------------------------------------------------
create or replace function public.cancel_order(
    p_order_id uuid,
    p_reason   text default null
)
    returns boolean
    language plpgsql
    security definer
    set search_path = public, extensions
as $$
declare
    v_order public.orders%rowtype;
begin
    select * into v_order
      from public.orders
     where id = p_order_id
     for update;

    if not found then
        return false;
    end if;

    if v_order.payment_status = 'PAID' then
        -- never touch a paid order
        return false;
    end if;

    update public.products p
       set stock_quantity = p.stock_quantity + i.qty
      from (
            select oi.product_id as product_id, sum(oi.quantity) as qty
              from public.order_items oi
             where oi.order_id = v_order.id
               and oi.product_id is not null
             group by oi.product_id
           ) i
     where p.id = i.product_id;

    update public.orders
       set status         = 'FAILED',
           payment_status = 'FAILED',
           failure_reason = coalesce(p_reason, 'invoice_creation_failed')
     where id = v_order.id;

    return true;
end;
$$;

-- -----------------------------------------------------------------------------
-- apply_xendit_invoice_event(...)
--   The single place where an order may become PAID.
--   * called only by the xendit-webhook edge function (service role)
--   * validates invoice, amount and currency before marking the order paid
--   * idempotent: repeated deliveries are recorded and ignored
--   * atomic: the whole state change happens inside one transaction
-- -----------------------------------------------------------------------------
create or replace function public.apply_xendit_invoice_event(
    p_invoice_id     text,
    p_external_id   text,
    p_status        text,
    p_amount_cents  bigint,
    p_currency      text,
    p_event_key     text,
    p_paid_at       timestamptz default null,
    p_payment_method text default null,
    p_payload       jsonb   default null
)
    returns table (result text, order_id uuid, order_status text)
    language plpgsql
    security definer
    set search_path = public, extensions
as $$
declare
    v_order    public.orders%rowtype;
    v_expected bigint;
    v_inserted boolean := false;
begin
    if p_invoice_id is null and p_external_id is null then
        return query select 'invalid_payload'::text, null::uuid, null::text;
        return;
    end if;

    select * into v_order
      from public.orders
     where (p_invoice_id is not null and xendit_invoice_id = p_invoice_id)
        or (p_external_id is not null and external_id = p_external_id)
     order by created_at desc
     limit 1
     for update;

    if not found then
        return query select 'not_found'::text, null::uuid, null::text;
        return;
    end if;

    -- Idempotency guard: the same event delivered twice is only stored once.
    begin
        insert into public.payment_webhook_events (
            event_key, invoice_id, external_id, event_type, payload, processed_at
        )
        values (
            p_event_key, p_invoice_id, p_external_id,
            coalesce(p_status, 'UNKNOWN'), p_payload, now()
        );
        v_inserted := true;
    exception
        when unique_violation then
            v_inserted := false;
    end;

    if not v_inserted then
        update public.payment_webhook_events
           set result = 'duplicate'
         where event_key = p_event_key;
        return query select 'duplicate'::text, v_order.id, v_order.payment_status;
        return;
    end if;

    -- Never downgrade an order that is already paid.
    if v_order.payment_status = 'PAID' then
        update public.payment_webhook_events
           set result = 'already_paid'
         where event_key = p_event_key;
        return query select 'already_paid'::text, v_order.id, v_order.payment_status;
        return;
    end if;

    if p_status in ('PAID', 'SETTLED') then
        v_expected := round(v_order.total_amount * 100)::bigint;

        if p_amount_cents is null
           or p_amount_cents <> v_expected
           or coalesce(p_currency, '') <> v_order.currency then
            update public.payment_webhook_events
               set result = 'mismatch'
             where event_key = p_event_key;
            return query select 'mismatch'::text, v_order.id, v_order.payment_status;
            return;
        end if;

        update public.orders
           set status         = 'PAID',
               payment_status = 'PAID',
               paid_at        = coalesce(p_paid_at, now()),
               payment_method = coalesce(p_payment_method, payment_method),
               failure_reason = null
         where id = v_order.id;

        update public.payment_webhook_events
           set result = 'paid'
         where event_key = p_event_key;

        return query select 'paid'::text, v_order.id, 'PAID'::text;
        return;
    end if;

    if p_status = 'EXPIRED' then
        -- give the reserved stock back
        update public.products p
           set stock_quantity = p.stock_quantity + i.qty
          from (
                select oi.product_id as product_id, sum(oi.quantity) as qty
                  from public.order_items oi
                 where oi.order_id = v_order.id
                   and oi.product_id is not null
                 group by oi.product_id
               ) i
         where p.id = i.product_id;

        update public.orders
           set status         = 'EXPIRED',
               payment_status = 'EXPIRED'
         where id = v_order.id;

        update public.payment_webhook_events
           set result = 'expired'
         where event_key = p_event_key;

        return query select 'expired'::text, v_order.id, 'EXPIRED'::text;
        return;
    end if;

    update public.payment_webhook_events
       set result = 'ignored'
     where event_key = p_event_key;

    return query select 'ignored'::text, v_order.id, v_order.payment_status;
end;
$$;

-- -----------------------------------------------------------------------------
-- get_my_orders(text)
--   Convenience read used by the Flutter app.
--     * signed in  -> returns the orders of auth.uid()   (RLS also protects it)
--     * guest      -> returns only the orders that match the supplied token
--   SECURITY DEFINER because a guest has no Postgres role to filter with; the
--   token itself is the credential, and only its hash is stored.
-- -----------------------------------------------------------------------------
create or replace function public.get_my_orders(p_guest_token text default null)
    returns jsonb
    language plpgsql
    stable
    security definer
    set search_path = public, extensions
as $$
declare
    v_uid   uuid := auth.uid();
    v_hash  text;
    v_result jsonb;
begin
    if v_uid is not null then
        select coalesce(jsonb_agg(jsonb_build_object(
                   'id', o.id,
                   'status', o.status,
                   'payment_status', o.payment_status,
                   'total_amount', o.total_amount,
                   'currency', o.currency,
                   'external_id', o.external_id,
                   'xendit_invoice_id', o.xendit_invoice_id,
                   'xendit_invoice_url', o.xendit_invoice_url,
                   'payment_method', o.payment_method,
                   'failure_reason', o.failure_reason,
                   'created_at', o.created_at,
                   'paid_at', o.paid_at,
                   'updated_at', o.updated_at,
                   'items', coalesce((
                       select jsonb_agg(jsonb_build_object(
                                  'id', i.id,
                                  'product_id', i.product_id,
                                  'product_name', i.product_name,
                                  'quantity', i.quantity,
                                  'unit_price', i.unit_price,
                                  'subtotal', i.subtotal
                              ) order by i.created_at)
                         from public.order_items i
                        where i.order_id = o.id
                   ), '[]'::jsonb)
               ) order by o.created_at desc), '[]'::jsonb)
          into v_result
          from public.orders o
         where o.user_id = v_uid;

    elsif p_guest_token is not null and char_length(p_guest_token) >= 32 then
        v_hash := public.guest_token_hash(p_guest_token);

        select coalesce(jsonb_agg(jsonb_build_object(
                   'id', o.id,
                   'status', o.status,
                   'payment_status', o.payment_status,
                   'total_amount', o.total_amount,
                   'currency', o.currency,
                   'external_id', o.external_id,
                   'xendit_invoice_id', o.xendit_invoice_id,
                   'xendit_invoice_url', o.xendit_invoice_url,
                   'payment_method', o.payment_method,
                   'failure_reason', o.failure_reason,
                   'created_at', o.created_at,
                   'paid_at', o.paid_at,
                   'updated_at', o.updated_at,
                   'items', coalesce((
                       select jsonb_agg(jsonb_build_object(
                                  'id', i.id,
                                  'product_id', i.product_id,
                                  'product_name', i.product_name,
                                  'quantity', i.quantity,
                                  'unit_price', i.unit_price,
                                  'subtotal', i.subtotal
                              ) order by i.created_at)
                         from public.order_items i
                        where i.order_id = o.id
                   ), '[]'::jsonb)
               ) order by o.created_at desc), '[]'::jsonb)
          into v_result
          from public.orders o
         where o.guest_token_hash = v_hash;

    else
        v_result := '[]'::jsonb;
    end if;

    return v_result;
end;
$$;

-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------
alter table public.products               enable row level security;
alter table public.orders                 enable row level security;
alter table public.order_items            enable row level security;
alter table public.guest_sessions         enable row level security;
alter table public.payment_webhook_events enable row level security;

-- products: everybody may read the active catalogue, nobody may write.
drop policy if exists "products_select_active" on public.products;
create policy "products_select_active"
    on public.products
    for select
    to anon, authenticated
    using (is_active = true);

-- orders: a signed in user may only read their own orders.
drop policy if exists "orders_select_own" on public.orders;
create policy "orders_select_own"
    on public.orders
    for select
    to authenticated
    using (auth.uid() = user_id);

-- order_items: a signed in user may only read the items of their own orders.
drop policy if exists "order_items_select_own" on public.order_items;
create policy "order_items_select_own"
    on public.order_items
    for select
    to authenticated
    using (
        exists (
            select 1
              from public.orders o
             where o.id = order_items.order_id
               and o.user_id = auth.uid()
        )
    );

-- There is intentionally NO insert / update / delete policy for orders,
-- order_items, guest_sessions or payment_webhook_events. A client (Flutter)
-- therefore cannot create an order, cannot change a price and - most
-- importantly - cannot mark an order as PAID. Only the edge functions
-- (service role) can write to those tables.

-- -----------------------------------------------------------------------------
-- Grants
-- -----------------------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;

grant select on public.products to anon, authenticated;
grant select on public.orders, public.order_items to authenticated;

revoke all on public.guest_sessions         from anon, authenticated;
revoke all on public.payment_webhook_events from anon, authenticated;

-- helper functions used by the app
revoke all on function public.guest_token_hash(text) from public;
grant  execute on function public.guest_token_hash(text) to service_role;

revoke all on function public.get_my_orders(text) from public;
grant  execute on function public.get_my_orders(text) to anon, authenticated;

-- functions that may only be used by the edge functions
revoke all on function public.create_order(uuid, integer, uuid, text, text, text) from public;
grant  execute on function public.create_order(uuid, integer, uuid, text, text, text) to service_role;

revoke all on function public.cancel_order(uuid, text) from public;
grant  execute on function public.cancel_order(uuid, text) to service_role;

revoke all on function public.apply_xendit_invoice_event(text, text, text, bigint, text, text, timestamptz, text, jsonb) from public;
grant  execute on function public.apply_xendit_invoice_event(text, text, text, bigint, text, text, timestamptz, text, jsonb) to service_role;
