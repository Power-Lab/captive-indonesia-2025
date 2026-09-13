#!/usr/bin/env julia
# One-time environment setup: installs the pinned Julia packages and checks
# that the default open-source solver (HiGHS) can solve a model.
#
#   julia bootstrap.jl
using Pkg

const REPO_ROOT = @__DIR__

println("Activating the Julia environment at $(REPO_ROOT)")
Pkg.activate(REPO_ROOT)
Pkg.instantiate()

using JuMP
using HiGHS
include(joinpath(REPO_ROOT, "functions", "solver.jl"))

println("Checking the default open-source solver (HiGHS)")
validate_solver("highs")

println("Julia environment is ready.")
println("Gurobi is optional: set \"solver\": \"gurobi\" in a config.json to use it (licence required).")
