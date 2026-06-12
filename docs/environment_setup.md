# Environment Setup

## Julia

Install via [juliaup](https://github.com/JuliaLang/juliaup) (avoid conda-forge
Julia). Tested with Julia 1.12; `Project.toml`/`Manifest.toml` pin package
versions — `julia --project=. bootstrap.jl` installs everything and checks the
Gurobi licence.

**Harden juliaup on shared/training machines.** A stalled background
`juliaup self update` holds juliaup's configuration lock and silently blocks
every new `julia` launch (symptom: the process prints `Juliaup configuration is
locked by another process, waiting for it to unlock` and appears hung). Disable
auto-updates:

```bash
# juliaup ≥ 1.20 — set the update intervals to 0 to disable
juliaup config backgroundselfupdateinterval 0
juliaup config startupselfupdateinterval 0
juliaup config versionsdbupdateinterval 0
```

If it happens anyway: `ps aux | grep juliaup`, kill the `self update` process,
and the queued launches proceed.

## Python

Only `click` and `pyyaml` are needed (`pip install click pyyaml`) — but install
them **in the interpreter you actually invoke**. macOS machines often have
several Pythons (system, Homebrew, conda); `ModuleNotFoundError: No module
named 'click'` means you ran a different one. `which python python3` and pick
the conda/miniforge one, or create a venv.

## Gurobi licensing

The model is a MILP (binary unit commitment), solved with Gurobi by default.

| Option | Who | Notes |
|--------|-----|-------|
| **Academic Named-User** | University staff/students (UCSD side) | Free; per-machine; renew yearly; requires campus network or VPN to issue |
| **Academic WLS** | Academic teams, cloud/HPC | Free; floating web licence, works in containers |
| **Commercial / NGO** | IESR if no academic affiliation applies | Gurobi has NGO programs — contact sales early; this is a Phase-2 handoff risk |
| **Size-limited free** | Anyone | Bundled with `Gurobi.jl`; too small for these models (Maluku base ≈ 290k constraints) — preflight will pass licence check only with a real licence |

Setup: install Gurobi or let `Gurobi.jl` fetch it, place `gurobi.lic` in the
default location or set `GRB_LICENSE_FILE=/path/to/gurobi.lic`, then run
`julia --project=. bootstrap.jl` — it solves a 1-variable test model to verify
the licence before you discover a problem mid-batch.

### Open-source solver fallback (assessment)

For the promised open-access toolkit, the realistic fallback is
[HiGHS](https://highs.dev) (`HiGHS.jl`). Scope of the change:

- `Model(Gurobi.Optimizer)` and the attribute names (`MIPGap`, `TimeLimit`,
  `Crossover`) appear in `functions/optimizer.jl` (and the optional
  `benders_decomposition.jl`); swapping to HiGHS means a solver argument and an
  attribute-name mapping (`mip_rel_gap`, `time_limit`) — roughly a day of work
  including testing.
- Expect HiGHS to solve `timor_demo`- and `maluku`-scale MILPs fine, but
  several-fold slower at `papua` scale and above. Recommendation: keep Gurobi
  for production runs, add HiGHS as an option so training and small replication
  work without a licence.

Not implemented yet — tracked as follow-up work.
