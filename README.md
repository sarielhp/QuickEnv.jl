# QuickEnv.jl

[![Build Status](https://github.com/sarielhp/QuickEnv.jl/workflows/CI/badge.svg)](https://github.com/sarielhp/QuickEnv.jl/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Julia Version](https://img.shields.io/badge/julia-v1.10+-8A2BE2.svg)](https://julialang.org/)

`QuickEnv.jl` provides a **set-and-forget environment setup** for standalone Julia scripts.

The overhead is minimal, both in **[runtime](docs/tradeoffs.md#1-startup-performance-on-cached-runs-second-run)** (~47 ms on cached runs) and **[disk space](docs/DESIGN.md#8-the-economics-of-julia-environments-why-having-100-environments-costs-almost-nothing)** (~3 KB per environment).

After installing `QuickEnv` once in your global environment (`@v1.x`), simply add `using QuickEnv` to the top of any standalone script. QuickEnv automatically inspects your imports, discovers or fast-stitches a matching shared environment, installs any missing packages into isolated environments, and activates the project before your code runs—**without ever modifying your global environment**.

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

## Optional Configuration (Magic Comments)

QuickEnv requires no configuration for typical usage. However, power users can supply optional directives via inline comments:

```julia
using QuickEnv # fallback: plotting, exclude: global, silent
```

Common directives include:
- `# fallback: <env>` — Target a specific named environment if no match exists.
- `# create: <env>` — Force QuickEnv to use and manage a specific named environment.
- `# local` — Activate the script's local directory as `--project=.`.
- `# exclude: global` — Avoid matching the global environment (`@v1.x`).
- `# silent` / `# verbose` — Configure output logging levels.

> For the complete reference of all available magic comments and standalone directives (`# desc:`, multiline formats, environment variables), see the **[Configuration Guide](docs/README.md#optional-configuration-magic-comments-reference)**.

---

## Example: Cross-Script Environment Reuse

QuickEnv builds a compounding pool of isolated environments. Once an environment is bootstrapped, future scripts in any directory reuse it automatically:

### Step 1: Run your first script (`analyze_data.jl`)
```julia
#!/usr/bin/env julia
using QuickEnv
using Plots, DataFrames, CSV

# First execution: QuickEnv automatically bootstraps an isolated environment
# containing Plots, DataFrames, and CSV without touching your global environment.
df = DataFrame(time = 1:10, signal = sin.(1:10))
p = plot(df.time, df.signal, title="Data Analysis")
savefig(p, "analysis.pdf")
```

### Step 2: Later, run a second script (`quick_plot.jl`) anywhere on your machine
```julia
#!/usr/bin/env julia
using QuickEnv
using Plots

# Immediate launch (<1ms): QuickEnv detects that Plots is already satisfied
# by the environment created in Step 1—zero download, zero solve, zero recompilation.
p = plot(1:100, rand(100), title="Quick Plot")
savefig(p, "quick.pdf")
```

> For additional specialized examples (fallback overrides, warning handling, typo diagnostics), see the **[examples/](examples/)** directory and the **[User Guide](docs/README.md)**.

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
