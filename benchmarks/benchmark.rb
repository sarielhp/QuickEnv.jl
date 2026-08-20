#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'

def measure(cmd, runs = 15, warmups = 3)
  # Warmups
  warmups.times do
    Open3.capture3(*cmd)
  end

  times = []
  runs.times do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    stdout, stderr, status = Open3.capture3(*cmd)
    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    unless status.success?
      warn "Command failed: #{stderr}"
      exit 1
    end
    times << (t1 - t0) * 1000.0 # in ms
  end
  times.sort
end

def stats(times)
  mean = times.sum / times.size
  median = times[times.size / 2]
  min = times.first
  max = times.last
  stddev = Math.sqrt(times.map { |t| (t - mean)**2 }.sum / (times.size - 1))
  { mean: mean, median: median, min: min, max: max, stddev: stddev }
end

plain_cmd = %w[julia --project=. benchmarks/hello_plain.jl]
quickenv_cmd = %w[julia --project=. benchmarks/hello_quickenv.jl]

puts "Running benchmarks (15 runs each, 3 warmups)..."
puts

plain_times = measure(plain_cmd)
quickenv_times = measure(quickenv_cmd)

s_plain = stats(plain_times)
s_quickenv = stats(quickenv_times)

diff_median = s_quickenv[:median] - s_plain[:median]
diff_mean = s_quickenv[:mean] - s_plain[:mean]
diff_min = s_quickenv[:min] - s_plain[:min]

puts "=========================================================================="
puts "                          BENCHMARK RESULTS                               "
puts "=========================================================================="
puts format("%-22s %10s %10s %10s %10s", "Benchmark", "Median", "Mean", "Min", "StdDev")
puts "--------------------------------------------------------------------------"
puts format("%-22s %8.2f ms %8.2f ms %8.2f ms %8.2f ms", "Plain Hello World", s_plain[:median], s_plain[:mean], s_plain[:min], s_plain[:stddev])
puts format("%-22s %8.2f ms %8.2f ms %8.2f ms %8.2f ms", "With using QuickEnv", s_quickenv[:median], s_quickenv[:mean], s_quickenv[:min], s_quickenv[:stddev])
puts "=========================================================================="
puts
puts format("Time difference (Median): +%.2f ms (%.1f%% overhead)", diff_median, (diff_median / s_plain[:median]) * 100.0)
puts format("Time difference (Mean):   +%.2f ms (%.1f%% overhead)", diff_mean, (diff_mean / s_plain[:mean]) * 100.0)
puts format("Time difference (Min):    +%.2f ms", diff_min)
puts
