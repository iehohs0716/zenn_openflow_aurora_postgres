-- R: 現在の件数と、直近の変更を表示する
-- 変数: count (表示する件数。batch_id は使わないが、他の操作と引数をそろえるため渡される)

SELECT 'customers' AS table_name, count(*) AS rows FROM sample.customers
UNION ALL
SELECT 'orders', count(*) FROM sample.orders;

SELECT status, count(*) AS orders, sum(total_amount) AS total_amount
FROM sample.orders
GROUP BY status
ORDER BY status;

SELECT order_id, customer_id, status, total_amount, last_batch_id, updated_at
FROM sample.orders
ORDER BY updated_at DESC, order_id DESC
LIMIT :count;
