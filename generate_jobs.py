#!/usr/bin/env python3
"""Generate one job folder (config.json + SLURM submit script) per
island/year/scenario/clean combination for an HPC cluster, and optionally
submit them with sbatch.

    python generate_jobs.py --scenarios-file scenario_2030_example.yml --submit-script submit_template.sb
    python generate_jobs.py --scenarios-file scenario_2030_example.yml --submit

Optional per-run keys in the scenario YAML (top level) are copied into every
job's config.json: solver, mipgap, relax_uc, time_limit, RE_limit, run_tag.
`--solver` on the command line overrides the YAML for all jobs. For local
(non-SLURM) runs use generate_jobs_local.py instead.
"""
import json
import subprocess
from itertools import product
from pathlib import Path

import click
import yaml

# Optional keys copied from the scenario YAML into each job's config.json. Keep in
# sync with the keys run_model.jl reads; a key missing here is silently dropped and
# the run solves at the model default.
PASSTHROUGH_KEYS = ('solver', 'mipgap', 'relax_uc', 'time_limit', 'RE_limit', 'run_tag')


def build_configs(data, solver_override=None):
    """Yield (job_name, config dict) for every combination in a scenario file."""
    islands       = data['islands']
    years         = data['years']
    scns          = data['scenarios']
    cleans        = data['cleans']
    island_params = data['island_params']
    co2_limits    = data['co2_limits']

    run_tag = str(data.get('run_tag', '')).strip()
    tag_suffix = f"__{run_tag}" if run_tag else ""

    for isl, yr, scn, cln in product(islands, years, scns, cleans):
        name = f"{scn}_{isl}_{yr}_{cln}{tag_suffix}"

        bau_val = island_params.get(isl)
        if bau_val is None:
            raise click.ClickException(f"No island_params entry for '{isl}'")
        reduction_active = (str(yr) == "2035" and cln == "clean")

        co2_lim = co2_limits.get(yr, {}).get(isl)
        if co2_lim is None:
            raise click.ClickException(f"No co2_limits entry for '{isl}' in year '{yr}'")

        cfg = {
            'island':          isl,
            'year':            str(yr),
            'scenario':        scn,
            'clean':           cln,
            'CO235reduction':  reduction_active,
            'BAUCO2emissions': (bau_val if reduction_active else 0.0),
            'CO2_limit':       co2_lim,
        }
        for key in PASSTHROUGH_KEYS:
            if key in data:
                cfg[key] = data[key]
        if solver_override:
            cfg['solver'] = solver_override
        yield name, cfg


@click.command()
@click.option('--scenarios-file', '-s',
              type=click.Path(exists=True),
              default='scenarios.yml',
              help='YAML with islands, years, scenarios, cleans, island_params, co2_limits.')
@click.option('--submit-script', '-b',
              type=click.Path(exists=True),
              default='submit_template.sb',
              help='SLURM submission script to symlink into every job folder.')
@click.option('--output-root', '-o',
              type=click.Path(),
              default='jobs',
              help='Directory under which to create per-job folders.')
@click.option('--solver',
              type=click.Choice(['highs', 'gurobi'], case_sensitive=False),
              default=None,
              help='Override the solver for all jobs (default: YAML "solver" key, else highs).')
@click.option('--submit/--no-submit', default=False,
              help='Whether to call sbatch in each job folder.')
def main(scenarios_file, submit_script, output_root, solver, submit):
    """Generate per-scenario job folders and optionally submit them to SLURM."""
    data = yaml.safe_load(Path(scenarios_file).read_text())
    jobs_root = Path(output_root)
    jobs_root.mkdir(parents=True, exist_ok=True)

    total = 0
    for name, cfg in build_configs(data, solver.lower() if solver else None):
        job_dir = jobs_root / name
        job_dir.mkdir(parents=True, exist_ok=True)
        (job_dir / 'config.json').write_text(json.dumps(cfg, indent=2))

        # symlink the SLURM submit script into the job folder
        sb_link = job_dir / Path(submit_script).name
        if sb_link.exists() or sb_link.is_symlink():
            sb_link.unlink()
        sb_link.symlink_to(Path(submit_script).resolve())

        # short (<= 9 char) SLURM job name
        isl, yr, scn, cln = cfg['island'], cfg['year'], cfg['scenario'], cfg['clean']
        job_code = f"{scn[:3].upper()}{isl[:2].upper()}{yr[-2:]}{cln[0].upper()}"

        click.echo(f"Prepared job '{name}' (code '{job_code}', solver {cfg.get('solver', 'highs')})")
        if submit:
            subprocess.run(["sbatch", "--job-name", job_code, sb_link.name], cwd=job_dir, check=True)
            click.echo(f"  Submitted as SLURM job '{job_code}'")
        total += 1

    click.echo(f"\nDone: set up {total} job(s) under '{jobs_root}'")


if __name__ == '__main__':
    main()
