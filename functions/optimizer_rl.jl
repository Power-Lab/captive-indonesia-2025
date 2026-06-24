function capacity_expansion(inputs, mipgap, CO2_constraint, CO2_limit, RE_constraint, RE_limit, Grid, Captive, ImportPrice, NoCoal, CO235reduction, BAUCO2emissions)

    CE = Model(Gurobi.Optimizer)
    set_attribute(CE, "MIPGap", mipgap)
    #set_attribute(CE, "LogFile", "gurobi_output.log")
    set_attribute(CE, "Crossover", 0)
    #set_attribute(CE, "UnboundedRay", 1)
    #set_attribute(CE, "Nodes", 10)
    set_attribute(CE, "TimeLimit", 3*24*60*60)
    #set_attribute(CE, "Heuristics", 0)
    #set_attribute(CE, "Cuts", 3)

    #DECISION VARIABLES

    #Capacity decision variables
    @variables(CE, begin

        #standard capacity variables
        vCAP[g in inputs.G]                  >= 0 # power capacity (MW)
        vRET_CAP_ED[g in inputs.ED_OLD]      >= 0     # retirement of power capacity (MW)
        vNEW_CAP_ED[g in inputs.ED_NEW]      >= 0     # new build power capacity for (MW)

        vRET_CAP_UC[g in inputs.UC_OLD]            # retirement of power capacity for UC units (MW)
        vNEW_CAP_UC[g in inputs.UC_NEW]             # new build power capacity for UC units (MW)
            
        #storage variables
        vE_CAP[g in inputs.STOR]          >= 0 # storage energy capacity (MWh)
        vRET_E_CAP[g in intersect(inputs.STOR, inputs.OLD)]   >= 0 # retirement storage capacity
        vNEW_E_CAP[g in intersect(inputs.STOR, inputs.NEW)]   >= 0 # new build storage capacity

        #transmission variables
        vT_CAP[l in inputs.L]               >= 0 # transmission capacity (MW)
        vRET_T_CAP[l in inputs.L]           >= 0 # retirement transmission capacity (MW)
        vNEW_T_CAP[l in inputs.L]           >= 0 # new build transmission capacity (MW)
                
        vSTART[inputs.T, inputs.UC], Bin # start up units
        vSHUT[inputs.T, inputs.UC], Bin  # shut down units
        vCOMMIT[inputs.T, inputs.UC], Bin # commitment variable for UC units
    end)

    #unbounded till max_cap data is received
    for g in inputs.UC_NEW[inputs.generators[inputs.UC_NEW, :Max_Cap_MW].>0]
        set_upper_bound(vNEW_CAP_UC[g], inputs.generators.Max_Cap_MW[g])
    end

    for g in inputs.ED_NEW[inputs.generators[inputs.ED_NEW, :Max_Cap_MW].>0]
        set_upper_bound(vNEW_CAP_ED[g], inputs.generators.Max_Cap_MW[g])
    end

    #set upper bounds on transmission capacity expansion
    for l in inputs.L
        set_upper_bound(vNEW_T_CAP[l], inputs.lines.Line_Max_Reinforcement_MW[l])
    end

    #operational decision variables
    @variables(CE, begin
            vGEN[inputs.T, inputs.G]            >= 0 # power generation (MW)
            vCHARGE[inputs.T, inputs.STOR]     >= 0 # power charging (MW)
            vSOC[inputs.T, inputs.STOR]        >= 0 # energy storage state of charge (MW)
            vNSE[inputs.T, inputs.S, inputs.Z]  >= 0 # non-served energy/demand curtailment (MW)
            vFLOW[inputs.T, inputs.L]           >= 0 # transmission line flow (MW)
            # vTHETA[inputs.T, inputs.Z]          >= 0 # theta angle for transmission lines (radians)
    end)

    #industrial park decision variables
    @variables(CE, begin
   
            vIP_CAP[inputs.IP_G]                                >= 0 #capacity of onsite power options
            vIP_E_CAP[inputs.IP_STOR]                          >= 0 #energy storage capacity (MWh)
            vIP_RET_E_CAP[inputs.IP_STOR]                      >= 0 #retirement of onsite storage units
            vIP_NEW_E_CAP[inputs.IP_STOR]                      >= 0 #new build onsite storage units

            vIP_RET_CAP_ED[inputs.IP_ED]                        >= 0 #retirement of onsite ED units
            vIP_NEW_CAP_ED[inputs.IP_ED]                        >= 0 #new build onsite ED units
            vIP_RET_CAP_UC[inputs.IP_UC]                        >= 0 #retirement of onsite UC units
            vIP_NEW_CAP_UC[inputs.IP_UC]                        >= 0 #new build onsite UC units

            vIP_COMMIT[inputs.T, inputs.IP_UC], Bin #commitment variable for onsite UC units
            vIP_START[inputs.T, inputs.IP_UC], Bin #start up variable for onsite UC units
            vIP_SHUT[inputs.T, inputs.IP_UC], Bin #shut down variable for onsite UC units
            #vIP_CONNECT[inputs.IP], Bin #binary variable for grid connection 
    end)

    #operational decision variables for industrial
    @variables(CE, begin
            vIP_GEN[inputs.T, inputs.IP_G]                      >= 0 #generation of onsite power options
            vIP_GEN_HEAT[inputs.T, inputs.IP_G]                 >= 0 #generation of onsite heat options
            vIP_SOC[inputs.T, inputs.IP_STOR]                   >= 0 #energy storage state of charge (MW)
            vIP_CHARGE[inputs.T, inputs.IP_STOR]                >= 0 #power charging (MW)
            vIP_NSE[inputs.T, inputs.S, inputs.IP]              >= 0 #non-served energy for industrial parks
            vIP_NSE_HEAT[inputs.T, inputs.S, inputs.IP]         >= 0 #non-served energy for industrial parks
    end)

    if Grid
        @variables(CE, begin
            vIP_IMPORT[inputs.T, inputs.IP]  >= 0  #grid import for the industrial plants
            #vIP_EXPORT[inputs.T, inputs.IP]                     >= 0 #grid export for the industrial plants
        end)
    end

    # for g in inputs.IP_UC_NEW[inputs.ip_generators[inputs.IP_UC_NEW, :Max_Cap_MW].>0]
    #     set_upper_bound(vIP_NEW_CAP_UC[g], inputs.ip_generators.Max_Cap_MW[g])
    # end

    # for g in inputs.IP_ED_NEW[inputs.ip_generators[inputs.ED_NEW, :Max_Cap_MW].>0]
    #     set_upper_bound(vIP_NEW_CAP_ED[g], inputs.ip_generators.Max_Cap_MW[g])
    # end

    for g in intersect(inputs.IP_STOR, inputs.IP_NEW)
        set_upper_bound(vIP_NEW_E_CAP[g], 208.0)
    end


    

    #CONSTRAINTS
    if Grid
        #Supply Demand Balance Constraint
        @constraint(CE, cDemandBalance[t in inputs.T, z in inputs.Z], 
        sum(vGEN[t,g] for g in intersect(inputs.generators[inputs.generators.Zone.==z,:R_ID],inputs.G)) +
        sum(vNSE[t,s,z] for s in inputs.S) - 
        sum(vCHARGE[t,g] for g in intersect(inputs.generators[inputs.generators.Zone.==z,:R_ID],inputs.STOR)) -
        inputs.demand[t,z] - 
        sum(inputs.lines[l,Symbol(string("z",z))] * vFLOW[t,l] for l in inputs.L) -
        sum(vIP_IMPORT[t,ip] for ip in intersect(inputs.ip_generators[inputs.ip_generators.Zone.==z,:R_ID],inputs.IP)) == 0
        )
    else
        #Supply Demand Balance Constraint
        @constraint(CE, cDemandBalance[t in inputs.T, z in inputs.Z], 
        sum(vGEN[t,g] for g in intersect(inputs.generators[inputs.generators.Zone.==z,:R_ID],inputs.G)) +
        sum(vNSE[t,s,z] for s in inputs.S) - 
        sum(vCHARGE[t,g] for g in intersect(inputs.generators[inputs.generators.Zone.==z,:R_ID],inputs.STOR)) -
        inputs.demand[t,z] - 
        sum(inputs.lines[l,Symbol(string("z",z))] * vFLOW[t,l] for l in inputs.L) == 0
        )
    end

    
    
    
    #capacitated constraints
    @constraints(CE, begin

            #max power constraint for ED generators
            cMaxPowerED[t in inputs.T, g in inputs.ED], vGEN[t,g] <= inputs.variability[t,g]*vCAP[g]
            
            #max power constraints for UC generators
            cMaxPowerUC[t in inputs.T, g in inputs.UC], vGEN[t,g] <= inputs.generators.Existing_Cap_MW[g]*vCOMMIT[t,g]

            #min power constraints for UC generators
            cMinPowerUC[t in inputs.T, g in inputs.UC], vGEN[t,g] >=   
                inputs.generators.Min_Power_MW[g]*inputs.generators.Existing_Cap_MW[g]*vCOMMIT[t,g]
            
            #max charge constraint
            cMaxCharge[t in inputs.T, g in inputs.STOR], vCHARGE[t,g] <= vCAP[g]
            
            #max state of charge constraint
            cMaxSOC[t in inputs.T, g in inputs.STOR], vSOC[t,g] <= vE_CAP[g]
            
            #max NSE constraint
            cMaxNSE[t in inputs.T, s in inputs.S, z in inputs.Z], vNSE[t,s,z] <= 
                inputs.nse.NSE_Max[s]*inputs.demand[t,z]
            
            #max flow constraint
            cMaxFlow[t in inputs.T, l in inputs.L], vFLOW[t,l] <= vT_CAP[l]
            
            #min flow constraint
            cMinFlow[t in inputs.T, l in inputs.L], vFLOW[t,l] >= -vT_CAP[l]        
        end);

    #total capacity constraint
    @constraints(CE, begin

            #total capacity for exisiting ED units
            cCapOld[g in inputs.ED_OLD], vCAP[g] == inputs.generators.Existing_Cap_MW[g] - vRET_CAP_ED[g]

            #total capacity for new ED units
            cCapNew[g in inputs.ED_NEW], vCAP[g] == vNEW_CAP_ED[g]

            #total capacity for old UC units
            cCapOldUC[g in inputs.UC_OLD], vCAP[g] == inputs.generators.Existing_Cap_MW[g] - 
            vRET_CAP_UC[g]
        
            #total capacity for new UC units
            cCapNewUC[g in inputs.UC_NEW], vCAP[g] == vNEW_CAP_UC[g]

            #total energy storage capacity for existing units
            cCapEnergyOld[g in intersect(inputs.STOR, inputs.OLD)], 
                vE_CAP[g] == inputs.generators.Existing_Cap_MWh[g] - vRET_E_CAP[g]

            #total energy storage capacity for new units
            cCapEnergyNew[g in intersect(inputs.STOR, inputs.NEW)], 
                vE_CAP[g] == vNEW_E_CAP[g]

            #total transmission capacity
            cTransCap[l in inputs.L], vT_CAP[l] == inputs.lines.Line_Max_Flow_MW[l] - vRET_T_CAP[l] + vNEW_T_CAP[l]       
            
            # #setting reference bus for transmission lines
            # cThetaRef[t in inputs.T, z in inputs.Z], vTHETA[t,1] == 0
            
        end);

        # #DC power flow constraint
        # @constraint(CE, cDCPowerFlow[t in inputs.T, l in inputs.L],
        #    vFLOW[t,l] == (inputs.lines[l,:B] / inputs.lines[l,:distance_km]) * sum(inputs.lines[l,Symbol(string("z",i))] * vTHETA[t,i] for i in inputs.Z)
        # );

    # ramp, min up, min down, and storage constraints
    @constraints(CE, begin

            #ramp up for ED units, normal
            cRampUp[t in inputs.INTERIOR, g in inputs.ED],
                vGEN[t,g] - vGEN[t-1,g] <= inputs.generators.Ramp_Up_Percentage[g]*vCAP[g]

            #ramp up for ED units, sub-period wrapping
            cRampUpWrap[t in inputs.START, g in inputs.ED],
                vGEN[t,g] - vGEN[t+inputs.hours_per_period-1,g] <= inputs.generators.Ramp_Up_Percentage[g]*vCAP[g]

            #ramp up constraints for UC units, normal
            cRampUpUC[t in inputs.INTERIOR, g in inputs.UC],
                vGEN[t,g] - vGEN[t-1,g] <= 
                inputs.generators.Ramp_Up_Percentage[g]*inputs.generators.Existing_Cap_MW[g]*(vCOMMIT[t,g] - vSTART[t,g]) +
                max(inputs.generators.Min_Power_MW[g], 
                inputs.generators.Ramp_Up_Percentage[g])*inputs.generators.Existing_Cap_MW[g]*vSTART[t,g] - 
                inputs.generators.Min_Power_MW[g]*inputs.generators.Existing_Cap_MW[g]*vSHUT[t,g]

            #ramp up constraints for UC units, sub-period wrapping
            cRampUpWrapUC[t in inputs.START, g in inputs.UC],    
                vGEN[t,g] - vGEN[t+inputs.hours_per_period-1,g] <= 
                inputs.generators.Ramp_Up_Percentage[g]*inputs.generators.Existing_Cap_MW[g]*(vCOMMIT[t,g] - vSTART[t,g]) +
                max(inputs.generators.Min_Power_MW[g], 
                inputs.generators.Ramp_Up_Percentage[g])*inputs.generators.Existing_Cap_MW[g]*vSTART[t,g] - 
                inputs.generators.Min_Power_MW[g]*inputs.generators.Existing_Cap_MW[g]*vSHUT[t,g]
        
            #ramp down for ED units, normal
            cRampDown[t in inputs.INTERIOR, g in inputs.ED],
                vGEN[t-1,g] - vGEN[t,g] <= inputs.generators.Ramp_Dn_Percentage[g]*vCAP[g]

            #ramp down for ED units, sub-period warping
            cRampDownWrap[t in inputs.START, g in inputs.ED],
                vGEN[t+inputs.hours_per_period-1,g] - vGEN[t,g] <= inputs.generators.Ramp_Dn_Percentage[g]*vCAP[g]
 
            #ramp down constraints for UC units, normal
            cRampDownUC[t in inputs.INTERIOR, g in inputs.UC],
                vGEN[t-1,g] - vGEN[t,g] <= 
                inputs.generators.Ramp_Dn_Percentage[g]*inputs.generators.Existing_Cap_MW[g]*(vCOMMIT[t,g] - vSTART[t,g]) +
                max(inputs.generators.Min_Power_MW[g], 
                inputs.generators.Ramp_Dn_Percentage[g])*inputs.generators.Existing_Cap_MW[g]*vSHUT[t,g] - 
                inputs.generators.Min_Power_MW[g]*inputs.generators.Existing_Cap_MW[g]*vSTART[t,g]

            #ramp down constraints for UC units, sub-period wrapping
            cRampDownWrapUC[t in inputs.START, g in inputs.UC],    
                vGEN[t+inputs.hours_per_period-1,g] - vGEN[t,g] <= 
                inputs.generators.Ramp_Dn_Percentage[g]*inputs.generators.Existing_Cap_MW[g]*
                (vCOMMIT[t,g] - vSTART[t,g]) +
                max(inputs.generators.Min_Power_MW[g], inputs.generators.Ramp_Dn_Percentage[g])*
                inputs.generators.Existing_Cap_MW[g]*vSHUT[t,g] - 
                inputs.generators.Min_Power_MW[g]*inputs.generators.Existing_Cap_MW[g]*vSTART[t,g]

            #minimum up constraints
            cUpTime[t in inputs.T, g in inputs.UC],
                vCOMMIT[t,g] >= sum(vSTART[tt, g]
                                for tt in intersect(inputs.T,
                                (t-inputs.generators.Up_Time[g]:t)))
            #minimum down constraints
            cDownTime[t in inputs.T, g in inputs.UC],
                vCAP[g] / inputs.generators.Existing_Cap_MW[g] >= sum(vSHUT[tt, g]
                                                            for tt in intersect(inputs.T,
                                                            (t-inputs.generators.Down_Time[g]:t)))

            #storage state of charge, normal
            cSOC[t in inputs.INTERIOR, g in inputs.STOR],
                vSOC[t,g] == vSOC[t-1,g] + inputs.generators.Eff_Up[g]*vCHARGE[t,g] - 
                vGEN[t,g]/inputs.generators.Eff_Down[g]

            #storage state of charge, sub-period warping
            cSOCWrap[t in inputs.START, g in inputs.STOR], 
                vSOC[t,g] == vSOC[t+inputs.hours_per_period-1,g] + inputs.generators.Eff_Up[g]*vCHARGE[t,g] - 
                vGEN[t,g]/inputs.generators.Eff_Down[g]

    
        end);

    #state variables
    @constraints(CE, begin
            
            #upper bound commit constraints
            cCommitBound[t in inputs.T, g in inputs.UC],
                vCOMMIT[t,g] <= vCAP[g] / inputs.generators.Existing_Cap_MW[g]

            #upper bound start constraints
            cStartBound[t in inputs.T, g in inputs.UC],
                vSTART[t,g] <= vCAP[g] / inputs.generators.Existing_Cap_MW[g]

            #upper bound shut constraints
            cShutBound[t in inputs.T, g in inputs.UC],
                vSHUT[t,g] <= vCAP[g] / inputs.generators.Existing_Cap_MW[g]

            #define the commit variable
            cCommitState[t in inputs.T_red, g in inputs.UC],
                vCOMMIT[t+1,g] == vCOMMIT[t,g] + vSTART[t+1,g] - vSHUT[t+1,g]

        end);



    #industrial park constraints - demand balance
    #demand balance for industrial parks - heat
    @constraints(CE, begin
            cIPHeatBalance[t in inputs.T, ip in inputs.IP],
            sum(vIP_GEN_HEAT[t,g] for g in intersect(inputs.ip_generators[inputs.ip_generators.Industrial_Park.==ip,:R_ID],inputs.IP_UC)) +
            sum(vIP_NSE_HEAT[t,s,ip] for s in inputs.IP_S) -  
            inputs.ip_demandheat[t,ip] == 0
        end);

    #demand balance for industrial parks - electricity
    if Grid
        if NoCoal
            @constraints(CE, begin
                cIPElectricityBalance[t in inputs.T, ip in inputs.IP], 
                sum(vIP_GEN[t,g] for g in intersect(inputs.ip_generators[inputs.ip_generators.Industrial_Park.==ip,:R_ID],inputs.IP_RE)) +
                sum(vIP_IMPORT[t,ip]) +
                sum(vIP_NSE[t,s,ip] for s in inputs.IP_S) - 
                sum(vIP_CHARGE[t,g] for g in intersect(inputs.ip_generators[inputs.ip_generators.Industrial_Park.==ip,:R_ID],inputs.IP_STOR)) -
                # include export variable here -
                inputs.ip_demand[t,ip] == 0
            end);

        elseif Captive
            @constraints(CE, begin
                cIPElectricityBalance[t in inputs.T, ip in inputs.IP], 
                sum(vIP_GEN[t,g] for g in intersect(inputs.ip_generators[inputs.ip_generators.Industrial_Park.==ip,:R_ID],inputs.IP_G)) +
                sum(vIP_IMPORT[t,ip]) +
                sum(vIP_NSE[t,s,ip] for s in inputs.IP_S) -
                sum(vIP_CHARGE[t,g] for g in intersect(inputs.ip_generators[inputs.ip_generators.Industrial_Park.==ip,:R_ID],inputs.IP_STOR)) -
                # include export variable here -
                inputs.ip_demand[t,ip] == 0
            end);

        else
            @constraints(CE, begin
                cIPElectricityBalance[t in inputs.T, ip in inputs.IP], 
                sum(vIP_GEN[t,g] for g in intersect(inputs.ip_generators[inputs.ip_generators.Industrial_Park.==ip,:R_ID],inputs.IP_UC)) +
                sum(vIP_IMPORT[t,ip]) + 
                sum(vIP_NSE[t,s,ip] for s in inputs.IP_S) -
                # include export variable here -
                inputs.ip_demand[t,ip] == 0
            end);
        end
    else
        if NoCoal
            @constraints(CE, begin
                cIPElectricityBalance[t in inputs.T, ip in inputs.IP], 
                sum(vIP_GEN[t,g] for g in intersect(inputs.ip_generators[inputs.ip_generators.Industrial_Park.==ip,:R_ID],inputs.IP_RE)) +
                sum(vIP_NSE[t,s,ip] for s in inputs.IP_S) -
                sum(vIP_CHARGE[t,g] for g in intersect(inputs.ip_generators[inputs.ip_generators.Industrial_Park.==ip,:R_ID],inputs.IP_STOR)) -
                # include export variable here -
                inputs.ip_demand[t,ip] == 0
            end);

        elseif Captive
            @constraints(CE, begin
                cIPElectricityBalance[t in inputs.T, ip in inputs.IP], 
                sum(vIP_GEN[t,g] for g in intersect(inputs.ip_generators[inputs.ip_generators.Industrial_Park.==ip,:R_ID],inputs.IP_G)) +
                sum(vIP_NSE[t,s,ip] for s in inputs.IP_S) -
                sum(vIP_CHARGE[t,g] for g in intersect(inputs.ip_generators[inputs.ip_generators.Industrial_Park.==ip,:R_ID],inputs.IP_STOR)) -
                # include export variable here -
                inputs.ip_demand[t,ip] == 0
            end);

        else
            @constraints(CE, begin
                cIPElectricityBalance[t in inputs.T, ip in inputs.IP], 
                sum(vIP_GEN[t,g] for g in intersect(inputs.ip_generators[inputs.ip_generators.Industrial_Park.==ip,:R_ID],inputs.IP_UC)) + 
                sum(vIP_NSE[t,s,ip] for s in inputs.IP_S) -
                # include export variable here -
                inputs.ip_demand[t,ip] == 0
            end);
        end
    end

    #industrial park capacity constraints
    @constraints(CE, begin

            #capacity for existing ED units
            cIPEdOld[g in inputs.IP_ED_OLD], 
                vIP_CAP[g] == inputs.ip_generators.Existing_Cap_MW[g] - vIP_RET_CAP_ED[g]

            #capacity for new ED units
            cIPEdNew[g in inputs.IP_ED_NEW], 
                vIP_CAP[g] == vIP_NEW_CAP_ED[g]

            #capacity for existing UC units
            cIPUcOld[g in inputs.IP_UC_OLD], 
                vIP_CAP[g] == inputs.ip_generators.Existing_Cap_MW[g] - vIP_RET_CAP_UC[g]

            #capacity for new UC units
            cIPUcNew[g in inputs.IP_UC_NEW], 
                vIP_CAP[g] == vIP_NEW_CAP_UC[g]

            #max charge constraint
            cIPMaxCharge[t in inputs.T, g in inputs.IP_STOR], vIP_CHARGE[t,g] <= vIP_CAP[g]
            
            #max state of charge constraint
            cIPMaxSOC[t in inputs.T, g in inputs.IP_STOR], vIP_SOC[t,g] <= vIP_E_CAP[g]

            #total energy storage capacity for existing units
            cIPCapEnergyOld[g in intersect(inputs.IP_STOR, inputs.IP_OLD)], 
                vIP_E_CAP[g] == inputs.ip_generators.Existing_Cap_MWh[g] - vIP_RET_E_CAP[g]

            #total energy storage capacity for new units
            cIPCapEnergyNew[g in intersect(inputs.IP_STOR, inputs.IP_NEW)], 
                vIP_E_CAP[g] == vIP_NEW_E_CAP[g]

            #NSE constraints for industrial parks electricity
            cIPNSE[t in inputs.T, s in inputs.IP_S, ip in inputs.IP], 
                vIP_NSE[t,s,ip] <= inputs.ip_nse.NSE_Max[s]*inputs.ip_demand[t,ip]

            #NSE constraints for industrial parks heat
            cIPNSEHeat[t in inputs.T, s in inputs.IP_S, ip in inputs.IP], 
                vIP_NSE_HEAT[t,s,ip] <= inputs.ip_nse.NSE_Max[s]*inputs.ip_demandheat[t,ip]

        end);

    #industrial park capacity constraints
    @constraints(CE, begin

            #max power constraint for ED generators
            cIPEdMaxPower[t in inputs.T, g in inputs.IP_ED], 
            vIP_GEN[t,g] <= inputs.ip_variability[t,g]*vIP_CAP[g]

            #max power constraints for UC generators
            cIPUcMaxPower[t in inputs.T, g in inputs.IP_UC], 
                (vIP_GEN_HEAT[t,g] + vIP_GEN[t,g]) <= inputs.ip_generators.Existing_Cap_MW[g]*vIP_COMMIT[t,g]

            #min power constraints for UC generators
            cIPUcMinPower[t in inputs.T, g in inputs.IP_UC], 
                (vIP_GEN[t,g] + vIP_GEN_HEAT[t,g]) >=   
                inputs.ip_generators.Min_Power_MW[g]*inputs.ip_generators.Existing_Cap_MW[g]*vIP_COMMIT[t,g]
            
        end);

    #industrial park ramp, min up, min down, and storage constraints
    @constraints(CE, begin

            #ramp up for ED units, normal
            cIPRampUp[t in inputs.INTERIOR, g in inputs.IP_ED],
                vIP_GEN[t,g] - vIP_GEN[t-1,g] <= 
                inputs.ip_generators.Ramp_Up_Percentage[g]*vIP_CAP[g]

            #ramp up for ED units, sub-period wrapping
            cIPRampUpWrap[t in inputs.START, g in inputs.IP_ED],
                vIP_GEN[t,g] - vIP_GEN[t+inputs.hours_per_period-1,g]  <= 
                inputs.ip_generators.Ramp_Up_Percentage[g]*vIP_CAP[g]

            # #ramp up constraints for UC units, normal
            # cIPRampUpUC[t in inputs.INTERIOR, g in inputs.IP_UC],
            #     (vIP_GEN[t,g] + vIP_GEN_HEAT[t,g]) - (vIP_GEN[t-1,g] + vIP_GEN_HEAT[t-1,g]) <= 
            #     inputs.ip_generators.Ramp_Up_Percentage[g]*inputs.ip_generators.Existing_Cap_MW[g]*(vIP_COMMIT[t,g] - vIP_START[t,g]) +
            #     max(inputs.ip_generators.Min_Power_MW[g], 
            #     inputs.ip_generators.Ramp_Up_Percentage[g])*inputs.ip_generators.Existing_Cap_MW[g]*vIP_START[t,g] - 
            #     inputs.ip_generators.Min_Power_MW[g]*inputs.ip_generators.Existing_Cap_MW[g]*vIP_SHUT[t,g]

            # #ramp up constraints for UC units, sub-period wrapping
            # cIPRampUpWrapUC[t in inputs.START, g in inputs.IP_UC],    
            #     (vIP_GEN[t,g] + vIP_GEN_HEAT[t,g]) - (vIP_GEN[t+inputs.hours_per_period-1,g] + vIP_GEN_HEAT[t+inputs.hours_per_period-1,g]) <= 
            #     inputs.ip_generators.Ramp_Up_Percentage[g]*inputs.ip_generators.Existing_Cap_MW[g]*(vIP_COMMIT[t,g] - vIP_START[t,g]) +
            #     max(inputs.ip_generators.Min_Power_MW[g], 
            #     inputs.ip_generators.Ramp_Up_Percentage[g])*inputs.ip_generators.Existing_Cap_MW[g]*vIP_START[t,g] - 
            #     inputs.ip_generators.Min_Power_MW[g]*inputs.ip_generators.Existing_Cap_MW[g]*vIP_SHUT[t,g]

            #ramp down for ED units, normal
            cIPRampDown[t in inputs.INTERIOR, g in inputs.IP_ED],
                vIP_GEN[t-1,g] - vIP_GEN[t,g] <= inputs.ip_generators.Ramp_Dn_Percentage[g]*vIP_CAP[g]

            #ramp down for ED units, sub-period warping
            cIPRampDownWrap[t in inputs.START, g in inputs.IP_ED],
                vIP_GEN[t+inputs.hours_per_period-1,g] - vIP_GEN[t,g] <= inputs.ip_generators.Ramp_Dn_Percentage[g]*vIP_CAP[g]

            # #ramp down constraints for UC units, normal
            # cIPRampDownUC[t in inputs.INTERIOR, g in inputs.IP_UC],
            #     (vIP_GEN[t-1,g] + vIP_GEN_HEAT[t-1,g]) - (vIP_GEN[t,g] + vIP_GEN_HEAT[t,g]) <= 
            #     inputs.ip_generators.Ramp_Dn_Percentage[g]*inputs.ip_generators.Existing_Cap_MW[g]*(vIP_COMMIT[t,g] - vIP_START[t,g]) +
            #     max(inputs.ip_generators.Min_Power_MW[g], 
            #     inputs.ip_generators.Ramp_Dn_Percentage[g])*inputs.ip_generators.Existing_Cap_MW[g]*vIP_SHUT[t,g] - 
            #     inputs.ip_generators.Min_Power_MW[g]*inputs.ip_generators.Existing_Cap_MW[g]*vIP_START[t,g]

            # #ramp down constraints for UC units, sub-period wrapping
            # cIPRampDownWrapUC[t in inputs.START, g in inputs.IP_UC],    
            #     (vIP_GEN[t+inputs.hours_per_period-1,g] + vIP_GEN_HEAT[t+inputs.hours_per_period-1,g]) - (vIP_GEN[t,g] + vIP_GEN_HEAT[t,g]) <= 
            #     inputs.ip_generators.Ramp_Dn_Percentage[g]*inputs.ip_generators.Existing_Cap_MW[g]*(vIP_COMMIT[t,g] - vIP_START[t,g]) +
            #     max(inputs.ip_generators.Min_Power_MW[g], 
            #     inputs.ip_generators.Ramp_Dn_Percentage[g])*inputs.ip_generators.Existing_Cap_MW[g]*vIP_SHUT[t,g] - 
            #     inputs.ip_generators.Min_Power_MW[g]*inputs.ip_generators.Existing_Cap_MW[g]*vIP_START[t,g]
                
            #minimum up constraints
            cIPUpTime[t in inputs.T, g in inputs.IP_UC],
                vIP_COMMIT[t,g] >= sum(vIP_START[tt,g]
                                for tt in intersect(inputs.T,
                                (t-inputs.ip_generators.Up_Time[g]:t)))
            #minimum down constraints
            cIPDownTime[t in inputs.T, g in inputs.IP_UC],
                vIP_CAP[g] / inputs.ip_generators.Existing_Cap_MW[g] >= sum(vIP_SHUT[tt,g]
                                                            for tt in intersect(inputs.T,
                                                            (t-inputs.ip_generators.Down_Time[g]:t)))
            #storage state of charge, normal
            cIPSOC[t in inputs.INTERIOR, g in inputs.IP_STOR],
                vIP_SOC[t,g] == vIP_SOC[t-1,g] + inputs.ip_generators.Eff_Up[g]*vIP_CHARGE[t,g] -
                vIP_GEN[t,g]/inputs.ip_generators.Eff_Down[g]

            #storage state of charge, sub-period warping
            cIPSOCWrap[t in inputs.START, g in inputs.IP_STOR],
                vIP_SOC[t,g] == vIP_SOC[t+inputs.hours_per_period-1,g] + inputs.ip_generators.Eff_Up[g]*vIP_CHARGE[t,g] -
                vIP_GEN[t,g]/inputs.ip_generators.Eff_Down[g]
        end);

    #industrial park state variables
    @constraints(CE, begin
            
            #upper bound commit constraints
            cIPCommitBound[t in inputs.T, g in inputs.IP_UC],
                vIP_COMMIT[t,g] <= vIP_CAP[g] / inputs.ip_generators.Existing_Cap_MW[g]

            #upper bound start constraints
            cIPStartBound[t in inputs.T, g in inputs.IP_UC],
                vIP_START[t,g] <= vIP_CAP[g] / inputs.ip_generators.Existing_Cap_MW[g]

            #upper bound shut constraints
            cIPShutBound[t in inputs.T, g in inputs.IP_UC],
                vIP_SHUT[t,g] <= vIP_CAP[g] / inputs.ip_generators.Existing_Cap_MW[g]

            #define the commit variable
            cIPCommitState[t in inputs.T_red, g in inputs.IP_UC],
                vIP_COMMIT[t+1,g] == vIP_COMMIT[t,g] + vIP_START[t+1,g] - vIP_SHUT[t+1,g]

        end);


    # clean energy constraints

    #CO2 emissions
    @expression(CE, eCO2EmissionsGrid,
    (sum(inputs.sample_weight[t]*inputs.generators.CO2_Rate[g]*vGEN[t,g] for t in inputs.T, g in inputs.G) +
    sum(inputs.sample_weight[t]*inputs.generators.CO2_Per_Start[g]*vSTART[t,g] for t in inputs.T, g in inputs.UC))
    );

    @expression(CE, eCO2EmissionsIP,
    (sum(inputs.sample_weight[t]*inputs.ip_generators.CO2_Rate[g]*(vIP_GEN[t,g] + vIP_GEN_HEAT[t,g]) for t in inputs.T, g in inputs.IP_UC) +
    sum(inputs.sample_weight[t]*inputs.ip_generators.CO2_Per_Start[g]*vIP_START[t,g] for t in inputs.T, g in inputs.IP_UC))
    );
    
    
    if CO2_constraint
        #setting CO2 emissions constraint to 290 as per JETP agreement
        @constraint(CE, cCO2EmissionsGrid, eCO2EmissionsGrid <= CO2_limit);
    end

    if CO235reduction
        #setting CO2 emissions constraint to 235 as per JETP agreement
        @constraint(CE, cCO2EmissionsIP,  eCO2EmissionsIP <= 0.65*BAUCO2emissions);
    end

    #renewable energy share
    @expression(CE, eREShare, 
    (sum(inputs.sample_weight[t]*inputs.generators.RE[g]*vGEN[t,g] for t in inputs.T, g in inputs.G) /
    sum(inputs.sample_weight[t]*inputs.demand[t,z] for t in inputs.T, z in inputs.Z))
    );
    
    if RE_constraint
        #setting renewable energy share constraint to 34% as per JETP agreement
        @constraint(CE, cREShare, eREShare >= RE_limit);
    end

    #OBJECTIVE FUNCTION
    
    #fixed cost for generation
    @expression(CE, eFixedCostsGeneration,
        #fixed costs for total capacity
        sum(inputs.generators.Fixed_OM_Cost_per_MWyr[g]*vCAP[g] for g in inputs.G) +
        # Investment cost for new ED capacity
        sum(inputs.generators.Inv_Cost_per_MWyr[g]*vNEW_CAP_ED[g] for g in inputs.ED_NEW) + 
         # Investment cost for new UC capacity
        sum(inputs.generators.Inv_Cost_per_MWyr[g]*vNEW_CAP_UC[g] for g in inputs.UC_NEW)
        );

    #fixed cost for industrial park generation
    @expression(CE, eFixedCostsIPGeneration,
        #fixed costs for total capacity
        sum(inputs.ip_generators.Fixed_OM_Cost_per_MWyr[g]*vIP_CAP[g] for g in inputs.IP_G) +
        # Investment cost for new ED capacity
        sum(inputs.ip_generators.Inv_Cost_per_MWyr[g]*vIP_NEW_CAP_ED[g] for g in inputs.IP_ED) + 
         # Investment cost for new UC capacity
        sum(inputs.ip_generators.Inv_Cost_per_MWyr[g]*vIP_NEW_CAP_UC[g] for g in inputs.IP_UC)
        );
    
    #fixed cost for storage
    @expression(CE, eFixedCostsStorage,
        #fixed costs for total storage capacity
        sum(inputs.generators.Fixed_OM_Cost_per_MWhyr[g]*vE_CAP[g] for g in inputs.STOR) + 
        #investment costs for new storage energy capacity
        sum(inputs.generators.Inv_Cost_per_MWhyr[g]*vNEW_E_CAP[g] for g in intersect(inputs.STOR, inputs.NEW))
        );

    #fixed cost for storage
    @expression(CE, eIPFixedCostsStorage,
        #fixed costs for total storage capacity
        sum(inputs.ip_generators.Fixed_OM_Cost_per_MWhyr[g]*vIP_E_CAP[g] for g in inputs.IP_STOR) + 
        #investment costs for new storage energy capacity
        sum(inputs.ip_generators.Inv_Cost_per_MWhyr[g]*vIP_NEW_E_CAP[g] for g in intersect(inputs.IP_STOR, inputs.IP_NEW))
        );
    
    #fixed cost for transmission
    @expression(CE, eFixedCostsTransmission,
     # Investment and fixed O&M costs for transmission lines
        sum(inputs.lines.Line_Fixed_Cost_per_MW_yr[l]*vT_CAP[l] +
            inputs.lines.Line_Reinforcement_Cost_per_MWyr[l]*vNEW_T_CAP[l] for l in inputs.L)
        );

    #variable costs for grid generators
    @expression(CE, eVariableCostsGrid,
        # Variable costs for generation, weighted by hourly sample weight 
        sum(inputs.sample_weight[t]*inputs.generators.Var_Cost[g]*vGEN[t,g] for t in inputs.T, g in inputs.G)
        );

    #variable costs for industrial park ED generators
    @expression(CE, eVariableCostsIPED,
        # Variable costs for generation, weighted by hourly sample weight 
        sum(inputs.sample_weight[t]*inputs.ip_generators.Var_Cost[g]*vIP_GEN[t,g] for t in inputs.T, g in inputs.IP_ED)
        );

    #variable costs for industrial park UC generators
    @expression(CE, eVariableCostsIPUC,
        # Variable costs for generation, weighted by hourly sample weight 
        sum(inputs.sample_weight[t]*inputs.ip_generators.Var_Cost[g]*(vIP_GEN[t,g] + vIP_GEN_HEAT[t,g]) for t in inputs.T, g in inputs.IP_UC)
        );

    #NSE costs for grid
    @expression(CE, eNSECosts,
     # Non-served energy costs, weighted by hourly sample weight to ensure non-served energy costs estimate annual costs
    sum(inputs.sample_weight[t]*inputs.nse.NSE_Cost[s]*vNSE[t,s,z] for t in inputs.T, s in inputs.S, z in inputs.Z)
        );

    #NSE costs for industrial park
    @expression(CE, eIPNSECosts,
        # Non-served energy costs, weighted by hourly sample weight to ensure non-served energy costs estimate annual costs
        sum(inputs.sample_weight[t]*inputs.ip_nse.NSE_Cost[s]*vIP_NSE[t,s,ip] for t in inputs.T, s in inputs.S, ip in inputs.IP)
        );

    #NSE costs for industrial park heat
    @expression(CE, eIPNSEHeatCosts,
         # Non-served energy costs, weighted by hourly sample weight to ensure non-served energy costs estimate annual costs
        sum(inputs.sample_weight[t]*inputs.ip_nse.NSE_Cost[s]*vIP_NSE_HEAT[t,s,ip] for t in inputs.T, s in inputs.S, ip in inputs.IP)
        );


    #start costs for grid generators
    @expression(CE, eStartCostsGrid,
    sum(inputs.sample_weight[t]*inputs.generators.Start_Cost[g]*vSTART[t,g]*inputs.generators.Existing_Cap_MW[g] 
            for t in inputs.T, g in inputs.UC)
        );
    
    #start costs for industrial park generators
    @expression(CE, eStartCostsIP,
    sum(inputs.sample_weight[t]*inputs.ip_generators.Start_Cost[g]*vIP_START[t,g]*inputs.ip_generators.Existing_Cap_MW[g] 
            for t in inputs.T, g in inputs.IP_UC)
        );
    
    if Grid
        #grid import costs
        @expression(CE, eGridImportCosts,
            sum(inputs.sample_weight[t]*ImportPrice*vIP_IMPORT[t,ip] for t in inputs.T, ip in inputs.IP) #change import cost to a constant value
        );
    else
        @expression(CE, eGridImportCosts,
            0
        );
    end
    @expression(CE, eCostObjective,
    eFixedCostsGeneration + eFixedCostsIPGeneration + 
    eFixedCostsStorage + eIPFixedCostsStorage +
    eFixedCostsTransmission + eGridImportCosts +
    eVariableCostsGrid + eVariableCostsIPED + eVariableCostsIPUC +
    eNSECosts + eIPNSECosts + eIPNSEHeatCosts + 
    eStartCostsGrid + eStartCostsIP
        );
    
    @objective(CE, Min, eCostObjective);


    optimize!(CE)

    # … after you build CE …
    #report_unbounded_continuous(CE)

    if termination_status(CE) == MOI.OPTIMAL
        println("The model solved successfully.")
    elseif termination_status(CE) == MOI.TIME_LIMIT
        println("The model reached the time limit.")
    elseif termination_status(CE) == MOI.INFEASIBLE
        println("The model is infeasible.")
    else
        println("The model did not solve successfully. Termination status: ", termination_status(CE))
    end

    if Grid
        IP_IMPORT = vIP_IMPORT
    else
        IP_IMPORT = 0
    end

    if Captive
        IP_E_CAP = 0
    else
        IP_E_CAP = vIP_E_CAP
    end
    
    return (
        CAP = vCAP,
        GEN = vGEN,
        E_CAP = vE_CAP,
        IP_CAP = vIP_CAP,
        IP_E_CAP = IP_E_CAP,
        IP_GEN = vIP_GEN,
        IP_GEN_HEAT = vIP_GEN_HEAT,
        IP_IMPORT = IP_IMPORT,
        T_CAP = vT_CAP,
        NSE = vNSE,
        IP_NSE = vIP_NSE,
        IP_NSE_HEAT = vIP_NSE_HEAT,
        FixedCostsGeneration = eFixedCostsGeneration,
        FixedCostsStorage = eFixedCostsStorage,
        FixedCostsTransmission = eFixedCostsTransmission,
        FixedCostsIPGeneration = eFixedCostsIPGeneration,
        FixedCostsIPStorage = eIPFixedCostsStorage,
        VariableCostsGrid = eVariableCostsGrid,
        VariableCostsIP = eVariableCostsIPED + eVariableCostsIPUC,
        GridImportCosts = eGridImportCosts,
        StartCostsGrid = eStartCostsGrid,
        StartCostsIP = eStartCostsIP,
        CO2Emissions = eCO2EmissionsGrid + eCO2EmissionsIP,
        CO2EmissionsGrid = eCO2EmissionsGrid,
        CO2EmissionsIP = eCO2EmissionsIP,
        REShare = eREShare,
        NSECosts = eNSECosts,
        IPNSECosts = eIPNSECosts,
        IPNSEHeatCosts = eIPNSEHeatCosts,
        cost = objective_value(CE)
        )

end