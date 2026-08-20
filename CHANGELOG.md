# Changelog

All notable changes to the `QuickEnv` package will be documented in this file.

## [0.4.0] - 2026-08-20

### Added
- **Optimization A (Partial Fast Stitch + Incremental `Pkg.add`)**: When a script's requested dependencies cannot be 100% covered by existing environments, QuickEnv finds the maximal compatible subset of existing environments, pre-stitches their `Manifest.toml` into `@auto_<hash>` in <2ms, and runs `Pkg.add` only on the remaining missing packages. This saves up to 37% resolution time on cold starts and guarantees zero recompilation of base packages.
- Added `find_partial_covering_envs` implementing strict subset containment and greedy seed initialization.
- Added GitHub Actions CI test matrix workflow (`.github/workflows/CI.yml`).
- Added comprehensive benchmark scripts in Ruby for steady-state startup (`benchmarks/benchmark.rb`) and cold-start incremental resolution (`benchmarks/benchmark_opt_a.rb`).

### Fixed
- **Local Project Activation (`# local`)**: Replaced `Pkg.activate(script_dir)` with `activate_local_dir_env(script_dir)` using `Base.set_active_project`, eliminating unnecessary `Pkg` module loading in local directory mode.
- **Cache Corruption Resilience**: Hardened `check_cache_hit` to handle corrupted cache entries with mismatched sources/mtimes gracefully without throwing exceptions.
- **Exact Script Cache Timestamp Matching**: Changed script cache mtime comparison from `<=` to strict equality `==` to prevent stale cache hits on clock adjustments.
- **Single Hash Computation**: Optimized `get_cache_hash` to compute `hash(key)` once into a local variable.
- **Exact Project Directory Matching**: Fixed substring match in `activate_matched_env` and `handle_forced_creation` to use `basename(dirname(current_project)) != env_name`.
- **String Quote Escaping**: Properly escaped double quotes when updating environment descriptions in `Project.toml`.
- **Debug Logging**: Added structured `@debug` logging across all previously bare `catch` blocks.
- **`jlenv` Tool Enhancements**: Configured `jlenv` to dynamically respect `DEPOT_PATH[1]`, delegate parsing helpers directly to `QuickEnv`, and properly handle fallback resolution when manifest merging encounters incompatibilities.

### Documentation
- Created **`docs/DESIGN.md`** providing a technical deep-dive into fast stitching vs. stacking, bitmask set-cover math, and caching internals.
- Created **`docs/jlenv.md`** as a complete CLI manual and command reference for the `jlenv` environment management utility.
- Created **`docs/tradeoffs.md`** objectively analyzing steady-state startup costs (+47ms) vs. cold-run resolution speedups (up to 37% faster) and global environment protection.
- Streamlined root `README.md` to focus on quick start and magic comments syntax while removing duplicate sections.

### Testing
- Expanded test suite from 86 to 116 passing unit tests, covering partial set-cover, mock manifest stitching, corrupted cache recovery, local directory activation, and stdlib diagnostic suggestions.

## [0.3.1] - 2026-08-19

### Documentation
- Clarified and streamlined package overview and quick-start instructions in `README.md`.

## [0.3.0] - 2026-08-19

### Added
- Silent by default: QuickEnv now runs completely silently during normal script execution when matching existing environments. Information logs are only printed when a new environment is being configured/created or missing packages are being installed.
- Added `verbose` mode support via inline `# verbose`, standalone `# quickenv_verbose: true`, or environment variable `QUICKENV_VERBOSE=true`.
- Added smart package diagnosis and typo detection: automatically checks imported packages for casing mistakes (e.g., `using cairo` $\rightarrow$ `using Cairo`) and typos (e.g., `using Pltos` $\rightarrow$ `using Plots`) across local environments, stdlibs, and the Julia General Registry with zero startup overhead on valid scripts.
- Added `examples/example_diagnostics.jl` to demonstrate package typo and casing diagnosis.

## [0.2.0] - 2026-06-04

### Added
- Supported custom named environment descriptions via inline keyword option `desc` / `description` and standalone comments `# QuickEnv.desc:` / `# QuickEnv.description:`.
- Added warning logs when local `Project.toml` or `Manifest.toml` files are being bypassed by an active named/fallback environment.
- Added standard vertical padding to info and warning prints to improve log visibility on `stderr`.
- Added interactive script `examples/example_warning.jl` to demonstrate local ignored files warnings.
- Added tests for warning logs, metadata parsing, and `Project.toml` description writing.

## [0.1.0] - 2026-05-28

### Added
- Created `.JuliaFormatter.toml` to enforce the community standard Blue Style Guide formatting rules with a 92-character margin.
- Introduced standard `@error` logging in all TOML parsing exception catch blocks, explicitly reporting the occurred exception alongside the file path where parsing failed.
- Implemented a session-wide silent mode tip printed at most once when no package modifications occur in interactive log mode.

### Changed
- Refactored `__init__` and `parse_script_metadata` into clean, modular subfunctions to improve codebase maintainability.
- Refactored the core bootstrapping and environment selection logic in `handle_matching_or_fallback` into isolated helper functions (`activate_matched_env`, `activate_fallback_env`, `bootstrap_packages`).
- Simplified and flattened control flow nesting by replacing complex conditional branches with guard clauses and early returns.
- Standardized multi-variable assignment destructuring to follow idiomatic Julia patterns.
- Exclusively consolidated all silent configuration options around the `silent` keyword, removing alternative `quiet` parsing logic and updating the documentation accordingly.

### Fixed
- Manually reflowed long comment lines, docstrings, and string literals to align within clean, legible margins.
