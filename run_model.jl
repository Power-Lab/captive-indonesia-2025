#!/usr/bin/env julia
#
# Entry point: solve one scenario described by a config.json and write the
# result CSVs.
#
#   julia --project=. run_model.jl --config test_case/maluku/config.json
#   julia --project=. run_model.jl                 # reads ./config.json (job folders)
#   julia --project=. run_model.jl --config cfg.json --solver gurobi
#   julia --project=. run_model.jl --config cfg.json --preflight-only
#
# Required config keys: island, year, scenario, clean, CO235reduction,
# BAUCO2emissions, CO2_limit. Optional keys (defaults in brackets):
#   solver      "highs" | "gurobi"          ["highs"]  open-source HiGHS needs no licence
#   mipgap      relative MIP gap            [0.01]
#   relax_uc    LP-relax unit commitment    [false]    fast approximation, not the published model
#   time_limit  solver limit in seconds     [259200]   3 days; on expiry the incumbent is written
#   RE_limit    minimum RE share, clean runs [0.34]
#   run_tag     suffix for the results folder [""]
using Pkg

const REPO_ROOT = @__DIR__
Pkg.activate(REPO_ROOT; io = devnull)   # use the pinned Project.toml/Manifest.toml

using JSON
using JuMP
using DataFrames, CSV
using HiGHS
using Base.Filesystem: mkpath

include(joinpath(REPO_ROOT, "functions", "preflight.jl"))
include(joinpath(REPO_ROOT, "functions", "function_compiler.jl"))

# 1) Command line and solver choice. Gurobi is imported only when requested so
#    that an open-source set-up never needs it.
cli    = parse_cli_args(ARGS)
solver = lowercase(strip(something(cli.solver, get(JSON.parsefile(cli.config_path), "solver", "highs"))))
solver == "gurobi" && @eval using Gurobi

# 2) Validate the config, the input folder and the solver before building anything
pre = run_preflight(cli.config_path, REPO_ROOT; solver = solver)
cfg = pre.cfg

island          = String(cfg["island"])
year            = String(cfg["year"])
scenario        = String(cfg["scenario"])
clean           = String(cfg["clean"])
CO235reduction  = Bool(cfg["CO235reduction"])
BAUCO2emissions = Float64(cfg["BAUCO2emissions"])
CO2_limit       = Float64(cfg["CO2_limit"])

# 3) Model settings (published set-up unless overridden in the config)
mipgap     = Float64(get(cfg, "mipgap", 0.01))
relax_uc   = Bool(get(cfg, "relax_uc", false))
time_limit = Float64(get(cfg, "time_limit", 3 * 24 * 60 * 60))
RE_limit   = Float64(get(cfg, "RE_limit", 0.34))
time_limit > 0 || error("config key time_limit must be > 0 seconds, got $(time_limit)")
0 <= RE_limit <= 1 || error("config key RE_limit must be a share in [0, 1], got $(RE_limit)")

# 4) Scenario and clean-case switches
Grid           = pre.flags.Grid
Captive        = pre.flags.Captive
ImportPrice    = pre.flags.ImportPrice
NoCoal         = pre.flags.NoCoal
CO2_constraint = pre.clean_flags.CO2_constraint
RE_constraint  = pre.clean_flags.RE_constraint

println("Job $(pre.job_name): solver=$(solver), mipgap=$(mipgap), relax_uc=$(relax_uc), " *
        "Grid=$(Grid), Captive=$(Captive), NoCoal=$(NoCoal), CO2_constraint=$(CO2_constraint), RE_constraint=$(RE_constraint)")
println("Inputs:  $(pre.inputs_path)")
println("Results: $(pre.results_dir)")

if cli.preflight_only
    println("Preflight checks passed.")
    exit(0)
end

mkpath(pre.results_dir)

# 5) Solve and write results
wall_t0 = time()
solution = function_compiler(
    pre.inputs_path,
    pre.results_dir,
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
    BAUCO2emissions;
    solver = solver,
    relax_uc = relax_uc,
    time_limit = time_limit
)
wall_s = time() - wall_t0

# 6) Record how this run was produced next to its results
function git_commit(root)
    try
        strip(read(pipeline(`git -C $(root) rev-parse --short HEAD`; stderr = devnull), String))
    catch
        nothing
    end
end
function git_dirty(root)
    try
        !isempty(strip(read(pipeline(`git -C $(root) status --porcelain --untracked-files=no`; stderr = devnull), String)))
    catch
        nothing
    end
end
jsonnum(x) = (x isa AbstractFloat && !isfinite(x)) ? nothing : x
# record the config location relative to the repository (basename if outside it) so
# that run_info.json never contains machine-specific absolute paths
config_label(path, root) = startswith(path, root) ? relpath(path, root) : basename(path)
solver_pkg = solver == "gurobi" ? Gurobi : HiGHS
run_info = Dict(
    "job_name"             => pre.job_name,
    "config_file"          => config_label(cli.config_path, REPO_ROOT),
    "config"               => cfg,
    "solver"               => solution.solver_name,
    "solver_package_version" => string(pkgversion(solver_pkg)),
    "jump_version"         => string(pkgversion(JuMP)),
    "julia_version"        => string(VERSION),
    "platform"             => "$(Sys.KERNEL) $(Sys.ARCH), $(Sys.CPU_THREADS) threads",
    "git_commit"           => git_commit(REPO_ROOT),
    "git_uncommitted_changes" => git_dirty(REPO_ROOT),
    "mipgap"               => mipgap,
    "relax_uc"             => relax_uc,
    "time_limit_s"         => time_limit,
    "termination_status"   => solution.termination_status,
    "objective_usd_per_yr" => jsonnum(solution.cost),
    "relative_gap"         => jsonnum(solution.relative_gap),
    "solve_time_s"         => jsonnum(solution.solve_time_s),
    "wall_time_s"          => round(wall_s; digits = 1),
    "finished_at"          => string(Libc.strftime("%Y-%m-%dT%H:%M:%S", time())),
)
open(joinpath(pre.results_dir, "run_info.json"), "w") do io
    JSON.print(io, run_info, 2)
end

println()
println("Run complete: $(pre.job_name)")
println("  status          $(solution.termination_status)")
println("  objective       $(round(solution.cost / 1e6; digits = 3)) million USD/yr")
isfinite(solution.relative_gap) && println("  MIP gap         $(round(100 * solution.relative_gap; digits = 3)) %")
println("  solver time     $(round(solution.solve_time_s; digits = 1)) s  (wall $(round(wall_s; digits = 1)) s incl. build and I/O)")
println("  results         $(pre.results_dir)")
println("Summarise with:   julia --project=. scripts/summarize_results.jl $(relpath(pre.results_dir, pwd()))")
