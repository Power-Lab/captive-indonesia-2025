#!/usr/bin/env julia
# One-time environment setup: installs the pinned Julia packages and checks
# that the default open-source solver (HiGHS) can solve a model.
#
#   julia bootstrap.jl
using Pkg

const REPO_ROOT = @__DIR__

println("Activating the Julia environment at $(REPO_ROOT)")
Pkg.activate(REPO_ROOT)
try
    Pkg.instantiate()
catch err
    println()
    println("Pkg.instantiate() failed. Manifest.toml was resolved with Julia 1.12; on Julia $(VERSION) run")
    println("    julia --project=. -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'")
    println("(this re-resolves the package versions for your Julia) and then re-run bootstrap.jl.")
    rethrow(err)
end

using JuMP
using HiGHS
include(joinpath(REPO_ROOT, "functions", "solver.jl"))

println("Checking the default open-source solver (HiGHS)")
validate_solver("highs")

println("Julia environment is ready.")
println("Gurobi is optional: set \"solver\": \"gurobi\" in a config.json to use it (licence required).")
