# preflight.jl
#
# Command-line parsing, config validation and the scenario-flag mapping for
# run_model.jl. Everything here runs before the (slow) model build so that a
# bad path, a missing input file or an unusable solver fails fast.

const REQUIRED_CONFIG_KEYS = (
    "island", "year", "scenario", "clean",
    "CO235reduction", "BAUCO2emissions", "CO2_limit",
)

const USAGE = """
Usage:
  julia --project=. run_model.jl [--config <config.json>] [--solver highs|gurobi] [--preflight-only]
  julia --project=. run_model.jl <config.json>

With no --config the driver reads ./config.json (the job-folder convention used
by generate_jobs.py and generate_jobs_local.py). Results are written to
results/<scenario>_<island>_<year>_<clean>[__<run_tag>]/ under the repository root.
"""

function parse_cli_args(args::Vector{String})
    config_path = "config.json"
    solver = nothing
    preflight_only = false
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--config"
            i += 1
            i <= length(args) || error("Missing value after --config\n" * USAGE)
            config_path = args[i]
        elseif a == "--solver"
            i += 1
            i <= length(args) || error("Missing value after --solver\n" * USAGE)
            solver = args[i]
        elseif a == "--preflight-only"
            preflight_only = true
        elseif a in ("-h", "--help")
            println(USAGE)
            exit(0)
        elseif startswith(a, "--")
            error("Unknown argument: $(a)\n" * USAGE)
        else
            config_path = a
        end
        i += 1
    end
    return (config_path = abspath(config_path), solver = solver, preflight_only = preflight_only)
end

function load_config(config_path::AbstractString)
    isfile(config_path) || error("Config file not found: $(config_path)\n" * USAGE)
    cfg = JSON.parsefile(config_path)
    missing_keys = [k for k in REQUIRED_CONFIG_KEYS if !haskey(cfg, k)]
    isempty(missing_keys) ||
        error("Config file $(config_path) is missing required keys: $(join(missing_keys, ", "))")
    return cfg
end

# Scenario name -> model switches. This is the single definition used by every
# run; the names are the ones accepted in the scenario YAML files.
function scenario_settings(scenario::AbstractString)
    if scenario == "base"
        return (Grid = false, Captive = false, ImportPrice = 59.0,        NoCoal = false)
    elseif scenario == "gridcaptive"
        return (Grid = true,  Captive = true,  ImportPrice = 59.0,        NoCoal = false)
    elseif scenario == "grid"
        return (Grid = true,  Captive = false, ImportPrice = 59.0,        NoCoal = false)
    elseif scenario == "captive"
        return (Grid = false, Captive = true,  ImportPrice = 59.0,        NoCoal = false)
    elseif scenario == "highimportprice"
        return (Grid = true,  Captive = true,  ImportPrice = 59.0 * 1.21, NoCoal = false)
    elseif scenario == "nocoal"
        return (Grid = true,  Captive = false, ImportPrice = 59.0,        NoCoal = true)
    end
    error("Unknown scenario: $(scenario). Valid values: base, grid, captive, gridcaptive, highimportprice, nocoal")
end

function clean_settings(clean::AbstractString)
    if clean == "reference"
        return (CO2_constraint = false, RE_constraint = false)
    elseif clean == "clean"
        return (CO2_constraint = true, RE_constraint = true)
    end
    error("Unknown clean flag: $(clean). Valid values: reference, clean")
end

const CORE_INPUT_FILES = ("generators.csv", "demand.csv", "generators_variability.csv", "fuels_data.csv")
const IP_INPUT_FILES   = ("ip_generators.csv", "ip_demand.csv", "ip_demandheat.csv", "ip_generators_variability.csv")

function validate_input_files(inputs_path::AbstractString, flags)
    isdir(inputs_path) || error("Input data directory not found: $(inputs_path)")
    missing_files = [f for f in CORE_INPUT_FILES if !isfile(joinpath(inputs_path, f))]
    isempty(missing_files) ||
        error("Missing required input files in $(inputs_path): $(join(missing_files, ", "))")
    if flags.Captive
        missing_ip = [f for f in IP_INPUT_FILES if !isfile(joinpath(inputs_path, f))]
        isempty(missing_ip) ||
            @warn "Scenario enables captive generation but $(inputs_path) has no $(join(missing_ip, ", ")); the industrial-park layer will be empty."
    end
    if flags.Grid && !isfile(joinpath(inputs_path, "network.csv"))
        @info "No network.csv in $(inputs_path); the grid is treated as a single zone with no transmission lines."
    end
    return nothing
end

function run_preflight(config_path::AbstractString, repo_root::AbstractString; solver::AbstractString)
    cfg = load_config(config_path)
    flags = scenario_settings(String(cfg["scenario"]))
    clean_flags = clean_settings(String(cfg["clean"]))
    inputs_path = joinpath(repo_root, "data_indonesia", String(cfg["year"]), String(cfg["island"]))
    run_tag = strip(String(get(cfg, "run_tag", "")))
    job_name = "$(cfg["scenario"])_$(cfg["island"])_$(cfg["year"])_$(cfg["clean"])" *
               (isempty(run_tag) ? "" : "__$(run_tag)")
    results_dir = joinpath(repo_root, "results", job_name)

    validate_solver(solver)
    validate_input_files(inputs_path, flags)

    return (cfg = cfg, flags = flags, clean_flags = clean_flags,
            inputs_path = inputs_path, results_dir = results_dir,
            job_name = job_name, solver = solver)
end
