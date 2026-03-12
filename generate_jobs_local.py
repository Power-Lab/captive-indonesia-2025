#!/usr/bin/env python3
import json
import subprocess
from itertools import product
from pathlib import Path
from datetime import datetime

import click
import yaml

@click.command()
@click.option('--scenarios-file', '-s',
              type=click.Path(exists=True),
              default='scenarios.yml',
              help='YAML with islands, years, scenarios, cleans, island_params, co2_limits.')
@click.option('--run-script', '-r',
              type=click.Path(exists=True),
              default='run_model.jl',
              help='Path to your Julia entrypoint (run_model.jl).')
@click.option('--output-root', '-o',
              type=click.Path(),
              default='jobs',
              help='Directory under which to make per-scenario folders.')
def main(scenarios_file, run_script, output_root):
    """Generate configs and run each scenario locally, reporting start & finish times."""
    # load scenarios
    data = yaml.safe_load(Path(scenarios_file).read_text())
    islands       = data['islands']
    years         = data['years']
    scns          = data['scenarios']
    cleans        = data['cleans']
    island_params = data['island_params']
    co2_limits    = data['co2_limits']

    jobs_root = Path(output_root)
    jobs_root.mkdir(parents=True, exist_ok=True)

    for isl, yr, scn, cln in product(islands, years, scns, cleans):
        name    = f"{scn}_{isl}_{yr}_{cln}"
        job_dir = jobs_root / name
        job_dir.mkdir(parents=True, exist_ok=True)

        # build config
        bau_val       = island_params.get(isl)
        if bau_val is None:
            raise click.ClickException(f"No island_params for '{isl}'")
        reduction_active = (yr == "2035" and cln == "clean")

        year_map = co2_limits.get(yr, {})
        co2_lim  = year_map.get(isl)
        if co2_lim is None:
            raise click.ClickException(f"No co2_limits for '{isl}' in year '{yr}'")

        cfg = {
            'island':            isl,
            'year':              yr,
            'scenario':          scn,
            'clean':             cln,
            'CO235reduction':    reduction_active,
            'BAUCO2emissions':   (bau_val if reduction_active else 0.0),
            'CO2_limit':         co2_lim
        }
        (job_dir / 'config.json').write_text(json.dumps(cfg, indent=2))

        # run
        start = datetime.now()
        click.echo(f"[{start.isoformat()}] ▶ Starting job {name}")
        subprocess.run(
            ['julia', str(Path(run_script).resolve())],
            cwd=job_dir, check=True
        )
        end = datetime.now()
        elapsed = end - start
        click.echo(f"[{end.isoformat()}] ✅ Completed {name} (took {elapsed})\n")

    click.echo("🎉 All scenarios finished.")

if __name__ == '__main__':
    main()

