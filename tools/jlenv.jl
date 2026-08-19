#!/usr/bin/env julia
# jlenv - A colorful command-line utility to manage Julia named environments.
#
# Enables listing, describing, showing, adding packages, automatically 
# creating named environments based on imported packages in a Julia script, 
# matching scripts to environments, running scripts or REPLs, removing environments,
# merging environments, checking compatibility, managing cache, and searching packages.

using QuickEnv # silent, create: packaging
using Pkg
using Crayons
using Printf
using TOML

# Core terminal colors using standard Crayons package
bold(s) = string(Crayon(bold=true), s, Crayon(reset=true))
red(s) = string(Crayon(foreground=:red), s, Crayon(reset=true))
green(s) = string(Crayon(foreground=:green), s, Crayon(reset=true))
yellow(s) = string(Crayon(foreground=:yellow), s, Crayon(reset=true))
blue(s) = string(Crayon(foreground=:blue), s, Crayon(reset=true))
cyan(s) = string(Crayon(foreground=:cyan), s, Crayon(reset=true))
gray(s) = string(Crayon(foreground=:dark_gray), s, Crayon(reset=true))

const ENV_DIR = joinpath(homedir(), ".julia", "environments")

# Custom parser for Julia Project.toml files using standard TOML library
function parse_project_toml(file_path::String)
    data = Dict{String,Any}("description" => nothing, "deps" => Dict{String,String}())
    if !isfile(file_path)
        return data
    end

    try
        toml_data = TOML.parsefile(file_path)
        data["description"] = get(toml_data, "description", nothing)
        deps_raw = get(toml_data, "deps", Dict{String,Any}())
        for (k, v) in deps_raw
            data["deps"][k] = string(v)
        end
    catch e
    end
    return data
end

# Extract packages from a single code line (helper from QuickEnv logic)
function extract_packages_from_line(line::String)
    packages = String[]
    clean_line = strip(first(split(line, '#')))
    m = match(r"^\s*(using|import)\s+(.*)$", clean_line)
    if m === nothing
        return packages
    end

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

# Extract Julia packages used in a script
function extract_packages(script_path::String)
    packages = String[]
    if !isfile(script_path)
        println(stderr, red("Error: Script file not found: $script_path"))
        return packages
    end

    for line in eachline(script_path)
        for pkg in extract_packages_from_line(line)
            if !(pkg in packages)
                push!(packages, pkg)
            end
        end
    end
    return packages
end

# Update or insert the description key in a Project.toml file
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

# Strip leading '@' symbol from environment name if present
clean_env_name(name::String) = startswith(name, "@") ? name[2:end] : name

# 1. List all existing named environments
function list_environments()
    if !isdir(ENV_DIR)
        println(yellow("No named environments found in $ENV_DIR"))
        return
    end

    envs = filter(
        d -> isdir(joinpath(ENV_DIR, d)) && !startswith(d, "."), readdir(ENV_DIR)
    )

    if isempty(envs)
        println(yellow("No named environments found in $ENV_DIR"))
        return
    end

    println(bold(cyan("\nJulia Named Environments (~/.julia/environments):")))
    println(gray("─"^80))

    max_len = maximum(length.(envs))
    format_str = Printf.Format("  $(bold("%-$(max_len + 3)s")) %s\n")

    for env in sort(envs)
        proj_file = joinpath(ENV_DIR, env, "Project.toml")
        data = parse_project_toml(proj_file)
        desc = data["description"]

        desc_str = if desc !== nothing && !isempty(desc)
            desc
        else
            pkg_count = length(data["deps"])
            gray("($pkg_count packages, no description)")
        end

        Printf.format(stdout, format_str, "@" * env, desc_str)
    end
    println()
end

# 2. Show detailed package contents of a single environment
function show_environment(env_raw::String)
    env_name = clean_env_name(env_raw)
    env_path = joinpath(ENV_DIR, env_name)
    proj_file = joinpath(env_path, "Project.toml")

    if !isdir(env_path) || !isfile(proj_file)
        println(stderr, red("Error: Named environment '@$env_name' does not exist."))
        return
    end

    data = parse_project_toml(proj_file)

    println(bold(cyan("\nEnvironment: ")) * bold("@$env_name"))
    println(bold(cyan("Location:    ")) * gray(env_path))

    if data["description"] !== nothing && !isempty(data["description"])
        println(bold(cyan("Description: ")) * data["description"])
    else
        println(bold(cyan("Description: ")) * gray("(None)"))
    end

    deps = data["deps"]
    println(bold(cyan("Packages ($(length(deps))):")))

    if isempty(deps)
        println(gray("  (No direct package dependencies found)"))
    else
        for (pkg, uuid) in sort(collect(deps); by=first)
            println("  • $(bold(green(pkg))) " * gray("($uuid)"))
        end
    end
    println()
end

# 3. Add packages to an environment
function add_packages(env_raw::String, pkgs::Vector{String})
    env_name = clean_env_name(env_raw)
    if isempty(pkgs)
        println(stderr, red("Error: No packages specified to add."))
        return
    end

    println(
        bold(
            cyan("Adding $(length(pkgs)) package(s) to environment '@$env_name'...\n")
        ),
    )
    Pkg.activate(env_name; shared=true)
    Pkg.add(pkgs)
    println(green("\nSuccessfully added packages to '@$env_name'."))
end

# 4. Describe an environment
function describe_environment(env_raw::String, desc::String)
    env_name = clean_env_name(env_raw)
    env_path = joinpath(ENV_DIR, env_name)
    proj_file = joinpath(env_path, "Project.toml")

    if !isdir(env_path)
        println(bold(yellow("Creating new environment '@$env_name'...")))
        mkpath(env_path)
    end

    update_description(proj_file, desc)
    println(
        green(
            "Successfully updated description for '@$env_name':\n  " * bold(desc)
        ),
    )
end

# 5. Create an environment from script dependencies
function create_from_script(env_raw::String, script_path::String)
    env_name = clean_env_name(env_raw)
    pkgs = extract_packages(script_path)

    if isempty(pkgs)
        println(yellow("No packages found in $script_path to install."))
        return
    end

    println(bold(cyan("Found $(length(pkgs)) package(s) in $script_path:")))
    println("  " * join(green.(pkgs), ", "))
    println()

    println(bold(cyan("Initializing environment '@$env_name'...")))
    Pkg.activate(env_name; shared=true)
    Pkg.add(pkgs)

    proj_file = joinpath(ENV_DIR, env_name, "Project.toml")
    desc = "Environment created for script $(basename(script_path))"
    update_description(proj_file, desc)

    println(green("\nSuccessfully created '@$env_name' for $script_path!"))
end

# 6. Find environments matching a script
function find_matching_environments(script_path::String)
    pkgs = extract_packages(script_path)
    if isempty(pkgs)
        println(yellow("No packages found in $script_path."))
        return
    end

    println(bold(cyan("Required packages for $script_path:")))
    println("  " * join(green.(pkgs), ", "))
    println()

    if !isdir(ENV_DIR)
        println(yellow("No environments found in $ENV_DIR."))
        return
    end

    envs = filter(
        d -> isdir(joinpath(ENV_DIR, d)) && !startswith(d, "."), readdir(ENV_DIR)
    )
    matching = String[]

    for env in envs
        proj_file = joinpath(ENV_DIR, env, "Project.toml")
        data = parse_project_toml(proj_file)
        deps = data["deps"]

        if all(pkg -> haskey(deps, pkg), pkgs)
            push!(matching, env)
        end
    end

    if isempty(matching)
        println(
            yellow("No existing environment contains all required packages."),
        )
        println(
            gray(
                "Tip: You can create one with: jlenv create @<new_env> $script_path",
            ),
        )
    else
        println(
            bold(
                green(
                    "Matching environment(s) ($(length(matching)) found):\n",
                ),
            ),
        )
        for env in sort(matching)
            proj_file = joinpath(ENV_DIR, env, "Project.toml")
            data = parse_project_toml(proj_file)
            desc = data["description"]
            desc_str = if desc !== nothing && !isempty(desc)
                desc
            else
                gray("(no description)")
            end
            println("  • $(bold("@" * env)) - $desc_str")
        end
        println()
    end
end

# 7. Match and run a script
function match_and_run(script_path::String, extra_args::Vector{String})
    pkgs = extract_packages(script_path)

    if !isdir(ENV_DIR)
        println(stderr, red("Error: No environments directory found at $ENV_DIR"))
        return
    end

    envs = filter(
        d -> isdir(joinpath(ENV_DIR, d)) && !startswith(d, "."), readdir(ENV_DIR)
    )
    matching = String[]

    for env in envs
        proj_file = joinpath(ENV_DIR, env, "Project.toml")
        data = parse_project_toml(proj_file)
        deps = data["deps"]

        if all(pkg -> haskey(deps, pkg), pkgs)
            push!(matching, env)
        end
    end

    if isempty(matching)
        println(
            stderr,
            red(
                "Error: No matching environment found for $script_path with packages: $(join(pkgs, ", "))",
            ),
        )
        return
    end

    selected_env = sort(matching)[1]
    println(bold(cyan("Selected matching environment: ")) * bold("@$selected_env"))
    cmd = `julia --project=@$selected_env $script_path $extra_args`
    run(cmd)
end

# 8. Run a script in a specified environment
function run_script(
    env_raw::String, script_path::String, extra_args::Vector{String}
)
    env_name = clean_env_name(env_raw)
    env_path = joinpath(ENV_DIR, env_name)

    if !isdir(env_path)
        println(stderr, red("Error: Named environment '@$env_name' does not exist."))
        return
    end

    if !isfile(script_path)
        println(stderr, red("Error: Script file not found: $script_path"))
        return
    end

    cmd = `julia --project=@$env_name $script_path $extra_args`
    run(cmd)
end

# 9. Launch REPL in environment
function launch_repl(env_raw::String)
    env_name = clean_env_name(env_raw)
    env_path = joinpath(ENV_DIR, env_name)

    if !isdir(env_path)
        println(stderr, red("Error: Named environment '@$env_name' does not exist."))
        return
    end

    println(bold(cyan("Launching Julia REPL in '@$env_name'...")))
    cmd = `julia --project=@$env_name`
    run(cmd)
end

# 10. Delete an environment
function remove_environment(env_raw::String)
    env_name = clean_env_name(env_raw)
    env_path = joinpath(ENV_DIR, env_name)

    if !isdir(env_path)
        println(stderr, red("Error: Named environment '@$env_name' does not exist."))
        return
    end

    print(
        yellow(
            "Are you sure you want to delete environment '@$env_name'? [y/N]: "
        ),
    )
    choice = strip(readline())

    if lowercase(choice) in ("y", "yes")
        rm(env_path; recursive=true, force=true)
        println(green("Successfully deleted environment '@$env_name'."))
    else
        println(gray("Aborted."))
    end
end

# 11. Search General Registry
function search_packages(query::String)
    println(bold(cyan("Searching Julia General Registry for: ")) * bold(query))
    registries = Pkg.Registry.reachable_registries()
    if isempty(registries)
        println(yellow("No reachable registries found."))
        return
    end

    results = Tuple{String,String}[]
    for reg in registries
        for (uuid, pkg) in reg.pkgs
            if occursin(lowercase(query), lowercase(pkg.name))
                push!(results, (pkg.name, string(uuid)))
            end
        end
    end

    if isempty(results)
        println(yellow("No packages matching '$query' were found."))
    else
        println(bold(green("\nFound $(length(results)) match(es):")))
        for (name, uuid) in sort(results; by=first)
            println("  • $(bold(name)) " * gray("($uuid)"))
        end
        println()
    end
end

# 12. Merge multiple environments
function merge_environments(target_raw::String, source_raws::Vector{String})
    target_env = clean_env_name(target_raw)
    source_envs = [clean_env_name(s) for s in source_raws]

    if isempty(source_envs)
        println(stderr, red("Error: Please provide at least one source environment to merge."))
        return
    end

    println(bold(cyan("\nMerging into @$target_env from: ")) * join(["@" * s for s in source_envs], ", "))

    compat, merged_deps, _ = QuickEnv.check_manifest_compat(source_envs)
    if compat
        QuickEnv.stitch_environments(target_env, source_envs, false)
        println(green("Merge complete! Environment @$target_env is ready to use with zero recompilation."))
    else
        println(yellow("Warning: Dependency version conflicts detected between sources."))
        println(yellow("Falling back to full Pkg joint resolution..."))
        pkgs = collect(keys(merged_deps))
        Pkg.activate(target_env; shared=true)
        Pkg.add(pkgs)
        println(green("Resolved and created @$target_env successfully!"))
    end
end

# 13. Check compatibility of environments
function check_compatibility(source_raws::Vector{String})
    source_envs = [clean_env_name(s) for s in source_raws]
    if length(source_envs) < 2
        println(stderr, red("Error: Please provide at least two environments to check compatibility."))
        return
    end

    println(bold(cyan("\nChecking Manifest Compatibility for: ")) * join(["@" * s for s in source_envs], ", "))
    compat, merged_deps, merged_m_deps = QuickEnv.check_manifest_compat(source_envs)

    if compat
        println(green("Status: COMPATIBLE ✅"))
        println(gray("All shared dependencies match identical versions and hashes."))
        println("Direct dependencies: " * join(bold.(collect(keys(merged_deps))), ", "))
    else
        println(red("Status: INCOMPATIBLE ❌"))
        println(yellow("Conflicting versions or UUIDs found among dependencies."))
    end
    println()
end

# 14. Manage QuickEnv resolution cache
function manage_cache(args::Vector{String})
    action = isempty(args) ? "list" : args[1]
    cfile = QuickEnv.get_cache_file()

    if action == "clean" || action == "clear"
        if isfile(cfile)
            rm(cfile; force=true)
        end
        println(green("QuickEnv resolution cache cleared."))
    else
        cache = QuickEnv.load_cache()
        println(bold(cyan("\nQuickEnv Resolution Cache (~/.julia/quickenv/cache.toml):")))
        println(gray("─"^80))
        if isempty(cache)
            println(gray("  (Cache is empty)"))
        else
            for (key, val) in cache
                env = get(val, "env", "unknown")
                sources = get(val, "sources", String[])
                println("  • Key: $(bold(key)) → $(bold(green("@" * env))) " * gray("(sources: " * join(sources, ", ") * ")"))
            end
        end
        println()
    end
end

# Print detailed help for a specific command
function print_command_help(cmd::String)
    cmd_clean = clean_env_name(cmd)
    if cmd_clean == "list"
        println("""
        $(bold(cyan("Command:"))) list
        $(bold(yellow("Description:"))) List all shared named environments found in ~/.julia/environments.
        $(bold(yellow("Usage:"))) jlenv list
        """)
    elseif cmd_clean == "show"
        println("""
        $(bold(cyan("Command:"))) show
        $(bold(yellow("Description:"))) Display metadata, description, and direct package dependencies of a named environment.
        $(bold(yellow("Usage:"))) jlenv show <env_name>
        """)
    elseif cmd_clean == "merge"
        println("""
        $(bold(cyan("Command:"))) merge
        $(bold(yellow("Description:"))) Merge multiple existing named environments into a target environment.
        $(bold(yellow("Usage:"))) jlenv merge <target_env> <env1> <env2> ...
        $(bold(yellow("Example:"))) jlenv merge @plotting_data @plotting @data
        """)
    elseif cmd_clean in ("compat", "check-compat")
        println("""
        $(bold(cyan("Command:"))) check-compat
        $(bold(yellow("Description:"))) Check whether multiple named environments have compatible dependency manifests.
        $(bold(yellow("Usage:"))) jlenv check-compat <env1> <env2> ...
        """)
    elseif cmd_clean == "cache"
        println("""
        $(bold(cyan("Command:"))) cache
        $(bold(yellow("Description:"))) Inspect or clear QuickEnv's resolution cache.
        $(bold(yellow("Usage:"))) jlenv cache [list|clean]
        """)
    else
        println(stderr, red("Error: Unknown command '$cmd'"))
        print_help()
    end
end

function print_help()
    println("""
$(bold(cyan("jlenv"))) - Manage Julia Named Environments (QuickEnv CLI)

$(bold(yellow("Usage:"))) jlenv <command> [arguments...]

$(bold(yellow("Commands:")))
  list                                List all environments and descriptions
  show <env_name>                     Show registered packages in an environment
  merge <target> <env1> <env2> ...    Fast-stitch multiple environments together
  check-compat <env1> <env2> ...      Check dependency compatibility across envs
  cache [list|clean]                  Inspect or clear QuickEnv resolution cache
  add <env_name> <pkg1> <pkg2>..      Add packages to a named environment
  describe <env_name> "<desc>"        Add/change description of an environment
  create <env_name> <script.jl>       Create an environment from a Julia script
  match <script.jl>                   Find environments that can run a script
  mrun <script.jl> [args...]          Run a Julia script in a matching named env
  run <env_name> <script.jl> [..]     Run a Julia script in a named environment
  repl <env_name>                     Launch Julia REPL in a named environment
  rm <env_name>                       Delete a named environment
  search <query>                      Search General Registry for a package

$(bold(gray("Tip: Run 'jlenv help <command>' or call a command without arguments to view its detailed usage.")))
""")
end

function (@main)(args)
    if isempty(args)
        print_help()
        return 0
    end

    action = args[1]
    action_args = args[2:end]

    if action == "list"
        list_environments()
    elseif action == "show"
        isempty(action_args) ? print_command_help("show") : show_environment(action_args[1])
    elseif action == "merge"
        length(action_args) < 2 ? print_command_help("merge") : merge_environments(action_args[1], action_args[2:end])
    elseif action in ("compat", "check-compat")
        length(action_args) < 2 ? print_command_help("check-compat") : check_compatibility(action_args)
    elseif action == "cache"
        manage_cache(action_args)
    elseif action == "add"
        isempty(action_args) ? print_command_help("add") : add_packages(action_args[1], action_args[2:end])
    elseif action == "describe"
        length(action_args) < 2 ? print_command_help("describe") : describe_environment(action_args[1], action_args[2])
    elseif action == "create"
        length(action_args) < 2 ? print_command_help("create") : create_from_script(action_args[1], action_args[2])
    elseif action == "match"
        isempty(action_args) ? print_command_help("match") : find_matching_environments(action_args[1])
    elseif action == "mrun"
        isempty(action_args) ? print_command_help("mrun") : match_and_run(action_args[1], action_args[2:end])
    elseif action == "run"
        length(action_args) < 2 ? print_command_help("run") : run_script(action_args[1], action_args[2], action_args[3:end])
    elseif action == "repl"
        isempty(action_args) ? print_command_help("repl") : launch_repl(action_args[1])
    elseif action in ("rm", "delete")
        isempty(action_args) ? print_command_help("rm") : remove_environment(action_args[1])
    elseif action == "search"
        isempty(action_args) ? print_command_help("search") : search_packages(action_args[1])
    elseif action in ("help", "--help", "-h")
        isempty(action_args) ? print_help() : print_command_help(action_args[1])
    else
        println(stderr, red("Error: Unknown command '$action'"))
        print_help()
    end

    return 0
end
