-- Openflow に送る変更の対象 (publication) を定義する (PostgreSQL)
-- 繰り返し実行できる。コネクタの Publication Name にはここで作る名前 (openflow_pub) を指定する。
-- 前提: schema/ のテーブルが作成済みであること
--
-- 対象テーブルを増やすときは、下の配列に追加して再実行する。
-- 主キーのあるテーブルは REPLICA IDENTITY DEFAULT で UPDATE / DELETE の行を識別できる。

DO $$
DECLARE
    t text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'openflow_pub') THEN
        CREATE PUBLICATION openflow_pub WITH (publish_via_partition_root = true);
    END IF;

    FOREACH t IN ARRAY ARRAY['sample.customers', 'sample.orders'] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'openflow_pub' AND schemaname || '.' || tablename = t
        ) THEN
            EXECUTE format('ALTER PUBLICATION openflow_pub ADD TABLE %s', t);
        END IF;
        EXECUTE format('ALTER TABLE %s REPLICA IDENTITY DEFAULT', t);
    END LOOP;
END
$$;
