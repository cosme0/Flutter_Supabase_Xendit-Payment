-- =============================================================================
-- BMC Finals Project - student_shop
-- Demo catalogue (Supabase project: kfvxqsxycpmawgbwugyr)
--
-- The flagship demo product is the "Mechanical Gaming Keyboard" priced at
-- PHP 1,500.00 as required by the Act 4 guidelines.
--
-- The script is idempotent: running it again refreshes the demo catalogue
-- instead of creating duplicates (products.name is unique).
-- =============================================================================

insert into public.products (name, price, image_url)
values
    (
        'Mechanical Gaming Keyboard',
        1500.00,
        'https://images.unsplash.com/photo-1595225476474-87563907a212?w=300'
    ),
    (
        'Wireless Ergonomic Mouse',
        850.00,
        'https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?w=300'
    ),
    (
        'USB-C Hub Multiport Adapter',
        600.00,
        'https://images.unsplash.com/photo-1625842268584-8f3296236761?w=300'
    )
on conflict (name) do update
    set price     = excluded.price,
        image_url = excluded.image_url;
