# Adding a New Island or Region (e.g. Timor)

Checklist for standing up a new study region. The fastest path is to copy
`data_indonesia/2030/timor_demo/` and replace its contents — it has exactly the
columns the model reads and nothing else. Full column semantics:
`data_indonesia/README.md`.

## 1. Create the folder

```
data_indonesia/<year>/<island>/
```

The `<island>` name must **exactly match** the entry you will put under
`islands:` in the scenario YAML, and `<year>` the `years:` entry — the input
path is assembled from them in `functions/preflight.jl`. Use lowercase
snake_case (e.g. `timor`).

## 2. Decide the structure

- **Zones**: how many grid buses? Single-zone needs no `network.csv` (for
  `base`/`village` runs). Multi-zone needs `network.csv` with one `z<i>`
  incidence column per zone.
- **Villages**: integer IDs `1..NV`. A "village" can be a cluster/archetype —
  for Timor, IESR's village archetypes each become one ID, with loads scaled to
  the number of physical villages they represent.
- **Time**: keep 8 representative weeks × 168 h unless you rebuild all hourly
  files together; `Sub_Weights` must sum to 8760 and every hourly file needs
  identical row count/order.

## 3. Populate the files

Minimum for the standalone-vs-coordinated comparison (`village` +
`gridvillage`):

1. `generators.csv` — existing grid units + candidates. `R_ID` consecutive
   from 1. Every `Commit = 1` row needs `Existing_Cap_MW > 0` (it is the unit
   size in commitment constraints).
2. `generators_variability.csv` — hour index column, then one profile column
   per generator **in R_ID order**. Every `Commit = 0` unit whose output
   follows a resource (solar/wind/hydro) needs a real profile.
3. `demand.csv` — VOLL, curtailment segments, rep-period block, hourly
   `demand_z<i>`.
4. `fuels_data.csv` — every fuel named in the generator files plus `None`.
5. `network.csv` — only for `grid*`/`nocoal` scenarios.
6. `village_generators.csv`, `village_demand.csv`, `village_demandheat.csv`
   (zeros for electricity-only), `village_generators_variability.csv`.

## 4. Register the region in a scenario YAML

```yaml
islands: [timor]
years: ["2030"]
scenarios: [village, gridvillage]
cleans: [reference]
island_params:
  timor: <BAU tCO2>        # used only by 2035 clean runs
co2_limits:
  "2030":
    timor: <cap tCO2>      # enforced only in clean runs
```

Optional top-level keys (`mipgap`, `RE_limit`, `import_price`,
`village_storage_max_mwh`) flow into each job's `config.json`.

## 5. Validate before solving

```bash
python generate_jobs_local.py -s scenario_timor.yml -r run_model.jl -o jobs --no-bootstrap
# or, per job, without solving:
julia --project=. run_model.jl --config jobs/<job>/config.json --preflight-only
```

Preflight checks the Gurobi licence and that all required files exist for each
scenario. Common first-run errors and fixes are in the README troubleshooting
table.

## 6. Sizing expectations

| Scale | Example | Where to run |
|-------|---------|--------------|
| ~25 units, 1 zone, 4 villages | `timor_demo` | Laptop, ~30 s |
| ~70 units, 1 zone | `maluku` | Laptop, ~3 min |
| ~115 grid + 16 village units | `papua` `village` | Laptop ceiling, ~35 min |
| Multi-zone with full village data | `sulawesi`, `kalimantan` | HPC (`generate_jobs.py` + SLURM) |

Binary unit-commitment variables (one set per `Commit = 1` unit per hour) drive
solve time; see the commitment note in `docs/village_adaptation.md`.
