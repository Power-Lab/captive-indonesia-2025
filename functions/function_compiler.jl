# function_compiler.jl
include("input_data.jl")
include("optimizer.jl")
include("result_extraction_function.jl")
# benders_decomposition.jl provides an optional capacity_expansion_benders
# solver for very large problems; include it and swap the call below to use it

function function_compiler(
        filepath::AbstractString,
        results_dir::AbstractString,
        mipgap::Float64,
        CO2_constraint::Bool,
        CO2_limit,
        RE_constraint::Bool,
        RE_limit,
        Grid::Bool,
        VillageBuild::Bool,
        ImportPrice,
        NoCoal::Bool,
        CO235reduction::Bool,
        BAUCO2emissions;
        village_storage_max_mwh::Float64 = 208.0
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
        VillageBuild,
        ImportPrice,
        NoCoal,
        CO235reduction,
        BAUCO2emissions;
        village_storage_max_mwh = village_storage_max_mwh
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