"""Генерує supabase/seed.sql зі списків студентів і банку питань."""
import json, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
st = json.loads((root/'private/data/students.json').read_text())
qs = json.loads((root/'private/data/questions.json').read_text())
def s(x): return "'" + x.replace("'", "''") + "'"
out = ["-- Згенеровано tools/build_seed.py. Повторний запуск оновлює питання, спроби не чіпає.", "begin;"]
out.append("insert into students (grp, name) values")
out.append(",\n".join(f"  ({s(g)}, {s(n)})" for g, names in st.items() for n in names) + "\non conflict do nothing;")
out.append("insert into questions (id, topic, text, options, correct, image) values")
out.append(",\n".join(f"  ({i+1}, {s(q['t'])}, {s(q['q'])}, {s(json.dumps(q['o'], ensure_ascii=False))}::jsonb, 0, {s(q['img']) if q.get('img') else 'null'})" for i, q in enumerate(qs))
           + "\non conflict (id) do update set topic=excluded.topic, text=excluded.text, options=excluded.options, correct=excluded.correct, image=excluded.image;")
out.append("commit;")
(root/'private/seed.sql').write_text("\n".join(out) + "\n")
print(len(qs), "питань,", sum(map(len, st.values())), "студентів")
