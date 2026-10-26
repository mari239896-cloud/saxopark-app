-- 体験中の受講生の提出を、体験添削会（members.trial_session_id）に自動で紐づける
create or replace function public.link_trial_submission_session()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
  declare
    t_session uuid;
  begin
    if new.critique_session_id is not null
       or new.in_reply_to_review_id is not null
       or new.extra_assignment_id is not null then
      return new;
    end if;

    select m.trial_session_id into t_session
      from public.members m
     where m.user_id = new.user_id
       and m.status = 'trial'
       and m.trial_session_id is not null
     order by m.updated_at desc
     limit 1;

    if t_session is not null then
      new.critique_session_id := t_session;
    end if;
    return new;
  end;
$function$;

-- BEFORE トリガーは名前順に動くので、締切チェック（submissions_group_deadline）より先に動く名前にする
drop trigger if exists submissions_a_link_trial_session on public.submissions;
create trigger submissions_a_link_trial_session
  before insert on public.submissions
  for each row execute function public.link_trial_submission_session();

-- 締切チェック：体験中の受講生が自分の体験添削会に出す提出は締切後も受け付ける
create or replace function public.check_group_submission_deadline()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
  declare
    s_at timestamptz;
    s_type text;
  begin
    if new.critique_session_id is null then
      return new;
    end if;
    if coalesce(auth.role(), '') = 'service_role' then
      return new;
    end if;

    if exists (
      select 1 from public.members m
       where m.user_id = new.user_id
         and m.status = 'trial'
         and m.trial_session_id = new.critique_session_id
    ) then
      return new;
    end if;

    select scheduled_at, event_type into s_at, s_type
      from public.critique_sessions where id = new.critique_session_id;

    if s_type is null or position('グループ添削会' in s_type) = 0 then
      return new;
    end if;

    if now() >= s_at - interval '48 hours' then
      raise exception '提出の締切（添削会の48時間前）を過ぎています';
    end if;
    return new;
  end;
$function$;
