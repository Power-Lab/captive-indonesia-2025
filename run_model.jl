#!/usr/bin/env julia
using JSON
using JuMP
using Plots
using DataFrames, CSV
using Gurobi
using Base.Filesystem: dirname, mkpath

# 1) Load your core modeling code
include(joinpath(@__DIR__, "functions/function_compiler.jl"))

# 2) Read config.json
cfg              = JSON.parsefile("config.json")
island           = cfg["island"]
year             = cfg["year"]
scenario         = cfg["scenario"]
clean            = cfg["clean"]
CO235reduction   = cfg["CO235reduction"]
BAUCO2emissions  = cfg["BAUCO2emissions"]
CO2_limit        = cfg["CO2_limit"]

# 3) Baseline model settings
mipgap         = 0.01
CO2_constraint = false
RE_constraint  = false
RE_limit       = 0.34

# 4) Scenario toggles
if scenario == "base"
    Grid = false; Captive = false; ImportPrice = 59;   NoCoal = false
elseif scenario == "gridcaptive"
    Grid = true;  Captive = true;  ImportPrice = 59;   NoCoal = false
elseif scenario == "grid"
    Grid = true;  Captive = false; ImportPrice = 59;   NoCoal = false
elseif scenario == "captive"
    Grid = false; Captive = true;  ImportPrice = 59;   NoCoal = false
elseif scenario == "highimportprice"
    Grid = true; Captive = true; ImportPrice = 59*1.21; NoCoal = false
elseif scenario == "nocoal"
    Grid = true; Captive = false; ImportPrice = 59;    NoCoal = true
else
    error("Unknown scenario: $scenario")
end

# 5) Clean‑flag overrides
if clean == "reference"
    CO2_constraint = false
    RE_constraint  = false
elseif clean == "clean"
    CO2_constraint = true
    RE_constraint  = true
else
    error("Unknown clean flag: $clean")
end

# 6) Build input path
base_dir    = @__DIR__
inputs_path = joinpath(base_dir, "data_indonesia", year, island)

# 7) Create a scenario‑specific results folder
results_root = joinpath(base_dir, "results_nodc")
job_name     = "$(scenario)_$(island)_$(year)_$(clean)"
results_dir  = joinpath(results_root, job_name)
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
