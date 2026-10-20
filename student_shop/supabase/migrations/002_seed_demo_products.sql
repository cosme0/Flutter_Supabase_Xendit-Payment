-- =============================================================================
-- BMC Finals Project - student_shop
-- Demo catalogue (Supabase project: BMC-ecom1)
--
-- The flagship demo product is the "Mechanical Gaming Keyboard" priced at
-- PHP 1,500.00 as required by the Act 4 guidelines.
--
-- The script is idempotent: running it again refreshes the demo catalogue
-- instead of creating duplicates (products.name is unique).
-- =============================================================================

insert into public.products (name, description, price, image_url, stock_quantity, is_active)
values
    (
        'Mechanical Gaming Keyboard',
        'A full-size 87-key mechanical gaming keyboard with RGB backlighting, '
        || 'tactile switches and a detachable USB-C cable. Perfect for gaming sessions '
        || 'and long typing hours at the university lab.',
        1500.00,
        'https://images.unsplash.com/photo-1587829741301-dc798b83add3?auto=format&fit=crop&w=800&q=80',
        25,
        true
    ),
    (
        'Wireless Gaming Mouse',
        'A lightweight 58g wireless mouse with 8000 DPI sensor, 2.4GHz receiver and '
        || 'up to 70 hours of battery life.',
        450.00,
        'https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?auto=format&fit=crop&w=800&q=80',
        40,
        true
    ),
    (
        'USB-C Docking Hub',
        'A 7-in-1 USB-C hub with HDMI 4K, USB 3.0 ports, SD card reader and 65W '
        || 'power delivery for laptops used in class.',
        850.00,
        'https://images.unsplash.com/photo-1625842268584-8f3296236761?auto=format&fit=crop&w=800&q=80',
        18,
        true
    )
on conflict (name) do update
    set description    = excluded.description,
        price          = excluded.price,
        image_url      = excluded.image_url,
        stock_quantity = excluded.stock_quantity,
        is_active      = excluded.is_active,
        updated_at     = now();
