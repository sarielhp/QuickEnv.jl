module QuickEnv

using Pkg
using TOML

const tip_printed = Ref(false)

"""
    print_silence_tip(is_silent)

Print instructions on how to make QuickEnv silent if logs are printed,
ensuring it is shown at most once.
"""
function print_silence_tip(is_silent::Bool)
    if !is_silent && !tip_printed[]
        @info "QuickEnv: Tip: To run silently, add '# silent' to " *
            "'using QuickEnv', set '# quickenv_silent: true', " *
            "or set QUICKENV_SILENT=true."
        tip_printed[] = true
    end
end

"""
    get_script_path() -> String

Retrieve the absolute path to the currently executing Julia script. Returns an
empty string if Julia is running interactively (e.g., in the REPL or over a
socket connection).
"""
function get_script_path()
    script_path = PROGRAM_FILE
    if isempty(script_path)
        sp = Base.source_path()
        script_path = sp !== nothing ? sp : ""
    end
    return isempty(script_path) ? "" : abspath(script_path)
end

"""
    handle_forced_creation(create_env, required_packages, is_silent) -> Bool

Handle the forced environment creation or update logic triggered by
`create: <env>` magic comments. If `create_env` is non-empty, checks if the
shared named environment already exists and satisfies all required imports.
If not, it activates the environment, displays a detailed update
description, disables silent mode, and installs all missing package
dependencies. Returns `true` if a forced environment was handled, allowing
`__init__` to return early.
"""
function handle_forced_creation(
    create_env::String, required_packages::Vector{String}, is_silent::Bool
)
    if isempty(create_env)
        return false
    end

    # Search if environment already exists and contains all required packages
    env_dir = joinpath(DEPOT_PATH[1], "environments", create_env)
    toml_path = joinpath(env_dir, "Project.toml")

    has_all_packages = false
    missing_pkgs = copy(required_packages)

    if isfile(toml_path)
        try
            project_data = TOML.parsefile(toml_path)
            deps = get(project_data, "deps", Dict{String,Any}())
            filter!(pkg -> !haskey(deps, pkg), missing_pkgs)
            if isempty(missing_pkgs)
                has_all_packages = true
            end
        catch e
            @error "QuickEnv: Error parsing Project TOML file at " * "$toml_path: $e"
        end
    end

    if has_all_packages
        # Simply activate the existing satisfying environment
        current_project = Base.active_project()
        if current_project === nothing || !occursin(create_env, current_project)
            if !is_silent
                @info "QuickEnv: Found existing environment @$create_env " *
                    "with all dependencies. Activating..."
                print_silence_tip(is_silent)
            end
            Pkg.activate(create_env; shared=true, io=is_silent ? devnull : stderr)
        end
        return true
    end

    # We need to add packages! Disable silent mode.
    is_silent = false

    # Print detailed description BEFORE modifying the environment
    println(stderr, "\n=== QuickEnv: Environment Configuration Required ===")
    if !isdir(env_dir)
        println(stderr, "Action: Creating new shared named environment @$create_env.")
    else
        println(
            stderr, "Action: Updating existing shared named environment " * "@$create_env."
        )
    end
    println(stderr, "Reason: Missing required packages: $missing_pkgs")
    println(stderr, "Triggering automatic package installation...")
    println(stderr, "====================================================\n")

    # Activate and bootstrap
    Pkg.activate(create_env; shared=true, io=stderr)
    Pkg.add(missing_pkgs; io=stderr)
    return true
end

"""
    activate_matched_env(matching, is_silent)

Select and activate the first satisfying non-versioned custom shared named
environment. If logs are enabled, displays an activation message and prints
the silence tip.
"""
function activate_matched_env(matching::Vector{String}, is_silent::Bool)
    # Select the first matching custom environment (excluding standard global
    # ones if any custom exist)
    selected = something(findfirst(env -> !occursin(r"^v\d+\.\d+$", env), matching), 1)
    env_name = matching[selected]

    # Activate the matched environment
    current_project = Base.active_project()
    if current_project === nothing || !occursin(env_name, current_project)
        if !is_silent
            @info "QuickEnv: Found matching environment @$env_name. " * "Activating..."
            print_silence_tip(is_silent)
        end
        Pkg.activate(env_name; shared=true, io=is_silent ? devnull : stderr)
    end
end

"""
    activate_fallback_env(
        fallback_env, script_path, is_silent
    ) -> Tuple{String, Bool}

Activate either the requested fallback environment or the script's local
directory project. Returns a tuple of the display name of the target
environment and a boolean indicating if an info log was printed.
"""
function activate_fallback_env(fallback_env::String, script_path::String, is_silent::Bool)
    if !isempty(fallback_env)
        # Use specified named fallback environment
        printed_info = !is_silent
        if printed_info
            @info "QuickEnv: No matching environment found. " *
                "Activating fallback @$fallback_env..."
        end
        Pkg.activate(fallback_env; shared=true, io=is_silent ? devnull : stderr)
        return "@" * fallback_env, printed_info
    end

    # Default: Activate local directory environment
    script_dir = dirname(script_path)
    printed_info = !is_silent
    if printed_info
        @info "QuickEnv: No matching environment found. " *
            "Activating local environment at $script_dir..."
    end
    Pkg.activate(script_dir; io=is_silent ? devnull : stderr)
    return "local directory environment", printed_info
end

"""
    bootstrap_packages(
        required_packages, target_env_display, printed_info, is_silent
    )

Scan the active environment's dependencies and automatically install missing
packages. Prevents package installation into standard versioned global scopes
as a safety check. If no packages were added and logs were printed, shows the
silence tip instruction.
"""
function bootstrap_packages(
    required_packages::Vector{String},
    target_env_display::String,
    printed_info::Bool,
    is_silent::Bool,
)
    project_file = Base.active_project()
    if project_file === nothing
        return nothing
    end

    # Safety Check: Prevent adding packages to the global environment
    env_name = basename(dirname(project_file))
    if occursin(r"^v\d+\.\d+$", env_name)
        if !is_silent
            @warn "QuickEnv: Safety check triggered. Blocked installation " *
                "of packages into the global environment ($env_name)."
        end
        return nothing
    end

    deps = Dict{String,Any}()
    if isfile(project_file)
        try
            project_data = TOML.parsefile(project_file)
            deps = get(project_data, "deps", Dict{String,Any}())
        catch e
            @error "QuickEnv: Error parsing Project TOML file at " * "$project_file: $e"
        end
    end

    missing_pkgs = filter(pkg -> !haskey(deps, pkg), required_packages)
    if !isempty(missing_pkgs)
        if !is_silent
            @info "QuickEnv: Installing missing packages into " *
                "$target_env_display: $missing_pkgs"
        end
        Pkg.add(missing_pkgs; io=is_silent ? devnull : stderr)
        return nothing
    end

    # No new packages were added! If we printed any activation logs,
    # show the silent tip.
    if printed_info && !is_silent
        print_silence_tip(is_silent)
    end
end

"""
    handle_matching_or_fallback(
        required_packages, fallback_env, excluded_envs, is_silent, script_path
    )

Find and activate a satisfying global shared named environment, or execute
fallback/auto-bootstrapping logic. If multiple environments match, the first
non-versioned custom named environment is preferred. If no matching
environment is found, it falls back to creating/updating the requested
fallback environment or activates the local directory project of the script
and installs any missing packages. Includes a safety check to prevent package
installation directly into standard versioned global scopes.
"""
function handle_matching_or_fallback(
    required_packages::Vector{String},
    fallback_env::String,
    excluded_envs::Vector{String},
    is_silent::Bool,
    script_path::String,
)
    # Locate all satisfying named environments
    matching = find_matching_envs(required_packages)

    # Filter matching list by exclusions and fallback request rules
    matching = filter_matching_envs(matching, fallback_env, excluded_envs)

    if !isempty(matching)
        activate_matched_env(matching, is_silent)
        return nothing
    end

    # No matching environment found! Apply fallback logic.
    target_env_display, printed_info = activate_fallback_env(
        fallback_env, script_path, is_silent
    )
    bootstrap_packages(required_packages, target_env_display, printed_info, is_silent)
end

"""
    update_description(file_path::String, new_desc::String)

Update or insert the description key in a Project.toml file.
"""
function update_description(file_path::String, new_desc::String)
    mkpath(dirname(file_path))
    lines = isfile(file_path) ? readlines(file_path, keep=true) : String[]
    description_replaced = false

    updated_lines = String[]
    for line in lines
        if occursin(r"^\s*description\s*=\s*\".*\"\s*$", line)
            description_replaced = true
            push!(updated_lines, "description = \"$new_desc\"\n")
        else
            push!(updated_lines, line)
        end
    end

    if !description_replaced
        pushfirst!(updated_lines, "description = \"$new_desc\"\n\n")
    end

    write(file_path, join(updated_lines))
end

"""
    update_active_env_description(description::String)

Update the description in the Project.toml of the active environment,
excluding standard versioned global environments to prevent pollution.
"""
function update_active_env_description(description::String)
    if isempty(description)
        return nothing
    end
    project_file = Base.active_project()
    if project_file !== nothing && isfile(project_file)
        env_name = basename(dirname(project_file))
        if !occursin(r"^v\d+\.\d+$", env_name)
            update_description(project_file, description)
        end
    end
    return nothing
end

"""
    warn_ignored_local_files(script_path::String, env_name::String, is_silent::Bool)

Warn the user if a local Project.toml or Manifest.toml exists in the script's
directory but is being ignored because a named environment is active.
"""
function warn_ignored_local_files(script_path::String, env_name::String, is_silent::Bool)
    if is_silent
        return nothing
    end
    script_dir = dirname(script_path)
    local_project = joinpath(script_dir, "Project.toml")
    local_manifest = joinpath(script_dir, "Manifest.toml")
    if isfile(local_project) || isfile(local_manifest)
        @warn "QuickEnv: Local Project.toml or Manifest.toml exists in the " *
              "script's directory, but is being ignored because named " *
              "environment @$env_name is activated."
    end
    return nothing
end

"""
    __init__()

Initialization hook executed automatically when `QuickEnv` is imported.
Orchestrates script path resolution, metadata parsing, silent-mode
configuration, and environment selection or fallback.
"""
function __init__()
    script_path = get_script_path()
    if isempty(script_path)
        return nothing
    end

    required_packages, fallback_env, excluded_envs, script_silent, create_env, description = parse_script_metadata(
        script_path
    )

    # Exclude QuickEnv itself from dependency matching
    filter!(p -> (p != "QuickEnv"), required_packages)

    # Resolve global silence (via QUICKENV_SILENT environment variable or
    # script comment)
    env_silent = get(ENV, "QUICKENV_SILENT", "false")
    is_silent = (lowercase(env_silent) == "true") || script_silent

    # Handle forced environment creation or updating
    if handle_forced_creation(create_env, required_packages, is_silent)
        warn_ignored_local_files(script_path, create_env, is_silent)
        update_active_env_description(description)
        return nothing
    end

    # Handle environment matching or fallback
    handle_matching_or_fallback(
        required_packages, fallback_env, excluded_envs, is_silent, script_path
    )

    # Check if local files are ignored by active named/fallback environment
    project_file = Base.active_project()
    if project_file !== nothing
        active_dir = dirname(project_file)
        if active_dir != dirname(script_path) && !occursin(r"^v\d+\.\d+$", basename(active_dir))
            warn_ignored_local_files(script_path, basename(active_dir), is_silent)
        end
    end

    update_active_env_description(description)
    return nothing
end

"""
    parse_inline_options(
        line::String
    ) -> Tuple{String, Vector{String}, Bool, String, String}

Parse inline configuration comments on the `using QuickEnv` import line.
Extracts fallback targets, exclusion lists, silent execution flag, forced
creation targets, and environment description.
"""
function parse_inline_options(line::String)
    fallback_env = ""
    excluded_envs = String[]
    is_silent = false
    create_env = ""
    description = ""

    parts = split(line, '#')
    if length(parts) <= 1
        return fallback_env, excluded_envs, is_silent, create_env, description
    end

    comment_part = strip(parts[2])
    clean_line = strip(parts[1])
    if !occursin(r"\bQuickEnv\b", clean_line)
        return fallback_env, excluded_envs, is_silent, create_env, description
    end

    # 1. Parse inline silent flags
    if occursin(r"(?i)\bsilent\b", comment_part)
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

    # 4. Parse inline description
    m_inline_desc = match(r"(?i)\bdesc(?:ription)?\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|([^,]*))", comment_part)
    if m_inline_desc !== nothing
        raw_desc = nothing
        for cap in m_inline_desc.captures
            if cap !== nothing
                raw_desc = cap
                break
            end
        end
        if raw_desc !== nothing
            description = String(strip(raw_desc))
        end
    end

    # 5. Parse inline exclude: <comma-separated list>
    m_inline_exclude = match(r"(?i)\bexclude\s*:\s*([^#;]+)", comment_part)
    if m_inline_exclude !== nothing
        raw_excl = m_inline_exclude.captures[1]
        # Remove other keywords to avoid capturing them if they
        # appear after 'exclude:'
        raw_excl = replace(raw_excl, r"(?i)\bfallback\s*:\s*[a-zA-Z0-9_\-]+" => "")
        raw_excl = replace(raw_excl, r"(?i)\bcreate\s*:\s*[a-zA-Z0-9_\-]+" => "")
        raw_excl = replace(raw_excl, r"(?i)\bdesc(?:ription)?\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|([^,]*))" => "")
        raw_excl = replace(raw_excl, r"(?i)\bsilent\b" => "")

        for item in split(raw_excl, ',')
            clean_item = strip(item)
            if !isempty(clean_item)
                push!(excluded_envs, String(clean_item))
            end
        end
    end
    return fallback_env, excluded_envs, is_silent, create_env, description
end

"""
    parse_standalone_comments(
        line::String
    ) -> Tuple{String, Vector{String}, Union{Nothing, Bool}, String, String}

Parse standalone configuration comments starting with `# quickenv_` or
`# QuickEnv.` on a single line. Extracts fallback targets, exclusion lists,
silent execution flag, forced creation targets, and environment description.
"""
function parse_standalone_comments(line::String)
    fallback_env = ""
    excluded_envs = String[]
    is_silent = nothing
    create_env = ""
    description = ""

    # 1. Parse standalone fallback magic comment
    m_fallback = match(r"^\s*#\s*quickenv_fallback\s*:\s*(.*)$", line)
    if m_fallback !== nothing
        content = m_fallback.captures[1]
        m_name = match(r"^\s*([a-zA-Z0-9_\-]+)", content)
        if m_name !== nothing
            fallback_env = String(m_name.captures[1])
        end
        m_inline_desc = match(r"(?i)\bdesc(?:ription)?\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|([^,]*))", content)
        if m_inline_desc !== nothing
            raw_desc = nothing
            for cap in m_inline_desc.captures
                if cap !== nothing
                    raw_desc = cap
                    break
                end
            end
            if raw_desc !== nothing
                description = String(strip(raw_desc))
            end
        end
    end

    # 2. Parse standalone exclude magic comment (comma-separated list of
    # env names or "global")
    m_exclude = match(r"^\s*#\s*quickenv_exclude\s*:\s*(.*)$", line)
    if m_exclude !== nothing
        for item in split(m_exclude.captures[1], ',')
            push!(excluded_envs, String(strip(item)))
        end
    end

    # 3. Parse standalone QuickEnv.create magic comment
    m_create = match(
        r"^\s*#\s*(?:QuickEnv\.create|quickenv_create)\s*:\s*(.*)$", line
    )
    if m_create !== nothing
        content = m_create.captures[1]
        m_name = match(r"^\s*([a-zA-Z0-9_\-]+)", content)
        if m_name !== nothing
            create_env = String(m_name.captures[1])
        end
        m_inline_desc = match(r"(?i)\bdesc(?:ription)?\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|([^,]*))", content)
        if m_inline_desc !== nothing
            raw_desc = nothing
            for cap in m_inline_desc.captures
                if cap !== nothing
                    raw_desc = cap
                    break
                end
            end
            if raw_desc !== nothing
                description = String(strip(raw_desc))
            end
        end
    end

    # 4. Parse standalone description magic comment
    m_desc = match(r"^\s*#\s*(?:QuickEnv\.desc(?:ription)?|quickenv_desc(?:ription)?)\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|(.*))$", line)
    if m_desc !== nothing
        raw_desc = nothing
        for cap in m_desc.captures
            if cap !== nothing
                raw_desc = cap
                break
            end
        end
        if raw_desc !== nothing
            description = String(strip(raw_desc))
        end
    end

    # 5. Parse standalone silent magic comment (e.g., # quickenv_silent: true)
    m_silent = match(r"^\s*#\s*quickenv_silent\s*:\s*([a-zA-Z0-9_\-]+)", line)
    if m_silent !== nothing
        is_silent = lowercase(strip(m_silent.captures[1])) == "true"
    end

    return fallback_env, excluded_envs, is_silent, create_env, description
end

"""
    extract_packages_from_line(line::String) -> Vector{String}

Parse a code line containing a `using` or `import` statement, stripping
inline comments and sub-imports following a colon (`:`), and return the
list of imported Julia package names.
"""
function extract_packages_from_line(line::String)
    packages = String[]
    clean_line = strip(first(split(line, '#')))
    m = match(r"^\s*(using|import)\s+(.*)$", clean_line)
    if m === nothing
        return packages
    end

    raw_imports = m.captures[2]
    # In Julia, standard 'using/import Module: item' syntax imports
    # items from a module.
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
    return packages
end

"""
    parse_script_metadata(script_path::String)

Reads a script and extracts required packages, fallback environments,
excluded environments, silent flag, forced creation targets, and environment description.
"""
function parse_script_metadata(script_path::String)
    packages = String[]
    fallback_env = ""
    excluded_envs = String[]
    is_silent = false
    create_env = ""
    description = ""

    if !isfile(script_path)
        return packages, fallback_env, excluded_envs, is_silent, create_env, description
    end

    for line in eachline(script_path)
        # 1. Parse inline options on the QuickEnv import line
        inline_fallback, inline_excl, inline_silent, inline_create, inline_desc = parse_inline_options(
            line
        )
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
        if !isempty(inline_desc)
            description = inline_desc
        end

        # 2. Parse standalone magic comments
        sa_fallback, sa_excl, sa_silent, sa_create, sa_desc = parse_standalone_comments(line)
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
        if !isempty(sa_desc)
            description = sa_desc
        end

        # 3. Extract package imports
        for pkg in extract_packages_from_line(line)
            if !(pkg in packages)
                push!(packages, pkg)
            end
        end
    end
    return packages, fallback_env, excluded_envs, is_silent, create_env, description
end

"""
    find_matching_envs(required_pkgs) -> Vector{String}

Scan Julia's standard depot path (`DEPOT_PATH[1]/environments/`) to find
all existing shared named environments that satisfy all of the required
packages. Returns a sorted list of environment names.
"""
function find_matching_envs(required_pkgs::Vector{String})
    env_dir = joinpath(DEPOT_PATH[1], "environments")
    if !isdir(env_dir)
        return String[]
    end

    matching_envs = String[]
    for entry in readdir(env_dir)
        path = joinpath(env_dir, entry)
        !isdir(path) && continue

        toml_path = joinpath(path, "Project.toml")
        !isfile(toml_path) && continue

        try
            project_data = TOML.parsefile(toml_path)
            deps = get(project_data, "deps", Dict{String,Any}())
            if all(pkg -> haskey(deps, pkg), required_pkgs)
                push!(matching_envs, entry)
            end
        catch e
            @error "QuickEnv: Error parsing Project TOML file at " * "$toml_path: $e"
        end
    end
    return sort(matching_envs)
end

"""
    filter_matching_envs(
        matching, fallback_env, excluded_envs
    ) -> Vector{String}

Filter the matched environments list based on exclusion rules and fallback
preferences:
- Excludes standard global environments (e.g., `@v1.12`) if the `"global"`
  keyword is in `excluded_envs`.
- Excludes any environments explicitly named in `excluded_envs`.
- Excludes standard global environments if a specific `fallback_env` has
  been requested, ensuring the fallback is created/used instead.
"""
function filter_matching_envs(
    matching::Vector{String}, fallback_env::String, excluded_envs::Vector{String}
)
    return filter(matching) do env
        # A. Exclude global standard environment if 'global' keyword is listed
        if ("global" in excluded_envs) && occursin(r"^v\d+\.\d+$", env)
            return false
        end
        # B. Exclude explicitly forbidden environments
        if env in excluded_envs
            return false
        end
        # C. Exclude standard global environments if a fallback environment
        # is requested
        # (This forces the creation/activation of the fallback environment)
        if !isempty(fallback_env) && occursin(r"^v\d+\.\d+$", env)
            return false
        end
        return true
    end
end

end # module
