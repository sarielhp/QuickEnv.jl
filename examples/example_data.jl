#!/usr/bin/env julia
using QuickEnv # fallback: data, exclude: global, silent
using DataFrames
using CSV

function (@main)(args)
    # Ensure output directory exists
    out_dir = joinpath(@__DIR__, "output")
    isdir(out_dir) || mkdir(out_dir)

    # Create a DataFrame using DataFrames.jl
    df = DataFrame(
        ID = 1:5,
        Name = ["Alice", "Bob", "Charlie", "David", "Eve"],
        Score = [85.5, 92.0, 78.3, 88.9, 95.2]
    )

    # Save to CSV using CSV.jl
    out_file = joinpath(out_dir, "data.csv")
    CSV.write(out_file, df)

    # Print the generated file name to standard output
    println(out_file)

    return 0
end
