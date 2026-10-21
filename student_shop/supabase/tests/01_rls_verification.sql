-- =============================================================================
-- BMC Finals Project - student_shop
-- Row Level Security verification
--
-- Run it in the Supabase SQL editor. Every check prints PASS or FAIL.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. the catalogue is readable by everybody (the app needs it)
-- -----------------------------------------------------------------------------
do $$
declare
    rows_found bigint;
begin
    select count(*) into rows_found from public.products;
    raise notice 'PASS - products are readable (% rows)', rows_found;
exception
    when others then
        raise notice 'FAIL - products are not readable: %', sqlerrm;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. the order history is readable by everybody (the app needs it)
-- -----------------------------------------------------------------------------
do $$
declare
    rows_found bigint;
begin
    select count(*) into rows_found from public.orders;
    raise notice 'PASS - orders are readable (% rows)', rows_found;
exception
    when others then
        raise notice 'FAIL - orders are not readable: %', sqlerrm;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. the `anon` role may NOT create an order
--    (only the edge functions may do that)
-- -----------------------------------------------------------------------------
do $$
declare
begin
    insert into public.orders (external_id, status, product_name, amount)
    values ('rls-test-' || floor(random() * 100000)::text, 'PENDING', 'RLS test', 1);
    raise notice 'FAIL - the anon role was able to create an order';
exception
    when others then
        raise notice 'PASS - the anon role cannot create an order (%)', sqlerrm;
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. the `anon` role may NOT mark an order as paid
--    (only the Xendit webhook may do that)
-- -----------------------------------------------------------------------------
do $$
declare
begin
    update public.orders set status = 'PAID';
    raise notice 'FAIL - the anon role was able to mark an order as PAID';
exception
    when others then
        raise notice 'PASS - the anon role cannot mark an order as PAID (%)', sqlerrm;
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. the `anon` role may NOT change the catalogue
-- -----------------------------------------------------------------------------
do $$
declare
begin
    update public.products set price = 1;
    raise notice 'FAIL - the anon role was able to change the catalogue';
exception
    when others then
        raise notice 'PASS - the anon role cannot change the catalogue (%)', sqlerrm;
end;
$$;
