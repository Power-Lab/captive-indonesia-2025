# Maluku 2030 test case

The smallest job in the study: Maluku island, planning year 2030, `base`
scenario (no grid imports or on-site investment for industrial parks) and the
`reference` case (no CO₂ cap or renewable-share floor). It uses only the four
core input files in `data_indonesia/2030/maluku/` and is the one job that solves
on a laptop in minutes.

Run it from the repository root:

```bash
julia bootstrap.jl                                            # once
julia --project=. test_case/run_maluku_test.jl                # exact MILP, HiGHS (no licence; hours, see below)
julia --project=. test_case/run_maluku_test.jl --solver gurobi  # same model, a few minutes (licence required)
```

## Files

| Path | Content |
|------|---------|
| `config.json` | The job definition (`solver` is `highs`; the runner overrides `solver` and `run_tag`). |
| `expected_results/` | Reference outputs of the published set-up: exact unit commitment, Gurobi, 1 % MIP gap. `run_info.json` records the versions, commit, achieved gap and solve time. |
| `../run_maluku_test.jl` | Solves, summarises and compares; exits non-zero if a headline metric is outside tolerance. |

## Reference outputs

Produced on an Apple Silicon laptop with Julia 1.12 and the package versions in
`Manifest.toml`. The model is solved to a 1 % MIP gap, so another solver or
machine can stop at a different near-optimal plan; the comparison checks
headline metrics with tolerances (see `scripts/compare_results.jl`).

| Metric | `expected_results/` (Gurobi 13.0, exact) |
|--------|------:|
| Total system cost (million USD/yr) | 88.01 |
| CO₂ emissions (tCO₂/yr) | 850,342 |
| Grid renewable share | 2.6 % |
| Non-served energy (share of demand) | 0.34 % |
| Achieved MIP gap | 0.82 % |
| Solver time | 183 s |

HiGHS 1.15 solves the same model without a licence but far more slowly: on the
reference laptop its root relaxation had not finished after 75 minutes. Use
`time_limit` in `config.json` to bound such a run; the incumbent and achieved
gap are written to `run_info.json` and compared like any other result.

In the reference plan all existing diesel, gas and coal units are kept and the
model adds a 50 MW diesel candidate, the 5 MW `plts_namlea` solar plant and a
small battery (3 MW, 2 MWh); about 0.3 % of demand is left unserved in the
price-responsive segments. Two features of the Maluku inputs are worth knowing
when reading these numbers: the `plts_namlea` column in
`generators_variability.csv` is a constant 1.0 (so that plant runs as firm
capacity), and `battery_candidate` has a zero cost per MW of power capacity
(its cost is per MWh), so `Total_MW` for it is not by itself an investment
signal.

## Regenerating the reference outputs

```bash
julia --project=. run_model.jl --config test_case/maluku/config.json --solver gurobi
cp results/base_maluku_2030_reference/*.csv results/base_maluku_2030_reference/run_info.json test_case/maluku/expected_results/
```

(`--solver gurobi` is recorded as the effective solver in the copied `run_info.json`.)

Do this only when the model or the inputs change deliberately, and say why in
the commit message.
