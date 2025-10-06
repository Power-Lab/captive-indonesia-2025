# Captive Indonesia Capacity Expansion Model

This repository contains an **open-source capacity expansion and operational model** tailored for Indonesia’s islands and industrial parks.  
The model simultaneously determines **generation capacity investments** and **dispatch decisions** under various policy scenarios, allowing researchers and planners to explore how **clean energy, grid expansion, captive industrial generation, and emissions constraints** affect electricity supply and industrial park operations.

It is written in **Julia** using **JuMP** for optimisation and is accompanied by a small **Python script** to create scenario jobs.

---

## Repository Structure

| Path / Folder | Description |
|----------------|--------------|
| `data_indonesia/<year>/<island>` | Raw input data used by the model. Each year/island folder contains CSV files describing generators (`generators.csv`), demand profiles (`demand.csv`), variability of renewable resources (`generators_variability.csv`), fuel costs (`fuels_data.csv`) and optional network files. Industrial park data are stored in analogous `ip_*` files. The Julia script reads these files and converts them into the sets and parameters required by the model. |
| `functions/` | Collection of Julia modules. `input_data.jl` parses the CSVs into data structures and calculates variable costs and emission rates; `optimizer.jl` builds the mixed-integer linear program representing the capacity expansion and dispatch problem; `result_extraction_function.jl` writes results such as generation by technology, industrial park outputs, and cost summaries to CSV files; `benders_decomposition.jl` implements an optional Benders decomposition algorithm for large problems; and `function_compiler.jl` ties everything together by loading input data, solving the optimisation, and exporting results. |
| `run_model.jl` | Stand-alone Julia script that reads a `config.json` file, interprets scenario flags and emission constraints, locates the appropriate input folder, and calls `function_compiler` to solve the model. It contains logic to enable or disable grid expansion, captive generation, high import prices, and coal restrictions based on the scenario name, and adjusts emissions and renewable requirements when a clean scenario is selected. |
| `generate_jobs.py` | Python CLI utility that reads a YAML scenario definition and generates subdirectories for every island/year/scenario/clean combination. For each job it writes a `config.json` file with the selected parameters and creates a symbolic link to a submission script for high-performance computing. With the `--submit` flag, it can immediately submit these jobs using `sbatch`. The script exposes CLI options such as `--scenarios` (path to the YAML), `--submit-script` (template SLURM script), `--output-dir`, and `--submit`. |
| `scenario_*.yml` | YAML files that list islands, model years, scenario names, and whether to run a reference or clean case. They also define baseline “business-as-usual” (BAU) emissions and specify CO₂ limits for each island and year. You can create your own scenario file to customise the analysis. |

---

## Quick Start

1. **Clone the repository** and make sure you have **Python ≥ 3.8** and **Julia ≥ 1.6** installed.

2. **Install Python dependencies** for the job generator:
   ```bash
   pip install click pyyaml
   ```

3. **Install Julia packages** used by the model:
   ```julia
   using Pkg
   Pkg.activate(".")  # optional: create a local environment
   Pkg.add(["JuMP", "DataFrames", "CSV", "JSON", "Gurobi", "Plots"])
   ```
   A valid **Gurobi licence** is required because the solver defaults to Gurobi.  
   You can modify `optimizer.jl` to use an open-source solver such as **CPLEX** or **GLPK** if necessary.

---

## Preparing a Scenario File

A scenario file (e.g., `scenario_2030.yml`) defines:

- `islands`: list of islands to model (e.g., `Sumatera`, `Jawa_Bali`)
- `years`: list of planning years (e.g., `2030`, `2035`)
- `scenarios`: names of policy/system configurations (`base`, `grid`, `captive`, `gridcaptive`, `nocoal`, `highimportprice`, …) that control flags in `run_model.jl`
- `cleans`: whether to run a reference (`ref`) or clean (`clean`) case
- `island_params` and `co2_limits`: baseline BAU emissions and CO₂ caps per island/year

You can adjust these values or add new keys to explore other scenarios.  
More examples are provided in `scenario_2030_example`.

---

## Running the Model

### Generate Job Directories

From the repository root, run:
```bash
python generate_jobs.py --scenarios scenario_2030.yml     --submit-script submit_template.sb --output-dir jobs
```

This creates a `jobs/` directory containing one subfolder per island/year/scenario/clean combination.  
Each job folder includes:
- `config.json` (job parameters)
- symbolic link to `submit_template.sb` (SLURM submission script)

Add `--submit` to automatically submit jobs via `sbatch`.

### Run a Model Manually

To run a single job without HPC:
```bash
cd jobs/<job_folder>
julia ../../run_model.jl
```

`run_model.jl` reads the local `config.json`, determines the input data path and scenario toggles, and calls `function_compiler` to solve the model.  
Results are written to `results_nodc/<job_name>/`, including CSVs for:
- generation by technology
- industrial park outputs
- storage behaviour
- transmission flows
- cost breakdowns

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
- Edit `run_model.jl` to change solver options or use another MILP solver.

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

## Contributing

Contributions are welcome!  
Please open an issue or pull request with a clear description of proposed changes or bugs.  
Major modifications should first be discussed via an issue to ensure consistency with the existing framework.

---

## Licence

This project is released under the **MIT Licence**.  
See [`LICENSE`](LICENSE) for details.
