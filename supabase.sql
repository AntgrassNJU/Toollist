-- ============================================================
--  问题求解·待办清单  数据库初始化脚本
--  用法：Supabase 控制台 → 左侧 SQL Editor → New query
--       把本文件全部内容粘贴进去 → Run
--  可重复执行（幂等），改错了重跑一遍即可。
-- ============================================================


-- ---------- 1. 建表 ------------------------------------------
-- 三类清单（A/B/C）共用这一张表，靠 category 区分。
create table if not exists public.tasks (
  id          uuid        primary key,                       -- 客户端生成，见 README「为什么不用 auto id」
  user_id     uuid        not null default auth.uid(),       -- 归属者；RLS 靠它判断"这是谁的数据"
  category    text        not null check (category in ('A','B','C')),
  title       text        not null,
  note        text        not null default '',
  due_at      timestamptz,                                   -- 可空：只有 A 类需要 DDL
  done        boolean     not null default false,
  pinned      boolean     not null default false,            -- B 类置顶用
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- 若你之前跑过旧版本，用这几行补上后来新增的列（列已存在会报错，可忽略）
-- alter table public.tasks add column if not exists note   text not null default '';
-- alter table public.tasks add column if not exists pinned boolean not null default false;


-- ---------- 2. 索引 ------------------------------------------
-- 你的每次查询都是"某人的某类清单，按时间排"，索引照着这个来。
create index if not exists tasks_user_cat_idx
  on public.tasks (user_id, category, created_at desc);


-- ---------- 3. updated_at 自动维护 ----------------------------
-- 让数据库自己写 updated_at，前端就不需要每次都记得带上它。
-- 少一处"靠自觉"的地方，就少一类 bug。
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists tasks_touch_updated_at on public.tasks;
create trigger tasks_touch_updated_at
  before update on public.tasks
  for each row execute function public.touch_updated_at();


-- ---------- 4. 行级安全（RLS） --------------------------------
-- 这是整个安全模型的核心：即使别人拿到了你的 anon key，
-- 数据库也只会返回 user_id = 他自己 的行。
alter table public.tasks enable row level security;

-- 先删后建，保证可重复执行
drop policy if exists "own_select" on public.tasks;
drop policy if exists "own_insert" on public.tasks;
drop policy if exists "own_update" on public.tasks;
drop policy if exists "own_delete" on public.tasks;

create policy "own_select" on public.tasks
  for select using (auth.uid() = user_id);

-- with check 是"写入后必须满足"的条件：
-- 它挡住了"把自己创建的行的 user_id 伪造成别人的"这种玩法。
create policy "own_insert" on public.tasks
  for insert with check (auth.uid() = user_id);

create policy "own_update" on public.tasks
  for update using (auth.uid() = user_id)
            with check (auth.uid() = user_id);

create policy "own_delete" on public.tasks
  for delete using (auth.uid() = user_id);


-- ---------- 5. （可选）实时推送 -------------------------------
-- 开启后两台设备能"一边改，另一边立刻变"。
-- 如果 Supabase 免费额度里 Realtime 不可用，跳过这一步也不影响使用。
-- alter publication supabase_realtime add table public.tasks;


-- ---------- 6. 自检 ------------------------------------------
-- 跑完后执行这句，应看到 rowsecurity = true
-- select relname, relrowsecurity from pg_class where relname = 'tasks';
