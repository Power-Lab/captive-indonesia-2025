#!/usr/bin/env python3
"""Generate one config.json per island/year/scenario/clean combination and run
each job locally, in sequence, with the pinned Julia environment.

    python generate_jobs_local.py --scenarios-file scenario_maluku_test.yml

Optional per-run keys in the scenario YAML (top level) are copied into every
job's config.json: solver, mipgap, relax_uc, time_limit, RE_limit, run_tag.
`--solver` on the command line overrides the YAML for all jobs.
"""
import json
import subprocess
from datetime import datetime
from itertools import product
from pathlib import Path

import click
import yaml

# Optional keys copied from the scenario YAML into each job's config.json. Keep in
# sync with the keys run_model.jl reads; a key missing here is silently dropped and
# the run solves at the model default.
PASSTHROUGH_KEYS = ('solver', 'mipgap', 'relax_uc', 'time_limit', 'RE_limit', 'run_tag')


def run_command(command, cwd, failure_message):
    try:
        subprocess.run(command, cwd=cwd, check=True)
    except FileNotFoundError as exc:
        raise click.ClickException("Julia executable was not found on PATH.") from exc
    except subprocess.CalledProcessError as exc:
        raise click.ClickException(f"{failure_message} (exit code {exc.returncode}).") from exc


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
@click.option('--run-script', '-r',
              type=click.Path(exists=True),
              default='run_model.jl',
              help='Path to the Julia entry point (run_model.jl).')
@click.option('--output-root', '-o',
              type=click.Path(),
              default='jobs',
              help='Directory under which to create per-job folders.')
@click.option('--solver',
              type=click.Choice(['highs', 'gurobi'], case_sensitive=False),
              default=None,
              help='Override the solver for all jobs (default: YAML "solver" key, else highs).')
@click.option('--bootstrap/--no-bootstrap', default=True,
              help='Instantiate the Julia environment and check HiGHS before running jobs.')
def main(scenarios_file, run_script, output_root, solver, bootstrap):
    """Generate configs and run each scenario locally, reporting start and finish times."""
    run_script_path = Path(run_script).resolve()
    repo_root = run_script_path.parent
    project_flag = f'--project={repo_root}'

    data = yaml.safe_load(Path(scenarios_file).read_text())
    jobs_root = Path(output_root)
    jobs_root.mkdir(parents=True, exist_ok=True)

    if bootstrap:
        start = datetime.now()
        click.echo(f"[{start.isoformat()}] Preparing the Julia environment")
        run_command(['julia', project_flag, str(repo_root / 'bootstrap.jl')],
                    cwd=repo_root, failure_message='Julia environment bootstrap failed')
        click.echo(f"[{datetime.now().isoformat()}] Julia environment ready\n")

    for name, cfg in build_configs(data, solver.lower() if solver else None):
        job_dir = jobs_root / name
        job_dir.mkdir(parents=True, exist_ok=True)
        config_path = job_dir / 'config.json'
        config_path.write_text(json.dumps(cfg, indent=2))

        start = datetime.now()
        click.echo(f"[{start.isoformat()}] Starting job {name} (solver {cfg.get('solver', 'highs')})")
        run_command(['julia', project_flag, str(run_script_path), '--config', str(config_path.resolve())],
                    cwd=repo_root, failure_message=f"Job {name} failed")
        end = datetime.now()
        click.echo(f"[{end.isoformat()}] Completed {name} (took {end - start})\n")

    click.echo("All scenarios finished.")


if __name__ == '__main__':
    main()
