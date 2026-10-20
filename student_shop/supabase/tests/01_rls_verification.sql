-- =============================================================================
-- Manual verification of the Row Level Security setup.
--
-- Run this script in the Supabase SQL editor of the project BMC-ecom1.
-- Every statement prints a result that can be checked during the
-- demonstration.
-- =============================================================================

-- 1) RLS must be enabled for every table of the shop.
select tablename, rowsecurity as rls_enabled
from pg_tables
where schemaname = 'public'
order by tablename;
-- expected: products, orders, order_items, guest_sessions and
--           payment_webhook_events all have rls_enabled = true

-- 2) There must be no policy that allows a client to write an order.
--    Only the edge functions (service role) may write.
select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
order by tablename, cmd;
-- expected: no row with cmd = 'INSERT' / 'UPDATE' / 'DELETE'

-- 3) The policies of the orders table.
select policyname, cmd, roles, qual
from pg_policies
where schemaname = 'public' and tablename = 'orders';
-- expected: one SELECT policy for role authenticated with
--           qual = '(auth.uid() = user_id)'

-- 4) The demo product must cost 1500.00 PHP.
select name, price, currency, stock_quantity, is_active
from public.products
where name = 'Mechanical Gaming Keyboard';
-- expected: 1500.00 | PHP

-- 5) The orders of the current customer (RLS filtered).
--    Run this while signed in as a customer.
select id, status, payment_status, total_amount, currency, created_at
from public.orders
order by created_at desc;
-- expected: only the orders of the signed in customer

-- 6) The items of those orders.
select oi.product_name, oi.quantity, oi.unit_price, oi.subtotal
from public.order_items oi
join public.orders o on o.id = oi.order_id
order by oi.created_at desc;

-- 7) The webhook log - every delivery is recorded exactly once.
select event_key, event_type, result, received_at
from public.payment_webhook_events
order by received_at desc;
-- expected: one row per delivery, result in
--           (paid, duplicate, already_paid, mismatch, expired, ignored)
