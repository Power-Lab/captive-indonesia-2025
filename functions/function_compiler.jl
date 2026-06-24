# function_compiler.jl
include("input_data.jl")
include("optimizer.jl")
include("result_extraction_function.jl")
include("benders_decomposition.jl")

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
        BAUCO2emissions
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
        BAUCO2emissions
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