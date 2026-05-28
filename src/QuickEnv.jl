module QuickEnv

using Pkg
using TOML

function __init__()
    # 1. Get the absolute path to the current script
    script_path = PROGRAM_FILE
    if isempty(script_path)
        sp = Base.source_path()
        script_path = sp !== nothing ? sp : ""
    end

    # If in interactive REPL, do nothing
    isempty(script_path) && return

    # Ensure path is absolute for directory tracking
    script_path = abspath(script_path)

    # 2. Parse script for package imports, fallback, and exclusions
    required_packages, fallback_env, excluded_envs, script_silent = parse_script_metadata(script_path)
    
    # Exclude QuickEnv itself from dependency matching
    filter!(p -> p != "QuickEnv", required_packages)

    # Resolve global silence (via QUICKENV_SILENT environment variable or script comment)
    env_silent = get(ENV, "QUICKENV_SILENT", "false")
    is_silent = (lowercase(env_silent) == "true") || script_silent

    # 3. Locate all satisfying named environments
    matching = find_matching_envs(required_packages)

    # Filter matching list by exclusions and fallback request rules
    matching = filter_matching_envs(matching, fallback_env, excluded_envs)

    if !isempty(matching)
        # Select the first matching custom environment (excluding standard global ones if any custom exist)
        selected = something(findfirst(env -> !occursin(r"^v\d+\.\d+$", env), matching), 1)
        env_name = matching[selected]
        
        # Activate the matched environment
        current_project = Base.active_project()
        if current_project === nothing || !occursin(env_name, current_project)
            if !is_silent
                @info "QuickEnv: Found matching environment @$env_name. Activating..."
            end
            Pkg.activate(env_name, shared=true, io=is_silent ? devnull : stderr)
        end
    else
        # 4. No matching environment found! Apply fallback logic.
        target_env_display = ""
        
        if !isempty(fallback_env)
            # Use specified named fallback environment
            if !is_silent
                @info "QuickEnv: No matching environment found. Activating fallback @$fallback_env..."
            end
            Pkg.activate(fallback_env, shared=true, io=is_silent ? devnull : stderr)
            target_env_display = "@" * fallback_env
        else
            # Default: Activate local directory environment
            script_dir = dirname(script_path)
            if !is_silent
                @info "QuickEnv: No matching environment found. Activating local environment at $script_dir..."
            end
            Pkg.activate(script_dir, io=is_silent ? devnull : stderr)
            target_env_display = "local directory environment"
        end

        # Bootstrap: Automatically install missing packages in the active environment
        project_file = Base.active_project()
        if project_file !== nothing
            # Safety Check: Prevent adding packages to the global environment
            env_name = basename(dirname(project_file))
            if occursin(r"^v\d+\.\d+$", env_name)
                if !is_silent
                    @warn "QuickEnv: Safety check triggered. Blocked installation of packages into the global environment ($env_name)."
                end
                return
            end

            deps = Dict{String, Any}()
            if isfile(project_file)
                try
                    project_data = TOML.parsefile(project_file)
                    deps = get(project_data, "deps", Dict{String, Any}())
                catch
                    # Ignore parsing errors
                end
            end
            
            missing_pkgs = filter(pkg -> !haskey(deps, pkg), required_packages)
            if !isempty(missing_pkgs)
                if !is_silent
                    @info "QuickEnv: Installing missing packages into $target_env_display: $missing_pkgs"
                end
                Pkg.add(missing_pkgs, io=is_silent ? devnull : stderr)
            end
        end
    end
end

"""
    parse_script_metadata(script_path::String)

Reads a script and extracts required packages, fallback environments, and excluded environments.
"""
function parse_script_metadata(script_path::String)
    packages = String[]
    fallback_env = ""
    excluded_envs = String[]
    is_silent = false
    
    if isfile(script_path)
        for line in eachline(script_path)
            # Check for inline silence comment on the QuickEnv import line
            # e.g., using QuickEnv # Silent
            parts = split(line, '#')
            if length(parts) > 1
                comment_part = strip(parts[2])
                clean_line = strip(parts[1])
                if occursin(r"(?i)silent", comment_part) && occursin(r"\bQuickEnv\b", clean_line)
                    is_silent = true
                end
            end

            # 1. Parse fallback magic comment
            m_fallback = match(r"^\s*#\s*quickenv_fallback\s*:\s*([a-zA-Z0-9_\-]+)", line)
            if m_fallback !== nothing
                fallback_env = String(m_fallback.captures[1])
            end

            # 2. Parse exclude magic comment (comma-separated list of env names or "global")
            m_exclude = match(r"^\s*#\s*quickenv_exclude\s*:\s*(.*)$", line)
            if m_exclude !== nothing
                for item in split(m_exclude.captures[1], ',')
                    push!(excluded_envs, strip(item))
                end
            end

            # 3. Parse silent magic comment (e.g., # quickenv_silent: true)
            m_silent = match(r"^\s*#\s*quickenv_silent\s*:\s*([a-zA-Z0-9_\-]+)", line)
            if m_silent !== nothing
                is_silent = lowercase(strip(m_silent.captures[1])) == "true"
            end

            # 4. Extract package imports
            clean_line = strip(first(split(line, '#')))
            m = match(r"^\s*(using|import)\s+(.*)$", clean_line)
            if m !== nothing
                raw_imports = m.captures[2]
                # In Julia, standard 'using/import Module: item' syntax imports items from a module.
                # The module/package name always appears before the colon.
                pkg_part = first(split(raw_imports, ':'))
                parts = split(pkg_part, ',')
                for part in parts
                    pkg = strip(part)
                    if !isempty(pkg) && isuppercase(first(pkg))
                        pkg_name = first(split(pkg))
                        if !(pkg_name in packages)
                            push!(packages, String(pkg_name))
                        end
                    end
                end
            end
        end
    end
    return packages, fallback_env, excluded_envs, is_silent
end

function find_matching_envs(required_pkgs::Vector{String})
    env_dir = joinpath(DEPOT_PATH[1], "environments")
    !isdir(env_dir) && return String[]
    
    matching_envs = String[]
    for entry in readdir(env_dir)
        path = joinpath(env_dir, entry)
        !isdir(path) && continue
        
        toml_path = joinpath(path, "Project.toml")
        !isfile(toml_path) && continue
        
        try
            project_data = TOML.parsefile(toml_path)
            deps = get(project_data, "deps", Dict{String, Any}())
            if all(pkg -> haskey(deps, pkg), required_pkgs)
                push!(matching_envs, entry)
            end
        catch
            # Ignore malformed TOML
        end
    end
    return sort(matching_envs)
end

"""
    filter_matching_envs(matching::Vector{String}, fallback_env::String, excluded_envs::Vector{String})

Filters a list of matching environments based on forbidden exclusion lists and fallback rules.
"""
function filter_matching_envs(matching::Vector{String}, fallback_env::String, excluded_envs::Vector{String})
    return filter(matching) do env
        # A. Exclude global standard environment if 'global' keyword is listed
        if ("global" in excluded_envs) && occursin(r"^v\d+\.\d+$", env)
            return false
        end
        # B. Exclude explicitly forbidden environments
        if env in excluded_envs
            return false
        end
        # C. Exclude standard global environments if a fallback environment is requested
        # (This forces the creation/activation of the fallback environment)
        if !isempty(fallback_env) && occursin(r"^v\d+\.\d+$", env)
            return false
        end
        return true
    end
end

end # module
