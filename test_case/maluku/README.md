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

| Metric | `expected_results/` (Gurobi, exact) | HiGHS, exact (observed) | `expected_results_relaxed/` (HiGHS, LP) |
|--------|------:|------:|------:|
| Total system cost (million USD/yr) | 68.31 | 68.11 | 67.59 |
| CO₂ emissions (tCO₂/yr) | 690,071 | 690,381 | 700,153 |
| Grid renewable share | 69.5 % | 69.5 % | 69.2 % |
| Non-served energy (share of demand) | 0.017 % | 0.036 % | 0.032 % |
| Achieved MIP gap | 1.00 % | 0.76 % | LP |
| Solver time | 36 s | 813 s | 83 s |

The exact plans agree on the fleet: all existing diesel, gas and coal units are
kept, and about 66 MW of new solar is built. Gurobi's solution adds a 12 MW
battery; HiGHS's does not, and instead accepts a little more non-served energy
in the price-responsive demand segments, which is why its cost is 0.3 % lower at
a smaller gap. Both are valid solutions within the 1 % MIP gap the study used.

## Regenerating the reference outputs

```bash
julia --project=. run_model.jl --config test_case/maluku/config.json --solver gurobi
cp results/base_maluku_2030_reference/*.csv results/base_maluku_2030_reference/run_info.json test_case/maluku/expected_results/
```

Do this only when the model or the inputs change deliberately, and say why in
the commit message.
