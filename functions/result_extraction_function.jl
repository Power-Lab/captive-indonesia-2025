# result_extraction_function.jl

using CSV
using DataFrames
import Base.Filesystem: mkpath

function result_extraction(
        solution,
        demand::DataFrame,
        inputs,
        input_path::AbstractString,
        results_dir::AbstractString
    )
    # 0) ensure output folder exists
    mkpath(results_dir)

    # 1) Compute generation totals
    NG = size(inputs.G, 1)
    generation = zeros(NG)
    for i in 1:NG
        generation[i] = sum(value.(solution.GEN)[:, inputs.G[i]].data)
    end

    NIPG = size(inputs.IP_G, 1)
    ip_generation = zeros(NIPG)
    for i in 1:NIPG
        ip_generation[i] = sum(value.(solution.IP_GEN)[:, inputs.IP_G[i]].data)
    end

    NIPUC = size(inputs.IP_UC, 1)
    ip_heat_generation = zeros(NIPUC)
    for i in 1:NIPUC
        ip_heat_generation[i] = sum(value.(solution.IP_GEN_HEAT)[:, inputs.IP_UC[i]].data)
    end

    total_demand = sum(sum.(eachcol(demand)))
    peak_demand  = maximum(sum(eachcol(demand)))
    MWh_share    = generation ./ total_demand .* 100
    cap_share    = value.(solution.CAP).data ./ peak_demand .* 100

    # 2) Build DataFrames…
    generator = DataFrame(
        ID             = inputs.G,
        Resource       = inputs.generators.Resource[inputs.G],
        Zone           = inputs.generators.Zone[inputs.G],
        technology     = inputs.generators.technology[inputs.G],
        owner          = inputs.generators.owner[inputs.G],
        Total_MW       = value.(solution.CAP).data,
        Start_MW       = inputs.generators.Existing_Cap_MW[inputs.G],
        Change_in_MW   = value.(solution.CAP).data .- inputs.generators.Existing_Cap_MW[inputs.G],
        Percent_MW     = cap_share,
        GWh            = generation ./ 1000,
        Percent_GWh    = MWh_share,
        STOR           = inputs.generators.STOR[inputs.G],
        VRE            = inputs.generators.VRE[inputs.G],
        THERM          = inputs.generators.THERM[inputs.G],
        New_Build      = inputs.generators.New_Build[inputs.G],
    )

    ip_generators = DataFrame(
        ID                   = inputs.IP_G,
        Resource             = inputs.ip_generators.Resource[inputs.IP_G],
        Zone                 = inputs.ip_generators.Zone[inputs.IP_G],
        Industrial_Park      = inputs.ip_generators.Industrial_Park[inputs.IP_G],
        technology           = inputs.ip_generators.technology[inputs.IP_G],
        Total_MW             = value.(solution.IP_CAP).data,
        Start_MW             = inputs.ip_generators.Existing_Cap_MW[inputs.IP_G],
        Change_in_MW         = value.(solution.IP_CAP).data .- inputs.ip_generators.Existing_Cap_MW[inputs.IP_G],
        Electricity_GWh      = ip_generation ./ 1000,
        commodity            = inputs.ip_generators.commodity[inputs.IP_G],
        plant_owner          = inputs.ip_generators.plant_owner[inputs.IP_G],
        owner_parent_company = inputs.ip_generators.owner_parent_company[inputs.IP_G],
        owner_home_country_flag = inputs.ip_generators.owner_home_country_flag[inputs.IP_G],
    )

    ip_heat_generators = DataFrame(
        ID                  = inputs.IP_UC,
        Resource            = inputs.ip_generators.Resource[inputs.IP_UC],
        Zone                = inputs.ip_generators.Zone[inputs.IP_UC],
        Industrial_Park     = inputs.ip_generators.Industrial_Park[inputs.IP_UC],
        technology          = inputs.ip_generators.technology[inputs.IP_UC],
        commodity           = inputs.ip_generators.commodity[inputs.IP_UC],
        GWh                 = ip_heat_generation ./ 1000
    )

    if all(value.(solution.IP_IMPORT) .== 0)
        ip_import = DataFrame(
            ID               = inputs.IP,
            Zone             = inputs.ip_generators.Zone[inputs.IP],
            Total_Import_MWh = zeros(length(inputs.IP)),
            Peak_Import_MW   = zeros(length(inputs.IP)),
        )
    else
        ip_import = DataFrame(
            ID               = inputs.IP,
            Zone             = inputs.ip_generators.Zone[inputs.IP],
            Total_Import_MWh = vec(sum(value.(solution.IP_IMPORT)[:, inputs.IP].data, dims=1)),
            Peak_Import_MW   = vec(maximum(value.(solution.IP_IMPORT)[:, inputs.IP].data, dims=1)),
        )
    end

    storage = DataFrame(
        ID                    = inputs.STOR,
        Zone                  = inputs.generators.Zone[inputs.STOR],
        Resource              = inputs.generators.Resource[inputs.STOR],
        Total_Storage_MWh     = value.(solution.E_CAP).data,
        Start_Storage_MWh     = inputs.generators.Existing_Cap_MW[inputs.STOR],
        Change_in_Storage_MWh = value.(solution.E_CAP).data .- inputs.generators.Existing_Cap_MW[inputs.STOR],
    )

    ip_storage = DataFrame()
    try
        if solution.IP_E_CAP isa AbstractArray
            total_storage = value.(solution.IP_E_CAP)
            start_storage = inputs.ip_generators.Existing_Cap_MW[inputs.IP_STOR]
            change_storage = total_storage .- start_storage

            ip_storage = DataFrame(
                ID                    = inputs.IP_STOR,
                Zone                  = inputs.ip_generators.Zone[inputs.IP_STOR],
                Industrial_Park       = inputs.ip_generators.Industrial_Park[inputs.IP_STOR],
                Resource              = inputs.ip_generators.Resource[inputs.IP_STOR],
                Total_Storage_MWh     = total_storage,
                Start_Storage_MWh     = start_storage,
                Change_in_Storage_MWh = change_storage,
            )
        else
            @warn "solution.IP_E_CAP is not a JuMP container. Using zero-filled values."
            N = length(inputs.IP_STOR)
            ip_storage = DataFrame(
                ID                    = inputs.IP_STOR,
                Zone                  = inputs.ip_generators.Zone[inputs.IP_STOR],
                Resource              = inputs.ip_generators.Resource[inputs.IP_STOR],
                Total_Storage_MWh     = zeros(N),
                Start_Storage_MWh     = inputs.ip_generators.Existing_Cap_MW[inputs.IP_STOR],
                Change_in_Storage_MWh = -inputs.ip_generators.Existing_Cap_MW[inputs.IP_STOR],
            )
        end
    catch e
        @error "Error generating ip_storage DataFrame: $e"
        ip_storage = DataFrame()  # Return an empty DataFrame to fail gracefully
    end


    transmission = DataFrame(
        ID                       = inputs.L,
        Path                     = inputs.lines.path_name[inputs.L],
        Substation_Path          = inputs.lines.substation_path[inputs.L],
        Total_Transfer_Capacity  = value.(solution.T_CAP).data,
        Start_Transfer_Capacity  = inputs.lines.Line_Max_Flow_MW,
        Change_in_Transfer_Capacity = value.(solution.T_CAP).data .- inputs.lines.Line_Max_Flow_MW,
    )

    num_s = maximum(inputs.S)
    num_z = maximum(inputs.Z)
    nse_r = DataFrame(
        Segment               = Int[],
        Zone                  = Int[],
        NSE_Price             = Float64[],
        Max_NSE_MW            = Float64[],
        Total_NSE_MWh         = Float64[],
        NSE_Percent_of_Demand = Float64[]
    )
    for s in inputs.S, z in inputs.Z
        push!(nse_r, (
            s,
            z,
            inputs.nse.NSE_Cost[s],
            maximum(value.(solution.NSE)[:, s, z].data),
            sum(value.(solution.NSE)[:, s, z].data),
            sum(value.(solution.NSE)[:, s, z].data) / total_demand * 100
        ))
    end

    nse_r_ip = DataFrame(
        Segment               = Int[],
        Zone                  = Int[],
        NSE_Price             = Float64[],
        Max_NSE_MW            = Float64[],
        Total_NSE_MWh         = Float64[],
        NSE_Percent_of_Demand = Float64[]
    )
    for s in inputs.S, ip in inputs.IP
        push!(nse_r_ip, (
            s,
            ip,
            inputs.nse.NSE_Cost[s],
            maximum(value.(solution.IP_NSE)[:, s, ip].data),
            sum(value.(solution.IP_NSE)[:, s, ip].data),
            sum(value.(solution.IP_NSE)[:, s, ip].data) / total_demand * 100
        ))
    end

    nse_heat_ip = DataFrame(
        Segment               = Int[],
        Zone                  = Int[],
        NSE_Price             = Float64[],
        Max_NSE_MW            = Float64[],
        Total_NSE_MWh         = Float64[],
        NSE_Percent_of_Demand = Float64[]
    )
    for s in inputs.S, ip in inputs.IP
        push!(nse_heat_ip, (
            s,
            ip,
            inputs.nse.NSE_Cost[s],
            maximum(value.(solution.IP_NSE_HEAT)[:, s, ip].data),
            sum(value.(solution.IP_NSE_HEAT)[:, s, ip].data),
            sum(value.(solution.IP_NSE_HEAT)[:, s, ip].data) / total_demand * 100
        ))
    end

    cost = DataFrame(
        Total_Costs              = solution.cost / 1e6,
        Fixed_Costs_Generation   = value.(solution.FixedCostsGeneration) / 1e6,
        Fixed_Costs_Transmission = value.(solution.FixedCostsTransmission) / 1e6,
        Fixed_Costs_Storage      = value.(solution.FixedCostsStorage) / 1e6,
        Fixed_Costs_IP           = value.(solution.FixedCostsIPGeneration) / 1e6,
        Fixed_Costs_IP_Storage   = value.(solution.FixedCostsIPStorage) / 1e6,
        Variable_Costs_Grid      = value.(solution.VariableCostsGrid) / 1e6,
        Variable_Costs_IP        = value.(solution.VariableCostsIP) / 1e6,
        NSE_Costs                = value.(solution.NSECosts) / 1e6,
        IPNSECosts               = value.(solution.IPNSECosts) / 1e6,
        IPNSEHeatCosts           = value.(solution.IPNSEHeatCosts) / 1e6,
        Grid_Import_Costs        = value.(solution.GridImportCosts) / 1e6,
        StartCostsGrid           = value.(solution.StartCostsGrid) / 1e6,
        StartCostsIP             = value.(solution.StartCostsIP) / 1e6

    )

    clean_energy = DataFrame(
        CO2_Emissions      = value.(solution.CO2Emissions),
        CO2_Emissions_Grid = value.(solution.CO2EmissionsGrid),
        CO2_Emissions_IP   = value.(solution.CO2EmissionsIP),
        Grid_REShare       = value.(solution.REShare)
    )

    # 11) Write CSVs into the scenario folder
    CSV.write(joinpath(results_dir, "generator_results.csv"),      generator)
    CSV.write(joinpath(results_dir, "ip_generator_results.csv"),   ip_generators)
    CSV.write(joinpath(results_dir, "ip_heat_generator_results.csv"), ip_heat_generators)
    CSV.write(joinpath(results_dir, "ip_import_results.csv"),      ip_import)
    CSV.write(joinpath(results_dir, "storage_results.csv"),        storage)
    CSV.write(joinpath(results_dir, "ip_storage_results.csv"),     ip_storage)
    CSV.write(joinpath(results_dir, "transmission_results.csv"),   transmission)
    CSV.write(joinpath(results_dir, "nse_results.csv"),            nse_r)
    CSV.write(joinpath(results_dir, "ip_nse_results.csv"),         nse_r_ip)
    CSV.write(joinpath(results_dir, "ip_nse_heat_results.csv"),    nse_heat_ip)
    CSV.write(joinpath(results_dir, "cost_results.csv"),           cost)
    CSV.write(joinpath(results_dir, "clean_energy_results.csv"),   clean_energy)

    return (
        generator_results        = generator,
        ip_generator_results     = ip_generators,
        ip_heat_generator_results = ip_heat_generators,
        ip_import_results        = ip_import,
        storage_results          = storage,
        ip_storage_results       = ip_storage,
        transmission_results     = transmission,
        nse_results              = nse_r,
        ip_nse_results           = nse_r_ip,
        ip_nse_heat_results      = nse_heat_ip,
        cost_results             = cost,
        clean_energy             = clean_energy
    )
end
