#!/usr/bin/env julia
# example_cli_merge.jl - Demonstrates merging environments using jlenv CLI.
#
# This script programmatically invokes the jlenv CLI tool to:
# 1. Check compatibility between @plotting and @data_test.
# 2. Fast-stitch them into a new named environment @merged_demo.
# 3. Verify that the merged environment is recognized and ready to use.

using QuickEnv

function (@main)(args)
    println("=== QuickEnv CLI Merge Demo (jlenv) ===")
    
    jlenv_path = joinpath(dirname(@__DIR__), "tools", "jlenv.jl")
    
    println("
1. Checking compatibility between @plotting and @data_test:")
    run(`julia $jlenv_path check-compat @plotting @data_test`)
    
    println("
2. Merging @plotting and @data_test into @merged_demo:")
    run(`julia $jlenv_path merge @merged_demo @plotting @data_test`)
    
    println("
3. Inspecting the new @merged_demo environment:")
    run(`julia $jlenv_path show @merged_demo`)
    
    # Cleanup demo environment
    merged_path = joinpath(homedir(), ".julia", "environments", "merged_demo")
    rm(merged_path, recursive=true, force=true)
    println("Cleanup of @merged_demo complete.")
    
    return 0
end
