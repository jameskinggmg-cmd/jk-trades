-- Pin every callable marketplace SECURITY DEFINER RPC to an empty search_path.
-- All referenced application objects are schema-qualified in these function bodies.
alter function public.withdraw_job_quote(uuid) set search_path = '';
alter function public.mark_conversation_message_read(uuid) set search_path = '';
alter function public.mark_notification_read(uuid) set search_path = '';
