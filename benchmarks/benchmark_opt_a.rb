#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'tmpdir'

puts "=========================================================================="
puts "     OPTIMIZATION A BENCHMARK: Full SAT Solve vs. Incremental Solve       "
puts "=========================================================================="
puts

Dir.mktmpdir("qenv_bench_") do |tmpdir|
  base_env = File.join(tmpdir, "base_env")
  scratch_env = File.join(tmpdir, "scratch_env")
  opt_a_env = File.join(tmpdir, "opt_a_env")
  [base_env, scratch_env, opt_a_env].each { |d| FileUtils.mkdir_p(d) }

  # Packages: 3 pre-existing base packages + 1 new package
  base_pkgs = ["JSON", "Crayons", "DataStructures"]
  new_pkg = "Example"
  all_pkgs = base_pkgs + [new_pkg]

  puts "1. Preparing pre-existing base environment with #{base_pkgs.join(', ')}..."
  setup_code = <<~JULIA
    using Pkg
    Pkg.activate("#{base_env}"; io=devnull)
    Pkg.add(#{base_pkgs.inspect}; io=devnull)
  JULIA
  _, err0, st0 = Open3.capture3("julia", "-e", setup_code)
  raise "Base setup failed: #{err0}" unless st0.success?
  puts "   Base environment created."

  # Test 1: Full SAT Solve from Scratch (All 4 packages into an empty project)
  puts "\n2. Measuring Approach 1: Full SAT Solve from Scratch (4 packages)..."
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  code_scratch = <<~JULIA
    using Pkg
    Pkg.activate("#{scratch_env}"; io=devnull)
    Pkg.add(#{all_pkgs.inspect}; io=devnull)
  JULIA
  _, err1, st1 = Open3.capture3("julia", "-e", code_scratch)
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  time_scratch = (t1 - t0) * 1000.0
  raise "Approach 1 failed: #{err1}" unless st1.success?

  # Test 2: Optimization A (Fast-Stitch Base Manifest + Incremental Pkg.add for 1 package)
  puts "3. Measuring Approach 2: Optimization A (Pre-Stitch base + Incremental Pkg.add for #{new_pkg})..."
  t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  code_opt_a = <<~JULIA
    # Step a: Fast-stitch base environment (<2ms)
    cp("#{File.join(base_env, "Project.toml")}", "#{File.join(opt_a_env, "Project.toml")}"; force=true)
    cp("#{File.join(base_env, "Manifest.toml")}", "#{File.join(opt_a_env, "Manifest.toml")}"; force=true)

    # Step b: Incremental Pkg.add for ONLY the 1 missing package
    using Pkg
    Pkg.activate("#{opt_a_env}"; io=devnull)
    Pkg.add(["#{new_pkg}"]; io=devnull)
  JULIA
  _, err2, st2 = Open3.capture3("julia", "-e", code_opt_a)
  t3 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  time_opt_a = (t3 - t2) * 1000.0
  raise "Approach 2 failed: #{err2}" unless st2.success?

  puts
  puts "=========================================================================="
  puts "                              TIMING RESULTS                              "
  puts "=========================================================================="
  puts format("%-50s : %8.2f ms", "1. Full SAT Solve from scratch (4 packages)", time_scratch)
  puts format("%-50s : %8.2f ms", "2. Optimization A (Stitch 3 pkgs + Solve 1 pkg)", time_opt_a)
  puts "--------------------------------------------------------------------------"
  saved = time_scratch - time_opt_a
  pct = (saved / time_scratch) * 100.0
  puts format("%-50s : %8.2f ms faster (%.1f%% reduction)", "Speedup / Time Saved", saved, pct)
  puts "=========================================================================="
  puts
end
