"""Annualise the overnight investment costs in generators.csv and ip_generators.csv.

Inv_Cost_per_MWyr and Inv_Cost_per_MWhyr hold overnight capex ($/MW, $/MWh), but optimizer.jl
adds them unchanged to a one-year objective (the representative-week weights sum to 8,760 h),
so new build costs about ten times too much. This multiplies both columns by the capital
recovery factor CRF = r(1+r)^n / ((1+r)^n - 1), r = 10 % WACC, n = the technology's lifetime
below. Fixed O&M is already annual and is left alone.

Batteries had no power cost (Inv_Cost_per_MWyr 0), so their power capacity was free. They get
150,000 $/MW overnight; the existing 578,000 $/MWh energy cost is annualised over 15 years
like the rest.

Every row of a listed technology is annualised (only New_Build = 1 rows enter the objective).
A technology that is not listed is left as it is if it has no New_Build = 1 row (existing
coal_captive units); a new-build row of an unlisted technology stops the script. A row with a
blank technology and STOR = 1 (the park batteries of Kalimantan and North Maluku, named
*_battery) is treated as a battery. Every change is logged to
data_indonesia/corrections/annualized_costs_<year>_<island>.csv.

network.csv is not changed: Line_Reinforcement_Cost_per_MWyr is a flat 35,178 $/MW on every
line of every island (the Sulawesi lines are 100-350 km), which is already of annual size (about
350,000 $/MW overnight over 40 years at 10 %), not an overnight line cost.

Usage (from the repository root; refuses to run twice):
  python3 scripts/annualize_costs.py [--year 2035] [--island sulawesi]
"""
import argparse
import csv
import io
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WACC = 0.10
LIFETIME = {'solar': 25, 'wind': 25, 'geothermal': 30, 'battery': 15, 'gas': 30, 'ccgt': 30,
            'hydropower': 50, 'hydropower_mini': 50, 'biomass': 25, 'biogas': 25, 'trash': 25,
            'diesel': 20, 'coal': 30, 'pumped_storage': 50}
BATTERY_POWER_OVERNIGHT = 150000.0   # $/MW
GUARD = 200000.0   # new-build solar above this is still overnight capex (560,000 before)


def crf(n, r=WACC):
    return r * (1 + r) ** n / ((1 + r) ** n - 1)


def fmt(x):
    return f'{x:.2f}'.rstrip('0').rstrip('.')


def tech_of(r, c):
    tech = r[c['technology']]
    return 'battery' if tech == '' and r[c['STOR']].strip() == '1' else tech


def parse(line):
    return next(csv.reader([line]))


def unparse(fields):
    out = io.StringIO()
    csv.writer(out, lineterminator='').writerow(fields)
    return out.getvalue()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--year', default='2035')
    ap.add_argument('--island', default='sulawesi')
    args = ap.parse_args()
    folder = os.path.join(ROOT, 'data_indonesia', args.year, args.island)
    log_path = os.path.join(ROOT, 'data_indonesia', 'corrections',
                            f'annualized_costs_{args.year}_{args.island}.csv')
    if os.path.exists(log_path):
        raise SystemExit(f'{log_path} exists: the costs have already been annualised')

    # read and check both files before writing either
    files = {}
    for name in ('generators.csv', 'ip_generators.csv'):
        path = os.path.join(folder, name)
        raw = open(path, 'rb').read()
        text = raw.decode('utf-8-sig')
        eol = '\r\n' if '\r\n' in text else '\n'
        lines = text.split(eol)
        head = parse(lines[0])
        c = {k: head.index(k) for k in ('R_ID', 'Resource', 'technology', 'New_Build',
                                       'Inv_Cost_per_MWyr', 'Inv_Cost_per_MWhyr', 'STOR')}
        rows = {i: parse(line) for i, line in enumerate(lines[1:], start=1) if line}
        for i, r in rows.items():
            assert unparse(r) == lines[i], f'{path}:{i + 1} does not round-trip through csv'
            tech, new = tech_of(r, c), r[c['New_Build']].strip() == '1'
            if tech == 'solar' and new and float(r[c['Inv_Cost_per_MWyr']]) < GUARD:
                raise SystemExit(f'{name} R_ID {r[c["R_ID"]]}: new-build solar costs '
                                 f'{r[c["Inv_Cost_per_MWyr"]]} $/MW-yr, below {GUARD:.0f}: '
                                 'already annualised')
            if tech not in LIFETIME and new:
                raise SystemExit(f'{name} R_ID {r[c["R_ID"]]}: new-build technology {tech!r} '
                                 'has no lifetime; add it to LIFETIME by decision, not by guess')
            if tech != 'battery' and float(r[c['Inv_Cost_per_MWhyr']] or 0) != 0:
                raise SystemExit(f'{name} R_ID {r[c["R_ID"]]}: {tech} has an energy cost')
            if tech == 'battery' and float(r[c['Inv_Cost_per_MWyr']] or 0) != 0:
                raise SystemExit(f'{name} R_ID {r[c["R_ID"]]}: battery already has a power cost')
        files[name] = (path, raw.startswith(b'\xef\xbb\xbf'), eol, lines, c, rows)

    log = []
    for name, (path, bom, eol, lines, c, rows) in files.items():
        changed = 0
        for i, r in rows.items():
            tech = tech_of(r, c)
            if tech not in LIFETIME:
                continue
            n = LIFETIME[tech]
            old_mw, old_mwh = r[c['Inv_Cost_per_MWyr']], r[c['Inv_Cost_per_MWhyr']]
            overnight_mw = BATTERY_POWER_OVERNIGHT if tech == 'battery' else float(old_mw)
            r[c['Inv_Cost_per_MWyr']] = fmt(overnight_mw * crf(n))
            if float(old_mwh or 0) != 0:
                r[c['Inv_Cost_per_MWhyr']] = fmt(float(old_mwh) * crf(n))
            log.append({'year': args.year, 'island': args.island, 'file': name,
                        'R_ID': r[c['R_ID']], 'Resource': r[c['Resource']], 'technology': tech,
                        'New_Build': r[c['New_Build']], 'lifetime_yr': n, 'crf': f'{crf(n):.6f}',
                        'Inv_Cost_per_MWyr_old': old_mw, 'Inv_Cost_per_MWyr_new': r[c['Inv_Cost_per_MWyr']],
                        'Inv_Cost_per_MWhyr_old': old_mwh, 'Inv_Cost_per_MWhyr_new': r[c['Inv_Cost_per_MWhyr']]})
            lines[i] = unparse(r)
            changed += 1
        with open(path, 'wb') as f:
            f.write((b'\xef\xbb\xbf' if bom else b'') + eol.join(lines).encode('utf-8'))
        left = sorted({tech_of(r, c) for r in rows.values() if tech_of(r, c) not in LIFETIME})
        print(f'{args.year}/{args.island}/{name}: {changed} rows annualised'
              + (f'; left as is (existing units only): {", ".join(left)}' if left else ''))
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(log[0]))
        w.writeheader()
        w.writerows(log)
    print(f'logged {len(log)} rows to {os.path.relpath(log_path, ROOT)}')
    for tech, n in sorted(LIFETIME.items(), key=lambda x: (x[1], x[0])):
        print(f'  {tech:16s} {n:3d} yr  CRF {crf(n):.6f}')


if __name__ == '__main__':
    main()
