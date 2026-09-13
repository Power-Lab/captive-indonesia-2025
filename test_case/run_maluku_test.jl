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
# results/base_maluku_2030_reference__test_<mode>_<solver>/.
using Pkg
const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))
Pkg.activate(REPO_ROOT; io = devnull)
using JSON

const USAGE = "usage: julia --project=. test_case/run_maluku_test.jl [--quick] [--solver highs|gurobi]"
if any(a -> a in ("-h", "--help"), ARGS)
    println(USAGE)
    exit(0)
end
quick  = "--quick" in ARGS
exact  = !quick
solver = let i = findfirst(==("--solver"), ARGS)
    if i === nothing
        "highs"
    else
        i < length(ARGS) || error("missing value after --solver\n" * USAGE)
        lowercase(ARGS[i + 1])
    end
end
solver in ("highs", "gurobi") || error("--solver must be highs or gurobi, got \"$(solver)\"\n" * USAGE)
for (k, a) in enumerate(ARGS)
    a in ("--quick", "--solver") && continue
    k > 1 && ARGS[k - 1] == "--solver" && continue
    error("unknown argument $(a)\n" * USAGE)
end
quick && solver != "highs" && println("Note: --quick is meant for HiGHS; running the LP relaxation on $(solver) anyway.")

mode      = exact ? "exact" : "quick"
case_dir  = joinpath(REPO_ROOT, "test_case", "maluku")
expected  = joinpath(case_dir, exact ? "expected_results" : "expected_results_relaxed")
isdir(expected) || error("reference folder not found: $(expected)")

cfg = JSON.parsefile(joinpath(case_dir, "config.json"))
cfg["solver"]   = solver
cfg["relax_uc"] = !exact
cfg["run_tag"]  = "test_$(mode)_$(solver)"
# the effective config is kept next to the results so run_info.json can point at it
results_dir = joinpath(REPO_ROOT, "results", "base_maluku_2030_reference__test_$(mode)_$(solver)")
mkpath(results_dir)
config_path = joinpath(results_dir, "config.json")
open(config_path, "w") do io
    JSON.print(io, cfg, 2)
end

julia = Base.julia_cmd()
project = "--project=$(REPO_ROOT)"
# flush so the banner precedes the child process output when stdout is a file
banner(s) = (println(); println("#" ^ 78); println("# ", s); println("#" ^ 78); flush(stdout))

banner("1/3  Solving Maluku 2030 base/reference  (mode: $(mode), solver: $(solver))")
exact && solver == "highs" &&
    println("Note: the exact MILP (~214k binaries) takes about 15 minutes on HiGHS on a recent laptop. Use --solver gurobi for a ~1 min solve, or --quick for the LP relaxation.")
# run() streams the child's output (success() would hide it); ignorestatus keeps a
# failing step from ending this script with a stack trace instead of a verdict.
step_ok(cmd) = run(ignorestatus(cmd)).exitcode == 0
function fail(step)
    println()
    println("MALUKU_TEST_FAILED ($(mode), $(solver)) - step \"$(step)\" did not complete; see the output above")
    exit(1)
end

step_ok(`$(julia) $(project) $(joinpath(REPO_ROOT, "run_model.jl")) --config $(config_path)`) || fail("solve")

banner("2/3  Summary of the run")
step_ok(`$(julia) $(project) $(joinpath(REPO_ROOT, "scripts", "summarize_results.jl")) $(results_dir)`) || fail("summary")

banner("3/3  Comparison with the reference outputs in $(relpath(expected, REPO_ROOT))")
ok = step_ok(`$(julia) $(project) $(joinpath(REPO_ROOT, "scripts", "compare_results.jl")) $(results_dir) $(expected)`)
println()
flush(stdout)
if ok
    println("MALUKU_TEST_PASSED ($(mode), $(solver))")
    exit(0)
else
    println("MALUKU_TEST_FAILED ($(mode), $(solver)) - a headline metric is outside tolerance; see the comparison above")
    exit(1)
end
