#!/usr/bin/env julia
using QuickEnv
using DataFrames
using CSV
using Distributions
using Plots
using Cairo

function (@main)(args)
    df = DataFrame(
        Group = repeat(["Control", "Treatment"], inner=50),
        Response = vcat(rand(Normal(5.0, 1.0), 50), rand(Normal(7.5, 1.2), 50))
    )
    gr()
    p = histogram(df[df.Group .== "Control", :Response], label="Control", alpha=0.5, title="Treatment vs Control", bins=15)
    histogram!(p, df[df.Group .== "Treatment", :Response], label="Treatment", alpha=0.5, bins=15)
    out_pdf = joinpath(@__DIR__, "output_pipeline.pdf")
    savefig(p, out_pdf)
    println("[08_data_stats_pipeline] Completed full data+stats+plots pipeline: $(basename(out_pdf))")
    return 0
end
