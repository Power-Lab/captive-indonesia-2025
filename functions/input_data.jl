function input_data(filepath)

    #GRID
    #Generators
    #reading generator data
    generators = DataFrame(CSV.File(joinpath(filepath, "generators.csv")));
    
    #ID for all generators for easy reference
    G = generators.R_ID;

    #set of zones
    Z = convert(Array{Int64}, unique(collect(skipmissing(generators.Zone))));

    #Demand
    #reading reference demand input data
    demand_inputs_ref = DataFrame(CSV.File(joinpath(filepath, "demand.csv")))
    
    #value of losr load (cost of involuntary non-served energy)
    VOLL = demand_inputs_ref.Voll[1]
    
    #set of price responsive demand (non-served energy) segments
    S = convert(Array{Int64}, collect(skipmissing(demand_inputs_ref.Demand_Segment)))
    
    #creating a data frame for nse segments
    nse = DataFrame(Segment = S, 
                    NSE_Cost = VOLL.*collect(skipmissing(demand_inputs_ref.Cost_of_Demand_Curtailment_per_MW)),
                    NSE_Max = collect(skipmissing(demand_inputs_ref.Max_Demand_Curtailment)))
    
    #set of time sample sub-periods
    P = convert(Array{Int64}, 1:demand_inputs_ref.Rep_Periods[1])
    #sub-period cluster weights = number of hours represented by each sample period
    W = convert(Array{Int64}, collect(skipmissing(demand_inputs_ref.Sub_Weights)))
    #set of sequential hours per sub-period
    hours_per_period = convert(Int64, demand_inputs_ref.Timesteps_per_Rep_Period[1])

    #set of all time steps
    T = convert(Array{Int64}, demand_inputs_ref.r_id);
    
    #set of all time steps excluding the last time step
    T_red = T[1:end-1]

    #creating a vector of sample weights
    sample_weight = zeros(Float64, size(T,1))
    t=1
    for p in P
        for h in 1:hours_per_period
            sample_weight[t]=W[p]/hours_per_period
            t += 1
        end
    end
    
    #grid demand
    demand_input = DataFrame(CSV.File(joinpath(filepath, "demand.csv")))
    demand_cols = [Symbol("demand_z$i") for i in Z]
    demand = select(demand_input, demand_cols...);
    

    #Variability
    #read generator capacity factors by hour
    variability = DataFrame(CSV.File(joinpath(filepath, "generators_variability.csv")))

    #Fuel - same data will be used for industrial park generators
    #read fuels data
    fuels = DataFrame(CSV.File(joinpath(filepath, "fuels_data.csv")));

    #Lines
    #reading network data
    if isfile(joinpath(filepath, "network.csv"))
        lines = DataFrame(CSV.File(joinpath(filepath, "network.csv")));
        #fixed O&M costs for lines
        lines.Line_Fixed_Cost_per_MW_yr = lines.Line_Reinforcement_Cost_per_MWyr
        #set of all lines
        L = convert(Array{Int64}, lines.r_id);
    else
        lines = DataFrame(
            r_id                       = Int[],
            path_name                  = String[],
            substation_path            = String[],
            Line_Reinforcement_Cost_per_MWyr = Float64[],
            Line_Max_Flow_MW           = Float64[],
            B                          = Float64[],
            distance_km                = Float64[],
        )
            L = Int[]  # empty line set
    end

    #calculating the associated variable costs for generators
    generators.Var_Cost = zeros(Float64, size(G,1))
    generators.CO2_Rate = zeros(Float64, size(G,1))
    generators.Start_Cost = zeros(Float64, size(G,1))
    generators.CO2_Per_Start = zeros(Float64, size(G,1))
    
    for g in G
        # Variable cost ($/MWh) = variable O&M ($/MWh) + fuel cost ($/MMBtu) * heat rate (MMBtu/MWh)
        generators.Var_Cost[g] = generators.Var_OM_Cost_per_MWh[g] +
            fuels[fuels.Fuel.==generators.Fuel[g],:Cost_per_MMBtu][1]*generators.Heat_Rate_MMBTU_per_MWh[g]
        # CO2 emissions rate (tCO2/MWh) = fuel CO2 content (tCO2/MMBtu) * heat rate (MMBtu/MWh)
        generators.CO2_Rate[g] = fuels[fuels.Fuel.==generators.Fuel[g],:CO2_content_tons_per_MMBtu][1]*generators.Heat_Rate_MMBTU_per_MWh[g]
        # Start-up cost ($/start/MW) = start up O&M cost ($/start/MW) + fuel cost ($/MMBtu) * start up fuel use (MMBtu/start/MW) 
        generators.Start_Cost[g] = generators.Start_Cost_per_MW[g] +
            fuels[fuels.Fuel.==generators.Fuel[g],:Cost_per_MMBtu][1]*generators.Start_Fuel_MMBTU_per_MW[g]
        # Start-up CO2 emissions (tCO2/start/MW) = fuel CO2 content (tCO2/MMBtu) * start up fuel use (MMBtu/start/MW) 
        generators.CO2_Per_Start[g] = fuels[fuels.Fuel.==generators.Fuel[g],:CO2_content_tons_per_MMBtu][1]*generators.Start_Fuel_MMBTU_per_MW[g]
    end
    
    #INDUSTRIAL PARKS
    #Industrial Park Generators
    #reading industrial park generator data
    if isfile(joinpath(filepath, "ip_generators.csv"))
        ip_generators = DataFrame(CSV.File(joinpath(filepath, "ip_generators.csv")));

    else
        ip_generators = DataFrame(
            R_ID                        = Int[],
            Resource                    = String[],
            Zone                        = String[],
            Industrial_Park             = Int[],
            technology                  = String[],
            Existing_Cap_MW            = Float64[],
            commodity                   = String[],
            plant_owner                 = String[],
            owner_parent_company        = String[],
            owner_home_country_flag     = String[],
            Fuel                        = String[],
            Heat_Rate_MMBTU_per_MWh     = Float64[],
            Var_OM_Cost_per_MWh         = Float64[],
            Start_Cost_per_MW           = Float64[],
            Start_Fuel_MMBTU_per_MW     = Float64[],
            Commit                      = Int[],
            New_Build                   = Int[],
            STOR                        = Int[]
        )
    end

    #ID for all industrial parks for easy reference
    IP = convert(Array{Int64}, unique(collect(skipmissing(ip_generators.Industrial_Park))));

    #industrial park generators set
    IP_G = ip_generators.R_ID;

    #Industrial Park Demand
    if isfile(joinpath(filepath, "ip_demand.csv"))
        ip_demand_input = DataFrame(CSV.File(joinpath(filepath, "ip_demand.csv")));
        #generate column symbols based on IP indices
        ip_demand_cols = [Symbol("demand_ip$i") for i in IP]
        ip_demand = select(ip_demand_input, ip_demand_cols...);

        #set of price responsive demand (non-served energy) segments
        IP_S = convert(Array{Int64}, collect(skipmissing(ip_demand_input.Demand_Segment)))

        IP_VOLL = ip_demand_input.Voll[1]
    
        #creating a data frame for nse segments
        nse_ip = DataFrame(Segment = IP_S, 
                    NSE_Cost = IP_VOLL.*collect(skipmissing(ip_demand_input.Cost_of_Demand_Curtailment_per_MW)),
                    NSE_Max = collect(skipmissing(ip_demand_input.Max_Demand_Curtailment)))
    else
        ip_demand = DataFrame(
            r_id = Int[]
        )

        nse_ip = DataFrame(
            Segment = Int[],
            NSE_Cost = Float64[],
            NSE_Max = Float64[]
        )

        IP_S = Int[]
        IP_VOLL = 0.0
    end

    if isfile(joinpath(filepath, "ip_demandheat.csv"))
        ip_heat_demand_input = DataFrame(CSV.File(joinpath(filepath, "ip_demandheat.csv")));
        # Generate column symbols based on IP indices
        ip_heat_demand_cols = [Symbol("demand_ip$i") for i in IP]
        ip_demandheat = select(ip_heat_demand_input, ip_heat_demand_cols...);
    else
        ip_demandheat = DataFrame(
            r_id = Int[]
        )
    end

    #IP Variability
    if isfile(joinpath(filepath, "ip_generators_variability.csv"))
        #read industrial park generator capacity factors by hour
        ip_variability = DataFrame(CSV.File(joinpath(filepath, "ip_generators_variability.csv")));
    else
        ip_variability = DataFrame(
            r_id = Int[]
        )
    end

    #calculating the associated variable costs for industrial park generators
    ip_generators.Var_Cost = zeros(Float64, size(IP_G,1))
    ip_generators.CO2_Rate = zeros(Float64, size(IP_G,1))
    ip_generators.Start_Cost = zeros(Float64, size(IP_G,1))
    ip_generators.CO2_Per_Start = zeros(Float64, size(IP_G,1))

    for g in IP_G
        # Variable cost ($/MWh) = variable O&M ($/MWh) + fuel cost ($/MMBtu) * heat rate (MMBtu/MWh)
        ip_generators.Var_Cost[g] = ip_generators.Var_OM_Cost_per_MWh[g] +
            fuels[fuels.Fuel.==ip_generators.Fuel[g],:Cost_per_MMBtu][1]*ip_generators.Heat_Rate_MMBTU_per_MWh[g]
        # CO2 emissions rate (tCO2/MWh) = fuel CO2 content (tCO2/MMBtu) * heat rate (MMBtu/MWh)
        ip_generators.CO2_Rate[g] = fuels[fuels.Fuel.==ip_generators.Fuel[g],:CO2_content_tons_per_MMBtu][1]*ip_generators.Heat_Rate_MMBTU_per_MWh[g]
        # Start-up cost ($/start/MW) = start up O&M cost ($/start/MW) + fuel cost ($/MMBtu) * start up fuel use (MMBtu/start/MW) 
        ip_generators.Start_Cost[g] = ip_generators.Start_Cost_per_MW[g] +
            fuels[fuels.Fuel.==ip_generators.Fuel[g],:Cost_per_MMBtu][1]*ip_generators.Start_Fuel_MMBTU_per_MW[g]
        # Start-up CO2 emissions (tCO2/start/MW) = fuel CO2 content (tCO2/MMBtu) * start up fuel use (MMBtu/start/MW) 
        ip_generators.CO2_Per_Start[g] = fuels[fuels.Fuel.==ip_generators.Fuel[g],:CO2_content_tons_per_MMBtu][1]*ip_generators.Start_Fuel_MMBTU_per_MW[g]
    end
    
    #SUBSET DEFINITIONS

    #subset of thermal generators that are subject to unit commitment constraints
    UC = intersect(generators.R_ID[generators.Commit.==1], G)
    
    #subset of generators that are not subject to unit commitment constraints
    ED = intersect(generators.R_ID[generators.Commit.==0], G)
    
    #subset of storage resources
    STOR = intersect(generators.R_ID[generators.STOR.>=1], G)
    
    #subset of variable renewable resources
    VRE = intersect(generators.R_ID[generators.VRE.==1], G)
    
    #subset of new build generators
    NEW = intersect(generators.R_ID[generators.New_Build.==1], G)
    
    #subset of existing generators
    OLD = intersect(generators.R_ID[.!(generators.New_Build.==1)], G)
    
    #subset of RPS qualifying resources
    #RPS = intersect(generators.R_ID[generators.RPS.==1], G);

    #subset of time steps that begin a sub period
    START = 1:hours_per_period:maximum(T)

    #subset of time periods that do not begin a sub period
    INTERIOR = setdiff(T, START)
    
    # Subset of all unit commitment generators
    UC_OLD = intersect(UC, OLD)
    
    # Subset of all new unit commitment generators
    UC_NEW = intersect(UC, NEW)
    
    # Subset of all oth2er old generators
    ED_OLD = intersect(ED, OLD)
    
    # Subset of all other new generators
    ED_NEW = intersect(ED, NEW);
    
    # Subset of all unit commitment generators
    UC_OLD = intersect(UC, OLD)
    
    # Subset of all new unit commitment generators
    UC_NEW = intersect(UC, NEW)
    
    # Subset of all other old generators
    ED_OLD = intersect(ED, OLD)
    
    # Subset of all other new generators
    ED_NEW = intersect(ED, NEW);

    # subset of IP generators that are subject to unit commitment constraints
    IP_UC = intersect(ip_generators.R_ID[ip_generators.Commit.==1], IP_G)

    # subset of IP generators that are not subject to unit commitment constraints
    IP_ED = intersect(ip_generators.R_ID[ip_generators.Commit.==0], IP_G)

    # subset of IP generators that are RE + storage
    IP_RE = intersect(ip_generators.R_ID[.!(ip_generators.Commit.==1)], IP_G)

    # subset of new IP generators
    IP_NEW = intersect(ip_generators.R_ID[ip_generators.New_Build.==1], IP_G)

    # subset of existing IP generators
    IP_OLD = intersect(ip_generators.R_ID[.!(ip_generators.New_Build.==1)], IP_G)

    #subset of all old IP UC generators
    IP_UC_OLD = intersect(IP_UC, IP_OLD)

    #subset of all new IP UC generators
    IP_UC_NEW = intersect(IP_UC, IP_NEW)

    #subset of all old IP ED generators
    IP_ED_OLD = intersect(IP_ED, IP_OLD)

    #subset of all new IP ED generators
    IP_ED_NEW = intersect(IP_ED, IP_NEW)

    #subset of all IP storage resources
    IP_STOR = intersect(ip_generators.R_ID[ip_generators.STOR.==1], IP_G)


    return (
        generators = generators,
        demand = demand,
        variability = variability,
        lines = lines,
        nse = nse,
        hours_per_period = hours_per_period,
        sample_weight = sample_weight,
        ip_generators = ip_generators,
        ip_nse = nse_ip,
        ip_demand = ip_demand,
        ip_demandheat = ip_demandheat,
        ip_variability = ip_variability,
        G = G,
        S = S,
        P = P,
        W = W,
        T = T,
        T_red = T_red,
        Z = Z,
        L = L,
        UC = UC,
        ED = ED,
        STOR = STOR,
        VRE = VRE,
        NEW = NEW,
        OLD = OLD,
        START = START,
        INTERIOR = INTERIOR,
        UC_OLD = UC_OLD,
        UC_NEW = UC_NEW,
        ED_OLD = ED_OLD,
        ED_NEW = ED_NEW,
        IP_UC = IP_UC,
        IP_ED = IP_ED,
        IP_NEW = IP_NEW,
        IP_OLD = IP_OLD,
        IP_RE = IP_RE,
        IP = IP,
        IP_G = IP_G,
        IP_S = IP_S,
        IP_UC_OLD = IP_UC_OLD,
        IP_UC_NEW = IP_UC_NEW,
        IP_ED_OLD = IP_ED_OLD,
        IP_ED_NEW = IP_ED_NEW,
        IP_STOR = IP_STOR
        )
    
end