#!/usr/bin/env julia
#
# Compare a fresh run against a reference results folder. Headline metrics
# are checked against tolerances and decide the exit code; the by-technology
# capacity table is printed side by side for information.
#
#   julia --project=. scripts/compare_results.jl <run_dir> <reference_dir> [--tol-cost 0.02] [--tol-co2 0.05] [--tol-re 0.03] [--tol-nse 0.001]
#
# Tolerances: cost and CO2 are relative; RE share and non-served energy are
# absolute differences in share units (0.03 = 3 percentage points). The
# defaults allow for a different solver reaching a different solution within
# the 1 % MIP gap; runs with the same solver and package versions typically
# agree far more closely.
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."); io = devnull)
using CSV, DataFrames, Printf

function parse_args(args)
    pos = String[]
    tol = Dict("cost" => 0.02, "co2" => 0.05, "re" => 0.03, "nse" => 0.001)
    i = 1
    while i <= length(args)
        a = args[i]
        if startswith(a, "--tol-")
            key = a[7:end]
            haskey(tol, key) || error("unknown option $(a)")
            i += 1
            i <= length(args) || error("missing value after $(a)")
            tol[key] = parse(Float64, args[i])
        else
            push!(pos, a)
        end
        i += 1
    end
    length(pos) == 2 || error("usage: julia --project=. scripts/compare_results.jl <run_dir> <reference_dir> [--tol-cost x] [--tol-co2 x] [--tol-re x] [--tol-nse x]")
    return abspath(pos[1]), abspath(pos[2]), tol
end

run_dir, ref_dir, tol = parse_args(ARGS)
for d in (run_dir, ref_dir)
    isdir(d) || error("folder not found: $(d)")
end
const REQUIRED_FILES = ("generator_results.csv", "cost_results.csv", "clean_energy_results.csv", "nse_results.csv", "storage_results.csv")
let missing = [(d, f) for d in (run_dir, ref_dir) for f in REQUIRED_FILES if !isfile(joinpath(d, f))]
    if !isempty(missing)
        for (d, f) in missing
            println("  FAIL missing $(f) in $(d)")
        end
        println("COMPARE_FAIL: $(length(missing)) required file(s) missing")
        exit(1)
    end
end
readcsv(d, f) = CSV.read(joinpath(d, f), DataFrame)

fails = 0
function check(name, got, want, tolerance; relative)
    global fails
    diff = got - want
    measure = relative ? abs(diff) / max(abs(want), 1e-12) : abs(diff)
    ok = measure <= tolerance
    ok || (fails += 1)
    unit = relative ? "% rel." : "abs."
    @printf("  %-4s %-38s run %16.4f   ref %16.4f   diff %10.4f %s (tol %g)\n",
            ok ? "ok" : "FAIL", name, got, want, relative ? 100measure : measure, unit, relative ? 100tolerance : tolerance)
end

println("Comparing run       $(run_dir)")
println("against reference   $(ref_dir)")
println()
println("Headline metrics")
println("-" ^ 110)
rc, xc = readcsv(run_dir, "cost_results.csv"), readcsv(ref_dir, "cost_results.csv")
re, xe = readcsv(run_dir, "clean_energy_results.csv"), readcsv(ref_dir, "clean_energy_results.csv")
rn, xn = readcsv(run_dir, "nse_results.csv"), readcsv(ref_dir, "nse_results.csv")
check("Total system cost (M USD/yr)", rc.Total_Costs[1], xc.Total_Costs[1], tol["cost"]; relative = true)
check("CO2 emissions (tCO2/yr)", re.CO2_Emissions[1], xe.CO2_Emissions[1], tol["co2"]; relative = true)
check("Grid RE share (fraction)", re.Grid_REShare[1], xe.Grid_REShare[1], tol["re"]; relative = false)
check("Non-served energy (fraction of demand)", sum(rn.NSE_Percent_of_Demand) / 100, sum(xn.NSE_Percent_of_Demand) / 100, tol["nse"]; relative = false)

# by-technology capacity, side by side (information only)
function cap_by_tech(d)
    g = readcsv(d, "generator_results.csv")
    combine(groupby(g, :technology), :Total_MW => sum => :Total_MW, :GWh => sum => :GWh)
end
a, b = cap_by_tech(run_dir), cap_by_tech(ref_dir)
t = outerjoin(rename(a, :Total_MW => :run_MW, :GWh => :run_GWh),
              rename(b, :Total_MW => :ref_MW, :GWh => :ref_GWh), on = :technology)
for c in (:run_MW, :ref_MW, :run_GWh, :ref_GWh)
    t[!, c] = round.(coalesce.(t[!, c], 0.0); digits = 2)
end
t = t[(t.run_MW .> 0) .| (t.ref_MW .> 0), :]
sort!(t, :ref_GWh, rev = true)
println()
println("Capacity (MW) and generation over the representative weeks (GWh) by technology, for information")
println("-" ^ 110)
show(stdout, select(t, :technology, :run_MW, :ref_MW, :run_GWh, :ref_GWh); allrows = true, allcols = true, summary = false, eltypes = false)
println()

println()
if fails == 0
    println("COMPARE_OK: headline metrics within tolerance of the reference")
    exit(0)
else
    println("COMPARE_FAIL: $(fails) check(s) outside tolerance")
    exit(1)
end
