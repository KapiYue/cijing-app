-- 补齐 0007 未撤销的客户端私有表写权限。
-- 客户端读取 hc_profiles 仍保留；写入必须经 hc_* RPC。

revoke insert, update, delete on public.hc_profiles from authenticated;
revoke insert, update, delete on public.hc_word_status from authenticated;
revoke insert, update, delete on public.hc_events from authenticated;