#!/usr/bin/env python3
"""Generate the synthetic Timor village-DRE demo dataset.

Writes data_indonesia/2030/timor_demo/ — a small, fully synthetic but
NTT-plausible test case for the village solar program:

- Grid side: a stylised two-zone Timor system (z1 = Kupang area, z2 = the
  Soe/Kefamenanu interior) with coal, gas-engine, and diesel units plus
  utility-scale solar and battery candidates (~132 MW existing, ~71 MW peak).
- Village side: four off-grid village clusters, each with an existing diesel
  genset and candidate solar PV + battery storage, evening-peak loads in the
  0.05-0.15 MW range, zero heat demand.

The numbers are deliberately round and documented inline; they are intended
for testing the model and training, not for policy results. Re-run this
script to regenerate the folder from scratch:

    python3 tools/make_timor_demo.py
"""

import csv
import math
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data_indonesia" / "2030" / "timor_demo"

# ---------------------------------------------------------------- time setup
REP_PERIODS = 8
HOURS_PER_PERIOD = 168
T = REP_PERIODS * HOURS_PER_PERIOD  # 1344
SUB_WEIGHT = 8760 // REP_PERIODS    # 1095, uniform weights
CORRESPONDING_WEEKS = [2, 9, 16, 24, 32, 40, 46, 52]

# weekly scaling factors (mild seasonality; NTT dry season = better solar)
DEMAND_WEEK_FACTOR = [1.00, 0.97, 0.95, 1.02, 1.05, 0.98, 1.00, 1.03]
SOLAR_WEEK_FACTOR = [1.05, 1.00, 0.95, 0.90, 1.00, 1.05, 1.10, 1.00]

# hour-of-day shapes (fraction of peak)
GRID_SHAPE = [0.68, 0.67, 0.66, 0.66, 0.67, 0.70, 0.75, 0.80, 0.82, 0.84,
              0.85, 0.86, 0.85, 0.84, 0.83, 0.85, 0.90, 0.96, 1.00, 0.98,
              0.95, 0.88, 0.80, 0.72]
# village: lighting/TV evening peak, modest daytime productive use
VILLAGE_SHAPE = [0.25, 0.22, 0.20, 0.20, 0.22, 0.30, 0.45, 0.50, 0.55, 0.60,
                 0.62, 0.60, 0.58, 0.55, 0.50, 0.45, 0.50, 0.80, 1.00, 0.95,
                 0.80, 0.60, 0.40, 0.30]

GRID_PEAK = {"z1": 55.0, "z2": 16.0}            # MW, ~71 MW system peak
VILLAGE_PEAK = [0.12, 0.08, 0.05, 0.15]          # MW per village cluster


def hod(t):
    """hour of day 0-23 for 1-based hour index t"""
    return (t - 1) % 24


def week(t):
    """representative week 0-7 for 1-based hour index t"""
    return (t - 1) // HOURS_PER_PERIOD


def solar_cf(t):
    h = hod(t)
    if 6 <= h <= 18:
        base = math.sin(math.pi * (h - 6) / 12) ** 1.3
        return round(min(1.0, 0.85 * base * SOLAR_WEEK_FACTOR[week(t)]), 4)
    return 0.0


def grid_demand(zone, t):
    return round(GRID_PEAK[zone] * GRID_SHAPE[hod(t)] * DEMAND_WEEK_FACTOR[week(t)], 3)


def village_demand(v, t):
    return round(VILLAGE_PEAK[v] * VILLAGE_SHAPE[hod(t)] * DEMAND_WEEK_FACTOR[week(t)], 5)


# ------------------------------------------------------------- generator data
GEN_COLS = ["R_ID", "Zone", "Resource", "technology", "owner",
            "Existing_Cap_MW", "Existing_Cap_MWh", "New_Build", "Max_Cap_MW",
            "Inv_Cost_per_MWyr", "Inv_Cost_per_MWhyr",
            "Fixed_OM_Cost_per_MWyr", "Fixed_OM_Cost_per_MWhyr",
            "Var_OM_Cost_per_MWh", "Min_Power_MW",
            "Ramp_Up_Percentage", "Ramp_Dn_Percentage", "Commit",
            "Start_Cost_per_MW", "Start_Fuel_MMBTU_per_MW",
            "Heat_Rate_MMBTU_per_MWh", "Fuel", "Up_Time", "Down_Time",
            "Eff_Up", "Eff_Down", "STOR", "VRE", "RE", "THERM"]


def thermal(rid, zone, name, tech, cap, fuel, hr, min_p, ramp, fom, vom,
            start_cost, start_fuel, up, down, owner="pln"):
    return [rid, zone, name, tech, owner, cap, 0, 0, 0,
            0, 0, fom, 0, vom, min_p, ramp, ramp, 1,
            start_cost, start_fuel, hr, fuel, up, down, 1, 1, 0, 0, 0, 1]


def solar(rid, zone, name, cap, new, max_cap, inv, owner="pln"):
    return [rid, zone, name, "solar", owner, cap, 0, new, max_cap,
            inv, 0, 9000, 0, 0, 0, 1, 1, 0,
            0, 0, 0, "None", 0, 0, 1, 1, 0, 1, 1, 0]


def battery(rid, zone, name, new, max_cap, inv_mw, inv_mwh, owner="pln"):
    return [rid, zone, name, "battery", owner, 0, 0, new, max_cap,
            inv_mw, inv_mwh, 5000, 2000, 1, 0, 1, 1, 0,
            0, 0, 0, "None", 0, 0, 0.92, 0.92, 1, 0, 0, 0]


GRID_GENS = [
    thermal(1, 1, "pltu_bolok_1", "coal", 16.5, "coal", 10.5, 0.4, 0.3, 40000, 4, 60, 1.5, 8, 8),
    thermal(2, 1, "pltu_bolok_2", "coal", 16.5, "coal", 10.5, 0.4, 0.3, 40000, 4, 60, 1.5, 8, 8),
    thermal(3, 1, "pltmg_kupang_peaker", "gas", 40.0, "gas", 7.8, 0.3, 1.0, 25000, 5, 30, 0.5, 2, 2),
    thermal(4, 1, "pltd_tenau", "diesel", 30.0, "diesel", 9.5, 0.3, 1.0, 15000, 6, 20, 0.3, 1, 1),
    thermal(5, 1, "pltd_kuanino", "diesel", 10.0, "diesel", 9.5, 0.3, 1.0, 15000, 6, 20, 0.3, 1, 1),
    thermal(6, 2, "pltd_soe", "diesel", 8.0, "diesel", 9.8, 0.3, 1.0, 15000, 6, 20, 0.3, 1, 1),
    thermal(7, 2, "pltd_kefamenanu", "diesel", 6.0, "diesel", 9.8, 0.3, 1.0, 15000, 6, 20, 0.3, 1, 1),
    solar(8, 1, "plts_kupang", 5.0, 0, 0, 0),
    solar(9, 1, "plts_candidate_kupang", 0.0, 1, 50, 65000),
    solar(10, 2, "plts_candidate_soe", 0.0, 1, 20, 65000),
    battery(11, 1, "batt_candidate_kupang", 1, 20, 25000, 15000),
    battery(12, 2, "batt_candidate_soe", 1, 10, 25000, 15000),
]

# villages: 1 amfoang, 2 boking, 3 raijua, 4 wini — all in zone 2
VILLAGES = ["amfoang", "boking", "raijua", "wini"]
DIESEL_CAP = [0.40, 0.25, 0.15, 0.50]

VILLAGE_GENS = []
rid = 1
for v, (name, cap) in enumerate(zip(VILLAGES, DIESEL_CAP), start=1):
    d = thermal(rid, 2, f"pltd_{name}", "diesel", cap, "diesel", 10.5,
                0.3, 1.0, 18000, 8, 30, 0.3, 1, 1, owner="village_coop")
    d.insert(2, v)  # Village column goes after Zone
    VILLAGE_GENS.append(d)
    rid += 1
    s = solar(rid, 2, f"plts_{name}", 0.0, 1, 0, 75000, owner="village_coop")
    s.insert(2, v)
    VILLAGE_GENS.append(s)
    rid += 1
    b = battery(rid, 2, f"batt_{name}", 1, 0, 30000, 18000, owner="village_coop")
    b.insert(2, v)
    VILLAGE_GENS.append(b)
    rid += 1

VILLAGE_GEN_COLS = GEN_COLS[:2] + ["Village"] + GEN_COLS[2:]

# NSE segment block (shared by grid and village demand files)
VOLL = 2000
SEGMENTS = [  # (segment, cost multiplier of VOLL, max share of hourly demand)
    (1, 1.0, 1.0),
    (2, 0.9, 0.04),
    (3, 0.55, 0.024),
    (4, 0.2, 0.003),
]


def scalar(rows, i, value):
    """value in first row(s), blank elsewhere"""
    return value if i < rows else ""


def write_csv(path, header, rows):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"wrote {path.relative_to(OUT.parent.parent.parent)} ({len(rows)} rows)")


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    write_csv(OUT / "generators.csv", GEN_COLS, GRID_GENS)
    write_csv(OUT / "village_generators.csv", VILLAGE_GEN_COLS, VILLAGE_GENS)

    write_csv(OUT / "fuels_data.csv",
              ["Fuel", "Cost_per_MMBtu", "CO2_content_tons_per_MMBtu", "fuel_indices"],
              [["None", 0, 0, 1], ["coal", 2.5, 0.0975, 2],
               ["gas", 8.0, 0.0531, 3], ["diesel", 18.0, 0.0732, 4]])

    write_csv(OUT / "network.csv",
              ["r_id", "path_name", "substation_path", "z1", "z2", "voltage_kV",
               "distance_km", "B", "Line_Max_Flow_MW", "Line_Max_Reinforcement_MW",
               "Line_Reinforcement_Cost_per_MWyr"],
              [[1, "kupang_soe", "kupang_soe_70kv", 1, -1, 70, 110, 100, 20, 30, 15000]])

    # grid demand: scalar block + hourly series
    rows = []
    for t in range(1, T + 1):
        i = t - 1
        rows.append([
            scalar(1, i, VOLL),
            scalar(len(SEGMENTS), i, SEGMENTS[i][0] if i < len(SEGMENTS) else ""),
            scalar(len(SEGMENTS), i, SEGMENTS[i][1] if i < len(SEGMENTS) else ""),
            scalar(len(SEGMENTS), i, SEGMENTS[i][2] if i < len(SEGMENTS) else ""),
            scalar(1, i, REP_PERIODS),
            scalar(1, i, HOURS_PER_PERIOD),
            scalar(REP_PERIODS, i, SUB_WEIGHT),
            scalar(REP_PERIODS, i, CORRESPONDING_WEEKS[i] if i < REP_PERIODS else ""),
            t,
            hod(t),
            grid_demand("z1", t),
            grid_demand("z2", t),
        ])
    write_csv(OUT / "demand.csv",
              ["Voll", "Demand_Segment", "Cost_of_Demand_Curtailment_per_MW",
               "Max_Demand_Curtailment", "Rep_Periods", "Timesteps_per_Rep_Period",
               "Sub_Weights", "corresponding_week", "r_id", "hour",
               "demand_z1", "demand_z2"],
              rows)

    # village demand: same segment block, one column per village
    rows = []
    for t in range(1, T + 1):
        i = t - 1
        rows.append([
            scalar(1, i, VOLL),
            scalar(len(SEGMENTS), i, SEGMENTS[i][0] if i < len(SEGMENTS) else ""),
            scalar(len(SEGMENTS), i, SEGMENTS[i][1] if i < len(SEGMENTS) else ""),
            scalar(len(SEGMENTS), i, SEGMENTS[i][2] if i < len(SEGMENTS) else ""),
            t,
            hod(t),
        ] + [village_demand(v, t) for v in range(len(VILLAGES))])
    write_csv(OUT / "village_demand.csv",
              ["Voll", "Demand_Segment", "Cost_of_Demand_Curtailment_per_MW",
               "Max_Demand_Curtailment", "r_id", "hour"] +
              [f"demand_village{v}" for v in range(1, len(VILLAGES) + 1)],
              rows)

    # village heat demand: zeros (electricity-only modelling)
    rows = [[t] + [0] * len(VILLAGES) for t in range(1, T + 1)]
    write_csv(OUT / "village_demandheat.csv",
              ["r_id"] + [f"demand_village{v}" for v in range(1, len(VILLAGES) + 1)],
              rows)

    # variability: profile column g belongs to R_ID g (hour index column is
    # dropped by the loader); solar gets the resource profile, others flat 1.0
    def variability_rows(gens, solar_tech_index):
        out = []
        for t in range(1, T + 1):
            row = [t]
            for g in gens:
                row.append(solar_cf(t) if g[solar_tech_index] == "solar" else 1.0)
            out.append(row)
        return out

    write_csv(OUT / "generators_variability.csv",
              ["r_id"] + [g[2] for g in GRID_GENS],
              variability_rows(GRID_GENS, 3))
    write_csv(OUT / "village_generators_variability.csv",
              ["r_id"] + [g[3] for g in VILLAGE_GENS],
              variability_rows(VILLAGE_GENS, 4))


if __name__ == "__main__":
    main()
