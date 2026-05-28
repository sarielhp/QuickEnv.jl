#!/usr/bin/env julia
# example_warning.jl - Demonstrates the ignored local files warning in QuickEnv.
#
# When a script uses a shared named environment but is run inside a folder
# containing local Project.toml or Manifest.toml files, QuickEnv alerts the user
# that their local directory configurations are being bypassed.

using QuickEnv # fallback: plotting, exclude: global
using Plots

function (@main)(args)
    # The script's directory
    script_dir = @__DIR__
    local_project = joinpath(script_dir, "Project.toml")

    # If the dummy local Project.toml doesn't exist, create it and ask the user to run again.
    if !isfile(local_project)
        println("=== QuickEnv Ignored Files Warning Demo ===")
        println("1. A dummy local Project.toml is being created in the examples/ directory.")
        
        # Write dummy TOML content
        write(local_project, "name = \"DummyExamplesProject\"\nversion = \"0.1.0\"\n")
        println(local_project)
        
        println("\n2. Run this script a second time to see the warning in action:")
        println("   julia examples/example_warning.jl")
        println()
        println("To clean up later, simply delete: examples/Project.toml")
    else
        println("=== QuickEnv Ignored Files Warning Demo ===")
        println("Success! The warning was successfully printed above because a local Project.toml")
        println("exists in this folder, but the script is running in named environment @plotting.")
        println()
        println("Cleaning up the dummy local Project.toml now...")
        rm(local_project, force=true)
        println("Cleanup complete!")
    end

    return 0
end
