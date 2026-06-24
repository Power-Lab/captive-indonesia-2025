#!/usr/bin/env julia
using Pkg

const REPO_ROOT = @__DIR__

println("Activating Julia environment at $(REPO_ROOT)")
Pkg.activate(REPO_ROOT)
Pkg.resolve()
Pkg.instantiate()

using JuMP
using Gurobi

include(joinpath(REPO_ROOT, "functions", "preflight.jl"))

println("Checking Gurobi availability")
validate_gurobi()

println("Julia environment is ready.")