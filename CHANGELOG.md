# Changelog

All notable changes to the `QuickEnv` package will be documented in this file.

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
