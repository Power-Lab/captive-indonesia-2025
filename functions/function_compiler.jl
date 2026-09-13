# function_compiler.jl
#
# Loads the inputs, solves the capacity-expansion model and writes the result
# CSVs. The entry point (run_model.jl) must have imported JuMP, CSV,
# DataFrames and the solver package (HiGHS always; Gurobi when requested)
# before including this file.
include("input_data.jl")
include("solver.jl")
include("optimizer.jl")
include("result_extraction_function.jl")
include("benders_decomposition.jl")   # optional, experimental; not used by default

function function_compiler(
        filepath::AbstractString,
        results_dir::AbstractString,
        mipgap::Float64,
        CO2_constraint::Bool,
        CO2_limit,
        RE_constraint::Bool,
        RE_limit,
        Grid::Bool,
        Captive::Bool,
        ImportPrice,
        NoCoal::Bool,
        CO235reduction::Bool,
        BAUCO2emissions;
        solver::AbstractString = "highs",
        relax_uc::Bool = false,
        time_limit::Real = 3 * 24 * 60 * 60
    )
    # 1) Load inputs
    inputs = input_data(filepath)

    # 2) Run the optimization
    solution = capacity_expansion(
        inputs,
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

    # 3) Extract & write results into the folder
    result_extraction(
        solution,
        inputs.demand,
        inputs,
        filepath,
        results_dir
    )

    return solution
end
