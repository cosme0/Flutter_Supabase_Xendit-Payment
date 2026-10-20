-- =============================================================================
-- Negative tests: a client must not be able to cheat.
--
-- Run every statement with the SQL editor role selector set to
-- "anon" (or "authenticated"). Each statement has to fail with
-- "new row violates row-level security policy" or "permission denied".
-- =============================================================================

-- 1) A client must not mark an order as paid.
update public.orders
   set status = 'PAID', payment_status = 'PAID'
 where status = 'PENDING';
-- expected: ERROR: new row violates row-level security policy for table "orders"

-- 2) A client must not change the price of an order.
update public.orders set total_amount = 1;
-- expected: ERROR: new row violates row-level security policy for table "orders"

-- 3) A client must not create orders.
insert into public.orders (external_id, total_amount, currency, user_id)
values ('cheat-order', 1, 'PHP', auth.uid());
-- expected: ERROR: new row violates row-level security policy for table "orders"

-- 4) A client must not insert order items.
insert into public.order_items (order_id, product_name, quantity, unit_price, subtotal)
values ('00000000-0000-0000-0000-000000000000', 'Fake item', 1, 1, 1);
-- expected: ERROR: new row violates row-level security policy for table "order_items"

-- 5) A client must not change the price of a product.
update public.products set price = 1 where name = 'Mechanical Gaming Keyboard';
-- expected: ERROR: new row violates row-level security policy for table "products"

-- 6) A client must not read the webhook log.
select * from public.payment_webhook_events;
-- expected: ERROR: permission denied for table payment_webhook_events

-- 7) A client must not read the guest sessions.
select * from public.guest_sessions;
-- expected: ERROR: permission denied for table guest_sessions

-- 8) A client must not call the order creation function.
select public.create_order(
    '00000000-0000-0000-0000-000000000000', 1, auth.uid(), null, null, null);
-- expected: ERROR: permission denied for function create_order

-- 9) A client must not call the webhook function.
select public.apply_xendit_invoice_event(
    'inv', 'ext', 'PAID', 150000, 'PHP', now(), 'GCASH', 'key', '{}'::jsonb);
-- expected: ERROR: permission denied for function apply_xendit_invoice_event
