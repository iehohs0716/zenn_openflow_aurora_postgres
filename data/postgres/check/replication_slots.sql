-- レプリケーションスロットの状態 (PostgreSQL。読み取りのみ)
-- Openflow のコネクタが接続していれば、スロットができて active が t になる。
-- スロットがない場合は、コネクタがまだレプリケーションを始められていない。
SELECT slot_name, plugin, active, restart_lsn, confirmed_flush_lsn FROM pg_replication_slots;
