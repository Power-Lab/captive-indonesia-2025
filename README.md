# Captive Indonesia Capacity Expansion Model

This repository contains an **open-source capacity expansion and operational model** tailored for Indonesia’s islands and industrial parks.  
The model simultaneously determines **generation capacity investments** and **dispatch decisions** under various policy scenarios, allowing researchers and planners to explore how **clean energy, grid expansion, captive industrial generation, and emissions constraints** affect electricity supply and industrial park operations.

It is written in **Julia** using **JuMP** for optimisation and is accompanied by Python scripts to create and run scenario jobs — `generate_jobs.py` for HPC/SLURM clusters and `generate_jobs_local.py` for local execution.

---

## Repository Structure

| Path / Folder | Description |
|----------------|--------------|
| `data_indonesia/<year>/<island>` | Raw input data used by the model. Each year/island folder contains CSV files describing generators (`generators.csv`), demand profiles (`demand.csv`), variability of renewable resources (`generators_variability.csv`), fuel costs (`fuels_data.csv`) and optional network files. Industrial park data are stored in analogous `ip_*` files. The Julia script reads these files and converts them into the sets and parameters required by the model. |
| `functions/` | Collection of Julia modules. `input_data.jl` parses the CSVs into data structures and calculates variable costs and emission rates; `optimizer.jl` builds the mixed-integer linear program representing the capacity expansion and dispatch problem; `result_extraction_function.jl` writes results such as generation by technology, industrial park outputs, and cost summaries to CSV files; `benders_decomposition.jl` implements an optional Benders decomposition algorithm for large problems; and `function_compiler.jl` ties everything together by loading input data, solving the optimisation, and exporting results. |
| `run_model.jl` | Stand-alone Julia script that reads a `config.json` file, interprets scenario flags and emission constraints, locates the appropriate input folder, and calls `function_compiler` to solve the model. It contains logic to enable or disable grid expansion, captive generation, high import prices, and coal restrictions based on the scenario name, and adjusts emissions and renewable requirements when a clean scenario is selected. |
| `generate_jobs.py` | Python CLI utility for **HPC/SLURM** clusters. Reads a YAML scenario definition and generates subdirectories for every island/year/scenario/clean combination. For each job it writes a `config.json` file with the selected parameters and creates a symbolic link to a submission script. With the `--submit` flag, it submits each job via `sbatch`. CLI options: `--scenarios-file`, `--submit-script`, `--output-root`, `--submit`. |
| `generate_jobs_local.py` | Python CLI utility for **local execution**. Generates the same per-job `config.json` files as `generate_jobs.py` but, instead of creating SLURM symlinks, it immediately runs each job with `julia run_model.jl` in sequence. Reports a timestamped start and finish line for every job. CLI options: `--scenarios-file`, `--run-script` (path to `run_model.jl`), `--output-root`. |
| `scenario_*.yml` | YAML files that list islands, model years, scenario names, and whether to run a reference or clean case. They also define baseline "business-as-usual" (BAU) emissions and specify CO₂ limits for each island and year. You can create your own scenario file to customise the analysis. `scenario_maluku_test.yml` is a minimal single-island test case for local runs — see the [Test Case](#test-case-maluku-island-local) section. |

---

## Getting Started

**Prerequisites:** [Julia ≥ 1.6](https://julialang.org/downloads/), Python ≥ 3.8, and a valid Gurobi licence.

> Install Julia from the [official downloads page](https://julialang.org/downloads/) or via [juliaup](https://github.com/JuliaLang/juliaup). Avoid conda-forge Julia — package resolution is more reliable with the official toolchain.

1. **Install Python dependencies:**
   ```bash
   pip install click pyyaml
   ```

2. **Bootstrap the Julia environment** (once, from the repository root):
   ```bash
   julia --project=. bootstrap.jl
   ```
   This resolves and installs all Julia packages into a repo-local environment and confirms Gurobi can start. Takes about a minute the first time; instant on subsequent runs.

---

## First Run: Maluku Island

`scenario_maluku_test.yml` is the recommended entry point. It runs a single small island (`maluku`, 2030, `base` scenario, no CO₂ constraints) that requires only four CSV files and typically solves in about a minute on a laptop.

```bash
python generate_jobs_local.py \
  --scenarios-file scenario_maluku_test.yml \
  --run-script run_model.jl \
  --output-root jobs
```

Expected output:
```
[...] ▶ Preparing Julia environment
[...] ✅ Julia environment ready (took 0:00:02)

[...] ▶ Starting job base_maluku_2030_reference
[...] ✅ Completed base_maluku_2030_reference (took 0:01:00)

🎉 All scenarios finished.
```

Results are written to `results/base_maluku_2030_reference/`.

Once this run succeeds, you can extend it by editing `scenario_maluku_test.yml`:
- Add `"clean"` to the `cleans` list to enable CO₂ and RE constraints.
- Add `"captive"` to `scenarios` — requires the `ip_*` input files not present in `data_indonesia/2030/maluku/`.
- Add `"2035"` to `years` once the corresponding data folder is populated.

---

## Run a Custom Scenario Locally

Create or edit a scenario YAML file (see [Preparing a Scenario File](#preparing-a-scenario-file)), then:

```bash
python generate_jobs_local.py \
  --scenarios-file your_scenario.yml \
  --run-script run_model.jl \
  --output-root jobs
```

This creates one job folder per island/year/scenario/clean combination under `jobs/`, runs each sequentially, and writes results to `results/<job_name>/`.

**Run a single job directly:**
```bash
julia --project=. run_model.jl --config jobs/<job_folder>/config.json
```

**Validate a config without solving** (preflight-only, useful before a long batch run):
```bash
julia --project=. run_model.jl --config jobs/<job_folder>/config.json --preflight-only
```

---

## HPC / SLURM Batch

`generate_jobs.py` generates job directories and SLURM submission scripts without running them locally:

```bash
python generate_jobs.py \
  --scenarios-file scenario_2030_example.yml \
  --submit-script submit_template.sb \
  --output-root jobs
```

Add `--submit` to automatically call `sbatch` on each generated job folder.

---

## Preparing a Scenario File

A scenario file (e.g., `scenario_2030_example.yml`) defines:

- `islands`: list of islands to model (e.g., `sumatera`, `jawa_bali`)
- `years`: list of planning years (e.g., `2030`, `2035`)
- `scenarios`: policy/system configurations that control flags in `run_model.jl` — valid values are `base`, `grid`, `captive`, `gridcaptive`, `nocoal`, `highimportprice`
- `cleans`: `reference` (no CO₂ or RE constraints) or `clean` (constraints active)
- `island_params`: baseline BAU CO₂ emissions per island (tonnes CO₂), used when `clean` is active
- `co2_limits`: CO₂ cap per island per year

See `scenario_maluku_test.yml` for a minimal working example and `scenario_2030_example.yml` for a full multi-island run.

---

## Customising Your Analysis

### Editing Scenario Parameters
- Modify scenario YAML files to adjust policies (e.g., include `highimportprice` to raise import costs).
- Emission caps and renewable shares can be changed by editing `co2_limits`, `BAU_emissions`, or setting `clean` cases.

### Adding New Input Data
- Create a new folder under `data_indonesia/` (e.g., `data_indonesia/2040/kalimantan`) and supply required CSVs (`generators.csv`, `demand.csv`, etc.).
- `input_data.jl` automatically parses these into the model.

### Changing Solver or Tolerance
- The default solver is **Gurobi** with a **0.1 % MIP gap** tolerance.
- Edit `run_model.jl` or `functions/optimizer.jl` to change solver options.

### Benders Decomposition
- For large problems, use the optional implementation in `functions/benders_decomposition.jl`.
- Modify the driver script to call `capacity_expansion_benders` instead of the default solver.

---

## Output Files

After solving, each job’s results folder contains:

| File | Description |
|------|--------------|
| `generator_results.csv` | Hourly generation and installed capacity by generator technology. |
| `ip_generator_results.csv` | Industrial park generator operations and heat production. |
| `storage_results.csv` | State of charge and power flows for storage technologies. |
| `cost_results.csv` | Fixed, variable, start-up, import costs, and non-served energy costs per scenario. |
| `clean_energy.csv` | Renewable energy share and CO₂ emissions metrics. |
| `transmission_results.csv` | (If provided) power flows across transmission links. |

You can import these CSVs into **Python (pandas)** or **Julia** for analysis and visualisation.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `julia: command not found` | Julia not on PATH | Install from [julialang.org](https://julialang.org/downloads/) or via juliaup, then restart your terminal |
| `Error: Gurobi is installed but could not start a licensed optimizer session` | Licence missing, expired, or wrong path | Ensure `GRB_LICENSE_FILE` points to a valid `gurobi.lic`; run `gurobi_cl` to confirm |
| `Error: Config file not found` | Wrong working directory or missing `--config` flag | Run from the repo root: `julia --project=. run_model.jl --config jobs/<job>/config.json` |
| `Error: Unknown scenario: <name>` | Typo in `scenarios` list | Valid values: `base`, `grid`, `captive`, `gridcaptive`, `highimportprice`, `nocoal` |
| `Error: Missing required input files … ip_generators.csv` | `captive` or `gridcaptive` on an island with no `ip_*` files | Supply the `ip_*` CSVs or remove captive scenarios for that island |
| `Error: Missing required input files … network.csv` | `grid`, `gridcaptive`, or `nocoal` on an island with no network data | Supply `network.csv` or use `base`/`captive` scenarios instead |
| Julia package error on first run | Stale or missing `Manifest.toml` | Run `julia --project=. bootstrap.jl` to resolve and reinstall |

---

## Contributing

Contributions are welcome!  
Please open an issue or pull request with a clear description of proposed changes or bugs.  
Major modifications should first be discussed via an issue to ensure consistency with the existing framework.

---

## Licence

This project is released under the **MIT Licence**.  
See [`LICENSE`](LICENSE) for details.
