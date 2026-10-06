module QuickEnv

using TOML
using SHA
using FileWatching: Pidfile

function isolate_load_path!()
    lowercase(get(ENV, "QUICKENV_ISOLATE_LOAD_PATH", "false")) == "true" ||
        return nothing
    filter!(entry -> !startswith(entry, "@v"), LOAD_PATH)
    "@" in LOAD_PATH || pushfirst!(LOAD_PATH, "@")
    "@stdlib" in LOAD_PATH || push!(LOAD_PATH, "@stdlib")
    package_root = dirname(@__DIR__)
    if package_root ∉ LOAD_PATH
        stdlib_index = findfirst(==("@stdlib"), LOAD_PATH)
        stdlib_index === nothing ? push!(LOAD_PATH, package_root) :
            insert!(LOAD_PATH, stdlib_index, package_root)
    end
    return nothing
end

# =============================================================================
# Path & Script Utilities
# =============================================================================

"""
    get_script_path() -> String

Retrieve the absolute path to the currently executing Julia script. Returns an
empty string if Julia is running interactively.
"""
function get_script_path()
    if !isempty(PROGRAM_FILE)
        return abspath(PROGRAM_FILE)
    end
    source_path = Base.source_path(nothing)
    if source_path !== nothing && !isempty(source_path)
        resolved = abspath(source_path)
        isfile(resolved) && !startswith(resolved, @__DIR__) && return resolved
    end
    for frame in stacktrace()
        raw_path = String(frame.file)
        raw_path in ("none", "REPL", "client.jl", "loading.jl") && continue
        resolved = abspath(raw_path)
        isfile(resolved) && !startswith(resolved, @__DIR__) && return resolved
    end
    return ""
end

function activate_shared_env(env_name::String)
    env_dir = joinpath(DEPOT_PATH[1], "environments", env_name)
    project = isfile(joinpath(env_dir, "JuliaProject.toml")) ?
        joinpath(env_dir, "JuliaProject.toml") : joinpath(env_dir, "Project.toml")
    if !isfile(project)
        mkpath(env_dir)
        touch(project)
    end
    Base.set_active_project(project)
    isolate_load_path!()
    return Base.active_project()
end

function activate_local_dir_env(dir_path::String)
    project = isfile(joinpath(dir_path, "JuliaProject.toml")) ?
        joinpath(dir_path, "JuliaProject.toml") : joinpath(dir_path, "Project.toml")
    isfile(project) || touch(project)
    Base.set_active_project(project)
    isolate_load_path!()
    return Base.active_project()
end

# =============================================================================
# Cache Subsystem (Content-Validated Script and Resolution Caches)
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
    return bytes2hex(sha256(key))[1:12]
end

file_digest(path::String) = isfile(path) ? bytes2hex(sha256(read(path))) : ""

function project_resolution_digest(path::String)
    isfile(path) || return ""
    try
        project = TOML.parsefile(path)
        relevant = Dict(
            key => project[key] for key in
            ("deps", "compat", "sources", "weakdeps", "extensions", "quickenv_sources") if
            haskey(project, key)
        )
        io = IOBuffer()
        TOML.print(io, relevant; sorted=true)
        return bytes2hex(sha256(take!(io)))
    catch
        return ""
    end
end

function environment_digest(env_name::String)
    env_dir = joinpath(DEPOT_PATH[1], "environments", env_name)
    project = joinpath(env_dir, "Project.toml")
    manifest = joinpath(env_dir, "Manifest.toml")
    (!isfile(project) || !isfile(manifest)) && return ""
    project_digest = project_resolution_digest(project)
    isempty(project_digest) && return ""
    return bytes2hex(sha256(project_digest * ":" * file_digest(manifest)))[1:24]
end

function environment_sources(env_name::String)
    project = joinpath(DEPOT_PATH[1], "environments", env_name, "Project.toml")
    isfile(project) || return String[]
    try
        return String.(get(TOML.parsefile(project), "quickenv_sources", String[]))
    catch
        return String[]
    end
end

function with_cache_lock(f::Function)
    try
        cdir = get_cache_dir()
        mkpath(cdir)
        return Pidfile.mkpidlock(f, joinpath(cdir, "cache.pid"); stale_age=10)
    catch e
        @debug "QuickEnv: Cache operation unavailable" exception=e
        return nothing
    end
end

function load_cache()
    cfile = get_cache_file()
    if isfile(cfile)
        try
            return TOML.parsefile(cfile)
        catch e
            @debug "QuickEnv: Failed to parse cache file" file=cfile exception=e
            return Dict{String,Any}()
        end
    end
    return Dict{String,Any}()
end

function save_cache_unlocked(cache_data::Dict{String,Any})
    cdir = get_cache_dir()
    mkpath(cdir)
    cfile = get_cache_file()
    tmpfile = cfile * ".tmp." * string(getpid())
    try
        open(tmpfile, "w") do io
            return TOML.print(io, cache_data)
        end
        mv(tmpfile, cfile; force=true)
    catch e
        @debug "QuickEnv: Failed to save cache file" file=cfile exception=e
        isfile(tmpfile) && rm(tmpfile; force=true)
    end
end

function save_cache(cache_data::Dict{String,Any})
    return with_cache_lock() do
        save_cache_unlocked(cache_data)
    end
end

function script_files(script_path::String)
    files = String[]
    discover_script_files!(files, abspath(script_path), Set{String}())
    return files
end

"""
    check_script_cache_hit(script_path::String) -> Union{Nothing, String}

Validate the cached entry script, static includes, target environment, and
stitch sources by content digest before returning the target environment.
"""
function check_script_cache_hit(script_path::String)
    isempty(script_path) && return nothing
    !isfile(script_path) && return nothing

    cache = load_cache()
    scripts_table = get(cache, "scripts", Dict{String,Any}())
    scripts_table isa AbstractDict || return nothing
    !haskey(scripts_table, script_path) && return nothing

    entry = scripts_table[script_path]
    entry isa AbstractDict || return nothing
    cached_files = get(entry, "files", String[])
    cached_digests = get(entry, "digests", String[])
    sources = get(entry, "sources", String[])
    source_digests = get(entry, "source_digests", String[])
    valid_vectors = cached_files isa Vector && cached_digests isa Vector &&
        sources isa Vector && source_digests isa Vector &&
        all(item -> item isa String, cached_files) &&
        all(item -> item isa String, cached_digests) &&
        all(item -> item isa String, sources) &&
        all(item -> item isa String, source_digests)
    if valid_vectors && !isempty(cached_files) &&
       length(cached_files) == length(cached_digests) &&
       all(isfile(path) && file_digest(path) == digest for (path, digest) in zip(cached_files, cached_digests))
        target_env = get(entry, "env", "")
        if target_env isa String && !isempty(target_env)
            current_env_digest = environment_digest(target_env)
            if !isempty(current_env_digest) &&
               current_env_digest == get(entry, "env_digest", "") &&
               environment_digest.(sources) == source_digests
                return target_env
            end
        end
    end
    return nothing
end

function update_script_cache_entry(script_path::String, env_name::String)
    isempty(script_path) && return nothing
    !isfile(script_path) && return nothing

    files = script_files(script_path)
    return with_cache_lock() do
        cache = load_cache()
        scripts_table = get(cache, "scripts", Dict{String,Any}())
        scripts_table isa AbstractDict || (scripts_table = Dict{String,Any}())
        sources = environment_sources(env_name)
        scripts_table[script_path] = Dict{String,Any}(
            "files" => files,
            "digests" => file_digest.(files),
            "env" => env_name,
            "env_digest" => environment_digest(env_name),
            "sources" => sources,
            "source_digests" => environment_digest.(sources),
            "updated_at" => string(time()),
        )
        cache["scripts"] = scripts_table
        save_cache_unlocked(cache)
    end
end

"""
    invalidate_script_cache(script_path::String)

Purge the cached resolution entry for a specific script. Automatically called
if a script exits with a non-zero exit code, ensuring that broken or partially
modified multi-file dependencies trigger a fresh resolution.
"""
function invalidate_script_cache(script_path::String)
    isempty(script_path) && return nothing
    return with_cache_lock() do
        cache = load_cache()
        scripts_table = get(cache, "scripts", Dict{String,Any}())
        scripts_table isa AbstractDict || return nothing
        if haskey(scripts_table, script_path)
            delete!(scripts_table, script_path)
            cache["scripts"] = scripts_table
            save_cache_unlocked(cache)
        end
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
    entry isa AbstractDict || return nothing
    env_name = get(entry, "env", "")
    sources = get(entry, "sources", String[])
    cached_digests = get(entry, "source_digests", String[])

    env_name isa String || return nothing
    sources isa Vector && all(item -> item isa String, sources) || return nothing
    cached_digests isa Vector && all(item -> item isa String, cached_digests) || return nothing
    isempty(env_name) && return nothing

    # Verify target environment exists
    target_dir = joinpath(DEPOT_PATH[1], "environments", env_name)
    !isfile(joinpath(target_dir, "Project.toml")) && return nothing
    !isfile(joinpath(target_dir, "Manifest.toml")) && return nothing
    environment_digest(env_name) != get(entry, "target_digest", "") && return nothing

    # Verify all source environments still exist with matching content digests
    if length(sources) != length(cached_digests)
        return nothing # Corrupted cache entry
    end
    for i in 1:length(sources)
        if environment_digest(sources[i]) != cached_digests[i]
            return nothing # Cache stale!
        end
    end

    return env_name
end

function update_cache_entry(
    required_packages::Vector{String}, target_env::String, source_envs::Vector{String}
)
    isempty(required_packages) && return nothing
    key = get_canonical_key(required_packages)
    return with_cache_lock() do
        cache = load_cache()
        cache[key] = Dict(
            "env" => target_env,
            "sources" => source_envs,
            "source_digests" => environment_digest.(source_envs),
            "target_digest" => environment_digest(target_env),
            "updated_at" => string(time()),
        )
        save_cache_unlocked(cache)
    end
end

# =============================================================================
# Time-Bounded Bitmask Cover Engine
# =============================================================================

"""
    find_minimal_covering_envs(
        required_pkgs::Vector{String},
        candidate_envs::Vector{Tuple{String, Vector{String}}};
        timeout_sec::Float64=1.0,
    ) -> Vector{String}

Given required packages and available candidate environments, use branch-and-bound
over UInt64 coverage masks. Minimize environment count, then extraneous direct
dependencies. Return the best complete cover found within the time budget.
"""
function find_minimal_covering_envs(
    required_pkgs::Vector{String},
    candidate_envs::Vector{Tuple{String,Vector{String}}};
    timeout_sec::Float64=1.0,
    compatibility_check::Function=(_ -> true),
)
    start_time = time()
    n = length(required_pkgs)
    (n == 0 || n > 64 || timeout_sec <= 0) && return String[]
    target_mask = n == 64 ? typemax(UInt64) : (UInt64(1) << n) - 1

    # Convert candidate environments to bitmasks and compute extraneous count
    env_info = Tuple{String,UInt64,Int}[] # (name, mask, extra_count)
    for (name, pkgs) in candidate_envs
        if (time() - start_time) > timeout_sec
            return String[]
        end

        package_set = Set(pkgs)
        mask = UInt64(0)
        matched_count = 0
        for (i, p) in enumerate(required_pkgs)
            if p in package_set
                mask |= (UInt64(1) << (i - 1))
                matched_count += 1
            end
        end
        if mask > 0
            extra_count = length(pkgs) - matched_count
            push!(env_info, (name, mask, extra_count))
        end
    end

    sort!(env_info; by=info -> (-count_ones(info[2]), info[3], info[1]))
    isempty(env_info) && return String[]

    suffix_union = fill(UInt64(0), length(env_info) + 1)
    for index in length(env_info):-1:1
        suffix_union[index] = suffix_union[index + 1] | env_info[index][2]
    end

    best = String[]
    best_count = Ref(typemax(Int))
    best_extra = Ref(typemax(Int))
    selected = String[]

    function search(index::Int, coverage::UInt64, extra::Int)
        (time() - start_time) > timeout_sec && return nothing
        if coverage == target_mask
            if length(selected) < best_count[] ||
               (length(selected) == best_count[] && extra < best_extra[])
                empty!(best)
                append!(best, selected)
                best_count[] = length(selected)
                best_extra[] = extra
            end
            return nothing
        end
        index > length(env_info) && return nothing
        length(selected) >= best_count[] && return nothing
        (coverage | suffix_union[index]) != target_mask && return nothing

        name, mask, candidate_extra = env_info[index]
        if count_ones(mask & ~coverage) > 0
            push!(selected, name)
            if compatibility_check(selected)
                search(index + 1, coverage | mask, extra + candidate_extra)
            end
            pop!(selected)
        end
        search(index + 1, coverage, extra)
        return nothing
    end

    search(1, UInt64(0), 0)
    return best
end

"""
    find_partial_covering_envs(
        required_pkgs::Vector{String},
        candidate_envs::Vector{Tuple{String,Vector{String}}};
        timeout_sec::Float64=1.0,
        strict_subset::Bool=true,
    ) -> Tuple{Vector{String}, Vector{String}}

Given required packages and available candidate environments, use hardware bitmasks
to find a maximal compatible subset of environments whose packages are strictly contained
in `required_pkgs` (when `strict_subset=true`). Maximizes compatible coverage, then
minimizes environment count and extraneous dependencies.
Returns `(selected_covering_envs, covered_packages)`.
"""
function find_partial_covering_envs(
    required_pkgs::Vector{String},
    candidate_envs::Vector{Tuple{String,Vector{String}}};
    timeout_sec::Float64=1.0,
    strict_subset::Bool=true,
    compatibility_check::Function=(_ -> true),
)
    start_time = time()
    n = length(required_pkgs)
    n > 64 && return String[], String[]
    req_set = Set(required_pkgs)

    valid_candidates = Tuple{String,UInt64,Int}[] # (name, mask, extra_count)
    for (name, pkgs) in candidate_envs
        if (time() - start_time) > timeout_sec
            return String[], String[]
        end
        if strict_subset && !all(p -> p in req_set, pkgs)
            continue
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
            push!(valid_candidates, (name, mask, extra_count))
        end
    end

    isempty(valid_candidates) && return String[], String[]

    sort!(valid_candidates; by=candidate -> (-count_ones(candidate[2]), candidate[3], candidate[1]))
    suffix_union = fill(UInt64(0), length(valid_candidates) + 1)
    for index in length(valid_candidates):-1:1
        suffix_union[index] = suffix_union[index + 1] | valid_candidates[index][2]
    end

    selected = String[]
    best = String[]
    best_cov = Ref(UInt64(0))
    best_extra = Ref(typemax(Int))

    function search(index::Int, coverage::UInt64, extra::Int)
        (time() - start_time) > timeout_sec && return nothing
        possible = coverage | suffix_union[index]
        possible_count = count_ones(possible)
        best_coverage_count = count_ones(best_cov[])
        possible_count < best_coverage_count && return nothing
        possible_count == best_coverage_count && !isempty(best) &&
            length(selected) >= length(best) && return nothing
        if index > length(valid_candidates)
            coverage_count = count_ones(coverage)
            best_count = count_ones(best_cov[])
            if coverage_count > best_count ||
               (coverage_count == best_count && length(selected) < length(best)) ||
               (coverage_count == best_count && length(selected) == length(best) && extra < best_extra[])
                best_cov[] = coverage
                best_extra[] = extra
                empty!(best)
                append!(best, selected)
            end
            return nothing
        end

        name, mask, candidate_extra = valid_candidates[index]
        if count_ones(mask & ~coverage) > 0
            push!(selected, name)
            compatibility_check(selected) &&
                search(index + 1, coverage | mask, extra + candidate_extra)
            pop!(selected)
        end
        search(index + 1, coverage, extra)
        return nothing
    end

    search(1, UInt64(0), 0)

    covered_pkgs = String[]
    for i in 1:n
        if (best_cov[] & (UInt64(1) << (i - 1))) != 0
            push!(covered_pkgs, required_pkgs[i])
        end
    end

    return best, covered_pkgs
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
function normalize_manifest_entry(entry::AbstractDict, env_dir::String)
    normalized = deepcopy(Dict{String,Any}(entry))
    if haskey(normalized, "path") && !isabspath(normalized["path"])
        normalized["path"] = normpath(joinpath(env_dir, normalized["path"]))
    end
    return normalized
end

function add_manifest_entry!(merged::Dict{String,Any}, package::String, entry::Dict{String,Any})
    if !haskey(merged, package)
        merged[package] = Any[entry]
        return nothing
    end
    existing = merged[package]
    entries = existing isa Vector ? existing : Any[existing]
    existing_uuid = get(first(entries), "uuid", "")
    entry_uuid = get(entry, "uuid", "")
    existing_uuid == entry_uuid ||
        error("ambiguous manifest name $package has UUIDs $existing_uuid and $entry_uuid")
    merged[package] = entries
    return nothing
end

function compatible_julia_version(manifest::AbstractDict)
    raw = get(manifest, "julia_version", nothing)
    format = string(get(manifest, "manifest_format", ""))
    (raw === nothing || !startswith(format, "2")) && return false
    try
        version = VersionNumber(raw)
        return version.major == VERSION.major && version.minor == VERSION.minor
    catch
        return false
    end
end

function check_manifest_compat(
    env_names::Vector{String}; require_current_julia::Bool=true
)
    isempty(env_names) && return false, Dict{String,Any}(), Dict{String,Any}()
    merged_deps = Dict{String,Any}()
    merged_manifest_deps = Dict{String,Any}()
    entries_by_uuid = Dict{String,Dict{String,Any}}()
    names_by_uuid = Dict{String,String}()

    for env_name in env_names
        env_dir = joinpath(DEPOT_PATH[1], "environments", env_name)
        proj_file = joinpath(env_dir, "Project.toml")
        mani_file = joinpath(env_dir, "Manifest.toml")
        (!isfile(proj_file) || !isfile(mani_file)) &&
            return false, Dict{String,Any}(), Dict{String,Any}()
        try
            project = TOML.parsefile(proj_file)
            manifest = TOML.parsefile(mani_file)
            (!require_current_julia || compatible_julia_version(manifest)) ||
                return false, Dict{String,Any}(), Dict{String,Any}()
            direct_deps = get(project, "deps", Dict{String,Any}())
            manifest_deps = get(manifest, "deps", nothing)
            manifest_deps isa AbstractDict ||
                return false, Dict{String,Any}(), Dict{String,Any}()

            source_uuids = Set{String}()
            for (package, value) in manifest_deps
                entries = value isa Vector ? value : Any[value]
                for raw_entry in entries
                    raw_entry isa AbstractDict ||
                        return false, Dict{String,Any}(), Dict{String,Any}()
                    entry = normalize_manifest_entry(raw_entry, env_dir)
                    uuid = string(get(entry, "uuid", ""))
                    isempty(uuid) && return false, Dict{String,Any}(), Dict{String,Any}()
                    push!(source_uuids, uuid)
                    if haskey(names_by_uuid, uuid) && names_by_uuid[uuid] != package
                        return false, Dict{String,Any}(), Dict{String,Any}()
                    end
                    if haskey(entries_by_uuid, uuid) && entries_by_uuid[uuid] != entry
                        return false, Dict{String,Any}(), Dict{String,Any}()
                    end
                    names_by_uuid[uuid] = String(package)
                    entries_by_uuid[uuid] = entry
                    add_manifest_entry!(merged_manifest_deps, String(package), entry)
                end
            end

            for (package, raw_uuid) in direct_deps
                uuid = string(raw_uuid)
                uuid in source_uuids ||
                    return false, Dict{String,Any}(), Dict{String,Any}()
                if haskey(merged_deps, package) && merged_deps[package] != raw_uuid
                    return false, Dict{String,Any}(), Dict{String,Any}()
                end
                merged_deps[String(package)] = raw_uuid
            end
        catch e
            @debug "QuickEnv: Invalid source environment" environment=env_name exception=e
            return false, Dict{String,Any}(), Dict{String,Any}()
        end
    end

    return true, merged_deps, merged_manifest_deps
end

function manifest_compatibility_checker()
    singleton_cache = Dict{String,Bool}()
    pair_cache = Dict{Tuple{String,String},Bool}()
    return function (env_names::Vector{String})
        isempty(env_names) && return false
        newest = last(env_names)
        get!(singleton_cache, newest) do
            first(check_manifest_compat([newest]))
        end || return false
        for previous in @view(env_names[1:(end - 1)])
            key = previous <= newest ? (previous, newest) : (newest, previous)
            get!(pair_cache, key) do
                first(check_manifest_compat(collect(key)))
            end || return false
        end
        return true
    end
end

"""
    stitch_environments(
        target_env::String,
        source_envs::Vector{String},
        is_silent::Bool
    ) -> Bool

Strictly validate and stitch compatible source environments into target_env without
invoking Pkg's resolver. Julia may reuse compatible compile caches.
"""
function stitch_environments(
    target_env::String, source_envs::Vector{String}, is_silent::Bool
)
    compat, merged_deps, merged_manifest_deps = check_manifest_compat(source_envs)
    !compat && return false

    env_root = joinpath(DEPOT_PATH[1], "environments")
    target_dir = joinpath(env_root, target_env)
    mkpath(env_root)

    compat_bounds = Dict{String,String}()
    for (package, value) in merged_manifest_deps
        entries = value isa Vector ? value : Any[value]
        direct_uuid = get(merged_deps, package, nothing)
        direct_uuid === nothing && continue
        entry = findfirst(item -> get(item, "uuid", nothing) == direct_uuid, entries)
        entry === nothing && continue
        version = get(entries[entry], "version", "")
        !isempty(version) && (compat_bounds[package] = "=" * string(version))
    end

    # Prepare a complete project before installing the staging directory.
    proj_content = Dict(
        "name" => target_env,
        "description" =>
            "Autonomous compound environment combining @" * join(source_envs, ", @"),
        "quickenv_sources" => source_envs,
        "deps" => merged_deps,
    )
    !isempty(compat_bounds) && (proj_content["compat"] = compat_bounds)
    manifest_content = Dict(
        "julia_version" => string(VERSION),
        "manifest_format" => "2.0",
        "deps" => merged_manifest_deps,
    )

    stage_dir = mktempdir(env_root; prefix=".$target_env.stage.")
    chmod(stage_dir, 0o755)
    try
        open(joinpath(stage_dir, "Project.toml"), "w") do io
            return TOML.print(io, proj_content)
        end
        open(joinpath(stage_dir, "Manifest.toml"), "w") do io
            return TOML.print(io, manifest_content)
        end
        lock_path = joinpath(env_root, ".$target_env.pid")
        Pidfile.mkpidlock(lock_path; stale_age=10) do
            if isdir(target_dir)
                staged_project = joinpath(stage_dir, "Project.toml")
                staged_manifest = joinpath(stage_dir, "Manifest.toml")
                same_project = file_digest(staged_project) ==
                    file_digest(joinpath(target_dir, "Project.toml"))
                same_manifest = file_digest(staged_manifest) ==
                    file_digest(joinpath(target_dir, "Manifest.toml"))
                same_project && same_manifest ||
                    error("auto-environment identity collision for @$target_env")
            else
                mv(stage_dir, target_dir)
            end
        end
    catch e
        @debug "QuickEnv: Failed to synthesize environment" environment=target_env exception=e
        return false
    finally
        isdir(stage_dir) && rm(stage_dir; recursive=true, force=true)
    end

    if !is_silent
        println(stderr)
        @info "QuickEnv: Fast-stitched autonomous environment @$target_env\nfrom " *
            join(source_envs, " + ")
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
    for i in 0:m
        d[i + 1, 1] = i
    end
    for j in 0:n
        d[1, j + 1] = j
    end
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
            startswith(entry, ".") && continue
            toml_path = joinpath(env_dir, entry, "Project.toml")
            if isfile(toml_path)
                try
                    project_data = TOML.parsefile(toml_path)
                    deps = get(project_data, "deps", Dict{String,Any}())
                    for (k, _) in deps
                        push!(known, String(k))
                    end
                catch e
                    @debug "QuickEnv: Error parsing Project.toml" file=toml_path exception=e
                end
            end
        end
    end

    active_proj = Base.active_project()
    if active_proj !== nothing && isfile(active_proj)
        try
            project_data = TOML.parsefile(active_proj)
            deps = get(project_data, "deps", Dict{String,Any}())
            for (k, _) in deps
                push!(known, String(k))
            end
        catch e
            @debug "QuickEnv: Error parsing active project Project.toml" file=active_proj exception=e
        end
    end

    return known
end

function is_stdlib(package::String)
    package in ("Base", "Core", "Main") && return true
    return isfile(joinpath(Sys.STDLIB, package, "Project.toml"))
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

        # Prefix / truncation check in known local environments
        # Catches common abbreviations or truncations (e.g. BasicCompGeom -> BasicCompGeometry)
        if suggestion === nothing && length(pkg) >= 4
            prefix_candidates = String[]
            pkg_lower = lowercase(pkg)
            for cand in known_local
                cand_lower = lowercase(cand)
                if (startswith(cand_lower, pkg_lower) || startswith(pkg_lower, cand_lower)) &&
                   abs(length(cand) - length(pkg)) <= 6
                    push!(prefix_candidates, cand)
                end
            end
            if length(prefix_candidates) == 1
                suggestion = first(prefix_candidates)
            elseif length(prefix_candidates) > 1
                sort!(prefix_candidates, by = c -> abs(length(c) - length(pkg)))
                if abs(length(prefix_candidates[1]) - length(pkg)) < abs(length(prefix_candidates[2]) - length(pkg))
                    suggestion = first(prefix_candidates)
                end
            end
        end

        if suggestion === nothing
            if !registry_loaded
                try
                    reg_file = joinpath(
                        DEPOT_PATH[1], "registries", "General", "Registry.toml"
                    )
                    if isfile(reg_file)
                        reg_data = TOML.parsefile(reg_file)
                        pkgs_dict = get(reg_data, "packages", Dict{String,Any}())
                        for (uuid, pinfo) in pkgs_dict
                            pname = get(pinfo, "name", "")
                            !isempty(pname) && push!(registry_pkgs, pname)
                        end
                    end
                catch e
                    @debug "QuickEnv: Error parsing Registry.toml" file=reg_file exception=e
                end

                # If registry_pkgs is empty (e.g. compressed General registry tarball), try Pkg reachable registries
                if isempty(registry_pkgs)
                    try
                        pkg_mod = Base.require(Main, :Pkg)
                        registry = Base.invokelatest(getproperty, pkg_mod, :Registry)
                        reachable = Base.invokelatest(
                            getproperty, registry, :reachable_registries
                        )
                        regs = Base.invokelatest(reachable)
                        for reg in regs
                            for (uuid, pkg_info) in reg.pkgs
                                push!(registry_pkgs, pkg_info.name)
                            end
                        end
                    catch e
                        @debug "QuickEnv: Error reading reachable registries via Pkg" exception=e
                    end
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

            # Prefix / truncation check in General registry (requires unique match)
            if suggestion === nothing && length(pkg) >= 5
                reg_prefix_candidates = String[]
                pkg_lower = lowercase(pkg)
                for cand in registry_pkgs
                    cand_lower = lowercase(cand)
                    if (startswith(cand_lower, pkg_lower) || startswith(pkg_lower, cand_lower)) &&
                       abs(length(cand) - length(pkg)) <= 4
                        push!(reg_prefix_candidates, cand)
                        length(reg_prefix_candidates) > 1 && break
                    end
                end
                if length(reg_prefix_candidates) == 1
                    suggestion = first(reg_prefix_candidates)
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
    env_name = first(matching)

    current_project = Base.active_project()
    if current_project === nothing || basename(dirname(current_project)) != env_name
        if is_verbose
            println(stderr)
            @info "QuickEnv: Found matching environment @$env_name.\nActivating..."
            println(stderr)
        end
        activate_shared_env(env_name)
    end
    isolate_load_path!()
end

function activate_fallback_env(fallback_env::String, script_path::String, is_verbose::Bool)
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

function lazy_pkg_add(packages::Vector{String}, is_silent::Bool)
    isempty(packages) && return nothing
    pkg_mod = Base.require(Main, :Pkg)
    add = Base.invokelatest(getproperty, pkg_mod, :add)
    preserve_tiered = Base.invokelatest(getproperty, pkg_mod, :PRESERVE_TIERED)
    return Base.invokelatest(
        add, packages;
        io=is_silent ? devnull : stderr,
        preserve=preserve_tiered,
    )
end

function auto_environment_name(required_packages::Vector{String}, source_envs=String[])
    key = get_canonical_key(required_packages)
    source_state = join((env * ":" * environment_digest(env) for env in source_envs), "+")
    version_state = "$(VERSION.major).$(VERSION.minor)"
    identity = bytes2hex(sha256(key * ":" * source_state * ":" * version_state))[1:24]
    return "auto_" * identity
end

function ensure_empty_environment(env_name::String)
    try
        env_root = joinpath(DEPOT_PATH[1], "environments")
        target_dir = joinpath(env_root, env_name)
        mkpath(env_root)
        lock_path = joinpath(env_root, ".$env_name.pid")
        return Pidfile.mkpidlock(lock_path; stale_age=10) do
            if isdir(target_dir)
                return isfile(joinpath(target_dir, "Project.toml")) &&
                    isfile(joinpath(target_dir, "Manifest.toml"))
            end
            stage_dir = mktempdir(env_root; prefix=".$env_name.stage.")
            chmod(stage_dir, 0o755)
            try
                open(joinpath(stage_dir, "Project.toml"), "w") do io
                    TOML.print(io, Dict("description" => "QuickEnv standard-library environment", "deps" => Dict()))
                end
                open(joinpath(stage_dir, "Manifest.toml"), "w") do io
                    TOML.print(
                        io,
                        Dict(
                            "julia_version" => string(VERSION),
                            "manifest_format" => "2.0",
                            "deps" => Dict(),
                        ),
                    )
                end
                mv(stage_dir, target_dir)
                return true
            finally
                isdir(stage_dir) && rm(stage_dir; recursive=true, force=true)
            end
        end
    catch e
        @debug "QuickEnv: Could not create empty environment" environment=env_name exception=e
        return false
    end
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

    deps = Dict{String,Any}()
    if isfile(project_file)
        try
            project_data = TOML.parsefile(project_file)
            deps = get(project_data, "deps", Dict{String,Any}())
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
            lazy_pkg_add(missing_pkgs, is_silent)
        catch e
            println(stderr)
            @error "QuickEnv: Failed to install packages $missing_pkgs into $target_env_display."
            diagnose_and_suggest_packages(missing_pkgs, false)
            println(stderr)
            rethrow(e)
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
2. Fast-path: Check the content-validated script and resolution caches.
3. Single-environment matching: Search existing named environments.
4. Bounded cover search and manifest stitching: combine compatible environments.
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
    filter!(package -> !is_stdlib(package), required_packages)
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
        activate_local_dir_env(script_dir)
        bootstrap_packages(required_packages, "local directory environment", is_silent)
        return nothing
    end

    if isempty(required_packages) && !isempty(fallback_env)
        activate_shared_env(fallback_env)
        return nothing
    end

    if isempty(required_packages)
        empty_env = auto_environment_name(required_packages)
        ensure_empty_environment(empty_env) && activate_shared_env(empty_env)
        return nothing
    end

    # -------------------------------------------------------------------------
    # 1. Check Content-Validated Resolution Cache
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
    filter!(env -> first(check_manifest_compat([env]; require_current_julia=false)), matching)
    sort!(matching; by=env -> (direct_dependency_count(env), env))

    if !isempty(matching)
        activate_matched_env(matching, is_verbose)
        if isempty(fallback_env) && isempty(excluded_envs)
            selected_env = matching[1]
            update_cache_entry(required_packages, selected_env, [selected_env])
        end
        return nothing
    end

    # -------------------------------------------------------------------------
    # 3. Time-Bounded Cover Search & Manifest Stitching
    # -------------------------------------------------------------------------
    if isempty(fallback_env) && length(required_packages) >= 2
        # Gather all candidate named environments and their packages
        candidate_envs = Tuple{String,Vector{String}}[]
        env_dir = joinpath(DEPOT_PATH[1], "environments")
        if isdir(env_dir)
            for entry in readdir(env_dir)
                startswith(entry, ".") && continue
                occursin(r"^v\d+\.\d+$", entry) && continue # Skip global envs
                entry in excluded_envs && continue
                toml_path = joinpath(env_dir, entry, "Project.toml")
                if isfile(toml_path)
                    try
                        p_data = TOML.parsefile(toml_path)
                        deps = get(p_data, "deps", Dict{String,Any}())
                        push!(candidate_envs, (entry, collect(keys(deps))))
                    catch e
                        @debug "QuickEnv: Error reading candidate environment Project.toml" file=toml_path exception=e
                    end
                end
            end
        end

        compatibility_check = manifest_compatibility_checker()
        covering_envs = find_minimal_covering_envs(
            required_packages,
            candidate_envs;
            compatibility_check=compatibility_check,
        )
        if !isempty(covering_envs)
            auto_env_name = auto_environment_name(required_packages, covering_envs)
            if stitch_environments(auto_env_name, covering_envs, is_silent)
                update_cache_entry(required_packages, auto_env_name, covering_envs)
                activate_matched_env([auto_env_name], is_verbose)
                return nothing
            end
        end

        # ---------------------------------------------------------------------
        # 3b. Optimization A: Partial Fast Stitch + Incremental Pkg.add
        # ---------------------------------------------------------------------
        partial_envs, covered_pkgs = find_partial_covering_envs(
            required_packages,
            candidate_envs;
            strict_subset=true,
            compatibility_check=compatibility_check,
        )
        if !isempty(partial_envs) && !isempty(covered_pkgs)
            auto_env_name = auto_environment_name(required_packages, partial_envs)
            if stitch_environments(auto_env_name, partial_envs, is_silent)
                target_env_display = activate_fallback_env(auto_env_name, script_path, is_verbose)
                try
                    length(covered_pkgs) < length(required_packages) &&
                        bootstrap_packages(required_packages, target_env_display, is_silent)
                    update_cache_entry(required_packages, auto_env_name, [auto_env_name])
                    return nothing
                catch e
                    @debug "QuickEnv: Partial environment completion failed; using clean fallback" exception=e
                end
            end
        end
    end

    # -------------------------------------------------------------------------
    # 4. Autonomous Environment Creation or Explicit Fallback Execution
    # -------------------------------------------------------------------------
    target_env = fallback_env
    if isempty(target_env)
        target_env = auto_environment_name(required_packages)
    end

    target_env_display = activate_fallback_env(target_env, script_path, is_verbose)
    bootstrap_packages(required_packages, target_env_display, is_silent)
    if isempty(fallback_env)
        update_cache_entry(required_packages, target_env, [target_env])
    end
end

function handle_forced_creation(
    create_env::String, required_packages::Vector{String}, is_verbose::Bool, is_silent::Bool
)
    isempty(create_env) && return false

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
            @error "QuickEnv: Error parsing Project TOML file at $toml_path: $e"
        end
    end

    if has_all_packages
        current_project = Base.active_project()
        if current_project === nothing || basename(dirname(current_project)) != create_env
            if is_verbose
                println(stderr)
                @info "QuickEnv: Found existing environment @$create_env\nwith all dependencies. Activating..."
                println(stderr)
            end
            activate_shared_env(create_env)
        end
        isolate_load_path!()
        return true
    end

    if !is_silent
        println(stderr, "\n=== QuickEnv: Environment Configuration Required ===")
        if !isdir(env_dir)
            println(stderr, "Action: Creating new shared named environment @$create_env.")
        else
            println(
                stderr, "Action: Updating existing shared named environment @$create_env."
            )
        end
        println(stderr, "Reason: Missing required packages: $missing_pkgs")
        println(stderr, "Triggering automatic package installation...")
        println(stderr, "====================================================\n")
    end

    activate_shared_env(create_env)
    isempty(missing_pkgs) && return true
    try
        lazy_pkg_add(missing_pkgs, is_silent)
    catch e
        println(stderr)
        @error "QuickEnv: Failed to install packages $missing_pkgs into @$create_env."
        diagnose_and_suggest_packages(missing_pkgs, false)
        println(stderr)
        rethrow(e)
    end
    return true
end

function update_description(file_path::String, new_desc::String)
    try
        mkpath(dirname(file_path))
        lock_path = joinpath(dirname(file_path), ".$(basename(file_path)).pid")
        return Pidfile.mkpidlock(lock_path; stale_age=10) do
            lines = isfile(file_path) ? readlines(file_path; keep=true) : String[]
            description_replaced = false
            escaped_desc = replace(new_desc, "\\" => "\\\\", "\"" => "\\\"")

            updated_lines = String[]
            for line in lines
                if occursin(r"^\s*description\s*=\s*\".*\"\s*$", line)
                    description_replaced = true
                    push!(updated_lines, "description = \"$escaped_desc\"\n")
                else
                    push!(updated_lines, line)
                end
            end

            if !description_replaced
                pushfirst!(updated_lines, "description = \"$escaped_desc\"\n\n")
            end

            temp_path, io = mktemp(dirname(file_path))
            try
                write(io, join(updated_lines))
                close(io)
                mv(temp_path, file_path; force=true)
            finally
                isopen(io) && close(io)
                isfile(temp_path) && rm(temp_path; force=true)
            end
        end
    catch e
        @debug "QuickEnv: Could not update environment description" file=file_path exception=e
        return nothing
    end
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

function import_root(node)
    if node isa Symbol
        name = String(node)
        return startswith(name, ".") ? "" : name
    end
    node isa Expr || return ""
    node.head == :as && return isempty(node.args) ? "" : import_root(first(node.args))
    if node.head == :colon || node.head == :(:)
        return isempty(node.args) ? "" : import_root(first(node.args))
    end
    node.head == :. || return ""
    isempty(node.args) && return ""
    first_arg = first(node.args)
    first_arg == :. && return ""
    return import_root(first_arg)
end

function collect_syntax_metadata!(packages::Vector{String}, includes::Vector{String}, node)
    node isa Expr || return nothing
    node.head in (:quote, :inert) && return nothing
    if node.head in (:using, :import)
        for arg in node.args
            package = import_root(arg)
            !isempty(package) && package ∉ packages &&
                push!(packages, package)
        end
        return nothing
    end
    if node.head == :call && length(node.args) == 2 && node.args[1] == :include &&
       node.args[2] isa String
        push!(includes, node.args[2])
        return nothing
    end
    for arg in node.args
        collect_syntax_metadata!(packages, includes, arg)
    end
    return nothing
end

function parse_source_syntax(source::String)
    packages = String[]
    includes = String[]
    try
        collect_syntax_metadata!(packages, includes, Meta.parseall(source))
    catch e
        @debug "QuickEnv: Julia syntax parsing failed" exception=e
    end
    return packages, includes
end

function lex_source_lines(source::String)
    lines = Tuple{String,String}[]
    code = IOBuffer()
    comment = IOBuffer()
    state = :code
    block_depth = 0
    escaped = false
    previous_significant = '\0'
    chars = collect(source)
    i = 1
    while i <= length(chars)
        char = chars[i]
        next_char = i < length(chars) ? chars[i + 1] : '\0'
        third_char = i + 1 < length(chars) ? chars[i + 2] : '\0'
        if char == '\n'
            push!(lines, (String(take!(code)), String(take!(comment))))
            state == :line_comment && (state = :code)
            escaped = false
            previous_significant = '\0'
            i += 1
            continue
        end
        if state == :line_comment
            print(comment, char)
        elseif state == :block_comment
            if char == '#' && next_char == '='
                block_depth += 1
                i += 1
            elseif char == '=' && next_char == '#'
                block_depth -= 1
                i += 1
                block_depth == 0 && (state = :code)
            end
        elseif state in (:string, :char, :command)
            print(code, char)
            delimiter = state == :string ? '"' : state == :char ? '\'' : '`'
            if char == delimiter && !escaped
                state = :code
            end
            escaped = char == '\\' && !escaped
            char != '\\' && (escaped = false)
        elseif state == :triple_string
            print(code, char)
            if char == '"' && next_char == '"' && third_char == '"'
                print(code, "\"\"")
                i += 2
                state = :code
            end
        elseif char == '#' && next_char == '='
            state = :block_comment
            block_depth = 1
            i += 1
        elseif char == '#'
            state = :line_comment
        elseif char == '"' && next_char == '"' && third_char == '"'
            print(code, "\"\"\"")
            i += 2
            state = :triple_string
        elseif char == '"'
            print(code, char)
            state = :string
        elseif char == '\''
            print(code, char)
            if !(isletter(previous_significant) || isnumeric(previous_significant) ||
                 previous_significant in (')', ']', '}', '\''))
                state = :char
            end
        elseif char == '`'
            print(code, char)
            state = :command
        else
            print(code, char)
        end
        state == :code && !isspace(char) && (previous_significant = char)
        i += 1
    end
    if position(code) > 0 || position(comment) > 0
        push!(lines, (String(take!(code)), String(take!(comment))))
    end
    return lines
end

function extract_packages_from_line(line::String)
    lines = lex_source_lines(line)
    isempty(lines) && return String[]
    parsed, _ = parse_source_syntax(first(lines)[1])
    return parsed
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
    length(parts) <= 1 && return fallback_env,
    excluded_envs, is_verbose, is_silent, create_env, description,
    is_local

    comment_part = strip(parts[2])
    clean_line = strip(parts[1])
    !occursin(r"\bQuickEnv\b", clean_line) && return fallback_env,
    excluded_envs, is_verbose, is_silent, create_env, description,
    is_local

    if occursin(r"(?i)\bverbose\b", comment_part)
        is_verbose = true
    end
    if occursin(r"(?i)\bsilent\b", comment_part)
        is_silent = true
    end
    if occursin(r"(?i)\blocal\b", comment_part)
        is_local = true
    end

    m_inline_fallback = match(r"(?i)\bfallback\s*:\s*([a-zA-Z0-9_\-]+)", comment_part)
    if m_inline_fallback !== nothing
        fallback_env = String(m_inline_fallback.captures[1])
    end

    m_inline_create = match(r"(?i)\bcreate\s*:\s*([a-zA-Z0-9_\-]+)", comment_part)
    if m_inline_create !== nothing
        create_env = String(m_inline_create.captures[1])
    end

    m_inline_desc = match(
        r"(?i)\bdesc(?:ription)?\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|([^,]*))", comment_part
    )
    if m_inline_desc !== nothing
        for cap in m_inline_desc.captures
            if cap !== nothing
                description = String(strip(cap))
                break
            end
        end
    end

    m_inline_exclude = match(r"(?i)\bexclude\s*:\s*([^#;]+)", comment_part)
    if m_inline_exclude !== nothing
        raw_excl = m_inline_exclude.captures[1]
        raw_excl = replace(raw_excl, r"(?i)\bfallback\s*:\s*[a-zA-Z0-9_\-]+" => "")
        raw_excl = replace(raw_excl, r"(?i)\bcreate\s*:\s*[a-zA-Z0-9_\-]+" => "")
        raw_excl = replace(
            raw_excl,
            r"(?i)\bdesc(?:ription)?\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|([^,]*))" => "",
        )
        raw_excl = replace(raw_excl, r"(?i)\bverbose\b" => "")
        raw_excl = replace(raw_excl, r"(?i)\bsilent\b" => "")
        raw_excl = replace(raw_excl, r"(?i)\blocal\b" => "")
        for item in split(raw_excl, ',')
            clean_item = strip(item)
            !isempty(clean_item) && push!(excluded_envs, String(clean_item))
        end
    end

    return fallback_env,
    excluded_envs, is_verbose, is_silent, create_env, description,
    is_local
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
        if m_name !== nothing
            fallback_env = String(m_name.captures[1])
        end
        m_inline_desc = match(
            r"(?i)\bdesc(?:ription)?\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|([^,]*))", content
        )
        if m_inline_desc !== nothing
            for cap in m_inline_desc.captures
                if cap !== nothing
                    description = String(strip(cap))
                    break
                end
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
        if m_name !== nothing
            create_env = String(m_name.captures[1])
        end
        m_inline_desc = match(
            r"(?i)\bdesc(?:ription)?\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|([^,]*))", content
        )
        if m_inline_desc !== nothing
            for cap in m_inline_desc.captures
                if cap !== nothing
                    description = String(strip(cap))
                    break
                end
            end
        end
    end

    m_desc = match(
        r"^\s*#\s*(?:QuickEnv\.desc(?:ription)?|quickenv_desc(?:ription)?)\s*:\s*(?:\"([^\"]*)\"|'([^']*)'|(.*))$",
        line,
    )
    if m_desc !== nothing
        for cap in m_desc.captures
            if cap !== nothing
                description = String(strip(cap))
                break
            end
        end
    end

    m_verbose = match(
        r"^\s*#\s*(?:quickenv_verbose|QuickEnv\.verbose)\s*:\s*([a-zA-Z0-9_\-]+)", line
    )
    if m_verbose !== nothing
        is_verbose = lowercase(strip(m_verbose.captures[1])) == "true"
    end

    m_silent = match(
        r"^\s*#\s*(?:quickenv_silent|QuickEnv\.silent)\s*:\s*([a-zA-Z0-9_\-]+)", line
    )
    if m_silent !== nothing
        is_silent = lowercase(strip(m_silent.captures[1])) == "true"
    end

    m_local = match(
        r"^\s*#\s*(?:quickenv_local|QuickEnv\.local)\s*:\s*([a-zA-Z0-9_\-]+)", line
    )
    if m_local !== nothing
        is_local = lowercase(strip(m_local.captures[1])) == "true"
    elseif occursin(r"^\s*#\s*local\s*$", line)
        is_local = true
    end

    return fallback_env,
    excluded_envs, is_verbose, is_silent, create_env, description,
    is_local
end

function extract_included_file(line::String, current_dir::String)
    lines = lex_source_lines(line)
    isempty(lines) && return ""
    _, includes = parse_source_syntax(first(lines)[1])
    isempty(includes) && return ""
    inc_target = first(includes)
    inc_path = isabspath(inc_target) ? inc_target : joinpath(current_dir, inc_target)
    return isfile(inc_path) ? abspath(inc_path) : ""
end

function discover_script_files!(files::Vector{String}, script_path::String, visited::Set{String})
    script_path in visited && return files
    !isfile(script_path) && return files
    push!(visited, script_path)
    push!(files, script_path)
    _, includes = parse_source_syntax(read(script_path, String))
    for target in includes
        included = isabspath(target) ? target : joinpath(dirname(script_path), target)
        isfile(included) && discover_script_files!(files, abspath(included), visited)
    end
    return files
end

function parse_script_metadata(script_path::String; visited=Set{String}())
    packages = String[]
    fallback_env = ""
    excluded_envs = String[]
    is_verbose = false
    is_silent = false
    create_env = ""
    description = ""
    is_local = false
    included_files = String[]

    !isfile(script_path) && return packages,
    fallback_env, excluded_envs, is_verbose, is_silent, create_env, description,
    is_local

    push!(visited, script_path)
    current_dir = dirname(script_path)

    source = read(script_path, String)
    syntax_packages, syntax_includes = parse_source_syntax(source)
    append!(packages, syntax_packages)

    for (code, comment) in lex_source_lines(source)
        line_packages, _ = parse_source_syntax(code)
        has_quickenv_import = "QuickEnv" in line_packages
        directive_line = isempty(comment) || !has_quickenv_import ? "" :
            code * " #" * comment
        inline_fallback, inline_excl, inline_verbose, inline_silent, inline_create, inline_desc, inline_local = parse_inline_options(
            directive_line
        )
        !isempty(inline_fallback) && (fallback_env = inline_fallback)
        !isempty(inline_excl) && append!(excluded_envs, inline_excl)
        inline_verbose && (is_verbose = true)
        inline_silent && (is_silent = true)
        inline_local && (is_local = true)
        !isempty(inline_create) && (create_env = inline_create)
        !isempty(inline_desc) && (description = inline_desc)

        standalone_comment = isempty(strip(code)) && !isempty(comment) ? "#" * comment : ""
        sa_fallback, sa_excl, sa_verbose, sa_silent, sa_create, sa_desc, sa_local = parse_standalone_comments(
            standalone_comment
        )
        !isempty(sa_fallback) && (fallback_env = sa_fallback)
        !isempty(sa_excl) && append!(excluded_envs, sa_excl)
        sa_verbose !== nothing && (is_verbose = sa_verbose)
        sa_silent !== nothing && (is_silent = sa_silent)
        sa_local !== nothing && (is_local = sa_local)
        !isempty(sa_create) && (create_env = sa_create)
        !isempty(sa_desc) && (description = sa_desc)

    end

    for target in syntax_includes
        inc_path = isabspath(target) ? target : joinpath(current_dir, target)
        inc_file = isfile(inc_path) ? abspath(inc_path) : ""
        if !isempty(inc_file) && !(inc_file in visited)
            push!(included_files, inc_file)
        end
    end

    # Recursively scan included files for hidden using/import statements
    for inc_file in included_files
        inc_pkgs, _, _, _, _, _, _, _ = parse_script_metadata(inc_file; visited=visited)
        new_pkgs = filter(p -> !(p in packages) && p != "QuickEnv", inc_pkgs)
        if !isempty(new_pkgs)
            if !is_silent
                println(stderr)
                @warn "QuickEnv: Detected package import(s) $new_pkgs inside included file:\n" *
                    "  $inc_file\n" *
                    "Best practice in Julia is to declare all `using` dependencies at the top of the main entry script.\n" *
                    "(Declare 'silent' to suppress this warning)."
                println(stderr)
            end
            for p in new_pkgs
                push!(packages, p)
            end
        end
    end

    return packages,
    fallback_env, excluded_envs, is_verbose, is_silent, create_env, description,
    is_local
end

function find_matching_envs(required_pkgs::Vector{String})
    env_dir = joinpath(DEPOT_PATH[1], "environments")
    !isdir(env_dir) && return String[]

    matching_envs = String[]
    for entry in readdir(env_dir)
        startswith(entry, ".") && continue
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
            @debug "QuickEnv: Error reading environment Project.toml" file=toml_path exception=e
        end
    end
    return sort(matching_envs)
end

function direct_dependency_count(env_name::String)
    project = joinpath(DEPOT_PATH[1], "environments", env_name, "Project.toml")
    try
        return length(get(TOML.parsefile(project), "deps", Dict{String,Any}()))
    catch
        return typemax(Int)
    end
end

function filter_matching_envs(
    matching::Vector{String}, fallback_env::String, excluded_envs::Vector{String}
)
    return filter(matching) do env
        if occursin(r"^v\d+\.\d+$", env)
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
    lowercase(get(ENV, "QUICKENV_DISABLE_AUTO", "false")) == "true" && return nothing
    script_path = get_script_path()
    isempty(script_path) && return nothing

    # Register automatic failure-invalidation exit hook:
    # If the script fails during runtime (e.g. unhandled exception),
    # invalidate its cached entry immediately.
    atexit() do exit_code
        if exit_code != 0
            try
                invalidate_script_cache(script_path)
            catch e
                @debug "QuickEnv: Could not invalidate script cache during shutdown" exception=e
            end
        end
    end

    env_verbose = get(ENV, "QUICKENV_VERBOSE", "false")
    env_silent = get(ENV, "QUICKENV_SILENT", "false")

    # Fast script-level cache hit with content and environment verification
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

    filter!(p -> p != "QuickEnv" && !is_stdlib(p), required_packages)

    is_verbose = (lowercase(env_verbose) == "true") || script_verbose
    is_silent = (lowercase(env_silent) == "true") || script_silent

    if handle_forced_creation(create_env, required_packages, is_verbose, is_silent)
        warn_ignored_local_files(script_path, create_env, is_silent)
        update_active_env_description(description)
        update_script_cache_entry(script_path, create_env)
        return nothing
    end

    handle_matching_or_fallback(
        required_packages,
        fallback_env,
        excluded_envs,
        is_verbose,
        is_silent,
        is_local,
        script_path,
    )

    project_file = Base.active_project()
    if project_file !== nothing
        active_dir = dirname(project_file)
        if active_dir != dirname(script_path) &&
            !occursin(r"^v\d+\.\d+$", basename(active_dir))
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
