# solver.jl
#
# Pluggable optimizer. Open-source HiGHS is the default so the model runs with
# no commercial licence; Gurobi is an optional fast path for large instances
# (it is what the published results were produced with). The chosen solver's
# package must already be imported by the entry point: run_model.jl imports
# HiGHS always and Gurobi only when a run requests it, so a pure open-source
# setup never loads Gurobi.

const SUPPORTED_SOLVERS = ("highs", "gurobi")

"""
    make_solver(solver="highs"; mipgap=0.01, time_limit=3*24*60*60, silent=false)

Return a configured, empty `JuMP.Model` for `solver` in `("highs", "gurobi")`,
mapping the relative MIP gap and the wall-clock limit (seconds) to each
solver's own attribute names (`mip_rel_gap`/`time_limit` for HiGHS,
`MIPGap`/`TimeLimit` for Gurobi). Errors on an unknown or unloaded solver.
"""
function make_solver(solver::AbstractString = "highs"; mipgap::Real = 0.01,
                     time_limit::Real = 3 * 24 * 60 * 60, silent::Bool = false)
    s = lowercase(strip(solver))
    if s == "highs"
        isdefined(@__MODULE__, :HiGHS) ||
            error("HiGHS.jl is not loaded. Add `using HiGHS` before including the model code.")
        model = Model(HiGHS.Optimizer)
        set_attribute(model, "mip_rel_gap", float(mipgap))
        set_attribute(model, "time_limit", float(time_limit))
    elseif s == "gurobi"
        isdefined(@__MODULE__, :Gurobi) ||
            error("Gurobi.jl is not loaded. run_model.jl imports it when the config sets " *
                  "\"solver\": \"gurobi\"; a Gurobi licence is required to solve.")
        model = Model(Gurobi.Optimizer)
        set_attribute(model, "MIPGap", mipgap)
        set_attribute(model, "TimeLimit", time_limit)
        set_attribute(model, "Crossover", 0)
    else
        error("Unknown solver \"$(solver)\"; expected one of $(join(SUPPORTED_SOLVERS, ", ")).")
    end
    silent && set_silent(model)
    return model
end

"""
    validate_solver(solver)

Solve a one-variable model with `solver` so that a missing package or an
invalid licence is reported before a long model build, not after it.
"""
function validate_solver(solver::AbstractString)
    try
        model = make_solver(solver; silent = true)
        @variable(model, 0 <= x <= 1)
        @objective(model, Max, x)
        optimize!(model)
        termination_status(model) == MOI.OPTIMAL ||
            error("test model finished with status $(termination_status(model))")
        # release the test model's solver environment now rather than at the next GC
        # (a Gurobi environment holds a licence token)
        MOI.empty!(backend(model))
        model = nothing
        GC.gc()
    catch err
        error("Solver \"$(solver)\" could not start a working optimizer session: " *
              sprint(showerror, err))
    end
    return nothing
end

# The unit-commitment binaries (grid and industrial-park units); fed to
# relax_binaries! when a run asks for the LP relaxation.
const UC_BINARIES = (:vCOMMIT, :vSTART, :vSHUT, :vIP_COMMIT, :vIP_START, :vIP_SHUT)

"""
    relax_binaries!(model, names)

LP-relax the named binary variable containers on `model`: each binary variable
is freed to the continuous range `[0, 1]`. Turns the unit-commitment MILP into
an LP. The relaxed solution is a lower bound on cost and is not the model used
for the published results; on HiGHS the LP is not necessarily faster than the
MILP for these instances.
Names absent from the model are skipped.
"""
function relax_binaries!(model, names)
    od = object_dictionary(model)
    n = 0
    for nm in names
        haskey(od, nm) || continue
        for v in model[nm]
            if is_binary(v)
                unset_binary(v)
                set_lower_bound(v, 0.0)
                set_upper_bound(v, 1.0)
                n += 1
            end
        end
    end
    return n
end
