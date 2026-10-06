# Tradeoffs of Using QuickEnv.jl

This document outlines the practical tradeoffs, advantages, and limitations of using `QuickEnv.jl` compared to standard Julia environment management approaches.

---

## 1. Startup Performance on Cached Runs (Second Run)

### The Second-Run Startup Cost
* **Without QuickEnv (explicit `--project=@env`)**: When a named environment is specified on the command line, Julia directly activates the environment at startup.
* **With QuickEnv (`using QuickEnv`)**: Julia starts in the default environment, loads the `TOML` standard library and the `QuickEnv` module, checks the cache file (`cache.toml`), and calls `Base.set_active_project`.

### Measured Execution Times (Baseline "Hello World"):
| Setup | Execution Time | Difference |
| :--- | :---: | :---: |
| Plain Julia (`julia --project=@env script.jl`) | ~210 ms | Baseline |
| QuickEnv (`julia script.jl` with `using QuickEnv`) | ~258 ms | **+47 ms** (~22% on empty startup) |

> **Summary**: Running a script for the second time is faster without `QuickEnv` if the exact `--project` flag is provided manually. The difference is approximately **47 milliseconds**, which represents the cost of loading `TOML` and the `QuickEnv` module. For scripts that load substantial packages (e.g. `Plots`, `DataFrames`) or perform multi-second computations, this 47 ms difference represents a small fraction of total runtime.

---

## 2. Resolution Performance on Cold Runs (First Run)

On the first execution of a script, QuickEnv can be faster than standard `Pkg.add` environment creation when it can reuse compatible resolved metadata and compile caches.

### Case A: Dependencies Fully Covered by Existing Environments (Fast-Stitching)
* **Standard `Pkg.add` from Scratch**: 5,000–30,000+ ms (evaluates dependency graphs across the registry and precompiles packages).
* **QuickEnv Fast Stitching**: Commonly milliseconds for small environment pools; it validates and unifies existing manifests without invoking Pkg's resolver. Julia can reuse compatible compile caches but may compile when no valid cache exists.

### Case B: Partial Cover + Incremental Solve (Optimization A)
When a script requires packages that are only partially covered by existing environments (e.g., 4 known packages + 1 new package):
* QuickEnv **pre-stitches the base manifest** containing the 4 known packages in `<2 ms`.
* It asks `Pkg.add` to add **only the 1 missing package**, preferring the pre-populated manifest while allowing Julia's resolver to change it when compatibility requires that.

#### Measured Cold Resolution Times (`benchmarks/benchmark_opt_a.rb`):
| Approach | Resolution Time | Difference |
| :--- | :---: | :---: |
| Full SAT solve from scratch (All packages) | 6,855 ms | Baseline |
| QuickEnv Optimization A (Pre-stitch base + solve 1 package) | 4,325 ms | **2,530 ms faster (36.9% reduction)** |

> **Why this is faster**:
> 1. **Constrained SAT Solving**: Exact direct-package bounds reduce the version choices for the pre-stitched base packages.
> 2. **Preserved Base Graph**: QuickEnv uses exact direct-package compatibility bounds and `PRESERVE_TIERED` while adding missing packages. This prefers the stitched dependency graph while allowing Pkg to relax preservation if required for a valid combined solution.
>
> *(A reproducible benchmark is provided in `benchmarks/benchmark_opt_a.rb`).*

---

## 3. Comparison Matrix

| Aspect | Default Global (`@v1.x`) | Local Projects (`--project=.`) | Named Envs (`--project=@env`) | QuickEnv.jl |
| :--- | :--- | :--- | :--- | :--- |
| **Command to run** | `julia script.jl` | `julia --project=. script.jl` | `julia --project=@env script.jl` | `julia script.jl` (or `./script.jl`) |
| **Global env safety** | Low (accumulates conflicts) | High | High | High |
| **Directory clutter** | None | High (`Project.toml`/`Manifest.toml` per script) | None | None |
| **Manual env tracking** | None | Low | High (must remember environment names) | None |
| **First-run setup** | Manual `Pkg.add` | Manual `Pkg.activate` + `add` | Manual `Pkg.activate` + `add` | Automatic (matching, stitching, or bootstrap) |
| **Steady-state overhead** | 0 ms | 0 ms | 0 ms | ~47 ms |

---

## 4. Advantages (Pros)

1. **Keeping the Global Environment Small and Conflict-Free**:
   * Because packages are installed into dedicated or shared named environments rather than the default `@v1.x` environment, the global environment remains small and clean. This prevents package version conflicts from accumulating over time.
2. **Flagless Execution & Shebang Compatibility**:
   * Scripts can be executed directly as `./script.jl` or `julia script.jl` without passing `--project` flags.
3. **Automatic Multi-Environment Reuse (Fast Stitching)**:
   * Preserves package identities across shared environments by synthesizing a combined manifest without invoking Pkg's resolver. Compatible compile caches can be reused.
4. **Faster Cold Resolution (Partial Stitching)**:
   * Constrains Pkg's SAT solver when adding new packages by pre-populating manifests from existing environments, saving seconds on cold bootstraps.
5. **Zero Directory Pollution**:
   * Does not create `Project.toml` or `Manifest.toml` files in script working directories unless explicitly requested via `# local`.
6. **Typo and Casing Detection**:
   * Identifies package casing mismatches (e.g., `using cairo` vs `using Cairo`) and typos against the General Registry before failure.
7. **Low Disk Footprint for Environments**:
   * Julia environments contain metadata and reuse content-addressed package sources and artifacts. Manifests can range from kilobytes to hundreds of kilobytes, but they do not duplicate package source trees or artifacts.
8. **LLM Context & Token Efficiency for AI Agents**:
   * Eliminates multi-turn package error-retry loops and verbose `Pkg.add` terminal output in AI coding agent context windows, saving thousands of tokens per task. (See **[docs/AGENTS.md](AGENTS.md#5-token-efficiency-eliminating-multi-turn-error-loops)**).

---

## 5. Disadvantages and Limitations (Cons)

1. **Startup Overhead on Cached Runs**:
   * Adds ~47 ms to every execution due to module loading and cache verification.
2. **Dependency on QuickEnv in Global Environment**:
   * Scripts containing `using QuickEnv` require `QuickEnv` to be installed in the target machine's global Julia environment.
3. **Not Suitable for Production Packages**:
   * Published Julia packages, libraries, and large multi-module applications should use standard `Project.toml` and committed `Manifest.toml` files tracked in Git for exact reproducibility.
4. **Static Include Limitation**:
   * QuickEnv can only discover dependencies in files included via static string literals (`include("file.jl")`). Dynamic includes (e.g., `include(joinpath(@__DIR__, var))`) cannot be analyzed before runtime.
5. **Time-Bounded Cover Search**:
   * Branch-and-bound minimizes source-environment count and then extraneous direct dependencies. With a large environment pool it may hit its time budget and use the best complete cover found so far or fall back to Pkg.
