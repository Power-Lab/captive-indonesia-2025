#!/usr/bin/env julia
using Pkg

const REPO_ROOT = @__DIR__
Pkg.activate(REPO_ROOT)

using JSON
using JuMP
using DataFrames, CSV
using Gurobi
using Base.Filesystem: mkpath

include(joinpath(REPO_ROOT, "functions", "preflight.jl"))

# 1) Load your core modeling code
include(joinpath(REPO_ROOT, "functions/function_compiler.jl"))

# 2) Read config.json
config_path, preflight_only = parse_cli_args(ARGS)
preflight = run_preflight(config_path, REPO_ROOT)
cfg = preflight.cfg
island           = cfg["island"]
year             = cfg["year"]
scenario         = cfg["scenario"]
clean            = cfg["clean"]
CO235reduction   = cfg["CO235reduction"]
BAUCO2emissions  = cfg["BAUCO2emissions"]
CO2_limit        = cfg["CO2_limit"]

# 3) Baseline model settings
mipgap         = 0.01
CO2_constraint = preflight.clean_flags.CO2_constraint
RE_constraint  = preflight.clean_flags.RE_constraint
RE_limit       = 0.34

# 4) Scenario toggles
Grid = preflight.flags.Grid
Captive = preflight.flags.Captive
ImportPrice = preflight.flags.ImportPrice
NoCoal = preflight.flags.NoCoal

if preflight_only
    println("Preflight checks passed for $(scenario)_$(island)_$(year)_$(clean)")
    exit()
end

# 6) Build input path
inputs_path = preflight.inputs_path

# 7) Create a scenario‑specific results folder
results_dir = preflight.results_dir
mkpath(results_dir)

# 8) Invoke the compiler, passing that folder
function_compiler(
    inputs_path,
    results_dir,
    mipgap,
    CO2_constraint,
    CO2_limit,
    RE_constraint,
    RE_limit,
    Grid,
    Captive,
    ImportPrice,
    NoCoal,
    CO235reduction,
    BAUCO2emissions
)
