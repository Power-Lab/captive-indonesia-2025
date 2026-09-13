#!/usr/bin/env julia
#
# One-command reviewer check: solve the Maluku 2030 base/reference case, print a
# summary and compare the headline numbers with the reference outputs shipped in
# this folder.
#
#   julia --project=. test_case/run_maluku_test.jl                  # exact MILP on HiGHS (~15 min on a laptop)
#   julia --project=. test_case/run_maluku_test.jl --solver gurobi  # exact MILP on Gurobi (~1 min, licence needed)
#   julia --project=. test_case/run_maluku_test.jl --quick          # LP-relaxed unit commitment on HiGHS (~2 min)
#
# The default and --solver gurobi modes solve the published model (exact unit
# commitment, 1 % MIP gap) and compare against expected_results/ (produced with
# Gurobi). --quick relaxes the commitment binaries to a fast LP and compares
# against expected_results_relaxed/ (produced with HiGHS). Results land in
# results/base_maluku_2030_reference__test_<mode>/.
using Pkg
const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))
Pkg.activate(REPO_ROOT; io = devnull)
using JSON

quick  = "--quick" in ARGS
exact  = !quick
solver = let i = findfirst(==("--solver"), ARGS)
    if i === nothing
        "highs"
    else
        i < length(ARGS) || error("missing value after --solver")
        lowercase(ARGS[i + 1])
    end
end
for (k, a) in enumerate(ARGS)
    a in ("--quick", "--solver") && continue
    k > 1 && ARGS[k - 1] == "--solver" && continue
    error("unknown argument $(a)\nusage: run_maluku_test.jl [--quick] [--solver highs|gurobi]")
end
quick && solver != "highs" && println("Note: --quick is meant for HiGHS; running the LP relaxation on $(solver) anyway.")

mode      = exact ? "exact" : "quick"
case_dir  = joinpath(REPO_ROOT, "test_case", "maluku")
expected  = joinpath(case_dir, exact ? "expected_results" : "expected_results_relaxed")
isdir(expected) || error("reference folder not found: $(expected)")

cfg = JSON.parsefile(joinpath(case_dir, "config.json"))
cfg["solver"]   = solver
cfg["relax_uc"] = !exact
cfg["run_tag"]  = "test_$(mode)"
tmp = mktempdir()
config_path = joinpath(tmp, "config.json")
open(config_path, "w") do io
    JSON.print(io, cfg, 2)
end
results_dir = joinpath(REPO_ROOT, "results", "base_maluku_2030_reference__test_$(mode)")

julia = Base.julia_cmd()
project = "--project=$(REPO_ROOT)"
# flush so the banner precedes the child process output when stdout is a file
banner(s) = (println(); println("#" ^ 78); println("# ", s); println("#" ^ 78); flush(stdout))

banner("1/3  Solving Maluku 2030 base/reference  (mode: $(mode), solver: $(solver))")
exact && solver == "highs" &&
    println("Note: the exact MILP (~214k binaries) takes about 15 minutes on HiGHS on a recent laptop. Use --solver gurobi for a ~1 min solve, or --quick for the LP relaxation.")
run(`$(julia) $(project) $(joinpath(REPO_ROOT, "run_model.jl")) --config $(config_path)`)

banner("2/3  Summary of the run")
run(`$(julia) $(project) $(joinpath(REPO_ROOT, "scripts", "summarize_results.jl")) $(results_dir)`)

banner("3/3  Comparison with the reference outputs in $(relpath(expected, REPO_ROOT))")
cmp = `$(julia) $(project) $(joinpath(REPO_ROOT, "scripts", "compare_results.jl")) $(results_dir) $(expected)`
ok = run(ignorestatus(cmp)).exitcode == 0   # run() streams the comparison table; success() would hide it
println()
flush(stdout)
if ok
    println("MALUKU_TEST_PASSED ($(mode), $(solver))")
    exit(0)
else
    println("MALUKU_TEST_FAILED ($(mode), $(solver)) - see the comparison above")
    exit(1)
end
