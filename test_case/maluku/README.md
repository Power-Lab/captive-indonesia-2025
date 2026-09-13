# Maluku 2030 test case

The smallest job in the study: Maluku island, planning year 2030, `base`
scenario (no grid imports or on-site investment for industrial parks) and the
`reference` case (no CO₂ cap or renewable-share floor). It uses only the four
core input files in `data_indonesia/2030/maluku/` and is the one job that solves
on a laptop in minutes.

Run it from the repository root:

```bash
julia bootstrap.jl                                            # once
julia --project=. test_case/run_maluku_test.jl                # exact MILP, HiGHS, about 15 minutes
julia --project=. test_case/run_maluku_test.jl --solver gurobi
julia --project=. test_case/run_maluku_test.jl --quick        # LP relaxation, about 2 minutes
```

## Files

| Path | Content |
|------|---------|
| `config.json` | The job definition (`solver` is `highs`; the runner overrides `solver`, `relax_uc` and `run_tag`). |
| `expected_results/` | Reference outputs of the published set-up: exact unit commitment, Gurobi, 1 % MIP gap. `run_info.json` records the versions, commit, achieved gap and solve time. |
| `expected_results_relaxed/` | Reference outputs for `--quick` (`relax_uc = true`, HiGHS interior point with crossover). Its cost is a lower bound on the exact model, about 1 % below it here. |
| `../run_maluku_test.jl` | Solves, summarises and compares; exits non-zero if a headline metric is outside tolerance. |

## Reference outputs

Produced on an Apple Silicon laptop with Julia 1.12 and the package versions in
`Manifest.toml`. The model is solved to a 1 % MIP gap, so another solver or
machine can stop at a different near-optimal plan; the comparison checks
headline metrics with tolerances (see `scripts/compare_results.jl`).

| Metric | `expected_results/` (Gurobi 13.0, exact) | HiGHS 1.15, exact (observed) | `expected_results_relaxed/` (HiGHS 1.15, LP) |
|--------|------:|------:|------:|
| Total system cost (million USD/yr) | 68.31 | 68.16 | 67.59 |
| CO₂ emissions (tCO₂/yr) | 690,071 | 686,908 | 700,153 |
| Grid renewable share | 69.5 % | 69.5 % | 69.2 % |
| Non-served energy (share of demand) | 0.017 % | 0.017 % | 0.032 % |
| Achieved MIP gap | 1.00 % | 0.83 % | LP |
| Solver time | 39 s | 813 s | 83 s |

The exact plans agree on the fleet: all existing diesel, gas and coal units are
kept, no storage energy is built, and 66 to 67 MW of new solar is added. The
HiGHS plan is 0.2 % cheaper with slightly more solar and 0.5 % lower emissions;
both are valid solutions within the 1 % MIP gap the study used.

One quirk to be aware of when reading `generator_results.csv`: the Maluku
inputs give `battery_candidate` a zero cost per MW of power capacity (its cost
is per MWh of energy), so the solver may report a non-zero `Total_MW` for it
even when `storage_results.csv` shows 0 MWh built. That power capacity is free
and unused, not a battery investment.

## Regenerating the reference outputs

```bash
julia --project=. run_model.jl --config test_case/maluku/config.json --solver gurobi
cp results/base_maluku_2030_reference/*.csv results/base_maluku_2030_reference/run_info.json test_case/maluku/expected_results/
```

Do this only when the model or the inputs change deliberately, and say why in
the commit message.
