#!/usr/bin/env julia
using QuickEnv
using Distributions
using StatsBase
using Random

function (@main)(args)
    Random.seed!(42)
    d = Normal(10.0, 2.5)
    samples = rand(d, 1000)
    m = mean(samples)
    s = std(samples)
    println("[01_stats_sampling] Sampled 1000 points: mean = $(round(m, digits=3)), std = $(round(s, digits=3))")
    return 0
end
