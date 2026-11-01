"""Copy an island's input folder with a different captive coal price, for coal-price sensitivity runs.

The park coal units (ip_generators.csv, Fuel coal_captive) take their fuel cost from the
coal_captive row of fuels_data.csv. This copies data_indonesia/<year>/<island> to
data_indonesia/<year>/<island>_coal<price> and changes only that one Cost_per_MMBtu; every other
file and value is copied byte for byte. The grid's coal fuel (row coal) is not touched.

The price is given in $/t and converted with the website's coal-price slider conversion:
4,200 kcal/kg GAR = 16.67 MMBtu/t, rounded to 3 decimals ($70/t -> 4.199, $100/t -> 5.999
$/MMBtu; the 3.846 $/MMBtu of the base inputs is about $64/t).

A run uses the copy with island: <island>_coal<price> in config.json, which needs island_params
and co2_limits entries under that name in the scenario file (the same values as <island>);
results are then named <scenario>_<island>_coal<price>_<year>_<clean>. The change is logged to
data_indonesia/corrections/coal_price_<year>_<island>_coal<price>.csv.

Usage (from the repository root; refuses to overwrite an existing output folder):
  python3 scripts/coal_price_variant.py --usd-per-t 70 [--year 2035] [--island sulawesi]
"""
import argparse
import csv
import io
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MMBTU_PER_T = 16.67   # 4,200 kcal/kg GAR, as on the website's coal-price slider
FUEL = 'coal_captive'


def parse(line):
    return next(csv.reader([line]))


def unparse(fields):
    out = io.StringIO()
    csv.writer(out, lineterminator='').writerow(fields)
    return out.getvalue()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--usd-per-t', type=int, required=True, help='captive coal price, $/t (4,200 kcal/kg GAR)')
    ap.add_argument('--year', default='2035')
    ap.add_argument('--island', default='sulawesi')
    args = ap.parse_args()
    name = f'{args.island}_coal{args.usd_per_t}'
    src = os.path.join(ROOT, 'data_indonesia', args.year, args.island)
    out = os.path.join(ROOT, 'data_indonesia', args.year, name)
    log_path = os.path.join(ROOT, 'data_indonesia', 'corrections', f'coal_price_{args.year}_{name}.csv')
    for p in (out, log_path):
        if os.path.exists(p):
            raise SystemExit(f'{p} exists; remove it first')

    # read and check fuels_data.csv before writing anything
    path = os.path.join(src, 'fuels_data.csv')
    raw = open(path, 'rb').read()
    text = raw.decode('utf-8-sig')
    eol = '\r\n' if '\r\n' in text else '\n'
    lines = text.split(eol)
    head = parse(lines[0])
    fuel, cost = head.index('Fuel'), head.index('Cost_per_MMBtu')
    hits = [i for i, line in enumerate(lines[1:], start=1) if line and parse(line)[fuel] == FUEL]
    if len(hits) != 1:
        raise SystemExit(f'{path}: {len(hits)} {FUEL} rows, expected 1')
    i = hits[0]
    r = parse(lines[i])
    assert unparse(r) == lines[i], f'{path}:{i + 1} does not round-trip through csv'
    old = r[cost]
    new = f'{args.usd_per_t / MMBTU_PER_T:.3f}'
    r[cost] = new
    lines[i] = unparse(r)

    shutil.copytree(src, out)
    with open(os.path.join(out, 'fuels_data.csv'), 'wb') as f:
        f.write((b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'') + eol.join(lines).encode('utf-8'))
    with open(log_path, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['year', 'source', 'output', 'file', 'Fuel', 'Cost_per_MMBtu_old', 'Cost_per_MMBtu_new',
                    'usd_per_t', 'mmbtu_per_t', 'usd_per_t_old'])
        w.writerow([args.year, os.path.relpath(src, ROOT), os.path.relpath(out, ROOT), 'fuels_data.csv', FUEL,
                    old, new, args.usd_per_t, MMBTU_PER_T, f'{float(old) * MMBTU_PER_T:.1f}'])
    print(f'{os.path.relpath(out, ROOT)}: {FUEL} Cost_per_MMBtu {old} -> {new} '
          f'(${args.usd_per_t}/t at {MMBTU_PER_T} MMBtu/t; was about ${float(old) * MMBTU_PER_T:.0f}/t)')
    print(f'logged to {os.path.relpath(log_path, ROOT)}')


if __name__ == '__main__':
    main()
