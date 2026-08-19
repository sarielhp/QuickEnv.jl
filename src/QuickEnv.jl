module QuickEnv

using TOML

# =============================================================================
# Path & Script Utilities
# =============================================================================

"""
    get_script_path() -> String

Retrieve the absolute path to the currently executing Julia script. Returns an
empty string if Julia is running interactively.
"""
function get_script_path()
    script_path = PROGRAM_FILE
    if isempty(script_path)
        sp = Base.source_path()
        script_path = sp !== nothing ? sp : ""
    end
    return isempty(script_path) ? "" : abspath(script_path)
end

function activate_shared_env(env_name::String)
    env_dir = joinpath(DEPOT_PATH[1], "environments", env_name)
    proj_file = isfile(joinpath(env_dir, "JuliaProject.toml")) ?
        joinpath(env_dir, "JuliaProject.toml") : joinpath(env_dir, "Project.toml")
    if !isfile(proj_file)
        mkpath(env_dir)
        touch(proj_file)
    end
    Base.set_active_project(proj_file)
end

function activate_local_dir_env(dir_path::String)
    proj_file = isfile(joinpath(dir_path, "JuliaProject.toml")) ?
        joinpath(dir_path, "JuliaProject.toml") : joinpath(dir_path, "Project.toml")
    if !isfile(proj_file)
        touch(proj_file)
    end
    Base.set_active_project(proj_file)
end

# =============================================================================
# Cache Subsystem (O(1) State-Aware Hashing & Fast Script Cache)
# =============================================================================

function get_cache_dir()
    return joinpath(DEPOT_PATH[1], "quickenv")
end

function get_cache_file()
    return joinpath(get_cache_dir(), "cache.toml")
end

function get_canonical_key(packages::Vector{String})
    return join(sort(unique(packages)), "+")
end

function get_cache_hash(key::String)
    return string(hash(key), base=16)[1:min(12, length(string(hash(key), base=16)))]
end

function load_cache()
    cfile = get_cache_file()
    if isfile(cfile)
        try
            return TOML.parsefile(cfile)
        catch
            return Dict{String, Any}()
        end
    end
    return Dict{String, Any}()
end

function save_cache(cache_data::Dict{String, Any})
    cdir = get_cache_dir()
    mkpath(cdir)
    cfile = get_cache_file()
    try
        open(cfile, "w") do io
            TOML.print(io, cache_data)
        end
    catch
    end
end

"""
    check_script_cache_hit(script_path::String) -> Union{Nothing, String}

Super-fast O(1) script cache lookup by script absolute path and mtime.
If the script file hasn't changed since its last execution and its target
environment still exists, immediately returns the target environment without
needing to parse file contents or run regexes.
"""
function check_script_cache_hit(script_path::String)
    isempty(script_path) && return nothing
    !isfile(script_path) && return nothing

    cache = load_cache()
    scripts_table = get(cache, "scripts", Dict{String, Any}())
    !haskey(scripts_table, script_path) && return nothing

    entry = scripts_table[script_path]
    cached_mtime = get(entry, "mtime", 0.0)
    current_mtime = mtime(script_path)
    if abs(cached_mtime - current_mtime) < 1e-3
        target_env = get(entry, "env", "")
        if !isempty(target_env)
            target_proj = joinpath(DEPOT_PATH[1], "environments", target_env, "Project.toml")
            if isfile(target_proj)
                return target_env
            end
        end
    end
    return nothing
end

function update_script_cache_entry(script_path::String, env_name::String)
    isempty(script_path) && return nothing
    !isfile(script_path) && return nothing

    cache = load_cache()
    scripts_table = get(cache, "scripts", Dict{String, Any}())
    scripts_table[script_path] = Dict{String, Any}(
        "mtime" => mtime(script_path),
        "env" => env_name,
        "updated_at" => string(time())
    )
    cache["scripts"] = scripts_table
    save_cache(cache)
end

"""
    invalidate_script_cache(script_path::String)

Purge the cached resolution entry for a specific script. Automatically called
if a script exits with a non-zero exit code, ensuring that broken or partially
modified multi-file dependencies trigger a fresh resolution.
"""
function invalidate_script_cache(script_path::String)
    isempty(script_path) && return nothing
    cache = load_cache()
    scripts_table = get(cache, "scripts", Dict{String, Any}())
    if haskey(scripts_table, script_path)
        delete!(scripts_table, script_path)
        cache["scripts"] = scripts_table
        save_cache(cache)
    end
end

"""
    check_cache_hit(required_packages::Vector{String}) -> Union{Nothing, String}

Check if a cached resolution exists for the given required packages. Verifies that
all source environments and their Manifest.toml files still exist and their
modification times have not changed.
"""
function check_cache_hit(required_packages::Vector{String})
    isempty(required_packages) && return nothing
    key = get_canonical_key(required_packages)
    cache = load_cache()
    !haskey(cache, key) && return nothing

    entry = cache[key]
    env_name = get(entry, "env", "")
    sources = get(entry, "sources", String[])
    cached_mtimes = get(entry, "mtimes", Float64[])

    isempty(env_name) && return nothing

    # Verify target environment exists
    target_dir = joinpath(DEPOT_PATH[1], "environments", env_name)
    !isdir(target_dir) && return nothing

    # Verify all source environments still exist with matching mtimes
    if length(sources) == length(cached_mtimes)
        for i in 1:length(sources)
            s_manifest = joinpath(DEPOT_PATH[1], "environments", sources[i], "Manifest.toml")
            if !isfile(s_manifest) || mtime(s_manifest) != cached_mtimes[i]
                return nothing # Cache stale!
            end
        end
    end

    return env_name
end

function update_cache_entry(
    required_packages::Vector{String}, target_env::String, source_envs::Vector{String}
)
    isempty(required_packages) && return nothing
    key = get_canonical_key(required_packages)
    cache = load_cache()

    mtimes = Float64[]
    for s in source_envs
        s_manifest = joinpath(DEPOT_PATH[1], "environments", s, "Manifest.toml")
        push!(mtimes, isfile(s_manifest) ? mtime(s_manifest) : 0.0)
    end

    cache[key] = Dict(
        "env" => target_env,
        "sources" => source_envs,
        "mtimes" => mtimes,
        "updated_at" => string(time())
    )
    save_cache(cache)
end

# =============================================================================
# Bitmask Greedy Set-Cover Engine
# =============================================================================

"""
    find_minimal_covering_envs(
        required_pkgs::Vector{String},
        candidate_envs::Vector{Tuple{String, Vector{String}}};
        timeout_sec::Float64=1.0,
    ) -> Vector{String}

Given required packages and available candidate environments, use hardware bitmasks
(UInt64) to find a minimal, non-polluting cover of environments. Implements a strict
1.0s timeout: if solver execution exceeds 1s, aborts and returns an empty cover to never
block script execution.
"""
function find_minimal_covering_envs(
    required_pkgs::Vector{String},
    candidate_envs::Vector{Tuple{String, Vector{String}}};
    timeout_sec::Float64=1.0,
)
    start_time = time()
    n = length(required_pkgs)
    n > 64 && return String[] # Fallback if >64 packages
    target_mask = (UInt64(1) << n) - 1

    # Convert candidate environments to bitmasks and compute extraneous count
    env_info = Tuple{String, UInt64, Int}[] # (name, mask, extra_count)
    for (name, pkgs) in candidate_envs
        if (time() - start_time) > timeout_sec
            return String[]
        end

        mask = UInt64(0)
        matched_count = 0
        for (i, p) in enumerate(required_pkgs)
            if p in pkgs
                mask |= (UInt64(1) << (i - 1))
                matched_count += 1
            end
        end
        if mask > 0
            extra_count = length(pkgs) - matched_count
            push!(env_info, (name, mask, extra_count))
        end
    end

    selected = String[]
    current_cov = UInt64(0)

    while current_cov != target_mask
        if (time() - start_time) > timeout_sec
            return String[]
        end

        best_env = ""
        best_score = -1.0
        best_mask = UInt64(0)

        for (name, mask, extra_count) in env_info
            gain = count_ones(mask & ~current_cov)
            if gain > 0
                # Priority score: newly covered packages divided by extraneous penalty
                score = Float64(gain) / (Float64(extra_count) + 1.0)
                if score > best_score
                    best_score = score
                    best_env = name
                    best_mask = mask
                end
            end
        end

        best_score <= 0 && break
        push!(selected, best_env)
        current_cov |= best_mask
    end

    return current_cov == target_mask ? selected : String[]
end

# =============================================================================
# Manifest Transitive Compatibility Validator & Fast Stitching
# =============================================================================

"""
    check_manifest_compat(env_names::Vector{String}) -> Tuple{Bool, Dict{String, Any}, Dict{String, Any}}

Inspect candidate environments and verify that all shared direct and transitive
dependencies in their Manifest.toml files have identical UUIDs, versions, and
git-tree-sha1 hashes. Standard libraries (in Sys.STDLIB) are validated by UUID.
"""
function check_manifest_compat(env_names::Vector{String})
    merged_deps = Dict{String, Any}()
    merged_manifest_deps = Dict{String, Any}()

    for env_name in env_names
        env_dir = joinpath(DEPOT_PATH[1], "environments", env_name)
        proj_file = joinpath(env_dir, "Project.toml")
        mani_file = joinpath(env_dir, "Manifest.toml")

        # Merge direct dependencies from Project.toml
        if isfile(proj_file)
            try
                p_data = TOML.parsefile(proj_file)
                for (k, v) in get(p_data, "deps", Dict{String, Any}())
                    merged_deps[k] = v
                end
            catch
            end
        end

        # Check and merge Manifest.toml dependencies
        if isfile(mani_file)
            try
                m_data = TOML.parsefile(mani_file)
                deps = get(m_data, "deps", Dict{String, Any}())

                for (pkg, val) in deps
                    entry = isa(val, Vector) ? first(val) : val
                    uuid = get(entry, "uuid", "")

                    if haskey(merged_manifest_deps, pkg)
                        existing_val = merged_manifest_deps[pkg]
                        existing = isa(existing_val, Vector) ? first(existing_val) : existing_val
                        existing_uuid = get(existing, "uuid", "")

                        # UUID conflict
                        if uuid != existing_uuid
                            return false, Dict{String, Any}(), Dict{String, Any}()
                        end

                        # Version & hash check (skip for stdlibs without versions)
                        v1 = get(entry, "version", "")
                        v2 = get(existing, "version", "")
                        s1 = get(entry, "git-tree-sha1", "")
                        s2 = get(existing, "git-tree-sha1", "")

                        if (!isempty(v1) && !isempty(v2) && v1 != v2) ||
                           (!isempty(s1) && !isempty(s2) && s1 != s2)
                            return false, Dict{String, Any}(), Dict{String, Any}()
                        end
                    else
                        merged_manifest_deps[pkg] = val
                    end
                end
            catch
                return false, Dict{String, Any}(), Dict{String, Any}()
            end
        end
    end

    return true, merged_deps, merged_manifest_deps
end

"""
    stitch_environments(
        target_env::String,
        source_envs::Vector{String},
        is_silent::Bool
    ) -> Bool

Fast-stitch compatible source environments into target_env in <5ms without Pkg SAT
solving or precompilation overhead.
"""
function stitch_environments(
    target_env::String,
    source_envs::Vector{String},
    is_silent::Bool
)
    compat, merged_deps, merged_manifest_deps = check_manifest_compat(source_envs)
    !compat && return false

    target_dir = joinpath(DEPOT_PATH[1], "environments", target_env)
    mkpath(target_dir)

    # Write Project.toml
    proj_content = Dict(
        "name" => target_env,
        "description" => "Autonomous compound environment combining @" * join(source_envs, ", @"),
        "deps" => merged_deps
    )
    open(joinpath(target_dir, "Project.toml"), "w") do io
        TOML.print(io, proj_content)
    end

    # Write Manifest.toml
    manifest_content = Dict(
        "julia_version" => string(VERSION),
        "manifest_format" => "2.0",
        "deps" => merged_manifest_deps
    )
    open(joinpath(target_dir, "Manifest.toml"), "w") do io
        TOML.print(io, manifest_content)
    end

    if !is_silent
        println(stderr)
        @info "QuickEnv: Fast-stitched autonomous environment @$target_env\nfrom " * join(source_envs, " + ")
        println(stderr)
    end

    return true
end

# =============================================================================
# Package Diagnosis & Typo Detection
# =============================================================================

function levenshtein_distance(s1::AbstractString, s2::AbstractString)
    m, n = length(s1), length(s2)
    d = zeros(Int, m + 1, n + 1)
    for i in 0:m; d[i + 1, 1] = i; end
    for j in 0:n; d[1, j + 1] = j; end
    for i in 1:m, j in 1:n
        cost = s1[i] == s2[j] ? 0 : 1
        d[i + 1, j + 1] = min(d[i, j + 1] + 1, d[i + 1, j] + 1, d[i, j] + cost)
    end
    return d[m + 1, n + 1]
end

function get_known_local_packages()
    known = Set{String}()
    if isdir(Sys.STDLIB)
        for entry in readdir(Sys.STDLIB)
            if isfile(joinpath(Sys.STDLIB, entry, "Project.toml"))
                push!(known, entry)
            end
        end
    end
    push!(known, "Base", "Core", "Main")

    env_dir = joinpath(DEPOT_PATH[1], "environments")
    if isdir(env_dir)
        for entry in readdir(env_dir)
            toml_path = joinpath(env_dir, entry, "Project.toml")
            if isfile(toml_path)
                try
                    project_data = TOML.parsefile(toml_path)
                    deps = get(project_data, "deps", Dict{String, Any}())
                    for (k, _) in deps
                        push!(known, String(k))
                    end
                catch
                end
            end
        end
    end

    active_proj = Base.active_project()
    if active_proj !== nothing && isfile(active_proj)
        try
            project_data = TOML.parsefile(active_proj)
            deps = get(project_data, "deps", Dict{String, Any}())
            for (k, _) in deps
                push!(known, String(k))
            end
        catch
        end
    end

    return known
end

function diagnose_and_suggest_packages(imported_packages::Vector{String}, is_silent::Bool)
    if is_silent || isempty(imported_packages)
        return nothing
    end

    known_local = get_known_local_packages()
    unrecognized = filter(pkg -> !(pkg in known_local), imported_packages)
    isempty(unrecognized) && return nothing

    registry_pkgs = String[]
    registry_loaded = false

    for pkg in unrecognized
        suggestion = nothing
        is_casing_issue = false

        for cand in known_local
            if cand != pkg && lowercase(cand) == lowercase(pkg)
                suggestion = cand
                is_casing_issue = true
                break
            end
        end

        if suggestion === nothing
            best_dist = 3
            for cand in known_local
                dist = levenshtein_distance(lowercase(pkg), lowercase(cand))
                if dist < best_dist && dist <= 2
                    best_dist = dist
                    suggestion = cand
                end
            end
        end

        if suggestion === nothing
            if !registry_loaded
                try
                    reg_file = joinpath(DEPOT_PATH[1], "registries", "General", "Registry.toml")
                    if isfile(reg_file)
                        reg_data = TOML.parsefile(reg_file)
                        pkgs_dict = get(reg_data, "packages", Dict{String, Any}())
                        for (uuid, pinfo) in pkgs_dict
                            pname = get(pinfo, "name", "")
                            !isempty(pname) && push!(registry_pkgs, pname)
                        end
                    end
                catch
                end
                registry_loaded = true
            end

            # If the package exists in the registry with the exact same name, it is a valid
            # registry package (not a typo or casing mistake).
            if pkg in registry_pkgs
                continue
            end

            for cand in registry_pkgs
                if cand != pkg && lowercase(cand) == lowercase(pkg)
                    suggestion = cand
                    is_casing_issue = true
                    break
                end
            end

            if suggestion === nothing
                best_dist = 3
                for cand in registry_pkgs
                    if abs(length(cand) - length(pkg)) <= 2
                        dist = levenshtein_distance(lowercase(pkg), lowercase(cand))
                        if dist < best_dist && dist <= 2
                            best_dist = dist
                            suggestion = cand
                        end
                    end
                end
            end
        end

        if suggestion !== nothing
            println(stderr)
            if is_casing_issue
                @warn "QuickEnv: Detected package '$pkg' with incorrect casing.\n" *
                    "Julia package names are case-sensitive. Did you mean '$suggestion'?\n" *
                    "Please update your import statement to:\n" *
                    "  using $suggestion"
            else
                @warn "QuickEnv: Package '$pkg' not found.\n" *
                    "Did you mean '$suggestion'?\n" *
                    "Please update your import statement to:\n" *
                    "  using $suggestion"
            end
            println(stderr)
        else
            if !isuppercase(first(pkg))
                println(stderr)
                @warn "QuickEnv: Package '$pkg' starts with a lowercase letter and was not found.\n" *
                    "Julia package names almost always start with a capital letter."
                println(stderr)
            end
        end
    end

    return nothing
end

# =============================================================================
# Core Environment Resolution & Activation Pipeline
# =============================================================================

function activate_matched_env(matching::Vector{String}, is_verbose::Bool)
    selected = something(findfirst(env -> !occursin(r"^v\d+\.\d+$", env), matching), 1)
    env_name = matching[selected]

    current_project = Base.active_project()
    if current_project === nothing || !occursin(env_name, current_project)
        if is_verbose
            println(stderr)
            @info "QuickEnv: Found matching environment @$env_name.\nActivating..."
            println(stderr)
        end
        activate_shared_env(env_name)
    end
end

function activate_fallback_env(
    fallback_env::String, script_path::String, is_verbose::Bool
)
    if !isempty(fallback_env)
        if is_verbose
            println(stderr)
            @info "QuickEnv: Activating environment @$fallback_env..."
            println(stderr)
        end
        activate_shared_env(fallback_env)
        return "@" * fallback_env
    end

    script_dir = dirname(script_path)
    if is_verbose
        println(stderr)
        @info "QuickEnv: Activating local environment at $script_dir..."
        println(stderr)
    end
    activate_local_dir_env(script_dir)
    return "local directory environment"
end

function bootstrap_packages(
    required_packages::Vector{String}, target_env_display::String, is_silent::Bool
)
    project_file = Base.active_project()
    project_file === nothing && return nothing

    env_name = basename(dirname(project_file))
    if occursin(r"^v\d+\.\d+$", env_name)
        if !is_silent
            @warn "QuickEnv: Safety check triggered. Blocked installation " *
                "of packages into the global environment ($env_name)."
        end
        return nothing
    end

    deps = Dict{String, Any}()
    if isfile(project_file)
        try
            project_data = TOML.parsefile(project_file)
            deps = get(project_data, "deps", Dict{String, Any}())
        catch e
            @error "QuickEnv: Error parsing Project TOML file at $project_file: $e"
        end
    end

    missing_pkgs = filter(pkg -> !haskey(deps, pkg), required_packages)
    if !isempty(missing_pkgs)
        if !is_silent
            println(stderr)
            @info "QuickEnv: Creating/updating environment. Installing missing packages into\n" *
                "$target_env_display: $missing_pkgs"
            println(stderr)
        end
        try
            @eval import Pkg
            Base.invokelatest(Pkg.add, missing_pkgs; io=is_silent ? devnull : stderr)
        catch e
            @error "QuickEnv: Failed to install packages $missing_pkgs: $e"
        end
    end
    return nothing
end

"""
    handle_matching_or_fallback(
        required_packages, fallback_env, excluded_envs, is_verbose, is_silent, is_local, script_path
    )

The main autonomous environment resolution pipeline:
1. Local directory override: If is_local is true (# local), activates script_dir (--project=.).
2. Fast-path: Check O(1) state-aware cache hit.
3. Single-environment matching: Search existing named environments.
4. Bitmask Set-Cover & Fast Manifest Stitching: Combine compatible environments (<5ms).
5. Autonomous Creation / Fallback: Create dedicated @auto_<hash> environment in depot or fallback.
"""
function handle_matching_or_fallback(
    required_packages::Vector{String},
    fallback_env::String,
    excluded_envs::Vector{String},
    is_verbose::Bool,
    is_silent::Bool,
    is_local::Bool,
    script_path::String,
)
    # -------------------------------------------------------------------------
    # 0. Local Directory Environment Override (# local)
    # -------------------------------------------------------------------------
    if is_local
        script_dir = dirname(script_path)
        if is_verbose
            println(stderr)
            @info "QuickEnv: Activating local directory environment at $script_dir..."
            println(stderr)
        end
        Pkg.activate(script_dir; io=devnull)
        bootstrap_packages(required_packages, "local directory environment", is_silent)
        return nothing
    end

    # -------------------------------------------------------------------------
    # 1. Check O(1) State-Aware Cache Hit
    # -------------------------------------------------------------------------
    if isempty(fallback_env) && isempty(excluded_envs)
        cached_env = check_cache_hit(required_packages)
        if cached_env !== nothing
            activate_matched_env([cached_env], is_verbose)
            return nothing
        end
    end

    # -------------------------------------------------------------------------
    # 2. Check Single Existing Environment Matches
    # -------------------------------------------------------------------------
    matching = find_matching_envs(required_packages)
    matching = filter_matching_envs(matching, fallback_env, excluded_envs)

    if !isempty(matching)
        activate_matched_env(matching, is_verbose)
        if isempty(fallback_env) && isempty(excluded_envs)
            selected_env = matching[1]
            update_cache_entry(required_packages, selected_env, [selected_env])
        end
        return nothing
    end

    # -------------------------------------------------------------------------
    # 3. Bitmask Greedy Set-Cover & Fast Manifest Stitching
    # -------------------------------------------------------------------------
    if isempty(fallback_env) && length(required_packages) >= 2
        # Gather all candidate named environments and their packages
        candidate_envs = Tuple{String, Vector{String}}[]
        env_dir = joinpath(DEPOT_PATH[1], "environments")
        if isdir(env_dir)
            for entry in readdir(env_dir)
                occursin(r"^v\d+\.\d+$", entry) && continue # Skip global envs
                entry in excluded_envs && continue
                toml_path = joinpath(env_dir, entry, "Project.toml")
                if isfile(toml_path)
                    try
                        p_data = TOML.parsefile(toml_path)
                        deps = get(p_data, "deps", Dict{String, Any}())
                        push!(candidate_envs, (entry, collect(keys(deps))))
                    catch
                    end
                end
            end
        end

        covering_envs = find_minimal_covering_envs(required_packages, candidate_envs)
        if !isempty(covering_envs) && length(covering_envs) > 1
            # Check manifest compatibility
            compat, _, _ = check_manifest_compat(covering_envs)
            if compat
                key = get_canonical_key(required_packages)
                auto_env_name = "auto_" * get_cache_hash(key)
                if stitch_environments(auto_env_name, covering_envs, is_silent)
                    update_cache_entry(required_packages, auto_env_name, covering_envs)
                    activate_matched_env([auto_env_name], is_verbose)
                    return nothing
                end
            end
        end
    end

    # -------------------------------------------------------------------------
    # 4. Autonomous Environment Creation or Explicit Fallback Execution
    # -------------------------------------------------------------------------
    target_env = fallback_env
    if isempty(target_env)
        key = get_canonical_key(required_packages)
        target_env = "auto_" * get_cache_hash(key)
    end

    target_env_display = activate_fallback_env(target_env, script_path, is_verbose)
    bootstrap_packages(required_packages, target_env_display, is_silent)
    if isempty(fallback_env)
        update_cache_entry(required_packages, target_env, [target_env])
    end
end

function handle_forced_creation(
    create_env::String,
    required_packages::Vector{String},
    is_verbose::Bool,
    is_silent::Bool,
)
    isempty(create_env) && return false

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
        catch e
            @error "QuickEnv: Error parsing Project TOML file at $toml_path: $e"
        end
    end

    if has_all_packages
        current_project = Base.active_project()
        if current_project === nothing || !occursin(create_env, current_project)
            if is_verbose
                println(stderr)
                @info "QuickEnv: Found existing environment @$create_env\nwith all dependencies. Activating..."
                println(stderr)
            end
            activate_shared_env(create_env)
        end
        return true
    end

    if !is_silent
        println(stderr, "\n=== QuickEnv: Environment Configuration Required ===")
        if !isdir(env_dir)
            println(stderr, "Action: Creating new shared named environment @$create_env.")
        else
            println(stderr, "Action: Updating existing shared named environment @$create_env.")
        end
        println(stderr, "Reason: Missing required packages: $missing_pkgs")
        println(stderr, "Triggering automatic package installation...")
        println(stderr, "====================================================\n")
    end

    activate_shared_env(create_env)
    try
        @eval import Pkg
        Base.invokelatest(Pkg.add, missing_pkgs; io=is_silent ? devnull : stderr)
    catch e
        @error "QuickEnv: Failed to install packages $missing_pkgs into @$create_env: $e"
    end
    return true
end

function update_description(file_path::String, new_desc::String)
    mkpath(dirname(file_path))
    lines = isfile(file_path) ? readlines(file_path; keep=true) : String[]
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

function update_active_env_description(description::String)
    isempty(description) && return nothing
    project_file = Base.active_project()
    if project_file !== nothing && isfile(project_file)
        env_name = basename(dirname(project_file))
        if !occursin(r"^v\d+\.\d+$", env_name)
            update_description(project_file, description)
        end
    end
    return nothing
end

function warn_ignored_local_files(script_path::String, env_name::String, is_silent::Bool)
    is_silent && return nothing
    script_dir = dirname(script_path)
    local_project = joinpath(script_dir, "Project.toml")
    local_manifest = joinpath(script_dir, "Manifest.toml")
    if isfile(local_project) || isfile(local_manifest)
        println(stderr)
        @warn "QuickEnv: Local Project.toml or Manifest.toml exists in the\n" *
            "script's directory, but is being ignored because named\n" *
            "environment @$env_name is activated."
        println(stderr)
    end
    return nothing
end

function extract_packages_from_line(line::String)
    packages = String[]
    clean_line = strip(first(split(line, '#')))
    m = match(r"^\s*(using|import)\s+(.*)$", clean_line)
    m === nothing && return packages

    raw_imports = m.captures[2]
    pkg_part = first(split(raw_imports, ':'))
    parts = split(pkg_part, ',')
    for part in parts
        pkg = strip(part)
        if !isempty(pkg) && !startswith(pkg, '.')
            pkg_name = first(split(pkg))
            push!(packages, String(pkg_name))
        end
    end
    return packages
end

function parse_inline_options(line::String)
    fallback_env = ""
    excluded_envs = String[]
    is_verbose = false
    is_silent = false
    create_env = ""
    description = ""
    is_local = false

    parts = split(line, '#')
    length(parts) <= 1 && return fallback_env, excluded_envs, is_verbose, is_silent, create_env, description, is_local

    comment_part = strip(parts[2])
    clean_line = strip(parts[1])
    !occursin(r"\bQuickEnv\b", clean_line) && return fallback_env, excluded_envs, is_verbose, is_silent, create_env, description, is_local

    if occursin(r"(?i)\bverbose\b", comment_part); is_verbose = true; end
    if occursin(r"(?i)\bsilent\b", comment_part); is_silent = true; end
    if occursin(r"(?i)\blocal\b", comment_part); is_local = true; end

    m_inline_fallback = match(r"(?i)\bfallback\s*:\s*([a-zA-Z0-9_\-]+)", comment_part)
    if m_inline_fallback !== nothing; fallback_env = String(m_inline_fallback.captures[1]); end

    m_inline_create = match(r"(?i)\bcreate\s*:\s*([a-zA-Z0-9_\-]+)", comment_part)
    if m_inline_create !== nothing; create_env = String(m_inline_create.captures[1]); end

    m_inline_desc = match(r"(?i)\bdesc(?:ription)?\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|([^,]*))", comment_part)
    if m_inline_desc !== nothing
        for cap in m_inline_desc.captures
            if cap !== nothing; description = String(strip(cap)); break; end
        end
    end

    m_inline_exclude = match(r"(?i)\bexclude\s*:\s*([^#;]+)", comment_part)
    if m_inline_exclude !== nothing
        raw_excl = m_inline_exclude.captures[1]
        raw_excl = replace(raw_excl, r"(?i)\bfallback\s*:\s*[a-zA-Z0-9_\-]+" => "")
        raw_excl = replace(raw_excl, r"(?i)\bcreate\s*:\s*[a-zA-Z0-9_\-]+" => "")
        raw_excl = replace(raw_excl, r"(?i)\bdesc(?:ription)?\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|([^,]*))" => "")
        raw_excl = replace(raw_excl, r"(?i)\bverbose\b" => "")
        raw_excl = replace(raw_excl, r"(?i)\bsilent\b" => "")
        raw_excl = replace(raw_excl, r"(?i)\blocal\b" => "")
        for item in split(raw_excl, ',')
            clean_item = strip(item)
            !isempty(clean_item) && push!(excluded_envs, String(clean_item))
        end
    end

    return fallback_env, excluded_envs, is_verbose, is_silent, create_env, description, is_local
end

function parse_standalone_comments(line::String)
    fallback_env = ""
    excluded_envs = String[]
    is_verbose = nothing
    is_silent = nothing
    create_env = ""
    description = ""
    is_local = nothing

    m_fallback = match(r"^\s*#\s*quickenv_fallback\s*:\s*(.*)$", line)
    if m_fallback !== nothing
        content = m_fallback.captures[1]
        m_name = match(r"^\s*([a-zA-Z0-9_\-]+)", content)
        if m_name !== nothing; fallback_env = String(m_name.captures[1]); end
        m_inline_desc = match(r"(?i)\bdesc(?:ription)?\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|([^,]*))", content)
        if m_inline_desc !== nothing
            for cap in m_inline_desc.captures
                if cap !== nothing; description = String(strip(cap)); break; end
            end
        end
    end

    m_exclude = match(r"^\s*#\s*quickenv_exclude\s*:\s*(.*)$", line)
    if m_exclude !== nothing
        for item in split(m_exclude.captures[1], ',')
            push!(excluded_envs, String(strip(item)))
        end
    end

    m_create = match(r"^\s*#\s*(?:QuickEnv\.create|quickenv_create)\s*:\s*(.*)$", line)
    if m_create !== nothing
        content = m_create.captures[1]
        m_name = match(r"^\s*([a-zA-Z0-9_\-]+)", content)
        if m_name !== nothing; create_env = String(m_name.captures[1]); end
        m_inline_desc = match(r"(?i)\bdesc(?:ription)?\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|([^,]*))", content)
        if m_inline_desc !== nothing
            for cap in m_inline_desc.captures
                if cap !== nothing; description = String(strip(cap)); break; end
            end
        end
    end

    m_desc = match(r"^\s*#\s*(?:QuickEnv\.desc(?:ription)?|quickenv_desc(?:ription)?)\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|(.*))$", line)
    if m_desc !== nothing
        for cap in m_desc.captures
            if cap !== nothing; description = String(strip(cap)); break; end
        end
    end

    m_verbose = match(r"^\s*#\s*(?:quickenv_verbose|QuickEnv\.verbose)\s*:\s*([a-zA-Z0-9_\-]+)", line)
    if m_verbose !== nothing; is_verbose = lowercase(strip(m_verbose.captures[1])) == "true"; end

    m_silent = match(r"^\s*#\s*(?:quickenv_silent|QuickEnv\.silent)\s*:\s*([a-zA-Z0-9_\-]+)", line)
    if m_silent !== nothing; is_silent = lowercase(strip(m_silent.captures[1])) == "true"; end

    m_local = match(r"^\s*#\s*(?:quickenv_local|QuickEnv\.local)\s*:\s*([a-zA-Z0-9_\-]+)", line)
    if m_local !== nothing
        is_local = lowercase(strip(m_local.captures[1])) == "true"
    elseif occursin(r"^\s*#\s*local\s*$", line)
        is_local = true
    end

    return fallback_env, excluded_envs, is_verbose, is_silent, create_env, description, is_local
end

function parse_script_metadata(script_path::String)
    packages = String[]
    fallback_env = ""
    excluded_envs = String[]
    is_verbose = false
    is_silent = false
    create_env = ""
    description = ""
    is_local = false

    !isfile(script_path) && return packages, fallback_env, excluded_envs, is_verbose, is_silent, create_env, description, is_local

    for line in eachline(script_path)
        inline_fallback, inline_excl, inline_verbose, inline_silent, inline_create, inline_desc, inline_local = parse_inline_options(line)
        !isempty(inline_fallback) && (fallback_env = inline_fallback)
        !isempty(inline_excl) && append!(excluded_envs, inline_excl)
        inline_verbose && (is_verbose = true)
        inline_silent && (is_silent = true)
        inline_local && (is_local = true)
        !isempty(inline_create) && (create_env = inline_create)
        !isempty(inline_desc) && (description = inline_desc)

        sa_fallback, sa_excl, sa_verbose, sa_silent, sa_create, sa_desc, sa_local = parse_standalone_comments(line)
        !isempty(sa_fallback) && (fallback_env = sa_fallback)
        !isempty(sa_excl) && append!(excluded_envs, sa_excl)
        sa_verbose !== nothing && (is_verbose = sa_verbose)
        sa_silent !== nothing && (is_silent = sa_silent)
        sa_local !== nothing && (is_local = sa_local)
        !isempty(sa_create) && (create_env = sa_create)
        !isempty(sa_desc) && (description = sa_desc)

        for pkg in extract_packages_from_line(line)
            !(pkg in packages) && push!(packages, pkg)
        end
    end
    return packages, fallback_env, excluded_envs, is_verbose, is_silent, create_env, description, is_local
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
        end
    end
    return sort(matching_envs)
end

function filter_matching_envs(
    matching::Vector{String}, fallback_env::String, excluded_envs::Vector{String}
)
    return filter(matching) do env
        if ("global" in excluded_envs) && occursin(r"^v\d+\.\d+$", env)
            return false
        end
        if env in excluded_envs
            return false
        end
        if !isempty(fallback_env) && occursin(r"^v\d+\.\d+$", env)
            return false
        end
        return true
    end
end

function __init__()
    script_path = get_script_path()
    isempty(script_path) && return nothing

    # Register automatic failure-invalidation exit hook:
    # If the script fails during runtime (e.g. non-zero exit code due to missing indirect
    # dependency or runtime exception), invalidate its cached entry immediately.
    atexit(function(exitcode=0)
        if exitcode != 0
            invalidate_script_cache(script_path)
        end
    end)

    env_verbose = get(ENV, "QUICKENV_VERBOSE", "false")
    env_silent = get(ENV, "QUICKENV_SILENT", "false")

    # Fast 1-step script-level cache hit (mtime + path verification)
    cached_script_env = check_script_cache_hit(script_path)
    if cached_script_env !== nothing
        is_verbose = (lowercase(env_verbose) == "true")
        if is_verbose
            println(stderr)
            @info "QuickEnv: Fast script cache hit for $script_path -> @$cached_script_env"
            println(stderr)
        end
        activate_shared_env(cached_script_env)
        return nothing
    end

    required_packages, fallback_env, excluded_envs, script_verbose, script_silent, create_env, description, is_local = parse_script_metadata(
        script_path
    )

    filter!(p -> (p != "QuickEnv"), required_packages)

    is_verbose = (lowercase(env_verbose) == "true") || script_verbose
    is_silent = (lowercase(env_silent) == "true") || script_silent

    diagnose_and_suggest_packages(required_packages, is_silent)

    if handle_forced_creation(create_env, required_packages, is_verbose, is_silent)
        warn_ignored_local_files(script_path, create_env, is_silent)
        update_active_env_description(description)
        update_script_cache_entry(script_path, create_env)
        return nothing
    end

    handle_matching_or_fallback(
        required_packages, fallback_env, excluded_envs, is_verbose, is_silent, is_local, script_path
    )

    project_file = Base.active_project()
    if project_file !== nothing
        active_dir = dirname(project_file)
        if active_dir != dirname(script_path) && !occursin(r"^v\d+\.\d+$", basename(active_dir))
            warn_ignored_local_files(script_path, basename(active_dir), is_silent)
            if isempty(fallback_env) && !is_local
                update_script_cache_entry(script_path, basename(active_dir))
            end
        end
    end

    update_active_env_description(description)
    return nothing
end

end # module
