-- U: 未出荷の注文を最大 :count 件進める (pending → paid → shipped) と、顧客の属性を最大 :count 件更新する
-- 変数: count (件数) / batch_id (この実行の識別子)

BEGIN;

WITH targets AS (
    SELECT order_id
    FROM sample.orders
    WHERE status IN ('pending', 'paid')
    ORDER BY order_id
    LIMIT :count
    FOR UPDATE SKIP LOCKED
)
UPDATE sample.orders AS o
SET status        = CASE o.status WHEN 'pending' THEN 'paid' ELSE 'shipped' END,
    last_batch_id = :'batch_id',
    updated_at    = now()
FROM targets AS t
WHERE o.order_id = t.order_id;

UPDATE sample.customers
SET attributes    = attributes || jsonb_build_object('last_update', :'batch_id'),
    last_batch_id = :'batch_id',
    updated_at    = now()
WHERE customer_id IN (
    SELECT customer_id FROM sample.customers ORDER BY customer_id DESC LIMIT :count
);

COMMIT;

SELECT 'update' AS operation, :'batch_id' AS batch_id,
       (SELECT count(*) FROM sample.customers WHERE last_batch_id = :'batch_id') AS customers,
       (SELECT count(*) FROM sample.orders    WHERE last_batch_id = :'batch_id') AS orders;
