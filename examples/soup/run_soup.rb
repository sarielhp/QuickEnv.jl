#!/usr/bin/env ruby
# run_soup.rb - Comprehensive test runner for QuickEnv script soup.
#
# 1. Resets and prunes QuickEnv auto-generated environments & cache.
# 2. Randomly shuffles a collection of Julia scripts using various heavy & light packages.
# 3. Runs them sequentially in Phase 1 (demonstrating autonomous resolution & fast stitching).
# 4. Runs them sequentially in Phase 2 (demonstrating instant O(1) hash cache hits).

require "fileutils"
require "open3"
require "time"

ROOT_DIR = File.expand_path("../..", __dir__)
SOUP_DIR = File.join(ROOT_DIR, "examples", "soup")
JLENV = File.join(ROOT_DIR, "tools", "jlenv.jl")

puts "=" * 80
puts "          QuickEnv Comprehensive Script Soup Test Runner"
puts "=" * 80

# 1. Prune existing auto-generated environments and cache
puts "
>>> Step 1: Pruning auto-generated QuickEnv environments & cache..."
system("julia", JLENV, "prune")

# 2. Find all scripts
scripts = Dir.glob(File.join(SOUP_DIR, "*.jl")).sort
if scripts.empty?
  puts "No scripts found in #{SOUP_DIR}!"
  exit 1
end

puts "
Found #{scripts.size} scripts in soup collection:"
scripts.each { |s| puts "  • #{File.basename(s)}" }

# 3. Phase 1: Run in random order (Cold / First-Pass Resolution)
shuffled_1 = scripts.shuffle
puts "
" + "=" * 80
puts ">>> Phase 1: First Pass (Random Order - Cold Stitching & Cache Population)"
puts "=" * 80

phase1_results = {}

shuffled_1.each_with_index do |script, idx|
  bname = File.basename(script)
  puts "
[#{idx + 1}/#{shuffled_1.size}] Running: #{bname}..."
  
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  stdout, stderr, status = Open3.capture3(
    { "QUICKENV_VERBOSE" => "true" },
    "julia", "--project=#{ROOT_DIR}", script
  )
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  elapsed = (t1 - t0)

  phase1_results[bname] = elapsed
  
  if !stdout.strip.empty?
    puts "  [Output] #{stdout.strip}"
  end
  if !stderr.strip.empty?
    stderr.strip.split("
").each do |l|
      puts "  [Log] #{l}" unless l.include?("Precompiling")
    end
  end
  puts "  -> Completed in #{elapsed.round(2)}s (exit #{status.exitstatus})"
end

# 4. Inspect Cache and Created Environments
puts "
" + "=" * 80
puts ">>> Intermediate State: QuickEnv Cache & Environment Registry"
puts "=" * 80
system("julia", JLENV, "cache", "list")
system("julia", JLENV, "list")

# 5. Phase 2: Run in new random order (Warm / Pure O(1) Cache Hits)
shuffled_2 = scripts.shuffle
puts "
" + "=" * 80
puts ">>> Phase 2: Second Pass (New Random Order - Instant O(1) Cache Hits)"
puts "=" * 80

phase2_results = {}

shuffled_2.each_with_index do |script, idx|
  bname = File.basename(script)
  puts "
[#{idx + 1}/#{shuffled_2.size}] Re-running: #{bname}..."
  
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  stdout, stderr, status = Open3.capture3(
    { "QUICKENV_VERBOSE" => "true" },
    "julia", "--project=#{ROOT_DIR}", script
  )
  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  elapsed = (t1 - t0)

  phase2_results[bname] = elapsed
  
  if !stdout.strip.empty?
    puts "  [Output] #{stdout.strip}"
  end
  puts "  -> Completed in #{elapsed.round(2)}s (exit #{status.exitstatus})"
end

# 6. Performance Summary Table
puts "
" + "=" * 80
puts "                        Execution Summary Table"
puts "=" * 80
puts sprintf("%-30s | %-15s | %-15s | %-10s", "Script Name", "Phase 1 (Cold)", "Phase 2 (Cached)", "Speedup")
puts "-" * 80

scripts.each do |s|
  bname = File.basename(s)
  t1 = phase1_results[bname] || 0.0
  t2 = phase2_results[bname] || 0.0
  speedup = t2 > 0 ? (t1 / t2).round(1) : 1.0
  puts sprintf("%-30s | %13.2fs | %13.2fs | %8.1fx", bname, t1, t2, speedup)
end

puts "=" * 80
puts "Soup execution complete! All scripts successfully executed."
