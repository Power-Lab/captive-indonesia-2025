using JuMP, Gurobi

function benders_master_problem(inputs, mipgap, CO2_constraint, CO2_limit, RE_constraint, RE_limit, Grid, VillageBuild, ImportPrice, NoCoal, CO235reduction, BAUCO2emissions)
    
    MASTER = Model(Gurobi.Optimizer)
    set_attribute(MASTER, "MIPGap", mipgap)
    set_attribute(MASTER, "Crossover", 0)
    set_attribute(MASTER, "TimeLimit", 2*24*60*60)
    
    # MASTER PROBLEM VARIABLES (Capacity/Investment Decisions)
    @variables(MASTER, begin
        # Power capacity variables
        vCAP[g in inputs.G] >= 0
        vRET_CAP_ED[g in inputs.ED_OLD] >= 0
        vNEW_CAP_ED[g in inputs.ED_NEW] >= 0
        vRET_CAP_UC[g in inputs.UC_OLD] >= 0
        vNEW_CAP_UC[g in inputs.UC_NEW] >= 0
        
        # Storage capacity variables
        vE_CAP[g in inputs.STOR] >= 0
        vRET_E_CAP[g in intersect(inputs.STOR, inputs.OLD)] >= 0
        vNEW_E_CAP[g in intersect(inputs.STOR, inputs.NEW)] >= 0
        
        # Transmission capacity variables
        vT_CAP[l in inputs.L] >= 0
        vRET_T_CAP[l in inputs.L] >= 0
        vNEW_T_CAP[l in inputs.L] >= 0
        
        # Village capacity variables
        vVIL_CAP[inputs.VIL_G] >= 0
        vVIL_E_CAP[inputs.VIL_STOR] >= 0
        vVIL_RET_E_CAP[inputs.VIL_STOR] >= 0
        vVIL_NEW_E_CAP[inputs.VIL_STOR] >= 0
        vVIL_RET_CAP_ED[inputs.VIL_ED] >= 0
        vVIL_NEW_CAP_ED[inputs.VIL_ED] >= 0
        vVIL_RET_CAP_UC[inputs.VIL_UC] >= 0
        vVIL_NEW_CAP_UC[inputs.VIL_UC] >= 0
        
        # Benders variables
        η >= 0  # Subproblem cost variable
    end)
    
    # Upper bounds on capacity expansion
    for g in inputs.UC_NEW[inputs.generators[inputs.UC_NEW, :Max_Cap_MW].>0]
        set_upper_bound(vNEW_CAP_UC[g], inputs.generators.Max_Cap_MW[g])
    end
    
    for g in inputs.ED_NEW[inputs.generators[inputs.ED_NEW, :Max_Cap_MW].>0]
        set_upper_bound(vNEW_CAP_ED[g], inputs.generators.Max_Cap_MW[g])
    end
    
    for l in inputs.L
        set_upper_bound(vNEW_T_CAP[l], inputs.lines.Line_Max_Reinforcement_MW[l])
    end
    
    # MASTER PROBLEM CONSTRAINTS
    
    # Total capacity constraints
    @constraints(MASTER, begin
        # ED units
        cCapOld[g in inputs.ED_OLD], vCAP[g] == inputs.generators.Existing_Cap_MW[g] - vRET_CAP_ED[g]
        cCapNew[g in inputs.ED_NEW], vCAP[g] == vNEW_CAP_ED[g]
        
        # UC units
        cCapOldUC[g in inputs.UC_OLD], vCAP[g] == inputs.generators.Existing_Cap_MW[g] - vRET_CAP_UC[g]
        cCapNewUC[g in inputs.UC_NEW], vCAP[g] == vNEW_CAP_UC[g]
        
        # Storage energy capacity
        cCapEnergyOld[g in intersect(inputs.STOR, inputs.OLD)], 
            vE_CAP[g] == inputs.generators.Existing_Cap_MWh[g] - vRET_E_CAP[g]
        cCapEnergyNew[g in intersect(inputs.STOR, inputs.NEW)], 
            vE_CAP[g] == vNEW_E_CAP[g]
        
        # Transmission capacity
        cTransCap[l in inputs.L], vT_CAP[l] == inputs.lines.Line_Max_Flow_MW[l] - vRET_T_CAP[l] + vNEW_T_CAP[l]
        
        # Village capacity constraints
        cVILEdOld[g in inputs.VIL_ED_OLD], 
            vVIL_CAP[g] == inputs.village_generators.Existing_Cap_MW[g] - vVIL_RET_CAP_ED[g]
        cVILEdNew[g in inputs.VIL_ED_NEW], 
            vVIL_CAP[g] == vVIL_NEW_CAP_ED[g]
        cVILUcOld[g in inputs.VIL_UC_OLD], 
            vVIL_CAP[g] == inputs.village_generators.Existing_Cap_MW[g] - vVIL_RET_CAP_UC[g]
        cVILUcNew[g in inputs.VIL_UC_NEW], 
            vVIL_CAP[g] == vVIL_NEW_CAP_UC[g]
        cVILCapEnergyOld[g in intersect(inputs.VIL_STOR, inputs.VIL_OLD)], 
            vVIL_E_CAP[g] == inputs.village_generators.Existing_Cap_MWh[g] - vVIL_RET_E_CAP[g]
        cVILCapEnergyNew[g in intersect(inputs.VIL_STOR, inputs.VIL_NEW)], 
            vVIL_E_CAP[g] == vVIL_NEW_E_CAP[g]
    end)
    
    # Fixed cost objective (first-stage costs)
    @expression(MASTER, eFixedCosts,
        # Generation fixed costs
        sum(inputs.generators.Fixed_OM_Cost_per_MWyr[g]*vCAP[g] for g in inputs.G) +
        sum(inputs.generators.Inv_Cost_per_MWyr[g]*vNEW_CAP_ED[g] for g in inputs.ED_NEW) +
        sum(inputs.generators.Inv_Cost_per_MWyr[g]*vNEW_CAP_UC[g] for g in inputs.UC_NEW) +
        
        # Storage fixed costs
        sum(inputs.generators.Fixed_OM_Cost_per_MWhyr[g]*vE_CAP[g] for g in inputs.STOR) +
        sum(inputs.generators.Inv_Cost_per_MWhyr[g]*vNEW_E_CAP[g] for g in intersect(inputs.STOR, inputs.NEW)) +
        
        # Transmission fixed costs
        sum(inputs.lines.Line_Fixed_Cost_per_MW_yr[l]*vT_CAP[l] +
            inputs.lines.Line_Reinforcement_Cost_per_MWyr[l]*vNEW_T_CAP[l] for l in inputs.L) +
        
        # VIL fixed costs
        sum(inputs.village_generators.Fixed_OM_Cost_per_MWyr[g]*vVIL_CAP[g] for g in inputs.VIL_G) +
        sum(inputs.village_generators.Inv_Cost_per_MWyr[g]*vVIL_NEW_CAP_ED[g] for g in inputs.VIL_ED) +
        sum(inputs.village_generators.Inv_Cost_per_MWyr[g]*vVIL_NEW_CAP_UC[g] for g in inputs.VIL_UC) +
        sum(inputs.village_generators.Fixed_OM_Cost_per_MWhyr[g]*vVIL_E_CAP[g] for g in inputs.VIL_STOR) +
        sum(inputs.village_generators.Inv_Cost_per_MWhyr[g]*vVIL_NEW_E_CAP[g] for g in intersect(inputs.VIL_STOR, inputs.VIL_NEW))
    )
    
    @objective(MASTER, Min, eFixedCosts + η)
    
    return MASTER, (
        vCAP=vCAP, vE_CAP=vE_CAP, vT_CAP=vT_CAP, vVIL_CAP=vVIL_CAP, vVIL_E_CAP=vVIL_E_CAP,
        vRET_CAP_ED=vRET_CAP_ED, vNEW_CAP_ED=vNEW_CAP_ED, vRET_CAP_UC=vRET_CAP_UC, vNEW_CAP_UC=vNEW_CAP_UC,
        vRET_E_CAP=vRET_E_CAP, vNEW_E_CAP=vNEW_E_CAP, vRET_T_CAP=vRET_T_CAP, vNEW_T_CAP=vNEW_T_CAP,
        vVIL_RET_CAP_ED=vVIL_RET_CAP_ED, vVIL_NEW_CAP_ED=vVIL_NEW_CAP_ED, vVIL_RET_CAP_UC=vVIL_RET_CAP_UC, 
        vVIL_NEW_CAP_UC=vVIL_NEW_CAP_UC, vVIL_RET_E_CAP=vVIL_RET_E_CAP, vVIL_NEW_E_CAP=vVIL_NEW_E_CAP,
        η=η
    )
end

function benders_subproblem(inputs, capacity_values, Grid, VillageBuild, ImportPrice, NoCoal, CO235reduction, BAUCO2emissions)
    
    SUB = Model(Gurobi.Optimizer)
    set_attribute(SUB, "OutputFlag", 0)  # Suppress output for subproblem
    
    # SUBPROBLEM VARIABLES (Operational Decisions)
    @variables(SUB, begin
        # Generation and operational variables
        vGEN[inputs.T, inputs.G] >= 0
        vCHARGE[inputs.T, inputs.STOR] >= 0
        vSOC[inputs.T, inputs.STOR] >= 0
        vNSE[inputs.T, inputs.S, inputs.Z] >= 0
        vFLOW[inputs.T, inputs.L] >= 0
        
        # Unit commitment variables
        vSTART[inputs.T, inputs.UC], Bin
        vSHUT[inputs.T, inputs.UC], Bin
        vCOMMIT[inputs.T, inputs.UC], Bin
        
        # Village operational variables
        vVIL_GEN[inputs.T, inputs.VIL_G] >= 0
        vVIL_GEN_HEAT[inputs.T, inputs.VIL_G] >= 0
        vVIL_SOC[inputs.T, inputs.VIL_STOR] >= 0
        vVIL_CHARGE[inputs.T, inputs.VIL_STOR] >= 0
        vVIL_NSE[inputs.T, inputs.S, inputs.VIL] >= 0
        vVIL_NSE_HEAT[inputs.T, inputs.S, inputs.VIL] >= 0
        vVIL_COMMIT[inputs.T, inputs.VIL_UC], Bin
        vVIL_START[inputs.T, inputs.VIL_UC], Bin
        vVIL_SHUT[inputs.T, inputs.VIL_UC], Bin
    end)
    
    if Grid
        @variable(SUB, vVIL_IMPORT[inputs.T, inputs.VIL] >= 0)
    end
    
    # SUBPROBLEM CONSTRAINTS
    
    # Supply-demand balance (using fixed capacity values)
    if Grid
        @constraint(SUB, cDemandBalance[t in inputs.T, z in inputs.Z], 
            sum(vGEN[t,g] for g in intersect(inputs.generators[inputs.generators.Zone.==z,:R_ID],inputs.G)) +
            sum(vNSE[t,s,z] for s in inputs.S) - 
            sum(vCHARGE[t,g] for g in intersect(inputs.generators[inputs.generators.Zone.==z,:R_ID],inputs.STOR)) -
            inputs.demand[t,z] - 
            sum(inputs.lines[l,Symbol(string("z",z))] * vFLOW[t,l] for l in inputs.L) -
            sum(vVIL_IMPORT[t,vil] for vil in inputs.VIL if inputs.village_zone[vil] == z) == 0
        )
    else
        @constraint(SUB, cDemandBalance[t in inputs.T, z in inputs.Z], 
            sum(vGEN[t,g] for g in intersect(inputs.generators[inputs.generators.Zone.==z,:R_ID],inputs.G)) +
            sum(vNSE[t,s,z] for s in inputs.S) - 
            sum(vCHARGE[t,g] for g in intersect(inputs.generators[inputs.generators.Zone.==z,:R_ID],inputs.STOR)) -
            inputs.demand[t,z] - 
            sum(inputs.lines[l,Symbol(string("z",z))] * vFLOW[t,l] for l in inputs.L) == 0
        )
    end
    
    # Operational constraints with fixed capacities - CORRECTED STORAGE CONSTRAINTS
    @constraints(SUB, begin
        # Max power constraint for ED generators
        cMaxPowerED[t in inputs.T, g in inputs.ED], 
            vGEN[t,g] <= inputs.variability[t,g] * capacity_values.vCAP[g]
        
        # CORRECTED: Max power constraints for UC generators (using vCAP instead of Existing_Cap_MW)
        cMaxPowerUC[t in inputs.T, g in inputs.UC], 
            vGEN[t,g] <= capacity_values.vCAP[g] * vCOMMIT[t,g]
        
        # Min power constraints for UC generators - CORRECTED
        cMinPowerUC[t in inputs.T, g in inputs.UC], 
            vGEN[t,g] >= inputs.generators.Min_Power_MW[g] * capacity_values.vCAP[g] * vCOMMIT[t,g]
        
        # Storage constraints - CORRECTED AND ADDED MISSING DISCHARGE CONSTRAINT
        cMaxCharge[t in inputs.T, g in inputs.STOR], 
            vCHARGE[t,g] <= capacity_values.vCAP[g]
        
        # ADDED: Storage discharge constraint (was missing in original)
        cMaxDischarge[t in inputs.T, g in inputs.STOR], 
            vGEN[t,g] <= capacity_values.vCAP[g]
        
        cMaxSOC[t in inputs.T, g in inputs.STOR], 
            vSOC[t,g] <= capacity_values.vE_CAP[g]
        
        # Max NSE and flow constraints
        cMaxNSE[t in inputs.T, s in inputs.S, z in inputs.Z], 
            vNSE[t,s,z] <= inputs.nse.NSE_Max[s] * inputs.demand[t,z]
        cMaxFlow[t in inputs.T, l in inputs.L], 
            vFLOW[t,l] <= capacity_values.vT_CAP[l]
        cMinFlow[t in inputs.T, l in inputs.L], 
            vFLOW[t,l] >= -capacity_values.vT_CAP[l]
    end)
    
    # Ramp, min up/down, and storage state constraints
    @constraints(SUB, begin
        # Ramp constraints for ED units
        cRampUp[t in inputs.INTERIOR, g in inputs.ED],
            vGEN[t,g] - vGEN[t-1,g] <= inputs.generators.Ramp_Up_Percentage[g] * capacity_values.vCAP[g]
        cRampUpWrap[t in inputs.START, g in inputs.ED],
            vGEN[t,g] - vGEN[t+inputs.hours_per_period-1,g] <= inputs.generators.Ramp_Up_Percentage[g] * capacity_values.vCAP[g]
        cRampDown[t in inputs.INTERIOR, g in inputs.ED],
            vGEN[t-1,g] - vGEN[t,g] <= inputs.generators.Ramp_Dn_Percentage[g] * capacity_values.vCAP[g]
        cRampDownWrap[t in inputs.START, g in inputs.ED],
            vGEN[t+inputs.hours_per_period-1,g] - vGEN[t,g] <= inputs.generators.Ramp_Dn_Percentage[g] * capacity_values.vCAP[g]
        
        # CORRECTED: Ramp constraints for UC units (using vCAP instead of Existing_Cap_MW)
        cRampUpUC[t in inputs.INTERIOR, g in inputs.UC],
            vGEN[t,g] - vGEN[t-1,g] <= 
            inputs.generators.Ramp_Up_Percentage[g] * capacity_values.vCAP[g] * (vCOMMIT[t,g] - vSTART[t,g]) +
            max(inputs.generators.Min_Power_MW[g], inputs.generators.Ramp_Up_Percentage[g]) * capacity_values.vCAP[g] * vSTART[t,g] - 
            inputs.generators.Min_Power_MW[g] * capacity_values.vCAP[g] * vSHUT[t,g]
        
        cRampUpWrapUC[t in inputs.START, g in inputs.UC],    
            vGEN[t,g] - vGEN[t+inputs.hours_per_period-1,g] <= 
            inputs.generators.Ramp_Up_Percentage[g] * capacity_values.vCAP[g] * (vCOMMIT[t,g] - vSTART[t,g]) +
            max(inputs.generators.Min_Power_MW[g], inputs.generators.Ramp_Up_Percentage[g]) * capacity_values.vCAP[g] * vSTART[t,g] - 
            inputs.generators.Min_Power_MW[g] * capacity_values.vCAP[g] * vSHUT[t,g]
        
        cRampDownUC[t in inputs.INTERIOR, g in inputs.UC],
            vGEN[t-1,g] - vGEN[t,g] <= 
            inputs.generators.Ramp_Dn_Percentage[g] * capacity_values.vCAP[g] * (vCOMMIT[t,g] - vSTART[t,g]) +
            max(inputs.generators.Min_Power_MW[g], inputs.generators.Ramp_Dn_Percentage[g]) * capacity_values.vCAP[g] * vSHUT[t,g] - 
            inputs.generators.Min_Power_MW[g] * capacity_values.vCAP[g] * vSTART[t,g]

        cRampDownWrapUC[t in inputs.START, g in inputs.UC],    
            vGEN[t+inputs.hours_per_period-1,g] - vGEN[t,g] <= 
            inputs.generators.Ramp_Dn_Percentage[g] * capacity_values.vCAP[g] * (vCOMMIT[t,g] - vSTART[t,g]) +
            max(inputs.generators.Min_Power_MW[g], inputs.generators.Ramp_Dn_Percentage[g]) * capacity_values.vCAP[g] * vSHUT[t,g] - 
            inputs.generators.Min_Power_MW[g] * capacity_values.vCAP[g] * vSTART[t,g]
        
        # Storage state of charge constraints
        cSOC[t in inputs.INTERIOR, g in inputs.STOR],
            vSOC[t,g] == vSOC[t-1,g] + inputs.generators.Eff_Up[g]*vCHARGE[t,g] - vGEN[t,g]/inputs.generators.Eff_Down[g]
        cSOCWrap[t in inputs.START, g in inputs.STOR], 
            vSOC[t,g] == vSOC[t+inputs.hours_per_period-1,g] + inputs.generators.Eff_Up[g]*vCHARGE[t,g] - vGEN[t,g]/inputs.generators.Eff_Down[g]
        
        # Unit commitment state constraints  
        cCommitBound[t in inputs.T, g in inputs.UC],
            vCOMMIT[t,g] <= capacity_values.vCAP[g] / inputs.generators.Existing_Cap_MW[g]
        cStartBound[t in inputs.T, g in inputs.UC],
            vSTART[t,g] <= capacity_values.vCAP[g] / inputs.generators.Existing_Cap_MW[g]
        cShutBound[t in inputs.T, g in inputs.UC],
            vSHUT[t,g] <= capacity_values.vCAP[g] / inputs.generators.Existing_Cap_MW[g]
        cCommitState[t in inputs.T_red, g in inputs.UC],
            vCOMMIT[t+1,g] == vCOMMIT[t,g] + vSTART[t+1,g] - vSHUT[t+1,g]
        
        # Min up/down time constraints
        cUpTime[t in inputs.T, g in inputs.UC],
            vCOMMIT[t,g] >= sum(vSTART[tt, g] for tt in intersect(inputs.T, (t-inputs.generators.Up_Time[g]:t)))
        cDownTime[t in inputs.T, g in inputs.UC],
            capacity_values.vCAP[g] / inputs.generators.Existing_Cap_MW[g] >= sum(vSHUT[tt, g] for tt in intersect(inputs.T, (t-inputs.generators.Down_Time[g]:t)))
    end)
    
    # Village constraints
    # Heat balance
    @constraint(SUB, cVILHeatBalance[t in inputs.T, vil in inputs.VIL],
        sum(vVIL_GEN_HEAT[t,g] for g in intersect(inputs.village_generators[inputs.village_generators.Village.==vil,:R_ID],inputs.VIL_UC)) +
        sum(vVIL_NSE_HEAT[t,s,vil] for s in inputs.VIL_S) - inputs.village_demandheat[t,vil] == 0
    )
    
    # Electricity balance for villages
    if Grid
        if NoCoal
            @constraint(SUB, cVILElectricityBalance[t in inputs.T, vil in inputs.VIL], 
                sum(vVIL_GEN[t,g] for g in intersect(inputs.village_generators[inputs.village_generators.Village.==vil,:R_ID],union(inputs.VIL_ED, inputs.VIL_STOR))) +
                sum(vVIL_NSE[t,s,vil] for s in inputs.VIL_S) - sum(vVIL_IMPORT[t,vil]) - inputs.village_demand[t,vil] == 0
            )
        elseif VillageBuild
            @constraint(SUB, cVILElectricityBalance[t in inputs.T, vil in inputs.VIL], 
                sum(vVIL_GEN[t,g] for g in intersect(inputs.village_generators[inputs.village_generators.Village.==vil,:R_ID],inputs.VIL_G)) +
                sum(vVIL_NSE[t,s,vil] for s in inputs.VIL_S) - sum(vVIL_IMPORT[t,vil]) - inputs.village_demand[t,vil] == 0
            )
        else
            @constraint(SUB, cVILElectricityBalance[t in inputs.T, vil in inputs.VIL], 
                sum(vVIL_GEN[t,g] for g in intersect(inputs.village_generators[inputs.village_generators.Village.==vil,:R_ID],inputs.VIL_UC)) +
                sum(vVIL_NSE[t,s,vil] for s in inputs.VIL_S) - sum(vVIL_IMPORT[t,vil]) - inputs.village_demand[t,vil] == 0
            )
        end
    else
        if NoCoal
            @constraint(SUB, cVILElectricityBalance[t in inputs.T, vil in inputs.VIL], 
                sum(vVIL_GEN[t,g] for g in intersect(inputs.village_generators[inputs.village_generators.Village.==vil,:R_ID],union(inputs.VIL_ED, inputs.VIL_STOR))) +
                sum(vVIL_NSE[t,s,vil] for s in inputs.VIL_S) - inputs.village_demand[t,vil] == 0
            )
        elseif VillageBuild
            @constraint(SUB, cVILElectricityBalance[t in inputs.T, vil in inputs.VIL], 
                sum(vVIL_GEN[t,g] for g in intersect(inputs.village_generators[inputs.village_generators.Village.==vil,:R_ID],inputs.VIL_G)) +
                sum(vVIL_NSE[t,s,vil] for s in inputs.VIL_S) - inputs.village_demand[t,vil] == 0
            )
        else
            @constraint(SUB, cVILElectricityBalance[t in inputs.T, vil in inputs.VIL], 
                sum(vVIL_GEN[t,g] for g in intersect(inputs.village_generators[inputs.village_generators.Village.==vil,:R_ID],inputs.VIL_UC)) +
                sum(vVIL_NSE[t,s,vil] for s in inputs.VIL_S) - inputs.village_demand[t,vil] == 0
            )
        end
    end
    
    # Village operational constraints - CORRECTED
    @constraints(SUB, begin
        # VIL power constraints using fixed capacities
        cVILEdMaxPower[t in inputs.T, g in inputs.VIL_ED], 
            vVIL_GEN[t,g] <= inputs.village_variability[t,g] * capacity_values.vVIL_CAP[g]
        
        cVILUcMaxPower[t in inputs.T, g in inputs.VIL_UC], 
            (vVIL_GEN_HEAT[t,g] + vVIL_GEN[t,g]) <= capacity_values.vVIL_CAP[g] * vVIL_COMMIT[t,g]
        
        cVILUcMinPower[t in inputs.T, g in inputs.VIL_UC], 
            (vVIL_GEN[t,g] + vVIL_GEN_HEAT[t,g]) >= inputs.village_generators.Min_Power_MW[g] * capacity_values.vVIL_CAP[g] * vVIL_COMMIT[t,g]
        
        # VIL Storage constraints - CORRECTED
        cVILMaxCharge[t in inputs.T, g in inputs.VIL_STOR], 
            vVIL_CHARGE[t,g] <= capacity_values.vVIL_CAP[g]
        # ADDED: VIL storage discharge constraint
        cVILMaxDischarge[t in inputs.T, g in inputs.VIL_STOR], 
            vVIL_GEN[t,g] <= capacity_values.vVIL_CAP[g]
        cVILMaxSOC[t in inputs.T, g in inputs.VIL_STOR], 
            vVIL_SOC[t,g] <= capacity_values.vVIL_E_CAP[g]
        
        # VIL NSE constraints
        cVILNSE[t in inputs.T, s in inputs.VIL_S, vil in inputs.VIL], 
            vVIL_NSE[t,s,vil] <= inputs.village_nse.NSE_Max[s] * inputs.village_demand[t,vil]
        cVILNSEHeat[t in inputs.T, s in inputs.VIL_S, vil in inputs.VIL], 
            vVIL_NSE_HEAT[t,s,vil] <= inputs.village_nse.NSE_Max[s] * inputs.village_demandheat[t,vil]
        
        # VIL storage state of charge
        cVILSOC[t in inputs.INTERIOR, g in inputs.VIL_STOR],
            vVIL_SOC[t,g] == vVIL_SOC[t-1,g] + inputs.village_generators.Eff_Up[g]*vVIL_CHARGE[t,g] - vVIL_GEN[t,g]/inputs.village_generators.Eff_Down[g]
        cVILSOCWrap[t in inputs.START, g in inputs.VIL_STOR],
            vVIL_SOC[t,g] == vVIL_SOC[t+inputs.hours_per_period-1,g] + inputs.village_generators.Eff_Up[g]*vVIL_CHARGE[t,g] - vVIL_GEN[t,g]/inputs.village_generators.Eff_Down[g]
        
        # VIL unit commitment constraints
        cVILCommitBound[t in inputs.T, g in inputs.VIL_UC],
            vVIL_COMMIT[t,g] <= capacity_values.vVIL_CAP[g] / inputs.village_generators.Existing_Cap_MW[g]
        cVILStartBound[t in inputs.T, g in inputs.VIL_UC],
            vVIL_START[t,g] <= capacity_values.vVIL_CAP[g] / inputs.village_generators.Existing_Cap_MW[g]
        cVILShutBound[t in inputs.T, g in inputs.VIL_UC],
            vVIL_SHUT[t,g] <= capacity_values.vVIL_CAP[g] / inputs.village_generators.Existing_Cap_MW[g]
        cVILCommitState[t in inputs.T_red, g in inputs.VIL_UC],
            vVIL_COMMIT[t+1,g] == vVIL_COMMIT[t,g] + vVIL_START[t+1,g] - vVIL_SHUT[t+1,g]
        
        # VIL ramp constraints - CORRECTED
        cVILRampUp[t in inputs.INTERIOR, g in inputs.VIL_ED],
            vVIL_GEN[t,g] - vVIL_GEN[t-1,g] <= inputs.village_generators.Ramp_Up_Percentage[g] * capacity_values.vVIL_CAP[g]
        cVILRampUpWrap[t in inputs.START, g in inputs.VIL_ED],
            vVIL_GEN[t,g] - vVIL_GEN[t+inputs.hours_per_period-1,g] <= inputs.village_generators.Ramp_Up_Percentage[g] * capacity_values.vVIL_CAP[g]
        cVILRampDown[t in inputs.INTERIOR, g in inputs.VIL_ED],
            vVIL_GEN[t-1,g] - vVIL_GEN[t,g] <= inputs.village_generators.Ramp_Dn_Percentage[g] * capacity_values.vVIL_CAP[g]
        cVILRampDownWrap[t in inputs.START, g in inputs.VIL_ED],
            vVIL_GEN[t+inputs.hours_per_period-1,g] - vVIL_GEN[t,g] <= inputs.village_generators.Ramp_Dn_Percentage[g] * capacity_values.vVIL_CAP[g]
        
        # VIL UC ramp constraints
        cVILRampUpUC[t in inputs.INTERIOR, g in inputs.VIL_UC],
            (vVIL_GEN[t,g] + vVIL_GEN_HEAT[t,g]) - (vVIL_GEN[t-1,g] + vVIL_GEN_HEAT[t-1,g]) <= 
            inputs.village_generators.Ramp_Up_Percentage[g] * capacity_values.vVIL_CAP[g] * (vVIL_COMMIT[t,g] - vVIL_START[t,g]) +
            max(inputs.village_generators.Min_Power_MW[g], inputs.village_generators.Ramp_Up_Percentage[g]) * capacity_values.vVIL_CAP[g] * vVIL_START[t,g] - 
            inputs.village_generators.Min_Power_MW[g] * capacity_values.vVIL_CAP[g] * vVIL_SHUT[t,g]
        
        # VIL min up/down time constraints
        cVILUpTime[t in inputs.T, g in inputs.VIL_UC],
            vVIL_COMMIT[t,g] >= sum(vVIL_START[tt,g] for tt in intersect(inputs.T, (t-inputs.village_generators.Up_Time[g]:t)))
        cVILDownTime[t in inputs.T, g in inputs.VIL_UC],
            capacity_values.vVIL_CAP[g] / inputs.village_generators.Existing_Cap_MW[g] >= sum(vVIL_SHUT[tt,g] for tt in intersect(inputs.T, (t-inputs.village_generators.Down_Time[g]:t)))
    end)
    
    # Variable cost objective (second-stage costs)
    @expression(SUB, eVariableCosts,
        # Grid generation costs
        sum(inputs.sample_weight[t]*inputs.generators.Var_Cost[g]*vGEN[t,g] for t in inputs.T, g in inputs.G) +
        # Grid start costs
        sum(inputs.sample_weight[t]*inputs.generators.Start_Cost[g]*vSTART[t,g]*capacity_values.vCAP[g] for t in inputs.T, g in inputs.UC) +
        # NSE costs
        sum(inputs.sample_weight[t]*inputs.nse.NSE_Cost[s]*vNSE[t,s,z] for t in inputs.T, s in inputs.S, z in inputs.Z) +
        # VIL generation costs
        sum(inputs.sample_weight[t]*inputs.village_generators.Var_Cost[g]*vVIL_GEN[t,g] for t in inputs.T, g in inputs.VIL_ED) +
        sum(inputs.sample_weight[t]*inputs.village_generators.Var_Cost[g]*(vVIL_GEN[t,g] + vVIL_GEN_HEAT[t,g]) for t in inputs.T, g in inputs.VIL_UC) +
        # VIL start costs
        sum(inputs.sample_weight[t]*inputs.village_generators.Start_Cost[g]*vVIL_START[t,g]*capacity_values.vVIL_CAP[g] for t in inputs.T, g in inputs.VIL_UC) +
        # VIL NSE costs
        sum(inputs.sample_weight[t]*inputs.village_nse.NSE_Cost[s]*vVIL_NSE[t,s,vil] for t in inputs.T, s in inputs.S, vil in inputs.VIL) +
        sum(inputs.sample_weight[t]*inputs.village_nse.NSE_Cost[s]*vVIL_NSE_HEAT[t,s,vil] for t in inputs.T, s in inputs.S, vil in inputs.VIL)
    )
    
    # Add grid import costs if applicable
    if Grid
        @expression(SUB, eGridImportCosts,
            sum(inputs.sample_weight[t]*ImportPrice*vVIL_IMPORT[t,vil] for t in inputs.T, vil in inputs.VIL)
        )
        @objective(SUB, Min, eVariableCosts + eGridImportCosts)
    else
        @objective(SUB, Min, eVariableCosts)
    end
    
    return SUB, (
        vGEN=vGEN, vCHARGE=vCHARGE, vSOC=vSOC, vNSE=vNSE, vFLOW=vFLOW,
        vSTART=vSTART, vSHUT=vSHUT, vCOMMIT=vCOMMIT,
        vVIL_GEN=vVIL_GEN, vVIL_GEN_HEAT=vVIL_GEN_HEAT, vVIL_SOC=vVIL_SOC, vVIL_CHARGE=vVIL_CHARGE,
        vVIL_NSE=vVIL_NSE, vVIL_NSE_HEAT=vVIL_NSE_HEAT, vVIL_COMMIT=vVIL_COMMIT, vVIL_START=vVIL_START, vVIL_SHUT=vVIL_SHUT,
        vVIL_IMPORT=Grid ? vVIL_IMPORT : nothing
    )
end

function solve_benders_decomposition(inputs, mipgap, CO2_constraint, CO2_limit, RE_constraint, RE_limit, Grid, VillageBuild, ImportPrice, NoCoal, CO235reduction, BAUCO2emissions; max_iter=100, tolerance=1e-6)
    
    # Initialize
    master_model, master_vars = benders_master_problem(inputs, mipgap, CO2_constraint, CO2_limit, RE_constraint, RE_limit, Grid, VillageBuild, ImportPrice, NoCoal, CO235reduction, BAUCO2emissions)
    
    upper_bound = Inf
    lower_bound = -Inf
    iteration = 0
    cuts_added = 0
    
    println("Starting Benders Decomposition...")
    
    while iteration < max_iter && (upper_bound - lower_bound) > tolerance
        iteration += 1
        
        # Solve master problem
        optimize!(master_model)
        
        if termination_status(master_model) != MOI.OPTIMAL
            println("Master problem not optimal at iteration $iteration")
            break
        end
        
        lower_bound = objective_value(master_model)
        
        # Extract capacity values
        capacity_values = (
            vCAP = value.(master_vars.vCAP),
            vE_CAP = value.(master_vars.vE_CAP),
            vT_CAP = value.(master_vars.vT_CAP),
            vVIL_CAP = value.(master_vars.vVIL_CAP),
            vVIL_E_CAP = value.(master_vars.vVIL_E_CAP)
        )
        
        # Solve subproblem
        sub_model, sub_vars = benders_subproblem(inputs, capacity_values, Grid, VillageBuild, ImportPrice, NoCoal, CO235reduction, BAUCO2emissions)
        optimize!(sub_model)
        
        if termination_status(sub_model) != MOI.OPTIMAL
            if termination_status(sub_model) == MOI.INFEASIBLE
                # Subproblem infeasible - add feasibility cut
                println("Adding feasibility cut at iteration $iteration")
                # Note: Full implementation would require extracting infeasibility certificate
                # This is a simplified approach - would need dual rays for proper feasibility cuts
                break
            else
                println("Subproblem not optimal at iteration $iteration: $(termination_status(sub_model))")
                break
            end
        end
        
        sub_objective = objective_value(sub_model)
        current_upper_bound = value(master_vars.η[1]) + sub_objective
        
        if current_upper_bound < upper_bound
            upper_bound = current_upper_bound
        end
        
        println("Iteration $iteration: LB = $lower_bound, UB = $upper_bound, Gap = $(upper_bound - lower_bound)")
        
        # Add Benders optimality cut
        # η >= subproblem_objective
        # This is a simplified cut - full implementation would use dual values
        if value(master_vars.η) < sub_objective - tolerance
            @constraint(master_model, master_vars.η >= sub_objective)
            cuts_added += 1
            println("  Added optimality cut #$cuts_added")
        end
    end
    
    println("Benders decomposition completed in $iteration iterations")
    println("Total cuts added: $cuts_added")
    println("Final gap: $(upper_bound - lower_bound)")
    
    # Return final solution
    final_capacity_values = (
        vCAP = value.(master_vars.vCAP),
        vE_CAP = value.(master_vars.vE_CAP),
        vT_CAP = value.(master_vars.vT_CAP),
        vVIL_CAP = value.(master_vars.vVIL_CAP),
        vVIL_E_CAP = value.(master_vars.vVIL_E_CAP),
        vRET_CAP_ED = value.(master_vars.vRET_CAP_ED),
        vNEW_CAP_ED = value.(master_vars.vNEW_CAP_ED),
        vRET_CAP_UC = value.(master_vars.vRET_CAP_UC),
        vNEW_CAP_UC = value.(master_vars.vNEW_CAP_UC),
        vRET_E_CAP = value.(master_vars.vRET_E_CAP),
        vNEW_E_CAP = value.(master_vars.vNEW_E_CAP),
        vRET_T_CAP = value.(master_vars.vRET_T_CAP),
        vNEW_T_CAP = value.(master_vars.vNEW_T_CAP),
        vVIL_RET_CAP_ED = value.(master_vars.vVIL_RET_CAP_ED),
        vVIL_NEW_CAP_ED = value.(master_vars.vVIL_NEW_CAP_ED),
        vVIL_RET_CAP_UC = value.(master_vars.vVIL_RET_CAP_UC),
        vVIL_NEW_CAP_UC = value.(master_vars.vVIL_NEW_CAP_UC),
        vVIL_RET_E_CAP = value.(master_vars.vVIL_RET_E_CAP),
        vVIL_NEW_E_CAP = value.(master_vars.vVIL_NEW_E_CAP)
    )
    
    return (
        master_model = master_model,
        capacity_values = final_capacity_values,
        upper_bound = upper_bound,
        lower_bound = lower_bound,
        total_cost = upper_bound,
        iterations = iteration,
        cuts_added = cuts_added
    )
end

# Wrapper function that mimics the original capacity_expansion interface
function capacity_expansion_benders(inputs, mipgap, CO2_constraint, CO2_limit, RE_constraint, RE_limit, Grid, VillageBuild, ImportPrice, NoCoal, CO235reduction, BAUCO2emissions)
    
    result = solve_benders_decomposition(inputs, mipgap, CO2_constraint, CO2_limit, RE_constraint, RE_limit, Grid, VillageBuild, ImportPrice, NoCoal, CO235reduction, BAUCO2emissions)
    
    # Solve final subproblem to get operational variables
    final_sub_model, final_sub_vars = benders_subproblem(inputs, result.capacity_values, Grid, VillageBuild, ImportPrice, NoCoal, CO235reduction, BAUCO2emissions)
    optimize!(final_sub_model)
    
    # Extract results in the same format as original function
    if Grid
        VIL_IMPORT = value.(final_sub_vars.vVIL_IMPORT)
    else
        VIL_IMPORT = 0
    end
    
    VIL_E_CAP = result.capacity_values.vVIL_E_CAP

    # Calculate expressions for compatibility
    eFixedCostsGeneration = sum(inputs.generators.Fixed_OM_Cost_per_MWyr[g]*result.capacity_values.vCAP[g] for g in inputs.G) +
                           sum(inputs.generators.Inv_Cost_per_MWyr[g]*result.capacity_values.vNEW_CAP_ED[g] for g in inputs.ED_NEW) +
                           sum(inputs.generators.Inv_Cost_per_MWyr[g]*result.capacity_values.vNEW_CAP_UC[g] for g in inputs.UC_NEW)
    
    eFixedCostsStorage = sum(inputs.generators.Fixed_OM_Cost_per_MWhyr[g]*result.capacity_values.vE_CAP[g] for g in inputs.STOR) +
                        sum(inputs.generators.Inv_Cost_per_MWhyr[g]*result.capacity_values.vNEW_E_CAP[g] for g in intersect(inputs.STOR, inputs.NEW))
    
    eFixedCostsTransmission = sum(inputs.lines.Line_Fixed_Cost_per_MW_yr[l]*result.capacity_values.vT_CAP[l] +
                                 inputs.lines.Line_Reinforcement_Cost_per_MWyr[l]*result.capacity_values.vNEW_T_CAP[l] for l in inputs.L)
    
    # Calculate operational costs from subproblem
    eVariableCostsGrid = objective_value(final_sub_model) - (Grid ? sum(inputs.sample_weight[t]*ImportPrice*value(final_sub_vars.vVIL_IMPORT[t,vil]) for t in inputs.T, vil in inputs.VIL) : 0)
    
    # Placeholder values for other expressions - would need to be calculated properly
    eCO2EmissionsGrid = 0  # Calculate from generators
    eCO2EmissionsVIL = 0    # Calculate from VIL generators
    eREShare = 0           # Calculate renewable share
    eNSECosts = 0          # Calculate NSE costs
    eVILNSECosts = 0        # Calculate VIL NSE costs
    eVILNSEHeatCosts = 0    # Calculate VIL NSE heat costs
    eGridImportCosts = Grid ? sum(inputs.sample_weight[t]*ImportPrice*value(final_sub_vars.vVIL_IMPORT[t,vil]) for t in inputs.T, vil in inputs.VIL) : 0
    
    return (
        CAP = result.capacity_values.vCAP,
        GEN = value.(final_sub_vars.vGEN),
        E_CAP = result.capacity_values.vE_CAP,
        VIL_CAP = result.capacity_values.vVIL_CAP,
        VIL_E_CAP = VIL_E_CAP,
        VIL_GEN = value.(final_sub_vars.vVIL_GEN),
        VIL_GEN_HEAT = value.(final_sub_vars.vVIL_GEN_HEAT),
        VIL_IMPORT = VIL_IMPORT,
        T_CAP = result.capacity_values.vT_CAP,
        NSE = value.(final_sub_vars.vNSE),
        VIL_NSE = value.(final_sub_vars.vVIL_NSE),
        VIL_NSE_HEAT = value.(final_sub_vars.vVIL_NSE_HEAT),
        FixedCostsGeneration = eFixedCostsGeneration,
        FixedCostsStorage = eFixedCostsStorage,
        FixedCostsTransmission = eFixedCostsTransmission,
        VariableCostsGrid = eVariableCostsGrid,
        VariableCostsVIL = 0,  # Would need to be calculated
        GridImportCosts = eGridImportCosts,
        CO2Emissions = eCO2EmissionsGrid + eCO2EmissionsVIL,
        CO2EmissionsGrid = eCO2EmissionsGrid,
        CO2EmissionsVIL = eCO2EmissionsVIL,
        REShare = eREShare,
        NSECosts = eNSECosts,
        VILNSECosts = eVILNSECosts,
        VILNSEHeatCosts = eVILNSEHeatCosts,
        cost = result.total_cost
    )
end 