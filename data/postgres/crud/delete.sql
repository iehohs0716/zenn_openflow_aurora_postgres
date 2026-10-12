-- D: 出荷済みの注文を古い順に最大 :count 件削除し、注文のなくなった顧客を最大 :count 件削除する
-- 変数: count (件数) / batch_id (この実行の識別子。削除した行は残らないため、件数だけを表示する)
--
-- 顧客の削除は、注文の削除より後の別の文で行う (同じ文の中では、削除前のスナップショットを見るため、
-- この実行で注文がなくなった顧客を拾えない)。件数は \gset で psql の変数に受け渡す。

BEGIN;

WITH deleted AS (
    DELETE FROM sample.orders
    WHERE order_id IN (
        SELECT order_id FROM sample.orders WHERE status = 'shipped' ORDER BY order_id LIMIT :count
    )
    RETURNING order_id
)
SELECT count(*) AS deleted_orders FROM deleted \gset

WITH deleted AS (
    DELETE FROM sample.customers
    WHERE customer_id IN (
        SELECT c.customer_id
        FROM sample.customers AS c
        WHERE NOT EXISTS (SELECT 1 FROM sample.orders AS o WHERE o.customer_id = c.customer_id)
        ORDER BY c.customer_id
        LIMIT :count
    )
    RETURNING customer_id
)
SELECT count(*) AS deleted_customers FROM deleted \gset

COMMIT;

SELECT 'delete' AS operation, :'batch_id' AS batch_id,
       :deleted_customers AS customers, :deleted_orders AS orders;
