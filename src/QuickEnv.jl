module QuickEnv

using Pkg
using TOML

function get_script_path()
    script_path = PROGRAM_FILE
    if isempty(script_path)
        sp = Base.source_path()
        script_path = sp !== nothing ? sp : ""
    end
    return isempty(script_path) ? "" : abspath(script_path)
end

function handle_forced_creation(create_env::String, required_packages::Vector{String}, is_silent::Bool)
    isempty(create_env) && return false

    # Search if environment already exists and contains all required packages
    env_dir = joinpath(DEPOT_PATH[1], "environments", create_env)
    toml_path = joinpath(env_dir, "Project.toml")
    
    has_all_packages = false
    missing_pkgs = copy(required_packages)
    
    if isfile(toml_path)
        try
            project_data = TOML.parsefile(toml_path)
            deps = get(project_data, "deps", Dict{String, Any}())
            filter!(pkg -> !haskey(deps, pkg), missing_pkgs)
            if isempty(missing_pkgs)
                has_all_packages = true
            end
        catch
            # Ignore parsing error
        end
    end
    
    if has_all_packages
        # Simply activate the existing satisfying environment
        current_project = Base.active_project()
        if current_project === nothing || !occursin(create_env, current_project)
            if !is_silent
                @info "QuickEnv: Found existing environment @$create_env with all dependencies. Activating..."
            end
            Pkg.activate(create_env, shared=true, io=is_silent ? devnull : stderr)
        end
    else
        # We need to add packages! Disable silent mode.
        is_silent = false
        
        # Print detailed description BEFORE modifying the environment
        println(stderr, "\n=== QuickEnv: Environment Configuration Required ===")
        if !isdir(env_dir)
            println(stderr, "Action: Creating new shared named environment @$create_env.")
        else
            println(stderr, "Action: Updating existing shared named environment @$create_env.")
        end
        println(stderr, "Reason: Missing required packages: $missing_pkgs")
        println(stderr, "Triggering automatic package installation...")
        println(stderr, "====================================================\n")
        
        # Activate and bootstrap
        Pkg.activate(create_env, shared=true, io=stderr)
        Pkg.add(missing_pkgs, io=stderr)
    end
    return true
end

function handle_matching_or_fallback(required_packages::Vector{String}, fallback_env::String, excluded_envs::Vector{String}, is_silent::Bool, script_path::String)
    # Locate all satisfying named environments
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
        # No matching environment found! Apply fallback logic.
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

function __init__()
    script_path = get_script_path()
    isempty(script_path) && return

    required_packages, fallback_env, excluded_envs, script_silent, create_env = parse_script_metadata(script_path)
    
    # Exclude QuickEnv itself from dependency matching
    filter!(p -> (p != "QuickEnv"), required_packages)

    # Resolve global silence (via QUICKENV_SILENT environment variable or script comment)
    env_silent = get(ENV, "QUICKENV_SILENT", "false")
    is_silent = (lowercase(env_silent) == "true") || script_silent

    # Handle forced environment creation or updating
    if handle_forced_creation(create_env, required_packages, is_silent)
        return
    end

    # Handle environment matching or fallback
    handle_matching_or_fallback(required_packages, fallback_env, excluded_envs, is_silent, script_path)
end

function parse_inline_options(line::String)
    fallback_env = ""
    excluded_envs = String[]
    is_silent = false
    create_env = ""
    
    parts = split(line, '#')
    if length(parts) > 1
        comment_part = strip(parts[2])
        clean_line = strip(parts[1])
        if occursin(r"\bQuickEnv\b", clean_line)
            # 1. Parse inline silent/quiet flags
            if occursin(r"(?i)\bsilent\b", comment_part) || occursin(r"(?i)\bquiet\b", comment_part)
                is_silent = true
            end
            
            # 2. Parse inline fallback: <name>
            m_inline_fallback = match(r"(?i)\bfallback\s*:\s*([a-zA-Z0-9_\-]+)", comment_part)
            if m_inline_fallback !== nothing
                fallback_env = String(m_inline_fallback.captures[1])
            end
            
            # 3. Parse inline create: <name>
            m_inline_create = match(r"(?i)\bcreate\s*:\s*([a-zA-Z0-9_\-]+)", comment_part)
            if m_inline_create !== nothing
                create_env = String(m_inline_create.captures[1])
            end
            
            # 4. Parse inline exclude: <comma-separated list>
            m_inline_exclude = match(r"(?i)\bexclude\s*:\s*([^#;]+)", comment_part)
            if m_inline_exclude !== nothing
                raw_excl = m_inline_exclude.captures[1]
                # Remove other keywords to avoid capturing them if they appear after 'exclude:'
                raw_excl = replace(raw_excl, r"(?i)\bfallback\s*:\s*[a-zA-Z0-9_\-]+" => "")
                raw_excl = replace(raw_excl, r"(?i)\bcreate\s*:\s*[a-zA-Z0-9_\-]+" => "")
                raw_excl = replace(raw_excl, r"(?i)\bsilent\b" => "")
                raw_excl = replace(raw_excl, r"(?i)\bquiet\b" => "")
                
                for item in split(raw_excl, ',')
                    clean_item = strip(item)
                    if !isempty(clean_item)
                        push!(excluded_envs, String(clean_item))
                    end
                end
            end
        end
    end
    return fallback_env, excluded_envs, is_silent, create_env
end

function parse_standalone_comments(line::String)
    fallback_env = ""
    excluded_envs = String[]
    is_silent = nothing
    create_env = ""

    # 1. Parse standalone fallback magic comment
    m_fallback = match(r"^\s*#\s*quickenv_fallback\s*:\s*([a-zA-Z0-9_\-]+)", line)
    if m_fallback !== nothing
        fallback_env = String(m_fallback.captures[1])
    end

    # 2. Parse standalone exclude magic comment (comma-separated list of env names or "global")
    m_exclude = match(r"^\s*#\s*quickenv_exclude\s*:\s*(.*)$", line)
    if m_exclude !== nothing
        for item in split(m_exclude.captures[1], ',')
            push!(excluded_envs, String(strip(item)))
        end
    end

    # 3. Parse standalone QuickEnv.create magic comment
    m_create = match(r"^\s*#\s*(?:QuickEnv\.create|quickenv_create)\s*:\s*([a-zA-Z0-9_\-]+)", line)
    if m_create !== nothing
        create_env = String(m_create.captures[1])
    end

    # 4. Parse standalone silent magic comment (e.g., # quickenv_silent: true)
    m_silent = match(r"^\s*#\s*quickenv_silent\s*:\s*([a-zA-Z0-9_\-]+)", line)
    if m_silent !== nothing
        is_silent = lowercase(strip(m_silent.captures[1])) == "true"
    end

    return fallback_env, excluded_envs, is_silent, create_env
end

function extract_packages_from_line(line::String)
    packages = String[]
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
                push!(packages, String(pkg_name))
            end
        end
    end
    return packages
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
    create_env = ""
    
    if isfile(script_path)
        for line in eachline(script_path)
            # 1. Parse inline options on the QuickEnv import line
            inline_fallback, inline_excl, inline_silent, inline_create = parse_inline_options(line)
            if !isempty(inline_fallback)
                fallback_env = inline_fallback
            end
            if !isempty(inline_excl)
                append!(excluded_envs, inline_excl)
            end
            if inline_silent
                is_silent = true
            end
            if !isempty(inline_create)
                create_env = inline_create
            end

            # 2. Parse standalone magic comments
            sa_fallback, sa_excl, sa_silent, sa_create = parse_standalone_comments(line)
            if !isempty(sa_fallback)
                fallback_env = sa_fallback
            end
            if !isempty(sa_excl)
                append!(excluded_envs, sa_excl)
            end
            if sa_silent !== nothing
                is_silent = sa_silent
            end
            if !isempty(sa_create)
                create_env = sa_create
            end

            # 3. Extract package imports
            for pkg in extract_packages_from_line(line)
                if !(pkg in packages)
                    push!(packages, pkg)
                end
            end
        end
    end
    return packages, fallback_env, excluded_envs, is_silent, create_env
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
