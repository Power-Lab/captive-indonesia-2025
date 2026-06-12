# Model Formulation

The model is a single-year capacity-expansion and unit-commitment MILP that
co-optimises an island grid and a set of village systems. This document states
the formulation as implemented in `functions/optimizer.jl`
(`capacity_expansion`), with line references for each block. Notation follows
the code.

## Sets (built in `functions/input_data.jl`)

| Set | Meaning |
|-----|---------|
| `T` | Hours across all representative periods (e.g. 8×168 = 1,344); `START`/`INTERIOR` split period-first hours from the rest |
| `Z` | Grid zones; `L` transmission corridors |
| `G` | Grid generators; partitioned into `UC` (`Commit=1`, binary commitment) and `ED` (economic dispatch), and `OLD`/`NEW` (existing vs candidate) |
| `STOR`, `VRE` | Grid storage / variable-renewable subsets |
| `S` | Demand-curtailment (NSE) segments |
| `VIL` | Villages; `VIL_G`, `VIL_UC`, `VIL_ED`, `VIL_STOR`, `VIL_NEW`, `VIL_OLD` mirror the grid subsets |

Each hour `t` carries `sample_weight[t] = Sub_Weights[p]/168`, scaling
representative-period operations to annual quantities.

## Decision variables (optimizer.jl 16–111)

**Grid investment** — `vCAP[g]` total power capacity; `vNEW_CAP_*`/`vRET_CAP_*`
new-build and retirement for ED and UC units; `vE_CAP[g]` storage energy
capacity with new/retire components; `vT_CAP[l]`, `vNEW_T_CAP[l]`,
`vRET_T_CAP[l]` transmission. New-build bounded by `Max_Cap_MW` when positive
(42–53).

**Grid operations** — `vGEN[t,g]`, `vCHARGE[t,g]`, `vSOC[t,g]`, `vNSE[t,s,z]`,
`vFLOW[t,l]`; binaries `vCOMMIT/vSTART/vSHUT[t,g∈UC]` (36–38).

**Village** — mirrored: `vVIL_CAP`, `vVIL_E_CAP` (+ new/retire),
`vVIL_GEN`, `vVIL_GEN_HEAT`, `vVIL_CHARGE`, `vVIL_SOC`, `vVIL_NSE`,
`vVIL_NSE_HEAT`, binaries `vVIL_COMMIT/START/SHUT`; and, in `Grid` scenarios,
imports `vVIL_IMPORT[t,vil] ≥ 0` (94–99). New village storage energy is bounded
per unit by `village_storage_max_mwh` (109–111). Village exports are not
modelled (commented `vVIL_EXPORT`).

## Constraints

**Zonal power balance** (117–136): for each `t, z` —
generation + NSE − storage charging − demand − line flows (incidence `z<i>` ∈
{+1, −1}) − village imports of villages in zone `z` (via `village_zone`) = 0.
Transport flow model; the DC power-flow variant is commented out (203–206).

**Capacity limits** (142–169): `vGEN ≤ variability×vCAP` for ED;
`vGEN ≤ Existing_Cap×vCOMMIT` and `vGEN ≥ Min_Power×Existing_Cap×vCOMMIT` for
UC (note: UC unit size is `Existing_Cap_MW`, so UC new-build adds copies of the
existing unit size); charge ≤ power capacity and SOC ≤ energy capacity for
storage; `vNSE ≤ NSE_Max×demand` per segment; |flow| ≤ `vT_CAP`.

**Capacity accounting** (171–201): total = existing − retired (OLD) or = new
build (NEW), for power, storage energy, and transmission
(`vT_CAP = Line_Max_Flow + vNEW_T_CAP − vRET_T_CAP`, expansion bounded by
`Line_Max_Reinforcement_MW`).

**Ramping** (209–258): up/down limits as fractions of capacity; for UC units
the start/shut terms allow jumps to/from `Min_Power`. Each constraint has a
wrap-around twin linking the first and last hour of each representative period.

**Commitment** (260–303): min up/down times via rolling sums of `vSTART`/
`vSHUT`; commitment-state recursion `vCOMMIT[t+1] = vCOMMIT[t] + vSTART − vSHUT`;
commit/start/shut bounded by installed units (`vCAP/Existing_Cap`).

**Storage SOC** (271–279): `vSOC[t] = vSOC[t−1] + Eff_Up×vCHARGE −
vGEN/Eff_Down`, with periodic wrap inside each representative period.

**Village blocks** (307–536): structurally identical, per village:

- *Heat balance* (309–314): UC-unit heat output + heat NSE = heat demand.
- *Electricity balance* (316–380): generators allowed to serve village demand
  depend on the scenario — `VIL_UC` only (no `VillageBuild`), all `VIL_G`
  (`VillageBuild`), or `VIL_ED`-only (`NoCoal`); plus `vVIL_IMPORT` when `Grid`
  is active; minus storage charging.
- Capacity, ramping, commitment, and SOC mirror the grid (382–536).

**Policy constraints** (539–572):

- CO₂ cap on grid emissions: `eCO2EmissionsGrid ≤ CO2_limit` (active in
  `clean` runs).
- 2035 village-emissions cut: `eCO2EmissionsVIL ≤ 0.65×BAU` when
  `CO235reduction`.
- RE share: weighted RE-flagged grid generation ≥ `RE_limit` × total grid
  demand (active in `clean` runs). **Grid-only**: village generation is in
  neither numerator nor denominator.

## Objective (574–687)

Minimise total annual cost:

```
  fixed costs:    Σ FOM×vCAP + Σ Inv×vNEW_CAP            (grid + village, power & storage energy)
+ transmission:   Σ (FOM + reinforcement cost)×vT_CAP
+ variable costs: Σ_t w_t × VarCost_g × vGEN             (VarCost = VOM + fuel×heat-rate)
+ start-up costs: Σ_t w_t × StartCost × vSTART × unit size
+ imports:        Σ_t w_t × ImportPrice × vVIL_IMPORT
+ reliability:    Σ_t w_t × (VOLL×segment cost) × NSE    (grid, village, village heat)
```

Emission rates and variable costs are precomputed per generator in
`input_data.jl` (87–104) from `fuels_data.csv`.

## Solver settings (optimizer.jl 3–9)

Gurobi; `MIPGap = mipgap` (config key, default 0.01), `TimeLimit` 72 h,
`Crossover 0`. An optional Benders decomposition
(`functions/benders_decomposition.jl`, not loaded by default) splits investment
(master) from dispatch (subproblem) for very large instances.

## Known formulation limitations

Collected in `CHANGES.md` "Flagged for follow-up": grid-only RE share,
unenforced village `Max_Cap_MW`, flat import price, no village exports, no
reserve constraints, and annual-only result extraction.
