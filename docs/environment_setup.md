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

## Windows + conda

The model runs on Windows — the Julia code uses `joinpath` throughout and the
local runner (`generate_jobs_local.py`) has no Unix dependencies. The friction
is all environment setup, not the code. Four points:

1. **Use conda for Python, not for Julia.** A conda/miniforge environment is a
   good home for the `click`/`pyyaml` dependencies. But install **Julia itself
   via [juliaup](https://github.com/JuliaLang/juliaup) or the official Windows
   installer — not conda-forge Julia.** conda-forge Julia has known artifact /
   C-runtime resolution problems with `Gurobi.jl` (the model will fail to build
   or solve). This is about which Julia *build* you use, independent of OS.

2. **`julia` must be on PATH in the same shell as your Python.**
   `generate_jobs_local.py` shells out to `julia`, so if you launch it from a
   conda prompt, `julia` has to be visible there too. Check with `where julia`
   (Command Prompt) or `Get-Command julia` (PowerShell). juliaup adds it to PATH
   on install; restart the shell afterwards.

3. **Set the Gurobi licence via a Windows environment variable**, not `export`:
   ```bat
   setx GRB_LICENSE_FILE "C:\path\to\gurobi.lic"
   ```
   (or System Properties → Environment Variables). Reopen the shell so it picks
   up the change. Gurobi runs natively on Windows.

4. **Put multi-line commands on one line.** The bash examples in this repo use
   `\` line continuations, which do not work in Command Prompt or PowerShell.
   Either put the whole command on a single line, e.g.

   ```bat
   python generate_jobs_local.py --scenarios-file scenario_timor_demo.yml --run-script run_model.jl --output-root jobs
   ```

   or use the shell's own continuation character (`^` in cmd, `` ` `` in
   PowerShell).

**Do not use `generate_jobs.py` on Windows** — it creates symlinks and calls
`sbatch`, which are for Linux HPC/SLURM clusters only. On a Windows laptop use
`generate_jobs_local.py` (or run a single job directly with
`julia --project=. run_model.jl --config <job>/config.json`).

A good first test on Windows is the Maluku run from the README, then the
`timor_demo` village scenarios — both solve in minutes on a laptop.

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
