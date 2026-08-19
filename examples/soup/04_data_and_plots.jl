#!/usr/bin/env julia
using QuickEnv
using DataFrames
using Plots
using Cairo

function (@main)(args)
    df = DataFrame(t = 1:20, val = cumsum(randn(20)))
    gr()
    p = plot(df.t, df.val, marker=:circle, title="DataFrames + Plots Compound", label="Random Walk")
    out_pdf = joinpath(@__DIR__, "output_data_plot.pdf")
    savefig(p, out_pdf)
    println("[04_data_and_plots] Generated DataFrames+Plots visualization: $(basename(out_pdf))")
    return 0
end
