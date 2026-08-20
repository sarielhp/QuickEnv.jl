# QuickEnv.jl

[![Build Status](https://github.com/sarielhp/QuickEnv.jl/workflows/CI/badge.svg)](https://github.com/sarielhp/QuickEnv.jl/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Julia Version](https://img.shields.io/badge/julia-v1.10+-8A2BE2.svg)](https://julialang.org/)

`QuickEnv.jl` provides a **set-and-forget environment workflow** for standalone Julia scripts—handling dependency discovery, fast manifest stitching, and isolated project activation behind the scenes without ever polluting your global environment.

After installing `QuickEnv` once in your global environment (`@v1.x`), simply add `using QuickEnv` to the top of any standalone script. QuickEnv inspects your script's imports, discovers or fast-stitches a matching shared environment, installs any missing packages into isolated environments, and activates everything transparently before your code runs.

> **Zero Friction, Zero Pollution**: Run standalone scripts (`julia script.jl` or `./script.jl`) with automatic environment resolution while keeping your global `@v1.x` environment completely pristine and conflict-free.

---

## Quick Start

### 1. Install once in your global environment

```julia
using Pkg
Pkg.activate()  # Activate standard global environment (e.g., @v1.12)
Pkg.add(url="https://github.com/sarielhp/QuickEnv.jl.git")
```

### 2. Add `using QuickEnv` to the top of your script

```julia
#!/usr/bin/env julia
using QuickEnv
using Plots, DataFrames

# Rest of your program...
```

When you execute `julia your_script.jl` or `./your_script.jl`:
- QuickEnv parses the script's imports (`using Plots, DataFrames`).
- If an existing [named environment](#shared-named-environments-in-julia) satisfies the imports (e.g., `@plotting_data`), QuickEnv activates it immediately.
- If multiple environments together cover the imports (e.g., `@plotting` + `@data`), QuickEnv fast-stitches them into a combined `@auto_<hash>` environment in `<5ms` with zero recompilation.
- If new packages are required, QuickEnv pre-stitches the known base packages and installs the missing packages via `Pkg.add` into a dedicated `@auto_<hash>` environment.
- **Your global environment (`@v1.x`) remains untouched.** Subsequent runs hit the cache for near-zero startup overhead.

---

## The Problem: The Global Environment Trap

Julia package environments typically follow one of three approaches:

1. **Global Environment (`@v1.x`)**: Convenient initially, but installing packages directly into `@v1.x` eventually leads to **dependency conflicts** across unrelated scripts and slower startup times.
2. **Local Directory Projects (`--project=.`)**: Provides project isolation, but litters working directories with `Project.toml` / `Manifest.toml` files for one-off scripts and duplicates package precompilations.
3. **Shared Named Environments (`@plotting`, `@data`)**: Stores reusable environments under `~/.julia/environments/`, but requires manually remembering and passing `--project=@env` flags on every run.

**QuickEnv provides the advantages of all three:**
- **Pristine Global Environment**: Strictly protects `@v1.x` from package contamination.
- **Autonomous Named Selection**: Automatically finds or synthesizes the right named environment in `~/.julia/environments/`.
- **Fast Compound Stitching**: Combines compatible environments in `<5ms` without running Pkg's SAT solver or recompiling packages.
- **Local Project Mode**: Supports `# local` whenever you want the local directory activated as `--project=.`.

---

## Shared Named Environments in Julia

A **Shared Named Environment** in Julia (such as `@plotting` or `@data`) is an isolated package environment stored in `~/.julia/environments/`.

Out of the box, Julia includes the standard versioned global environment (e.g., `@v1.12`). All other named environments are custom namespaces created by the user or generated automatically by `QuickEnv`.

---

## Configuration & Magic Comments

QuickEnv supports configuration via inline or standalone comments.

### 1. Compact Inline Format (Recommended)
Options can be specified on the `using QuickEnv` line:

```julia
using QuickEnv # fallback: plotting, exclude: global, silent, create: data, desc: "Data analysis environment"
```

### 2. Standalone Comment Directives

#### Forced Environment Creation (`create`)
Forces `QuickEnv` to use a specific named environment (e.g., `@science`), creating it if it does not exist and installing any missing packages:
```julia
# QuickEnv.create: science
```
or inline:
```julia
using QuickEnv # create: science
```

#### Fallback Environment (`fallback`)
Searches existing named environments first. If no existing environment satisfies the script's imports, it bootstraps the specified fallback (e.g., `@plotting`):
```julia
# quickenv_fallback: plotting
```
or inline:
```julia
using QuickEnv # fallback: plotting
```

#### Environment Description (`desc` / `description`)
Attaches a human-readable description to the target environment's `Project.toml`:
```julia
# QuickEnv.desc: Environment with plotting and data tools
```

#### Excluded Environments (`exclude`)
Prevents specific environments from being selected. Using `global` excludes standard versioned environments (e.g., `@v1.12`):
```julia
# quickenv_exclude: global, broken_plotting
```

#### Local Directory Project (`# local`)
Directs QuickEnv to activate the script's local directory as the project (equivalent to `julia --project=. script.jl`):
```julia
using QuickEnv # local
```

#### Logging Verbosity (`verbose` / `silent`)
- **Default**: Runs quietly on matching runs; outputs informative logs when creating environments or installing packages.
- **Verbose**: Logs detailed matching, candidate scoring, and timing info:
  ```julia
  using QuickEnv # verbose
  # or export QUICKENV_VERBOSE=true
  ```
- **Silent**: Suppresses all non-error output:
  ```julia
  using QuickEnv # silent
  # or export QUICKENV_SILENT=true
  ```

---

## Code Examples

### Example A: Global Environment Isolation & Plotting
Prevents matching the global environment and sets `@plotting` as the fallback target:

```julia
#!/usr/bin/env julia
using QuickEnv # fallback: plotting, exclude: global

using Plots
using Cairo

function (@main)(args)
    gr()
    p = plot(1:10, rand(10), title="Isolated Plot")
    savefig(p, "output/plot.pdf")
    println("Saved plot to output/plot.pdf")
    return 0
end
```

### Example B: Dedicated Data Workflow
Requests `@data` as the fallback named environment:

```julia
#!/usr/bin/env julia
using QuickEnv # fallback: data, exclude: global

using DataFrames
using CSV

function (@main)(args)
    df = DataFrame(A = 1:5, B = rand(5))
    CSV.write("output/data.csv", df)
    println("Saved data to output/data.csv")
    return 0
end
```

### Example C: Local Project Coexistence Warning
When activating a shared named environment while local project files (`Project.toml` / `Manifest.toml`) exist in the script directory, QuickEnv displays an informational warning to ensure intent is clear:

```julia
#!/usr/bin/env julia
using QuickEnv # fallback: plotting, exclude: global

using Plots

function (@main)(args)
    println("Running in @plotting despite local Project.toml present...")
    return 0
end
```

---

## Technical Architecture

QuickEnv resolves environments through an autonomous multi-stage pipeline:
1. **O(1) Fast Script-Level Cache**: Checks file modification times (`mtime`) against `~/.julia/quickenv/cache.toml` to reuse known environments in `<0.5ms`.
2. **Bitmask Set-Cover Solver**: Maps dependency sets to hardware bitmasks (`UInt64`) to find the minimal combination of existing named environments.
3. **Manifest Fast-Stitching (<5ms)**: Verifies transitive dependency compatibility and synthesizes compound `@auto_<hash>` environments on disk without running Pkg's SAT solver or recompiling packages.
4. **Partial Stitching & Incremental Bootstrap**: When new packages are requested, pre-stitches the known base manifest and runs `Pkg.add` only on the missing packages, avoiding recompilation cascades.

> For an in-depth explanation of fast stitching vs. runtime stacking (`LOAD_PATH`), bitmask scoring math, and caching internals, see **[docs/DESIGN.md](docs/DESIGN.md)**.

---

## Environment Management with `jlenv`

QuickEnv includes an administrative utility at `tools/jlenv.jl` to inspect, clean, and manage shared named environments:

```bash
# Clean up auto-generated environments and reset cache
./tools/jlenv.jl prune

# List all named environments and their descriptions
./tools/jlenv.jl list

# Show packages in a specific named environment
./tools/jlenv.jl show @plotting

# Inspect the resolution cache
./tools/jlenv.jl cache list

# Open an interactive Julia REPL inside a named environment
./tools/jlenv.jl repl @plotting
```

> For the complete CLI command reference and shell alias setup guide, see **[docs/jlenv.md](docs/jlenv.md)**.

---

## Best Practices & Limitations

### 1. Interactive Scripts vs. Production Packages
QuickEnv is designed for interactive exploration, data science workflows, standalone scripts, and computational tools. For published packages, shared libraries, or production services requiring strict long-term reproducibility, a committed `Manifest.toml` tracked in Git remains standard practice.

### 2. Static Include Scanning vs. Dynamic Includes
QuickEnv statically analyzes `include("path/to/file.jl")` calls before execution to discover dependencies across included files.
* **Limitation**: Dynamic include expressions (e.g., `include(joinpath(@__DIR__, ARGS[1]))`) cannot be evaluated prior to runtime.
* **Recommendation**: Declare dependencies at the top of the entry script, or use `using QuickEnv # local` for multi-file local project folders.

### 3. Submodule Imports
Submodule imports (such as `using HTTP.WebSockets` or `import DataFrames.DataFrame`) are automatically parsed and mapped to their registered root packages (`HTTP`, `DataFrames`).

> For a pros vs. cons analysis and startup performance comparison, see **[docs/tradeoffs.md](docs/tradeoffs.md)**.  
> Details on failure handling (`atexit` self-healing invalidation) and atomic POSIX writes are documented in **[docs/DESIGN.md](docs/DESIGN.md)**.

---

## Testing

Run the test suite:

```bash
julia --project=. test/runtests.jl
```

---

## Disclaimer

Most of the package was written using antigravity-cli. However, I (a real human) reviewed the code and it seems OK to me. This is hopefully a useful package and not just AI generated junk. I would of course handle any bugs/issues.

---

## License

Distributed under the MIT License. See `LICENSE` for more information.
