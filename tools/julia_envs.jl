#!/usr/bin/env julia
# julia_envs - A colorful command-line utility to manage Julia named environments.
#
# Enables listing, describing, showing, adding packages, automatically 
# creating named environments based on imported packages in a Julia script, 
# matching scripts to environments, running scripts or REPLs, removing environments,
# and searching the general Julia package registry.

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
        # Ignore parsing errors
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

# List all named environments and their descriptions
function list_environments()
    if !isdir(ENV_DIR)
        println(stderr, red("No Julia environments directory found at $ENV_DIR."))
        return
    end

    envs = filter(entry -> isdir(joinpath(ENV_DIR, entry)), readdir(ENV_DIR))
    sort!(envs)

    println("\n$(bold(cyan("Environment")))$(repeat(' ', 13))$(bold(cyan("Description")))")
    println(repeat('-', 80))

    for env in envs
        toml_path = joinpath(ENV_DIR, env, "Project.toml")
        data = parse_project_toml(toml_path)
        desc = get(data, "description", nothing)
        desc_display = desc !== nothing ? desc : gray("(No description)")

        env_display = env == "v1.12" ? yellow("v1.12 (Global)") : green("@$env")
        # Format padding accounting for internal ANSI escape color sequences (adds 9 chars)
        @printf("%-33s %-50s\n", env_display, desc_display)
    end
    println()
end

# Show registered packages inside a named environment
function show_environment(env_name::String)
    clean_name = startswith(env_name, '@') ? env_name[2:end] : env_name
    env_path = joinpath(ENV_DIR, clean_name)
    toml_path = joinpath(env_path, "Project.toml")

    if !isfile(toml_path)
        println(stderr, red("Error: Named environment '@$clean_name' does not exist."))
        return
    end

    data = parse_project_toml(toml_path)
    println("\n$(bold(cyan("Environment:"))) $(green("@$clean_name"))")
    desc = get(data, "description", nothing)
    desc_display = desc !== nothing ? desc : gray("(No description)")
    println("$(bold(cyan("Description:"))) $desc_display")
    println(repeat('-', 40))

    deps = get(data, "deps", Dict{String,String}())
    if isempty(deps)
        println(yellow("No registered packages found."))
    else
        println("Registered Packages (Direct Dependencies):")
        for pkg in sort(collect(keys(deps)))
            println("  - $(green(pkg))")
        end
    end
    println()
end

# Add package dependencies to a named environment
function add_packages(env_name::String, packages::Vector{String})
    if isempty(packages)
        println(stderr, red("Error: Please specify at least one package to add."))
        return
    end

    clean_name = startswith(env_name, '@') ? env_name[2:end] : env_name
    println("Adding package(s) $(green(join(packages, ", "))) to '$(green("@" * clean_name))'...")

    pkg_array = join(map(p -> "\"$p\"", packages), ", ")
    cmd = `julia --project=@$clean_name -e "using Pkg; Pkg.add([$pkg_array])"`
    
    try
        if success(cmd)
            println(bold(green("\nSuccessfully added package(s) to '@$clean_name'!")))
        else
            println(bold(red("\nError: Failed to add package(s) to '@$clean_name'.")))
        end
    catch e
        println(bold(red("\nError: Failed to add package(s) to '@$clean_name': $e")))
    end
end

# Add or update the description of a named environment
function describe_environment(env_name::String, description::String)
    clean_name = startswith(env_name, '@') ? env_name[2:end] : env_name
    env_path = joinpath(ENV_DIR, clean_name)
    toml_path = joinpath(env_path, "Project.toml")

    update_description(toml_path, description)
    println(green("Successfully updated description for '@$clean_name'."))
end

# Create a named environment based on packages imported inside a Julia script
function create_from_script(env_name::String, script_path::String)
    clean_name = startswith(env_name, '@') ? env_name[2:end] : env_name

    if !isfile(script_path)
        println(stderr, red("Error: Script file not found: $script_path"))
        return
    end

    println("Scanning script $(yellow(script_path)) for imports...")
    packages = extract_packages(script_path)

    if isempty(packages)
        println(yellow("No external packages detected in script. Environment was not created."))
        return
    end

    println("Detected packages: $(green(join(packages, ", ")))")

    env_path = joinpath(ENV_DIR, clean_name)
    toml_path = joinpath(env_path, "Project.toml")
    desc = "Auto-generated environment for running $(basename(script_path))"
    update_description(toml_path, desc)

    add_packages(clean_name, packages)
end

# Find existing environments that can run a script
function find_matching_environments(script_path::String)
    if !isfile(script_path)
        println(stderr, red("Error: Script file not found: $script_path"))
        return
    end

    println("Scanning script $(yellow(script_path)) for imports...")
    required_packages = extract_packages(script_path)

    if isempty(required_packages)
        println(yellow("No external packages detected in: $script_path"))
        return
    end

    println("Required packages: $(green(join(required_packages, ", ")))")

    if !isdir(ENV_DIR)
        println(stderr, red("No Julia environments directory found at $ENV_DIR."))
        return
    end

    envs = filter(entry -> isdir(joinpath(ENV_DIR, entry)), readdir(ENV_DIR))
    sort!(envs)
    matching_envs = String[]

    for env in envs
        toml_path = joinpath(ENV_DIR, env, "Project.toml")
        if !isfile(toml_path)
            continue
        end

        data = parse_project_toml(toml_path)
        deps = get(data, "deps", Dict{String,String}())

        if all(pkg -> haskey(deps, pkg), required_packages)
            push!(matching_envs, env)
        end
    end

    println("\n$(bold(cyan("Matching Environments:")))")
    if isempty(matching_envs)
        println(yellow("  No existing environments satisfy all required dependencies."))
        println(gray("  Tip: You can create a new environment for this script by running:"))
        println(gray("       julia_envs create @new_env_name $script_path"))
    else
        for env in matching_envs
            env_display = env == "v1.12" ? yellow("v1.12 (Global)") : green("@$env")
            println("  - $env_display")
        end
    end
    println()
end

# Run a Julia script in a matching named environment
function match_and_run(script_path::String, args::Vector{String})
    if !isfile(script_path)
        println(stderr, red("Error: Script file not found: $script_path"))
        return
    end

    required_packages = extract_packages(script_path)

    if !isdir(ENV_DIR)
        println(stderr, red("Error: No Julia environments directory found at $ENV_DIR."))
        return
    end

    envs = filter(entry -> isdir(joinpath(ENV_DIR, entry)), readdir(ENV_DIR))
    sort!(envs)
    matching_envs = String[]

    for env in envs
        toml_path = joinpath(ENV_DIR, env, "Project.toml")
        if !isfile(toml_path)
            continue
        end

        data = parse_project_toml(toml_path)
        deps = get(data, "deps", Dict{String,String}())

        if all(pkg -> haskey(deps, pkg), required_packages)
            push!(matching_envs, env)
        end
    end

    if isempty(matching_envs)
        println(stderr, red("Error: No existing environment satisfies all required dependencies for $script_path."))
        if !isempty(required_packages)
            println("Required packages: $(green(join(required_packages, ", ")))")
        end
        println(gray("Tip: You can create a new environment for this script by running:"))
        println(gray("     julia_envs create @new_env_name $script_path"))
        return
    end

    # Prefer user named environments (not matching 'vX.Y')
    selected_env = nothing
    for env in matching_envs
        if !occursin(r"^v\d+\.\d+$", env)
            selected_env = env
            break
        end
    end
    if selected_env === nothing
        selected_env = first(matching_envs)
    end

    println("Found matching environment: $(green("@" * selected_env))")
    println("Running $(yellow(script_path)) in '$(green("@" * selected_env))'...")

    cmd = `julia --project=@$selected_env $script_path $args`
    try
        exit(run(cmd).exitcode)
    catch e
        if e isa ProcessFailedException
            exit(e.process.exitcode)
        else
            println(stderr, red("Error running script: $e"))
            exit(1)
        end
    end
end

# Run a Julia script in a specified named environment
function run_script(env_name::String, script_path::String, args::Vector{String})
    clean_name = startswith(env_name, '@') ? env_name[2:end] : env_name
    if !isfile(script_path)
        println(stderr, red("Error: Script file not found: $script_path"))
        return
    end

    cmd = `julia --project=@$clean_name $script_path $args`
    try
        exit(run(cmd).exitcode)
    catch e
        if e isa ProcessFailedException
            exit(e.process.exitcode)
        else
            println(stderr, red("Error running script: $e"))
            exit(1)
        end
    end
end

# Launch Julia REPL inside a specified named environment
function launch_repl(env_name::String)
    clean_name = startswith(env_name, '@') ? env_name[2:end] : env_name
    println(bold("Launching Julia REPL in named environment '$(green("@" * clean_name))'..."))

    cmd = `julia --project=@$clean_name`
    try
        exit(run(cmd).exitcode)
    catch e
        if e isa ProcessFailedException
            exit(e.process.exitcode)
        else
            println(stderr, red("Error launching REPL: $e"))
            exit(1)
        end
    end
end

# Delete a specified named environment
function remove_environment(env_name::String)
    clean_name = startswith(env_name, '@') ? env_name[2:end] : env_name
    env_path = joinpath(ENV_DIR, clean_name)

    if !isdir(env_path)
        println(stderr, red("Error: Named environment '@$clean_name' does not exist."))
        return
    end

    print(bold(red("Are you sure you want to delete named environment $(green("@" * clean_name))? [y/N]: ")))
    response = strip(lowercase(readline()))

    if response in ("y", "yes")
        rm(env_path, recursive=true, force=true)
        println(bold(green("Successfully deleted environment '@$clean_name'.")))
    else
        println(yellow("Deletion cancelled."))
    end
end

# Search the official General Package Registry for a package by query (in-process)
function search_packages(query::String)
    if isempty(query)
        println(stderr, red("Error: Please specify a search query."))
        return
    end

    println("Searching Julia registry for '$(yellow(query))'...")

    matching_pkgs = String[]
    try
        for reg in Pkg.Registry.reachable_registries()
            pkgs = sort(collect(values(reg.pkgs)), by = x -> x.name)
            for pkg in pkgs
                if occursin(lowercase(query), lowercase(pkg.name))
                    push!(matching_pkgs, pkg.name)
                end
            end
        end
    catch e
        println(stderr, red("Error searching registry: $e"))
        return
    end

    unique!(matching_pkgs)
    sort!(matching_pkgs)

    if isempty(matching_pkgs)
        println(yellow("No matching packages found for '$query'."))
    else
        println("\n$(bold(cyan("Matching Packages (from General Registry):")))")
        counter = 0
        truncated = false
        for name in matching_pkgs
            counter += 1
            if counter > 25
                truncated = true
                break
            end
            println("  - $(green(name))")
        end
        if truncated
            println(gray("  - ... and more results (truncated to 25)"))
        end
        println()
    end
end

# Display usage instructions
function print_help()
    println("""
    $(bold(cyan("julia_envs"))) - Manage Julia Named Environments

    $(bold(yellow("Usage:")))
      julia_envs list                            List all environments and descriptions
      julia_envs show <env_name>                 Show registered packages in an environment
      julia_envs add <env_name> <pkg1> <pkg2>..  Add packages to a named environment
      julia_envs describe <env_name> "<desc>"    Add/change description of an environment
      julia_envs create <env_name> <script.jl>   Create an environment from a Julia script
      julia_envs match <script.jl>               Find environments that can run a script
      julia_envs mrun <script.jl> [args...]      Run a Julia script in a matching named env
      julia_envs run <env_name> <script.jl> [..] Run a Julia script in a named environment
      julia_envs repl <env_name>                 Launch Julia REPL in a named environment
      julia_envs rm <env_name>                   Delete a named environment
      julia_envs search <query>                  Search General Registry for a package

    $(bold(yellow("Examples:")))
      julia_envs list
      julia_envs show @plotting
      julia_envs add @plotting DataStructures DataFrames
      julia_envs describe @plotting "Plotting environment with Plots.jl and Cairo"
      julia_envs create @math_env solve_inequality.jl
      julia_envs match plot_inequality.jl
      julia_envs mrun plot_inequality.jl
      julia_envs run @plotting plot_inequality.jl
      julia_envs repl @plotting
      julia_envs rm @test_env
      julia_envs search DataStructures
    """)
end

# Main entry point parsing arguments
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
        if isempty(action_args)
            println(stderr, red("Error: Please specify an environment name."))
        else
            show_environment(action_args[1])
        end
    elseif action == "add"
        if isempty(action_args)
            println(stderr, red("Error: Please specify an environment name."))
        else
            add_packages(action_args[1], action_args[2:end])
        end
    elseif action == "describe"
        if length(action_args) < 2
            println(stderr, red("Error: Usage: julia_envs describe <env_name> \"<description>\""))
        else
            describe_environment(action_args[1], action_args[2])
        end
    elseif action == "create"
        if length(action_args) < 2
            println(stderr, red("Error: Usage: julia_envs create <env_name> <script.jl>"))
        else
            create_from_script(action_args[1], action_args[2])
        end
    elseif action == "match"
        if isempty(action_args)
            println(stderr, red("Error: Usage: julia_envs match <script.jl>"))
        else
            find_matching_environments(action_args[1])
        end
    elseif action == "mrun"
        if isempty(action_args)
            println(stderr, red("Error: Usage: julia_envs mrun <script.jl> [args...]"))
        else
            match_and_run(action_args[1], action_args[2:end])
        end
    elseif action == "run"
        if length(action_args) < 2
            println(stderr, red("Error: Usage: julia_envs run <env_name> <script.jl> [args...]"))
        else
            run_script(action_args[1], action_args[2], action_args[3:end])
        end
    elseif action == "repl"
        if isempty(action_args)
            println(stderr, red("Error: Usage: julia_envs repl <env_name>"))
        else
            launch_repl(action_args[1])
        end
    elseif action in ("rm", "delete")
        if isempty(action_args)
            println(stderr, red("Error: Usage: julia_envs rm <env_name>"))
        else
            remove_environment(action_args[1])
        end
    elseif action == "search"
        if isempty(action_args)
            println(stderr, red("Error: Usage: julia_envs search <query>"))
        else
            search_packages(action_args[1])
        end
    else
        print_help()
    end

    return 0
end
