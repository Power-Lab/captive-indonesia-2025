# Outputs Guide

Each job writes `results/<scenario>_<island>_<year>_<clean>/`. All energy
values are annualised via the representative-period weights; costs are **$M**
in `cost_results.csv` and $ elsewhere; emissions are tCO₂/yr.

## File-by-file

**`generator_results.csv`** (grid) / **`village_generator_results.csv`** —
one row per unit: `Total_MW` (optimised capacity), `Start_MW` (existing),
`Change_in_MW` (build > 0, retire < 0), `GWh`/`Electricity_GWh` (annual
generation). Village rows carry the `Village` ID.

**`storage_results.csv`** / **`village_storage_results.csv`** — energy
capacity per storage unit: `Total_Storage_MWh`, `Change_in_Storage_MWh`.
Pair with the power capacity row in the generator results to get duration
(MWh ÷ MW).

**`village_import_results.csv`** — per village: `Total_Import_MWh`,
`Peak_Import_MW`. Nonzero only in `grid*` scenarios.

**`nse_results.csv`** / **`village_nse_results.csv`** — non-served energy by
segment × zone (or village): `Total_NSE_MWh`, `NSE_Percent_of_Demand`,
`Max_NSE_MW`. The reliability outcome.

**`cost_results.csv`** — single-row $M breakdown:
`Total_Costs`, `Fixed_Costs_Generation/Storage/Transmission` (grid),
`Fixed_Costs_Village`, `Fixed_Costs_Village_Storage`,
`Variable_Costs_Grid/Village`, `NSE_Costs`, `VILNSECosts`, `VILNSEHeatCosts`,
`Grid_Import_Costs`, `StartCostsGrid`, `StartCostsVIL`.

**`clean_energy_results.csv`** — `CO2_Emissions` (total), `_Grid`, `_Village`,
and `Grid_REShare` (grid generation only — village solar is excluded).

**`transmission_results.csv`** — per corridor: existing, optimised, and change
in transfer capacity. `Change_in_Transfer_Capacity > 0` is grid reinforcement.

## Headline metrics for the village study

Comparing a standalone run (`village_…`) against a coordinated run
(`gridvillage_…`) on the same island/year:

| Concept-note metric | Computation |
|---------------------|-------------|
| System cost saving from coordination | `Total_Costs(village) − Total_Costs(gridvillage)` |
| Avoided grid reinforcement | Δ `Fixed_Costs_Transmission`, and per-line Δ in `transmission_results.csv` |
| Diesel displacement | Δ annual `GWh` summed over diesel rows in both generator results files; fuel burn = GWh × heat rate |
| Emissions reduction | Δ `CO2_Emissions` |
| Optimal battery sizing | `village_storage_results.csv` MWh with paired MW from `village_generator_results.csv` |
| Reliability improvement | Δ `Total_NSE_MWh` in `village_nse_results.csv` |

```python
import pandas as pd
base = "results/{}_timor_demo_2030_reference/cost_results.csv"
standalone  = pd.read_csv(base.format("village")).iloc[0]
coordinated = pd.read_csv(base.format("gridvillage")).iloc[0]
print("coordination saving ($M):", standalone.Total_Costs - coordinated.Total_Costs)
```

## Caveats

- `Start_Storage_MWh` is populated from `Existing_Cap_MW` (not `_MWh`) — a
  legacy quirk; existing-storage baselines in the storage files are only
  meaningful when power and energy capacity coincide.
- Hourly dispatch traces are not written by default; the model solves them but
  `result_extraction_function.jl` exports annual aggregates only.
