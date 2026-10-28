"""D4: rebuild the Jawa-Bali industrial-park hourly profiles with one column per generator.

data_indonesia/<year>/jawa_bali/ip_generators_variability.csv named its columns by province
(banten, banten.1, ..., Unnamed: 49, ...) and had 181 columns for 202 generators, so
align_profiles matched none of them and every Jawa-Bali IP generator ran with a flat 1.0
profile, solar included. This rewrites the file the way the other islands have it: one column
per row of ip_generators.csv, named by Resource, in generator order. Solar takes its province's
solar profile from the old file (each province has exactly one); coal, geothermal and batteries
take 1.0, as on the other islands.

Usage (from the repository root):
  python3 scripts/fix_jawa_bali_ip_profiles.py
"""
import csv
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(path):
    raw = open(path, 'rb').read()
    text = raw.decode('utf-8-sig')
    eol = '\r\n' if '\r\n' in text else '\n'
    return list(csv.reader(io.StringIO(text))), raw.startswith(b'\xef\xbb\xbf'), eol, raw.endswith(eol.encode())


def province_solar_profiles(rows):
    """{province: [hourly values as written]} from the old province-named columns."""
    head, body = rows[0], rows[1:]
    found = {}
    for j, name in enumerate(head[1:], start=1):
        prov = name.split('.')[0]
        col = [r[j] for r in body]
        if not prov or prov.startswith('Unnamed') or any(v in ('', 'NaN', 'nan') for v in col):
            continue
        if all(float(v) == 1.0 for v in col):
            continue
        if prov in found:
            assert found[prov] == col, f'{prov} has more than one solar profile'
        else:
            found[prov] = col
    return found


def rebuild(year):
    d = os.path.join(ROOT, 'data_indonesia', year, 'jawa_bali')
    gens, _, _, _ = read(os.path.join(d, 'ip_generators.csv'))
    gh = gens[0]
    res, prov, tech = gh.index('Resource'), gh.index('Province'), gh.index('technology')
    path = os.path.join(d, 'ip_generators_variability.csv')
    old, bom, eol, trailing = read(path)
    if old[0][1:] == [g[res].strip() for g in gens[1:]]:
        print(f'{year}/jawa_bali: already one column per generator; nothing to do')
        return
    solar = province_solar_profiles(old)
    n = len(old) - 1
    cols = []
    for g in gens[1:]:
        if g[tech] == 'solar':
            cols.append(solar[g[prov]])
        elif g[tech] == 'wind':
            raise SystemExit(f'{year}/jawa_bali: no wind profile source for {g[res]}')
        else:
            cols.append(['1'] * n)
    out = io.StringIO()
    w = csv.writer(out, lineterminator=eol)
    w.writerow(['r_id'] + [g[res].strip() for g in gens[1:]])
    for t in range(n):
        w.writerow([old[t + 1][0]] + [c[t] for c in cols])
    text = out.getvalue()
    if not trailing:
        text = text[:-len(eol)]
    with open(path, 'wb') as f:
        f.write((b'\xef\xbb\xbf' if bom else b'') + text.encode('utf-8'))
    n_solar = sum(g[tech] == 'solar' for g in gens[1:])
    print(f'{year}/jawa_bali: {len(cols)} columns ({n_solar} solar, province profiles: '
          f'{", ".join(sorted(solar))})')


if __name__ == '__main__':
    for year in ('2030', '2035'):
        rebuild(year)
