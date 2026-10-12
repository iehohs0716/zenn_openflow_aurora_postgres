-- サンプルの初期データ (PostgreSQL)
-- 繰り返し実行しても増えない (顧客はメールアドレスで重複を除き、注文は 1 件もないときだけ入れる)。
-- last_batch_id は 'seed'。

INSERT INTO sample.customers (name, email, is_active, attributes, last_batch_id)
VALUES
    ('Alice Tanaka',  'alice@example.com', true,  '{"rank": 3, "tags": ["vip"]}',        'seed'),
    ('Bob Suzuki',    'bob@example.com',   true,  '{"rank": 1, "tags": []}',             'seed'),
    ('Carol Sato',    'carol@example.com', true,  '{"rank": 2, "tags": ["newsletter"]}', 'seed'),
    ('Dave Ito',      'dave@example.com',  false, '{"rank": 1, "tags": []}',             'seed'),
    ('Eve Watanabe',  'eve@example.com',   true,  '{"rank": 5, "tags": ["vip", "beta"]}', 'seed')
ON CONFLICT (email) DO NOTHING;

INSERT INTO sample.orders (customer_id, status, total_amount, ordered_on, last_batch_id)
SELECT c.customer_id,
       s.status,
       s.total_amount,
       current_date - s.days_ago,
       'seed'
FROM sample.customers AS c
JOIN (VALUES
    ('alice@example.com', 'shipped',   12800.00, 10),
    ('alice@example.com', 'paid',       3200.50,  2),
    ('bob@example.com',   'pending',     980.00,  1),
    ('carol@example.com', 'cancelled',  4500.00,  7),
    ('eve@example.com',   'shipped',   25000.00, 14),
    ('eve@example.com',   'pending',    1200.75,  0)
) AS s (email, status, total_amount, days_ago) ON s.email = c.email
WHERE NOT EXISTS (SELECT 1 FROM sample.orders);
