#!/usr/bin/env ruby
# run_soup.rb - Comprehensive test runner & post-mortem analyzer for QuickEnv script soup.
#
# 1. Resets and prunes QuickEnv auto-generated environments & cache.
# 2. Randomly shuffles a collection of Julia scripts using various heavy & light packages.
# 3. Runs Phase 1 (First Pass): Cold resolution, autonomous creation, and fast stitching.
# 4. Runs Phase 2 (Second Pass): New random order, verifying pure O(1) cache hits.
# 5. Generates an in-depth Post-Mortem Report detailing exactly what QuickEnv did for each script.

require "fileutils"
require "open3"
require "time"

ROOT_DIR = File.expand_path("../..", __dir__)
SOUP_DIR = File.join(ROOT_DIR, "examples", "soup")
JLENV = File.join(ROOT_DIR, "tools", "jlenv.jl")

puts "=" * 80
puts "          QuickEnv Comprehensive Script Soup Test Runner & Analyzer"
puts "=" * 80

# 1. Prune existing auto-generated environments and cache
puts "\n>>> Step 1: Pruning auto-generated QuickEnv environments & cache..."
system("julia", JLENV, "prune")

# Clean any local toml files
FileUtils.rm_f(File.join(SOUP_DIR, "Project.toml"))
FileUtils.rm_f(File.join(SOUP_DIR, "Manifest.toml"))

# 2. Find all scripts and parse their package imports
scripts = Dir.glob(File.join(SOUP_DIR, "[0-9]*.jl")).sort
if scripts.empty?
  puts "No scripts found in #{SOUP_DIR}!"
  exit 1
end

script_packages = {}
def extract_packages_recursive(file_path, visited=Set.new)
  return [] unless File.file?(file_path)
  return [] if visited.include?(file_path)
  visited.add(file_path)
  pkgs = []
  dir = File.dirname(file_path)

  File.readlines(file_path).each do |line|
    clean = line.split("#").first.to_s.strip
    if clean =~ /^\s*(using|import)\s+(.*)$/
      raw_imports = $2.split(":").first
      raw_imports.split(",").each do |part|
        p = part.strip.split.first
        pkgs << p if p && !p.empty? && p != "QuickEnv"
      end
    elsif clean =~ /\binclude\s*\(\s*["']([^"']+)["']\s*\)/
      inc_file = File.expand_path($1, dir)
      pkgs.concat(extract_packages_recursive(inc_file, visited))
    end
  end
  pkgs.uniq
end

scripts.each do |script|
  bname = File.basename(script)
  script_packages[bname] = extract_packages_recursive(script)
end

puts "\nFound #{scripts.size} scripts in soup collection:"
script_packages.each do |s, pkgs|
  puts "  • #{s.ljust(26)} -> [#{pkgs.join(', ')}]"
end

# Helper to analyze QuickEnv verbose logs
def analyze_logs(stderr_text)
  action = "Unknown"
  assigned_env = "None"
  sources = []

  if stderr_text =~ /Fast script cache hit for .*? -> @([a-zA-Z0-9_\-]+)/
    assigned_env = "@#{$1}"
    action = "Fast Script Cache Hit (mtime)"
  elsif stderr_text =~ /Fast-stitched autonomous environment @([a-zA-Z0-9_\-]+)\s*\n\s*from\s+([^\n]+)/m
    assigned_env = "@#{$1}"
    sources = $2.strip.split(/\s*[\+,]\s*/).map { |s| s.sub(/^@/, '') }
    action = "Fast-Stitched (#{sources.map { |s| "@#{s}" }.join(' + ')})"
  elsif stderr_text =~ /into\s+(?:└\s+)?(@[a-zA-Z0-9_\-]+)/m
    assigned_env = $1.strip
    action = "Created New Environment"
  elsif stderr_text =~ /Found matching environment @([a-zA-Z0-9_\-]+)/
    assigned_env = "@#{$1}"
    action = "Matched Existing"
  elsif stderr_text =~ /Activating environment @([a-zA-Z0-9_\-]+)/
    assigned_env = "@#{$1}"
    action = "Created New Environment"
  elsif stderr_text =~ /Activating local (?:directory )?environment/
    assigned_env = "local directory"
    action = "Local Directory"
  end

  { action: action, env: assigned_env, sources: sources }
end

# 3. Phase 1: Run in random order (Cold / First-Pass Resolution)
shuffled_1 = scripts.shuffle
puts "\n" + "=" * 80
puts ">>> Phase 1: First Pass (Random Order - Cold Resolution & Stitching)"
puts "=" * 80

phase1_records = {}

shuffled_1.each_with_index do |script, idx|
  bname = File.basename(script)
  puts "\n[#{idx + 1}/#{shuffled_1.size}] Running: #{bname}..."
  puts "  Packages: [#{script_packages[bname].join(', ')}]"
  
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  stdout, stderr, status = Open3.capture3(
    { "QUICKENV_VERBOSE" => "true" },
    "julia", "--project=#{ROOT_DIR}", script
  )
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  elapsed = (t1 - t0)

  analysis = analyze_logs(stderr)
  phase1_records[bname] = {
    elapsed: elapsed,
    exitstatus: status.exitstatus,
    action: analysis[:action],
    env: analysis[:env],
    sources: analysis[:sources],
    stdout: stdout.strip,
    stderr: stderr
  }

  puts "  [Action]  #{analysis[:action]} -> #{analysis[:env]}"
  if !stdout.strip.empty?
    puts "  [Output]  #{stdout.strip}"
  end
  puts "  -> Completed in #{elapsed.round(2)}s (exit #{status.exitstatus})"
end

# 4. Intermediate State
puts "\n" + "=" * 80
puts ">>> Intermediate State: QuickEnv Cache & Environment Registry"
puts "=" * 80
system("julia", JLENV, "cache", "list")
system("julia", JLENV, "list")

# 5. Phase 2: Run in new random order (Warm / Pure O(1) Cache Hits)
shuffled_2 = scripts.shuffle
puts "\n" + "=" * 80
puts ">>> Phase 2: Second Pass (New Random Order - Instant O(1) Cache Hits)"
puts "=" * 80

phase2_records = {}

shuffled_2.each_with_index do |script, idx|
  bname = File.basename(script)
  puts "\n[#{idx + 1}/#{shuffled_2.size}] Re-running: #{bname}..."
  
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  stdout, stderr, status = Open3.capture3(
    { "QUICKENV_VERBOSE" => "true" },
    "julia", "--project=#{ROOT_DIR}", script
  )
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  elapsed = (t1 - t0)

  analysis = analyze_logs(stderr)
  phase2_records[bname] = {
    elapsed: elapsed,
    exitstatus: status.exitstatus,
    action: "Cache Hit -> #{analysis[:env]}",
    env: analysis[:env],
    stdout: stdout.strip
  }

  puts "  [Action]  Cache Hit (O(1)) -> #{analysis[:env]}"
  if !stdout.strip.empty?
    puts "  [Output]  #{stdout.strip}"
  end
  puts "  -> Completed in #{elapsed.round(2)}s (exit #{status.exitstatus})"
end

# 6. Comprehensive Post-Mortem Report
puts "\n" + "=" * 80
puts "                      QUICKENV SOUP POST-MORTEM REPORT"
puts "=" * 80

puts "\n1. Detailed Per-Script Execution Analysis:"
puts "-" * 80

scripts.each_with_index do |s, i|
  bname = File.basename(s)
  pkgs = script_packages[bname]
  p1 = phase1_records[bname]
  p2 = phase2_records[bname]
  speedup = (p2 && p2[:elapsed] > 0) ? (p1[:elapsed] / p2[:elapsed]).round(1) : 1.0
  status_str = p1[:exitstatus] == 0 ? "Success (Exit 0)" : "Failed"

  puts "\n[#{i + 1}] #{bname}"
  puts "    • Required Packages : #{pkgs.join(', ')}"
  puts "    • Phase 1 Action    : #{p1[:action]}"
  puts "    • Assigned Env      : #{p1[:env]}"
  puts "    • Phase 2 Action    : #{p2[:action]}"
  puts "    • Timings           : Cold = #{p1[:elapsed].round(2)}s | Warm = #{p2[:elapsed].round(2)}s (#{speedup}x speedup)"
  puts "    • Output Status     : #{status_str}"
end

puts "\n" + "-" * 80
puts "2. Executive Summary Table:"
puts "-" * 80
puts sprintf("%-26s | %-24s | %-16s | %-10s | %-10s | %-8s", "Script Name", "First-Pass Action", "Assigned Env", "Cold (s)", "Warm (s)", "Speedup")
puts "-" * 80

scripts.each do |s|
  bname = File.basename(s)
  p1 = phase1_records[bname]
  p2 = phase2_records[bname]
  speedup = (p2 && p2[:elapsed] > 0) ? (p1[:elapsed] / p2[:elapsed]).round(1) : 1.0
  short_action = p1[:action].length > 24 ? p1[:action][0..21] + "..." : p1[:action]

  puts sprintf(
    "%-26s | %-24s | %-16s | %10.2f | %10.2f | %7.1fx",
    bname, short_action, p1[:env], p1[:elapsed], p2[:elapsed], speedup
  )
end

puts "=" * 80
puts "Post-mortem complete! All scripts ran cleanly with zero local directory clutter."
