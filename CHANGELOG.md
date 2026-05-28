# Changelog

All notable changes to the `QuickEnv` package will be documented in this file.

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
