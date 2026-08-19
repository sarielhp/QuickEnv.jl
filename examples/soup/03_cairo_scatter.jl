#!/usr/bin/env julia
using QuickEnv
using Plots
using Cairo

function (@main)(args)
    gr()
    x = range(0, 2pi, length=50)
    y = sin.(x) .+ 0.1 .* randn(length(x))
    p = scatter(x, y, title="Cairo Scatter Plot", label="Noisy Sine", color=:red)
    out_pdf = joinpath(@__DIR__, "output_cairo_scatter.pdf")
    savefig(p, out_pdf)
    println("[03_cairo_scatter] Saved Cairo plot to $(basename(out_pdf))")
    return 0
end
