#!/usr/bin/env julia
using QuickEnv
using Distributions
using Plots
using Cairo

function (@main)(args)
    d = Exponential(1.5)
    samples = rand(d, 500)
    gr()
    p = histogram(samples, bins=25, title="Exponential Distribution", label="Samples", color=:blue)
    out_pdf = joinpath(@__DIR__, "output_exponential_dist.pdf")
    savefig(p, out_pdf)
    println("[07_stats_and_visual] Generated histogram for Exponential distribution: $(basename(out_pdf))")
    return 0
end
