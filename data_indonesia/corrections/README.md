# Input corrections

These are corrections to the industrial-park inputs. Each one has the script that applied it
and a log here. The decision numbers (D1, D4, D11) refer to the Earthwise refresh pipeline
design (`pipeline/DESIGN.md` on branch `earthwise-pipeline`). Together these are one flagged,
results-changing change, so runs from before it are not comparable with runs after it.

| Decision | What changed | Applied by | Log |
|---|---|---|---|
| D1 | The park new-build `Max_Cap_MW` bounds are restored in `functions/optimizer.jl`. The renewable candidates are now limited to their assessed potential, and park batteries to 100 MW (their `Max_Cap_MW`). `Max_Cap_MW` ≤ 0 still means unbounded, as for grid units. | code | this commit |
| D4 | `jawa_bali/ip_generators_variability.csv` (2030 and 2035) is rebuilt with one column per IP generator, named by `Resource`. Its columns used to be named by province, so no generator matched and all of them, solar included, ran at a flat 1.0. Solar now takes its province's solar profile from the old file; coal, geothermal and batteries take 1.0. | `scripts/fix_jawa_bali_ip_profiles.py` | the diff (2 files) |
| D11 | Solar class 2.5 candidates are scaled by 15. The QGIS assessment used 4 MW/km² (the wind density) instead of 60 for that class only. A capacity column is scaled only if its value is one of the QGIS solar 2.5 figures. | `scripts/fix_solar_class_2_5.py` | `d11_solar_class_2_5.csv` (108 rows) |
| Costs (2035 Sulawesi) | `Inv_Cost_per_MWyr` and `Inv_Cost_per_MWhyr` held overnight capex but enter a one-year objective. Both are multiplied by the capital recovery factor at 10 % WACC over each technology's lifetime (solar, wind, biomass, biogas, trash 25 y; geothermal, gas, CCGT 30 y; hydro 50 y; diesel 20 y; battery 15 y). Batteries get a power cost of 150,000 $/MW overnight. Existing-only coal and coal_captive rows and `network.csv` (already annual, flat 35,178 $/MW-yr) are unchanged. Only Sulawesi 2035 so far. | `scripts/annualize_costs.py` | `annualized_costs_2035_sulawesi.csv` (426 rows) |

## Known data errors left as they are (D5)

- **PT Kutai Refinery Nusantara** (Kalimantan, R_ID 38–47). `Max_Cap_MW` holds one copied
  value on every solar row (7,523.6 MW, PT Borneo Alumina's solar class 3) and on every
  geothermal row (3,134.8 MW). The park's own figures are in `Existing_Cap_MW`. D11 corrected
  only `Existing_Cap_MW` of its solar 2.5 row, so the bound the model uses is still the copied
  value.
- **BP Berau** (Papua, R_ID 10–15). `Max_Cap_MW` holds Amamapare's figures, and
  `Existing_Cap_MW` holds other values (e.g. 1.26 TW of class-1 solar).
- **Punagaya wind class 2.5** (Sulawesi, R_ID 165 in 2030, 124 in 2035) has `Max_Cap_MW` 0.
  Under the "≤ 0 is unbounded" rule, this candidate has no limit. It costs $1.28 M/MW-yr and
  its profile has a 2.6 % capacity factor, so building it is never economic.
