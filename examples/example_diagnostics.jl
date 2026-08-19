#!/usr/bin/env julia
# example_diagnostics.jl - Demonstrates QuickEnv smart package diagnosis.
#
# QuickEnv detects package casing mistakes (e.g., lowercase "cairo" instead of "Cairo")
# and typos (e.g., "Pltos" instead of "Plots") across both local environments and
# the entire Julia General Registry, printing helpful suggestions with zero
# startup overhead on working scripts.

using QuickEnv

println("=== QuickEnv Package Diagnosis Demo ===")
println("Diagnosing unrecognized package imports:")

# Demonstrate diagnostic warnings for casing errors and typos
QuickEnv.diagnose_and_suggest_packages(["cairo", "Pltos", "Datafarmes", "Fluxx"], false)

println("Diagnosis demo complete.")
