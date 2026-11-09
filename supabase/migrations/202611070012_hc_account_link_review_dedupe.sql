-- 再次关联时兼容“关联 -> 解绑 -> 再关联”。
--
-- 解绑会把规范账号的 review_events 复制回微信账号；两边因此可能保留同一
-- client_event_id。旧关联函数随后把微信侧事件改挂到规范账号，会撞上
-- review_events(user_id, client_event_id) 的唯一索引并返回 409。
--
-- 保留规范账号已有的事件，删除微信侧的重复副本，再调用已验证过的原事务函数。
alter function public.hc_execute_account_link(text, uuid, uuid, uuid, text)
  rename to hc_execute_account_link_v1;

create or replace function public.hc_execute_account_link(
  p_operation text,
  p_wechat_user_id uuid,
  p_cijing_user_id uuid,
  p_requested_by uuid,
  p_confirmation_version text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_operation = 'link' then
    delete from public.review_events source
    using public.review_events target
    where source.user_id = p_wechat_user_id
      and target.user_id = p_cijing_user_id
      and source.client_event_id is not null
      and source.client_event_id = target.client_event_id;
  end if;

  return public.hc_execute_account_link_v1(
    p_operation,
    p_wechat_user_id,
    p_cijing_user_id,
    p_requested_by,
    p_confirmation_version
  );
end;
$$;

revoke all on function public.hc_execute_account_link_v1(text, uuid, uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.hc_execute_account_link(text, uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.hc_execute_account_link(text, uuid, uuid, uuid, text)
  to service_role;
