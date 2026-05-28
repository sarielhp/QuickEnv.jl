#!/usr/bin/env julia
using QuickEnv # fallback: plotting, exclude: global, silent
using Plots
using Cairo

function (@main)(args)
    # Ensure output directory exists
    out_dir = joinpath(@__DIR__, "output")
    isdir(out_dir) || mkdir(out_dir)

    # Default to gr() backend as requested
    gr()

    # Generate a simple plot
    x = 1:10
    y = rand(10)
    p = plot(
        x,
        y;
        title="QuickEnv Test Plot",
        xlabel="X-Axis",
        ylabel="Y-Axis",
        label="Random Data",
    )

    # Save to PDF (defaulting to Cairo PDF rendering)
    out_file = joinpath(out_dir, "plot.pdf")
    savefig(p, out_file)

    # Print the generated file name to standard output
    println(out_file)

    return 0
end
