-- Openflow (PostgreSQL コネクタ) が論理レプリケーションで変更を読み取るためのユーザー (PostgreSQL)
-- 繰り返し実行できる。パスワードは環境変数 REPL_PASSWORD から取り込む
-- (SQL ファイルにも Terraform の state にも書かない。scripts/4_execute_sql_to_aurora.sh が渡す)
--
-- Aurora では REPLICATION 属性ではなく rds_replication ロールを付与する。
-- 接続先は必ずライター (リーダーからは論理デコードできない)。

\getenv repl_password REPL_PASSWORD

SELECT format('CREATE USER openflow_repl WITH PASSWORD %L', :'repl_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'openflow_repl') \gexec

SELECT format('ALTER USER openflow_repl WITH PASSWORD %L', :'repl_password')
WHERE EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'openflow_repl') \gexec

GRANT rds_replication TO openflow_repl;

-- 初回スナップショットで対象テーブルを SELECT するための権限
GRANT USAGE ON SCHEMA sample TO openflow_repl;
GRANT SELECT ON ALL TABLES IN SCHEMA sample TO openflow_repl;
ALTER DEFAULT PRIVILEGES IN SCHEMA sample GRANT SELECT ON TABLES TO openflow_repl;
