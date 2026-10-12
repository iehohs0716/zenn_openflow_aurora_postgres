-- サンプルのスキーマとテーブル (PostgreSQL)
-- CDC の検証用。繰り返し実行できる (IF NOT EXISTS)。
--
-- 主キーを必ず持たせる。論理レプリケーションで UPDATE / DELETE を送るには、
-- 行を識別する主キー (または REPLICA IDENTITY) が必要なため。
-- last_batch_id は「どの実行で最後に変更した行か」を示す。Snowflake 側で、
-- 欠落・重複・順序を確認するときに、実行 (バッチ) 単位で突き合わせるために使う。

CREATE SCHEMA IF NOT EXISTS sample;

CREATE TABLE IF NOT EXISTS sample.customers (
    customer_id   bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          text        NOT NULL,
    email         text        NOT NULL UNIQUE,
    is_active     boolean     NOT NULL DEFAULT true,
    attributes    jsonb       NOT NULL DEFAULT '{}'::jsonb,
    last_batch_id text        NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sample.orders (
    order_id      bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id   bigint        NOT NULL REFERENCES sample.customers (customer_id),
    status        text          NOT NULL CHECK (status IN ('pending', 'paid', 'shipped', 'cancelled')),
    total_amount  numeric(12,2) NOT NULL,
    ordered_on    date          NOT NULL DEFAULT current_date,
    last_batch_id text          NOT NULL,
    created_at    timestamptz   NOT NULL DEFAULT now(),
    updated_at    timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS orders_customer_id_idx ON sample.orders (customer_id);
