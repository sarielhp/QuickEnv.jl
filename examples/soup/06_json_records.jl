#!/usr/bin/env julia
using QuickEnv
using JSON
using Dates

function (@main)(args)
    record = Dict(
        "experiment" => "soup_test",
        "timestamp" => string(now()),
        "metrics" => [0.94, 0.96, 0.98],
        "passed" => true
    )
    json_str = JSON.json(record)
    parsed = JSON.parse(json_str)
    println("[06_json_records] Parsed JSON record for experiment '$(parsed["experiment"])'")
    return 0
end
