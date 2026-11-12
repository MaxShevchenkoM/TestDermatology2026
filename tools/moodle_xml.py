"""Експорт банку питань у Moodle XML (з вбудованими фото, категорія = тема)."""
import json, base64, pathlib, sys
from xml.sax.saxutils import escape
root = pathlib.Path(__file__).resolve().parent.parent
qs = json.loads(pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else root / 'private/data/questions.json').read_text())
out = ['<?xml version="1.0" encoding="UTF-8"?>', '<quiz>']
BASE = sys.argv[3] if len(sys.argv) > 3 else 'ЄДКІ Інфекційна дерматологія'
cur = None
for i, q in enumerate(qs, 1):
    if q['t'] != cur:
        cur = q['t']
        out.append(f'<question type="category"><category><text>$course$/top/{escape(BASE)}/{escape(cur)}</text></category></question>')
    files, html = '', f'<p>{escape(q["q"])}</p>'
    if q.get('img'):
        fn = f'{q["img"]}.jpg'
        b64 = base64.b64encode((root / 'site/img' / fn).read_bytes()).decode()
        html += f'<p><img src="@@PLUGINFILE@@/{fn}" alt="Клінічне фото" style="max-width:100%;max-height:420px"></p>'
        files = f'<file name="{fn}" path="/" encoding="base64">{b64}</file>'
    ans = ''.join(
        f'<answer fraction="{100 if k == 0 else 0}" format="html"><text>{escape(o)}</text><feedback format="html"><text></text></feedback></answer>'
        for k, o in enumerate(q['o']))
    out.append(f'''<question type="multichoice">
<name><text>{i:02d}. {escape(q["t"])}</text></name>
<questiontext format="html"><text><![CDATA[{html}]]></text>{files}</questiontext>
<generalfeedback format="html"><text></text></generalfeedback>
<defaultgrade>1</defaultgrade><penalty>0.3333333</penalty><hidden>0</hidden>
<single>true</single><shuffleanswers>true</shuffleanswers><answernumbering>ABCD</answernumbering>
{ans}
</question>''')
out.append('</quiz>')
dst = pathlib.Path(sys.argv[1])
dst.write_text('\n'.join(out), encoding='utf-8')
print(len(qs), 'питань →', dst, dst.stat().st_size // 1024, 'KB')
