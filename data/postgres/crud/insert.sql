-- C: 顧客と注文を :count 件ずつ追加する
-- 変数: count (件数) / batch_id (この実行の識別子。last_batch_id と行の内容に入る)

BEGIN;

WITH new_customers AS (
    INSERT INTO sample.customers (name, email, attributes, last_batch_id)
    SELECT 'customer-' || :'batch_id' || '-' || g,
           'user-' || :'batch_id' || '-' || g || '@example.com',
           jsonb_build_object('rank', (g % 5) + 1, 'batch', :'batch_id'),
           :'batch_id'
    FROM generate_series(1, :count) AS g
    RETURNING customer_id
)
INSERT INTO sample.orders (customer_id, status, total_amount, last_batch_id)
SELECT customer_id,
       'pending',
       round((random() * 10000)::numeric, 2),
       :'batch_id'
FROM new_customers;

COMMIT;

SELECT 'insert' AS operation, :'batch_id' AS batch_id,
       (SELECT count(*) FROM sample.customers WHERE last_batch_id = :'batch_id') AS customers,
       (SELECT count(*) FROM sample.orders    WHERE last_batch_id = :'batch_id') AS orders;
