"""D11: correct the industrial-park solar class 2.5 candidates (4 -> 60 MW/km2).

The QGIS assessment behind ip_generators.csv multiplied the solar class 2.5 area by the wind
density (4 MW/km2) instead of the solar one (60 MW/km2), so every solar class 2.5 candidate is
15x too small. In every solar class 2.5 row, this scales by 15 each of Max_Cap_MW and
Existing_Cap_MW whose value is one of the QGIS solar class 2.5 figures
(final_capacity_csv/candidate_solar_2_5.csv). A value that is not one of them was copied from
somewhere else by hand (a D5 data error) and is left alone; a row where neither column is a QGIS
solar 2.5 figure stops the script. Every change is logged to
data_indonesia/corrections/d11_solar_class_2_5.csv.

Usage (from the repository root; refuses to run twice):
  python3 scripts/fix_solar_class_2_5.py [--qgis-csv PATH]
"""
import argparse
import csv
import glob
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = os.path.join(ROOT, 'data_indonesia', 'corrections', 'd11_solar_class_2_5.csv')
FACTOR = 60 / 4


def fmt(x):
    return f'{x:.6f}'.rstrip('0').rstrip('.')


def parse(line):
    return next(csv.reader([line]))


def unparse(fields):
    out = io.StringIO()
    csv.writer(out, lineterminator='').writerow(fields)
    return out.getvalue()


def qgis_values(path):
    with open(path, newline='') as f:
        return [float(r['solar_MW_sum']) for r in csv.DictReader(f) if r['solar_MW_sum']]


def is_qgis(v, ref):
    return v != '' and any(abs(float(v) - q) <= 1e-6 * max(1.0, q) for q in ref)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--qgis-csv', default=os.path.expanduser(
        '~/Desktop/QGIS_NEW/final_capacity_csv/candidate_solar_2_5.csv'))
    args = ap.parse_args()
    if os.path.exists(LOG):
        raise SystemExit(f'{LOG} exists: D11 has already been applied')
    ref = qgis_values(args.qgis_csv)
    log = []
    for path in sorted(glob.glob(os.path.join(ROOT, 'data_indonesia', '*', '*', 'ip_generators.csv'))):
        raw = open(path, 'rb').read()
        bom = raw.startswith(b'\xef\xbb\xbf')
        text = raw.decode('utf-8-sig')
        eol = '\r\n' if '\r\n' in text else '\n'
        # edit only the affected lines, so line endings and every other byte stay as they are
        lines = text.split(eol)
        head = parse(lines[0])
        c = {k: head.index(k) for k in ('R_ID', 'Resource', 'technology', 'class', 'New_Build',
                                       'Max_Cap_MW', 'Existing_Cap_MW')}
        year, island = path.split(os.sep)[-3:-1]
        changed = 0
        for i, line in enumerate(lines[1:], start=1):
            if not line:
                continue
            r = parse(line)
            if r[c['technology']] != 'solar' or r[c['class']] == '' or float(r[c['class']]) != 2.5:
                continue
            assert unparse(r) == line, f'{path}:{i + 1} does not round-trip through csv'
            old = {k: r[c[k]] for k in ('Max_Cap_MW', 'Existing_Cap_MW')}
            scaled = [k for k, v in old.items() if is_qgis(v, ref)]
            if not scaled:
                raise SystemExit(f'{year}/{island} R_ID {r[c["R_ID"]]}: neither capacity column is a '
                                 'QGIS solar 2.5 figure; check the row by hand')
            for k in scaled:
                r[c[k]] = fmt(float(old[k]) * FACTOR)
            log.append({'year': year, 'island': island, 'R_ID': r[c['R_ID']],
                        'Resource': r[c['Resource']],
                        'Max_Cap_MW_old': old['Max_Cap_MW'], 'Max_Cap_MW_new': r[c['Max_Cap_MW']],
                        'Existing_Cap_MW_old': old['Existing_Cap_MW'],
                        'Existing_Cap_MW_new': r[c['Existing_Cap_MW']],
                        'scaled': '+'.join(scaled),
                        'note': '' if len(scaled) == 2 else
                                f'{"Existing_Cap_MW" if scaled == ["Max_Cap_MW"] else "Max_Cap_MW"} '
                                'is not a QGIS solar 2.5 figure (copied by hand, D5); left as is'})
            lines[i] = unparse(r)
            changed += 1
        with open(path, 'wb') as f:
            f.write((b'\xef\xbb\xbf' if bom else b'') + eol.join(lines).encode('utf-8'))
        print(f'{year}/{island}: {changed} solar class 2.5 rows corrected')
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(log[0]))
        w.writeheader()
        w.writerows(log)
    print(f'logged {len(log)} rows to {os.path.relpath(LOG, ROOT)}')


if __name__ == '__main__':
    main()
