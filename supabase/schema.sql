-- ЄДКІ-тест «Інфекційна дерматологія» — схема для Supabase
-- Вставити цілком у Supabase → SQL Editor → Run.
-- Після запуску змініть пароль викладача на сторінці teacher.html.

create extension if not exists pgcrypto with schema extensions;

-- ---------- Таблиці ----------
create table if not exists settings (
  id int primary key default 1 check (id = 1),
  is_open boolean not null default false,       -- чи відкритий тест для студентів
  n_questions int not null default 30,          -- скільки питань отримує студент
  time_limit_min int not null default 40,       -- обмеження часу, хв
  teacher_pw text not null                      -- bcrypt-хеш пароля викладача
);

create table if not exists students (
  id serial primary key,
  grp text not null,
  name text not null,
  unique (grp, name)
);

create table if not exists questions (
  id int primary key,
  topic text not null,
  text text not null,
  options jsonb not null,     -- масив із 5 рядків
  correct int not null,       -- індекс правильного варіанта в options
  image text                  -- ім'я фото в site/img без розширення
);

create table if not exists attempts (
  id uuid primary key default gen_random_uuid(),
  student_id int not null unique references students(id),  -- одна спроба на студента
  token uuid not null default gen_random_uuid(),
  question_ids int[] not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  answers jsonb,              -- {question_id: обраний індекс}
  n_correct int,
  n_total int,
  ip text,
  user_agent text,
  ip_finish text
);

alter table settings  enable row level security;
alter table students  enable row level security;
alter table questions enable row level security;
alter table attempts  enable row level security;
-- Політик немає: анонімний ключ не читає таблиці напряму, лише через функції нижче.

-- ---------- Допоміжне ----------
create or replace function _hdr(h text) returns text language sql stable as $$
  select coalesce(current_setting('request.headers', true)::json ->> h, '')
$$;

create or replace function _ip() returns text language sql stable as $$
  select coalesce(nullif(_hdr('cf-connecting-ip'), ''), split_part(_hdr('x-forwarded-for'), ',', 1))
$$;

create or replace function _ects(pct numeric) returns text language sql immutable as $$
  select case when pct >= 90 then 'A' when pct >= 82 then 'B' when pct >= 74 then 'C'
              when pct >= 64 then 'D' when pct >= 60 then 'E' when pct >= 35 then 'FX' else 'F' end
$$;

create or replace function _nat(pct numeric) returns text language sql immutable as $$
  select case when pct >= 90 then 'відмінно' when pct >= 74 then 'добре'
              when pct >= 60 then 'задовільно' else 'незадовільно' end
$$;

-- ---------- Функції для студента ----------
drop function if exists public_students();
create or replace function public_students()
returns table (id int, grp text, name text, done boolean, is_open boolean, n_q int, mins int)
language sql security definer set search_path = public, extensions as $$
  select s.id, s.grp, s.name,
         exists (select 1 from attempts a where a.student_id = s.id and a.finished_at is not null),
         (select is_open from settings), (select n_questions from settings), (select time_limit_min from settings)
  from students s order by s.grp, s.name
$$;

create or replace function start_attempt(p_student int)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare st settings; a attempts; qs json;
begin
  select * into st from settings;
  if not st.is_open then raise exception 'Тест зараз закритий'; end if;
  if not exists (select 1 from students where id = p_student) then raise exception 'Студента не знайдено'; end if;

  select * into a from attempts where student_id = p_student;
  if found and a.finished_at is not null then
    raise exception 'Цей студент уже пройшов тест';
  end if;
  if not found then
    insert into attempts (student_id, question_ids, ip, user_agent)
    values (p_student,
            array(select id from questions order by random() limit st.n_questions),
            _ip(), _hdr('user-agent'))
    returning * into a;
  end if;

  -- питання в порядку спроби, варіанти перемішані; правильну відповідь не віддаємо
  select json_agg(json_build_object(
           'id', q.id, 'text', q.text, 'image', q.image,
           'options', (select json_agg(json_build_object('k', o.ord - 1, 't', o.val) order by random())
                       from jsonb_array_elements_text(q.options) with ordinality as o(val, ord)))
         order by array_position(a.question_ids, q.id))
    into qs
  from questions q where q.id = any(a.question_ids);

  return json_build_object('attempt', a.id, 'token', a.token, 'started_at', a.started_at,
                           'deadline', a.started_at + make_interval(mins => st.time_limit_min),
                           'questions', qs);
end $$;

create or replace function submit_attempt(p_attempt uuid, p_token uuid, p_answers jsonb)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare a attempts; nc int; nt int;
begin
  select * into a from attempts where id = p_attempt and token = p_token for update;
  if not found then raise exception 'Спробу не знайдено'; end if;
  if a.finished_at is not null then raise exception 'Тест уже здано'; end if;

  select count(*) filter (where (p_answers ->> q.id::text)::int = q.correct), count(*)
    into nc, nt
  from questions q where q.id = any(a.question_ids);

  update attempts set finished_at = now(), answers = p_answers, n_correct = nc, n_total = nt,
         ip_finish = _ip()
   where id = a.id;

  return json_build_object('n_correct', nc, 'n_total', nt,
                           'pct', round(100.0 * nc / nt, 1),
                           'ects', _ects(100.0 * nc / nt), 'nat', _nat(100.0 * nc / nt));
end $$;

-- ---------- Функції для викладача ----------
create or replace function _check_pw(p_pw text) returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from settings where teacher_pw = crypt(p_pw, teacher_pw)) then
    raise exception 'Невірний пароль';
  end if;
end $$;

create or replace function teacher_results(p_pw text)
returns json language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _check_pw(p_pw);
  return json_build_object(
    'settings', (select json_build_object('is_open', is_open, 'n_questions', n_questions,
                                          'time_limit_min', time_limit_min) from settings),
    'rows', (select coalesce(json_agg(r order by r.grp, r.name), '[]'::json) from (
      select s.id, s.grp, s.name,
             a.started_at, a.finished_at,
             round(extract(epoch from a.finished_at - a.started_at) / 60, 1) as minutes,
             a.n_correct, a.n_total,
             round(100.0 * a.n_correct / nullif(a.n_total, 0), 1) as pct,
             case when a.n_total > 0 then _ects(100.0 * a.n_correct / a.n_total) end as ects,
             case when a.n_total > 0 then _nat(100.0 * a.n_correct / a.n_total) end as nat,
             a.ip, a.ip_finish, a.user_agent
      from students s left join attempts a on a.student_id = s.id) r),
    'items', (select coalesce(json_agg(i order by i.pct nulls last), '[]'::json) from (
      select q.id, q.topic, q.text, count(a.id) as shown,
             count(a.id) filter (where (a.answers ->> q.id::text)::int = q.correct) as correct,
             round(100.0 * count(a.id) filter (where (a.answers ->> q.id::text)::int = q.correct)
                   / nullif(count(a.id), 0), 1) as pct
      from questions q
      left join attempts a on a.finished_at is not null and q.id = any(a.question_ids)
      group by q.id) i)
  );
end $$;

create or replace function teacher_set(p_pw text, p_open boolean, p_n int, p_minutes int)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _check_pw(p_pw);
  update settings set is_open = p_open, n_questions = p_n, time_limit_min = p_minutes where id = 1;
end $$;

-- скинути спробу студента (напр., зник інтернет) — студент зможе пройти заново
create or replace function teacher_reset(p_pw text, p_student int)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _check_pw(p_pw);
  delete from attempts where student_id = p_student;
end $$;

create or replace function teacher_change_pw(p_pw text, p_new text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _check_pw(p_pw);
  if length(p_new) < 6 then raise exception 'Пароль має містити щонайменше 6 символів'; end if;
  update settings set teacher_pw = crypt(p_new, gen_salt('bf')) where id = 1;
end $$;

revoke all on function _check_pw(text), _hdr(text), _ip() from public, anon, authenticated;
grant execute on function public_students(), start_attempt(int), submit_attempt(uuid, uuid, jsonb),
  teacher_results(text), teacher_set(text, boolean, int, int), teacher_reset(text, int), teacher_change_pw(text, text) to anon;

-- ---------- Пароль викладача ----------
-- Початковий пароль 'zmini-mene' — змініть його на сторінці викладача (кнопка «Змінити пароль»).
insert into settings (id, teacher_pw) values (1, extensions.crypt('zmini-mene', extensions.gen_salt('bf')))
on conflict (id) do nothing;
