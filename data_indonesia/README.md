# Input Data Dictionary

This document describes every CSV the model reads, column by column, so that a new
region (e.g. Timor) can be added without reverse-engineering the existing files.
All inputs live in `data_indonesia/<year>/<island>/`. The folder name `<island>`
must exactly match the island key used in the scenario YAML, and `<year>` must
match the `years` entry (both are joined into the input path by
`functions/preflight.jl`).

## Which files are required when

| File | `base` / `grid` | `village` / `gridvillage` | `grid`-family (`grid`, `gridvillage`, `nocoal`, `highimportprice`) |
|------|:---:|:---:|:---:|
| `generators.csv` | required | required | required |
| `demand.csv` | required | required | required |
| `generators_variability.csv` | required | required | required |
| `fuels_data.csv` | required | required | required |
| `network.csv` | – | – | required |
| `village_generators.csv` | – | required | required for `gridvillage` |
| `village_demand.csv` | – | required | required for `gridvillage` |
| `village_demandheat.csv` | – | required | required for `gridvillage` |
| `village_generators_variability.csv` | – | required | required for `gridvillage` |
| `zones.csv` | informational only — never read by the code | | |

Run `julia --project=. run_model.jl --config <config.json> --preflight-only` to
check a folder before attempting a full solve.

## General conventions

- **Zones** are integers `1..NZ`. The `Zone` column in `generators.csv`, the
  `demand_z<i>` columns in `demand.csv`, and the `z<i>` columns in `network.csv`
  must all use the same numbering. Single-zone islands use `1` everywhere.
- **Villages** are integers `1..NV` in the `Village` column of
  `village_generators.csv`, matching the `demand_village<i>` columns in
  `village_demand.csv` and `village_demandheat.csv`.
- **R_ID** must be consecutive integers starting at 1, in file row order. R_IDs
  are used directly as array indices throughout the model.
- **Time** is modelled as representative periods (currently 8 representative weeks
  × 168 hours = 1,344 hours), defined inside `demand.csv`. Every hourly file
  (`demand.csv`, both variability files, both village demand files) must have
  exactly the same number of rows in the same hour order.
- **Costs** are in USD: $/MW-yr for annualised investment and fixed O&M, $/MWh for
  variable costs, $/MMBtu for fuels. Capacity is MW (AC), energy MWh.

---

## `generators.csv` — grid-side generators and storage

One row per existing unit or new-build candidate connected to the island grid.

Columns the model reads:

| Column | Unit / type | Meaning |
|--------|-------------|---------|
| `R_ID` | int | Unique ID, 1..N consecutive, row order. |
| `Zone` | int | Grid zone the unit connects to. |
| `Resource` | text | Unit name (also used as the column name convention in `generators_variability.csv`). |
| `technology` | text | Technology label (reporting only). |
| `owner` | text | Owner label (reporting only, may be blank). |
| `Existing_Cap_MW` | MW | Installed capacity. 0 for new-build candidates. **For unit-commitment units this is also the unit size used in commitment constraints, so it must be > 0 for any `Commit = 1` row.** |
| `Existing_Cap_MWh` | MWh | Installed energy capacity (storage rows only; 0 otherwise). |
| `New_Build` | int | `1` = candidate the model may build; any other value (`0`, `-1`) = existing unit that can only be retired. |
| `Max_Cap_MW` | MW | Upper bound on new-build capacity. Values ≤ 0 mean unbounded. |
| `Inv_Cost_per_MWyr` | $/MW-yr | Annualised investment cost (new-build candidates). |
| `Inv_Cost_per_MWhyr` | $/MWh-yr | Annualised investment cost for storage energy capacity. |
| `Fixed_OM_Cost_per_MWyr` | $/MW-yr | Fixed O&M on power capacity. |
| `Fixed_OM_Cost_per_MWhyr` | $/MWh-yr | Fixed O&M on storage energy capacity. |
| `Var_OM_Cost_per_MWh` | $/MWh | Variable O&M (fuel cost is added automatically from `fuels_data.csv` × heat rate). |
| `Min_Power_MW` | **fraction 0–1** | Minimum stable output as a *fraction of capacity* — despite the `_MW` suffix it is not in MW. |
| `Ramp_Up_Percentage` / `Ramp_Dn_Percentage` | fraction/h | Ramp limits as a fraction of capacity per hour. |
| `Commit` | 0/1 | `1` = thermal unit with binary commitment (start/stop/min-up/min-down); `0` = economic dispatch (VRE, hydro, storage). |
| `Start_Cost_per_MW` | $/MW-start | Start-up O&M cost. |
| `Start_Fuel_MMBTU_per_MW` | MMBtu/MW-start | Start-up fuel use. |
| `Heat_Rate_MMBTU_per_MWh` | MMBtu/MWh | Heat rate; multiplied by fuel cost and CO₂ content. |
| `Fuel` | text | Must match a row in `fuels_data.csv` (`None` for fuel-free units). |
| `Up_Time` / `Down_Time` | hours (int) | Minimum up/down time for `Commit = 1` units. |
| `Eff_Up` / `Eff_Down` | fraction | Storage charge / discharge efficiency (1 for non-storage). |
| `STOR` | 0/1 | `1` = storage resource (gets energy-capacity and state-of-charge variables). |
| `VRE` | 0/1 | Variable-renewable flag (reporting only; dispatch limits come from `Commit = 0` + the variability file). |
| `RE` | 0/1 | Counts toward the renewable-share constraint in `clean` runs. **Only grid generators count toward RE share — village generation does not.** |
| `THERM` | 0/1 | Thermal flag (reporting only). |

Columns present in legacy files but **ignored by the code**: `System`, `Province`,
`cod`, `status`, `quota_allocation`, `capex_mw`. They can be left blank or omitted
in new datasets.

---

## `demand.csv` — system settings, time structure, and hourly zonal demand

This file packs three things into one CSV (a legacy of the original spreadsheet
workflow). Scalar settings occupy the **first row(s)** of their column; the hourly
time series fills all rows.

| Column | Rows used | Meaning |
|--------|-----------|---------|
| `Voll` | row 1 only | Value of lost load, $/MWh (cost of involuntary curtailment, segment 1). |
| `Demand_Segment` | rows 1..S | Curtailment segment IDs (e.g. 1–4). |
| `Cost_of_Demand_Curtailment_per_MW` | rows 1..S | Segment cost as a **multiplier of VOLL** (e.g. 0.9 → 0.9 × VOLL). |
| `Max_Demand_Curtailment` | rows 1..S | Maximum share of hourly zonal demand the segment may curtail (fraction). |
| `Rep_Periods` | row 1 only | Number of representative periods P (e.g. 8). |
| `Timesteps_per_Rep_Period` | row 1 only | Hours per period (e.g. 168 = one week). |
| `Sub_Weights` | rows 1..P | Hours of the year each representative period stands for. **Must sum to 8760.** |
| `corresponding_week` | rows 1..P | Source week-of-year of each representative period (informational). |
| `r_id` | all rows | Hour index 1..(P × hours). Defines the model's time set. |
| `month`, `day`, `hour`, `date`, `$/MWh` | – | Informational only; not read. |
| `demand_z<i>` | all rows | Hourly demand (MW) for zone *i*. One column per zone. |

---

## `generators_variability.csv` — hourly availability factors

- Column 1 is the hour index (`r_id`); it is dropped on load.
- After that, **one column per generator, in `R_ID` order** — profile column *g*
  belongs to the generator with `R_ID = g`. Column *names* are ignored (duplicate
  resource names are fine); **order is what matters**.
- Values are availability factors 0–1. Use flat 1.0 for dispatchable thermal
  units and storage; actual hourly capacity factors for solar, wind, and hydro.
- Generators beyond the last profile column (e.g. trailing new-build candidates)
  are given a flat availability of 1.0 automatically. Any `Commit = 0` candidate
  whose output should follow a resource profile (solar/wind) **must** have a real
  column — otherwise it is treated as firm capacity.
- Row count and order must match `demand.csv`'s `r_id`.

> Note: before June 2026 the loader did not drop the leading `r_id` column, so
> every economic-dispatch generator silently used the profile of the *previous*
> generator. See `CHANGES.md` at the repo root if you are comparing against older
> results.

---

## `fuels_data.csv` — fuel prices and emission factors

| Column | Unit | Meaning |
|--------|------|---------|
| `Fuel` | text | Fuel name referenced by `generators.csv` / `village_generators.csv`. Must include a `None` row with zeros. |
| `Cost_per_MMBtu` | $/MMBtu | Fuel price. |
| `CO2_content_tons_per_MMBtu` | tCO₂/MMBtu | Emission factor. |
| `fuel_indices` | – | Ignored by the code. |

The same fuel table is used for grid and village generators.

---

## `network.csv` — transmission paths (grid scenarios only)

One row per transmission corridor between zones.

| Column | Unit | Meaning |
|--------|------|---------|
| `r_id` | int | Line ID, 1..L consecutive. |
| `path_name`, `substation_path` | text | Labels (reporting only). |
| `z<i>` | −1/0/+1 | Incidence: `+1` in the origin zone, `−1` in the destination zone, `0` elsewhere. Positive flow goes from the `+1` zone to the `−1` zone. One column per zone. |
| `Line_Max_Flow_MW` | MW | Existing transfer capacity. |
| `Line_Max_Reinforcement_MW` | MW | Upper bound on capacity expansion for this corridor. |
| `Line_Reinforcement_Cost_per_MWyr` | $/MW-yr | Annualised reinforcement cost (also reused as the line's fixed O&M). |
| `voltage_kV`, `distance_km`, `Dm`, `x`, `B`, `Line_Loss_Percentage` | – | Read but unused (kept for a commented-out DC power-flow formulation). |

Transport ("pipeline") flow model: no losses, no angle constraints.

---

## `village_generators.csv` — village-level generators and storage

Same structure and semantics as `generators.csv`, with one extra key column:

| Column | Meaning |
|--------|---------|
| `Village` | Integer ID of the village (or village cluster) the unit belongs to, 1..NV. Matches `demand_village<i>` columns. |
| `Zone` | Grid zone the village sits in — used to assign grid imports to the right zone bus in `gridvillage` runs. |

Columns read by the model: `R_ID`, `Zone`, `Village`, `Resource`, `technology`,
`Existing_Cap_MW`, `Existing_Cap_MWh`, `New_Build`, `Inv_Cost_per_MWyr`,
`Inv_Cost_per_MWhyr`, `Fixed_OM_Cost_per_MWyr`, `Fixed_OM_Cost_per_MWhyr`,
`Var_OM_Cost_per_MWh`, `Min_Power_MW` (fraction), `Ramp_Up_Percentage`,
`Ramp_Dn_Percentage`, `Commit`, `Start_Cost_per_MW`, `Start_Fuel_MMBTU_per_MW`,
`Heat_Rate_MMBTU_per_MWh`, `Fuel`, `Up_Time`, `Down_Time`, `Eff_Up`, `Eff_Down`,
`STOR`.

Differences from grid generators worth knowing:

- `Max_Cap_MW` is **not** enforced for village units (the bound is currently
  commented out in `functions/optimizer.jl`).
- New village **storage** energy capacity is capped at a hardcoded 208 MWh per
  unit (`functions/optimizer.jl`) — flagged for parameterisation.
- Village units do not count toward the system renewable-share constraint.
- The many ownership/financing columns in the legacy industrial-park files
  (`commodity`, `plant_owner`, `owner_parent_company`, `owner_home_country_flag`,
  `latitude`, `longitude`, etc.) are **not read**; new datasets can omit them.

## `village_demand.csv` — village settings and hourly electricity demand

Identical skeleton to `demand.csv` (VOLL, curtailment segments, `r_id`), but
demand columns are `demand_village<i>` (MW) — one per village. The VOLL and
segment definitions here apply to village demand and may differ from the grid's.
The `Rep_Periods` / `Sub_Weights` columns, if present, are ignored — the time
structure always comes from `demand.csv`.

## `village_demandheat.csv` — hourly village heat demand

`r_id` plus `demand_village<i>` columns giving hourly useful-heat demand (MWth)
served by village `Commit = 1` units. **For electricity-only village modelling,
fill these columns with zeros** — the file must still exist for `village` /
`gridvillage` runs.

## `village_generators_variability.csv` — village availability factors

Same rules as `generators_variability.csv`: hour-index first column (dropped on
load), then one profile column per village generator in `R_ID` order.

---

## `zones.csv` — province-to-zone lookup (informational)

Maps province names to zone numbers for the multi-zone islands. **Not read by the
code** — kept as documentation of the zone numbering used when the datasets were
built.
