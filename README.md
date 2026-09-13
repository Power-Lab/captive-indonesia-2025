# Captive Indonesia Capacity Expansion Model

[![maluku-test-case](https://github.com/Power-Lab/captive-indonesia-2025/actions/workflows/test-case.yml/badge.svg)](https://github.com/Power-Lab/captive-indonesia-2025/actions/workflows/test-case.yml)

An **open-source capacity expansion and unit-commitment model** for Indonesia's island power systems and their captive (industrial-park) generation. For each island and planning year the model co-optimises **generation and storage investments** with **hourly dispatch** over representative weeks, under policy scenarios that switch grid access for industrial parks, on-site captive generation, coal restrictions, import prices, and CO₂ and renewable-share constraints.

The model is written in **Julia** with [JuMP](https://jump.dev/) and runs end-to-end on the open-source **HiGHS** solver. **Gurobi** is optional; it is the solver the published results were produced with. Two small Python scripts generate batches of runs for a laptop or a SLURM cluster.

---

## Reproducibility package

This section is for reviewers and anyone who wants to check that the code runs and reproduces its reference outputs.

**What can be reproduced where**

| Set | Size | Where it runs | Solver | Status |
|-----|------|---------------|--------|--------|
| Maluku 2030, `base` scenario, `reference` case | 1 job; 214k binaries, 0.8M constraints | a laptop | HiGHS (no licence) or Gurobi | **run it yourself**, see below |
| Full study (8 islands × 6 scenarios × 2 cases × 2 years, `scenario_2030_example.yml`) | 96 jobs per year; the large islands are multi-zone MILPs that take hours to days each | HPC cluster | Gurobi | reproducible from the same inputs and code with `generate_jobs.py`; not practical on a laptop |

All input data for every island and year is in `data_indonesia/`, and the scenario files that define the published run set are in the repository root, so the full study can be regenerated on a cluster with the commands in [Batch runs](#batch-runs).

**Run the Maluku test case** (about 15 minutes on a recent laptop with HiGHS)

1. Install [Julia](https://julialang.org/downloads/) 1.10 or newer, ideally through [juliaup](https://github.com/JuliaLang/juliaup). Nothing else is needed.
2. From the repository root, install the pinned packages once:
   ```bash
   julia bootstrap.jl
   ```
3. Solve the test case, print a summary and compare it with the reference outputs:
   ```bash
   julia --project=. test_case/run_maluku_test.jl
   ```
   The last line is `MALUKU_TEST_PASSED` or `MALUKU_TEST_FAILED`. Results are written to `results/base_maluku_2030_reference__test_exact/`, including `run_info.json` (solver, package versions, git commit, MIP gap, solve time) and `summary_by_technology.csv`.

Variants:

```bash
julia --project=. test_case/run_maluku_test.jl --solver gurobi   # same model on Gurobi, about 1 minute (licence required)
julia --project=. test_case/run_maluku_test.jl --quick           # LP relaxation of unit commitment, about 2 minutes; a smoke test, not the published model
```

**What to expect.** The reference outputs in `test_case/maluku/expected_results/` were produced with Gurobi, the solver used for the article. The model is solved to a 1 % MIP gap, so a different solver (or a different machine) legitimately lands on a different near-optimal plan; the comparison therefore checks headline metrics against tolerances rather than requiring identical CSVs. Observed values on an Apple Silicon laptop:

| Metric | Reference (Gurobi 13, exact MILP) | HiGHS 1.25, exact MILP | Comparison tolerance |
|--------|------:|------:|------|
| Total system cost (million USD/yr) | 68.31 | 68.11 | 2 % relative |
| CO₂ emissions (tCO₂/yr) | 690,071 | 690,381 | 5 % relative |
| Grid renewable share | 69.5 % | 69.5 % | 3 percentage points |
| Non-served energy (share of demand) | 0.017 % | 0.036 % | 0.1 percentage points |
| New solar / battery built (MW) | 66.1 / 12.0 | 66.0 / 0.0 | information only |
| Achieved MIP gap | 1.00 % | 0.76 % | |
| Solver time | 36 s | 813 s | |

Re-running with the same solver and package versions reproduces the reference numbers exactly (verified for Gurobi on the reference machine). The `--quick` mode compares against `test_case/maluku/expected_results_relaxed/`, produced with HiGHS on the LP relaxation (total cost 67.59 million USD/yr, a lower bound about 1 % below the exact model; 83 s of solver time).

---

## Repository structure

| Path | Description |
|------|-------------|
| `run_model.jl` | Entry point. Reads a `config.json`, validates it, solves one scenario and writes the result CSVs plus `run_info.json`. |
| `functions/` | Julia model code: `input_data.jl` (CSV inputs to sets and parameters), `solver.jl` (HiGHS/Gurobi selection), `optimizer.jl` (the MILP: `capacity_expansion`), `result_extraction_function.jl` (result CSVs), `preflight.jl` (CLI, config and input checks), `function_compiler.jl` (ties them together), `benders_decomposition.jl` (an experimental Benders variant, not used for the published results). |
| `data_indonesia/<year>/<island>/` | Inputs for 2030 and 2035 for sumatera, jawa_bali, kalimantan, sulawesi, north_maluku, maluku, papua, nusa_tenggara: `generators.csv`, `demand.csv`, `generators_variability.csv`, `fuels_data.csv`, plus `network.csv`/`zones.csv` for multi-zone islands and `ip_*.csv` for industrial parks. `industrial_park_datasheet_sample.xlsx` documents the industrial-park data collection template. |
| `test_case/maluku/` | The reviewer test case: `config.json`, the reference outputs (`expected_results/`, `expected_results_relaxed/`) and `README.md`. `test_case/run_maluku_test.jl` runs it end to end. |
| `scripts/` | `summarize_results.jl` (headline metrics and capacity/generation by technology for any results folder) and `compare_results.jl` (tolerance-based comparison of two results folders). |
| `scenario_*.yml` | Run sets: islands, years, scenarios, clean cases, CO₂ limits and the solver. `scenario_maluku_test.yml` is the single test job; `scenario_2030_example.yml` is the full study set. |
| `generate_jobs_local.py`, `generate_jobs.py`, `submit_template.sb` | Batch runners: one `config.json` per island/year/scenario/case, run sequentially on a laptop or submitted to SLURM. |
| `Project.toml`, `Manifest.toml`, `bootstrap.jl` | Pinned Julia environment and its installer. |
| `.github/workflows/test-case.yml` | Continuous integration: runs the quick Maluku check on HiGHS and exercises the job generators on every push. |

---

## Installation

**Julia (required).** Julia 1.10 or newer; the `Manifest.toml` was resolved with Julia 1.12. Then, from the repository root:

```bash
julia bootstrap.jl
```

This activates the project, installs the exact package versions in `Manifest.toml` (JuMP, HiGHS, CSV, DataFrames, JSON and Gurobi.jl, which installs without a licence) and solves a one-variable model with HiGHS to confirm the solver works. Every command below uses `julia --project=.` so that this environment is used; `run_model.jl` also activates it itself, so forgetting the flag is harmless.

**Python (only for the batch generators).** `generate_jobs.py` and `generate_jobs_local.py` need `click` and `pyyaml`:

```bash
pip install -r requirements.txt
```

**Gurobi (optional).** To use Gurobi, install a licence (`GRB_LICENSE_FILE` or the default location) and set `"solver": "gurobi"` in the config, `solver: gurobi` in the scenario YAML, or pass `--solver gurobi`. Gurobi.jl is imported only when a run asks for it, so HiGHS runs never touch it. The published results used Gurobi with a 1 % MIP gap, `Crossover = 0` and a 3-day time limit; these are the settings `functions/solver.jl` applies.

---

## Running the model

### One job

A job is described by a `config.json`:

```json
{
  "island": "maluku",
  "year": "2030",
  "scenario": "base",
  "clean": "reference",
  "CO235reduction": false,
  "BAUCO2emissions": 0.0,
  "CO2_limit": 5820000,
  "solver": "highs"
}
```

```bash
julia --project=. run_model.jl --config test_case/maluku/config.json
julia --project=. run_model.jl --config my_job/config.json --solver gurobi
julia --project=. run_model.jl --config my_job/config.json --preflight-only   # validate config, inputs and solver only
julia --project=. run_model.jl        # with no --config: reads ./config.json, the job-folder convention
```

Required keys: `island`, `year`, `scenario`, `clean`, `CO235reduction`, `BAUCO2emissions`, `CO2_limit`. Optional keys:

| Key | Default | Meaning |
|-----|---------|---------|
| `solver` | `"highs"` | `"highs"` (open source) or `"gurobi"`; `--solver` on the command line overrides it |
| `mipgap` | `0.01` | relative MIP gap |
| `relax_uc` | `false` | LP-relax the unit-commitment binaries (HiGHS then uses its interior-point method). Fast and licence-free, and a lower bound on cost, but not the published model |
| `time_limit` | `259200` | solver wall-clock limit in seconds (3 days). On expiry the best incumbent is written and `run_info.json` records the achieved gap |
| `RE_limit` | `0.34` | minimum grid renewable energy share enforced in `clean` runs |
| `run_tag` | `""` | suffix for the results folder, for runs that differ only in config keys |

Results go to `results/<scenario>_<island>_<year>_<clean>[__<run_tag>]/` under the repository root (`results/` is git-ignored). Summarise any results folder with:

```bash
julia --project=. scripts/summarize_results.jl results/base_maluku_2030_reference
```

and compare two folders with:

```bash
julia --project=. scripts/compare_results.jl results/<run> test_case/maluku/expected_results
```

### Batch runs

A scenario YAML lists `islands`, `years`, `scenarios`, `cleans`, per-island baseline emissions (`island_params`) and per-year CO₂ caps (`co2_limits`), plus any of the optional config keys above at the top level (they are copied into every job's config; `solver` is the important one).

Locally, in sequence, with the pinned environment:

```bash
python generate_jobs_local.py --scenarios-file scenario_maluku_test.yml
python generate_jobs_local.py --scenarios-file scenario_2030_example.yml --solver gurobi
```

On a SLURM cluster (edit the resource, module and licence lines in `submit_template.sb` first):

```bash
python generate_jobs.py --scenarios-file scenario_2030_example.yml --submit-script submit_template.sb          # prepare jobs/
python generate_jobs.py --scenarios-file scenario_2030_example.yml --submit-script submit_template.sb --submit # and sbatch them
```

Each job folder `jobs/<job_name>/` holds its `config.json` and a symlink to the submit script; results land in `results/<job_name>/` as for a single run.

---

## Scenarios

The `scenario` name sets four model switches (defined once, in `functions/preflight.jl`):

| Scenario | Industrial parks may import from the grid | On-site captive generation may be built | Import price (USD/MWh) | Coal excluded at industrial parks |
|----------|:---:|:---:|---:|:---:|
| `base` | no | no | 59 | no |
| `grid` | yes | no | 59 | no |
| `captive` | no | yes | 59 | no |
| `gridcaptive` | yes | yes | 59 | no |
| `highimportprice` | yes | yes | 59 × 1.21 | no |
| `nocoal` | yes | no | 59 | yes |

The `clean` flag is `reference` (no policy constraints) or `clean` (grid CO₂ emissions capped at `CO2_limit` and grid renewable share at least `RE_limit`). For 2035 `clean` runs the job generators additionally set `CO235reduction`, which caps industrial-park emissions at 65 % of the island's baseline `BAUCO2emissions`.

Scenarios with captive generation need the `ip_*.csv` inputs for the island; `maluku` has none, so its captive scenarios run with an empty industrial-park layer.

---

## Test case: Maluku 2030

Maluku is the smallest system in the dataset: a single zone with no transmission network and no industrial-park files, so the `base`/`reference` job needs only the four core input files and is the quickest job to solve. `test_case/maluku/README.md` documents the reference outputs and how they were produced. To go beyond the test case, add `clean` to `cleans` in `scenario_maluku_test.yml` for a constrained run, or pick a larger island from `scenario_2030_example.yml` (expect much longer solve times).

---

## Outputs

Every run writes these CSVs to its results folder:

| File | Content |
|------|---------|
| `generator_results.csv` | Per grid generator: capacity before and after optimisation, generation and shares. `Start_MW` is the existing capacity for existing units and the maximum buildable size for new-build candidates (`New_Build = 1`). |
| `storage_results.csv`, `transmission_results.csv` | Grid storage energy capacity and transmission capacity, before and after. |
| `nse_results.csv` | Non-served energy by demand segment and zone. |
| `cost_results.csv` | Annual system cost in million USD/yr: total and its fixed, variable, start-up, import and non-served-energy components. |
| `clean_energy_results.csv` | Annual CO₂ emissions (grid, industrial parks, total) and the grid renewable share. |
| `ip_*.csv` | Industrial-park generators, heat, imports, storage and non-served energy (headers only when the island has no industrial-park data). |
| `run_info.json` | How the run was produced: config, solver and package versions, Julia version, git commit, termination status, objective, achieved MIP gap, solver and wall time. |
| `summary_by_technology.csv` | Written by `scripts/summarize_results.jl`: capacity and generation aggregated by technology. |

Costs and emissions are annual values (hours are weighted by the representative-period weights in `demand.csv`). The `GWh` columns are sums over the sampled hours (8 representative weeks, 1,344 hours) and are not annualised; the `Percent_GWh` shares are unaffected.

---

## Model overview

`functions/optimizer.jl` builds one mixed-integer linear program per job:

- **Investment decisions**: continuous new-build and retirement capacity for every grid and industrial-park generator, storage energy capacity, and transmission reinforcement (multi-zone islands), bounded by the `Max_Cap_MW` potentials in the inputs.
- **Operation**: hourly dispatch over the representative weeks in `demand.csv`, with zonal power balance, price-responsive non-served energy segments, storage state of charge, transmission flows, and binary unit commitment (commit, start, shut) with minimum up and down times, ramp limits and minimum stable output for thermal units. Inter-temporal constraints wrap within each representative week.
- **Industrial parks**: electricity and heat balances per park, on-site generation and storage, and grid imports at a fixed price when the scenario allows them.
- **Policy**: optional caps on grid CO₂ and industrial-park CO₂, and a minimum renewable share.
- **Objective**: annualised investment and fixed O&M cost plus fuel, variable O&M, start-up, import and non-served-energy costs.

Costs are annualised with the `Inv_Cost_per_MWyr` values in `generators.csv`; hourly quantities are weighted by the representative-week weights so that operating costs and emissions are annual. The solver settings are in `functions/solver.jl`.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `julia: command not found` | Install Julia (juliaup) and reopen the terminal. |
| Package errors on first run | Run `julia bootstrap.jl` again; if the Julia version differs from the one the manifest was resolved with, run `julia --project=. -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'`. |
| `Solver "gurobi" could not start a working optimizer session` | No usable Gurobi licence; use the default `highs` or set `GRB_LICENSE_FILE`. |
| `Config file is missing required keys` | Copy `test_case/maluku/config.json` and edit it. |
| `Missing required input files in data_indonesia/...` | The island/year folder needs the four core CSVs; check the spelling of `island` and `year`. |
| `ModuleNotFoundError: click` | `pip install -r requirements.txt` in the Python you actually invoke. |
| A HiGHS run seems stuck at the root node | The exact MILP spends most of its time there; Maluku takes about 15 minutes, larger islands much longer. Use `--quick`/`relax_uc` for a fast approximation or Gurobi for the exact model. |

---

## Contributing

Issues and pull requests are welcome. Please open an issue first for substantial changes so they can be discussed against the published model formulation.

## Licence

Released under the **MIT Licence**; see [`LICENSE`](LICENSE).
