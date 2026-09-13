#!/usr/bin/env julia
#
# Print a human-readable summary of one results folder and write the
# by-technology table next to the CSVs as summary_by_technology.csv.
#
#   julia --project=. scripts/summarize_results.jl results/base_maluku_2030_reference
#
# Only the pinned Julia environment is needed (CSV, DataFrames, JSON).
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."); io = devnull)
using CSV, DataFrames, JSON, Printf

length(ARGS) >= 1 || error("usage: julia --project=. scripts/summarize_results.jl <results_dir>")
const DIR = abspath(ARGS[1])
isdir(DIR) || error("results folder not found: $(DIR)")

readcsv(f) = CSV.read(joinpath(DIR, f), DataFrame)
fmt(x; d = 1) = x isa Number ? (isfinite(x) ? string(round(x; digits = d)) : "n/a") : string(x)

"""
    technology_table(gen)

Capacity and generation by technology. `Start_MW` in generator_results.csv is
the existing capacity for existing units and the maximum buildable size for
new-build candidates (New_Build == 1), so the two are separated here.
"""
function technology_table(gen::DataFrame)
    existing = gen[gen.New_Build .!= 1, :]
    newbuild = gen[gen.New_Build .== 1, :]
    ex = combine(groupby(existing, :technology),
                 :Start_MW => sum => :Existing_MW,
                 :Total_MW => sum => :Retained_MW)
    nb = combine(groupby(newbuild, :technology), :Total_MW => sum => :New_Build_MW)
    ge = combine(groupby(gen, :technology), :GWh => sum => :GWh_rep_weeks,
                 :Percent_GWh => sum => :Share_of_demand_pct)
    t = outerjoin(ex, nb, on = :technology)
    t = outerjoin(t, ge, on = :technology)
    for c in (:Existing_MW, :Retained_MW, :New_Build_MW, :GWh_rep_weeks, :Share_of_demand_pct)
        t[!, c] = coalesce.(t[!, c], 0.0)
    end
    t.Total_MW = t.Retained_MW .+ t.New_Build_MW
    t = t[(t.Total_MW .> 1e-6) .| (t.Existing_MW .> 1e-6) .| (t.GWh_rep_weeks .> 1e-6), :]
    sort!(t, :GWh_rep_weeks, rev = true)
    for c in names(t, Real)
        t[!, c] = round.(t[!, c]; digits = 2)
    end
    select(t, :technology, :Existing_MW, :Retained_MW, :New_Build_MW, :Total_MW, :GWh_rep_weeks, :Share_of_demand_pct)
end

gen   = readcsv("generator_results.csv")
cost  = readcsv("cost_results.csv")
clean = readcsv("clean_energy_results.csv")
nse   = readcsv("nse_results.csv")
stor  = isfile(joinpath(DIR, "storage_results.csv")) ? readcsv("storage_results.csv") : nothing
info  = isfile(joinpath(DIR, "run_info.json")) ? JSON.parsefile(joinpath(DIR, "run_info.json")) : nothing

println("=" ^ 78)
println("Results summary: $(DIR)")
println("=" ^ 78)
if info !== nothing
    println("Run:      $(info["job_name"])  |  solver $(info["solver"]) $(get(info, "solver_package_version", ""))  |  status $(info["termination_status"])")
    gap = get(info, "relative_gap", nothing)
    println("          Julia $(info["julia_version"]), JuMP $(info["jump_version"]), commit $(something(get(info, "git_commit", nothing), "n/a")), " *
            "relax_uc=$(info["relax_uc"]), mipgap=$(info["mipgap"])" *
            ((gap === nothing || get(info, "relax_uc", false) == true) ? "" : ", achieved gap $(fmt(100gap; d = 3)) %") *
            ", solver time $(fmt(get(info, "solve_time_s", NaN))) s")
end

println()
println("Headline metrics")
println("-" ^ 78)
@printf("  %-44s %14.3f\n", "Total system cost (million USD/yr)", cost.Total_Costs[1])
for (label, col) in (("  fixed cost, grid generation", :Fixed_Costs_Generation),
                     ("  fixed cost, storage", :Fixed_Costs_Storage),
                     ("  fixed cost, transmission", :Fixed_Costs_Transmission),
                     ("  fixed cost, industrial parks", :Fixed_Costs_IP),
                     ("  fixed cost, industrial-park storage", :Fixed_Costs_IP_Storage),
                     ("  variable cost, grid", :Variable_Costs_Grid),
                     ("  variable cost, industrial parks", :Variable_Costs_IP),
                     ("  start-up cost, grid", :StartCostsGrid),
                     ("  start-up cost, industrial parks", :StartCostsIP),
                     ("  grid import cost, industrial parks", :Grid_Import_Costs),
                     ("  non-served energy cost, grid", :NSE_Costs),
                     ("  non-served energy cost, IP electricity", :IPNSECosts),
                     ("  non-served heat cost, IP", :IPNSEHeatCosts))
    v = cost[1, col]
    (v isa Number && abs(v) > 1e-9) && @printf("  %-44s %14.3f\n", label, v)
end
@printf("  %-44s %14.0f\n", "CO2 emissions (tCO2/yr)", clean.CO2_Emissions[1])
abs(clean.CO2_Emissions_IP[1]) > 1e-9 && @printf("  %-44s %14.0f\n", "  of which industrial parks", clean.CO2_Emissions_IP[1])
@printf("  %-44s %14.1f\n", "Grid renewable energy share (%)", 100 * clean.Grid_REShare[1])
@printf("  %-44s %14.4f\n", "Non-served energy (% of demand, rep. weeks)", sum(nse.NSE_Percent_of_Demand))
if stor !== nothing && nrow(stor) > 0
    @printf("  %-44s %14.1f\n", "Storage energy capacity (MWh)", sum(stor.Total_Storage_MWh))
end

tech = technology_table(gen)
println()
println("Capacity and generation by technology")
println("  (MW; GWh and shares are over the representative weeks in the sample, not annualised)")
println("-" ^ 78)
show(stdout, tech; allrows = true, allcols = true, summary = false, eltypes = false)
println()

out = joinpath(DIR, "summary_by_technology.csv")
CSV.write(out, tech)
println()
println("Wrote $(out)")
