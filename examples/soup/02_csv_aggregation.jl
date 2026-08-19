#!/usr/bin/env julia
using QuickEnv
using DataFrames
using CSV
using Statistics

function (@main)(args)
    df = DataFrame(Category = ["A", "B", "A", "C", "B", "C"], Value = [10.2, 5.4, 8.1, 14.0, 3.2, 11.5])
    gdf = combine(groupby(df, :Category), :Value => mean => :MeanValue, nrow => :Count)
    println("[02_csv_aggregation] Aggregated $(nrow(df)) rows into $(nrow(gdf)) categories.")
    return 0
end
