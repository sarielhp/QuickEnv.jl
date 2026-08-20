# QuickEnv.jl

[![Build Status](https://github.com/sarielhp/QuickEnv.jl/workflows/CI/badge.svg)](https://github.com/sarielhp/QuickEnv.jl/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Julia Version](https://img.shields.io/badge/julia-v1.10+-8A2BE2.svg)](https://julialang.org/)

`QuickEnv.jl` automatically handles all environment setup required to run your Julia scripts—**without ever polluting your global environment**.

After installing `QuickEnv` once in your global environment (`@v1.x`), simply add `using QuickEnv` to the top of any standalone script. QuickEnv automatically inspects your script's imports, discovers or fast-stitches a matching shared environment, installs any missing packages into isolated environments, and activates everything transparently before your code runs.

> **Zero Friction, Zero Pollution**: Run standalone scripts (`julia script.jl` or `./script.jl`) with automatic environment resolution while keeping your global `@v1.x` environment completely pristine and conflict-free.

---

## Quick start

### 1. Install once in your global environment

```julia
using Pkg
Pkg.activate()  # Activate standard global environment (e.g., @v1.12)
Pkg.add(url="https://github.com/sarielhp/QuickEnv.jl.git")
```

### 2. Add `using QuickEnv` to the top of your script

Simply add `using QuickEnv` as the first import in your script:

```julia
#!/usr/bin/env julia
using QuickEnv
using Plots

# Rest of the program...
```

That's it! When you run `julia your_script.jl` or `./your_script.jl`:
- QuickEnv parses the script's imports (`using Plots`).
- If an existing [named environment](#understanding-shared-named-environments) satisfies the imports (e.g., `@plotting`), QuickEnv activates it immediately.
- If multiple environments cover the imports (e.g., `@plotting` + `@data`), QuickEnv fast-stitches them into a combined `@auto_<hash>` environment in `<5ms` without recompilation.
- If no existing environment matches, QuickEnv creates a dedicated named environment (`@auto_<hash>`), installs any missing packages via `Pkg.add`, and activates it.
- **Your global environment (`@v1.x`) is never modified.** Subsequent runs reuse cached resolution for near-zero startup overhead.

---

## The Problem: The Global Environment Trap

Julia package environments typically follow one of three approaches:

1. **Global Environment (`@v1.x`)**: Convenient for quick scripts, but installing multiple packages eventually leads to **dependency hell** (incompatible version bounds across unrelated scripts) and slow startup due to invalidations.
2. **Local Directory Projects (`--project=.`)**: Provides project isolation, but litters local directories with `Project.toml` / `Manifest.toml` files for simple one-off scripts and duplicates package precompilations.
3. **Shared Named Environments (`@plotting`, `@data`)**: Stores reusable environments under `~/.julia/environments/`, but requires manually remembering and typing `--project=@env` flags every time.

**QuickEnv gives you the best of all three:**

- **Pristine Global Environment**: Strictly protects `@v1.x` from package contamination.
- **Autonomous Named Selection**: Automatically finds or synthesizes the right named environment in `~/.julia/environments/`.
- **Fast Compound Stitching**: Combines compatible environments (e.g., `@plotting` + `@data`) in `<5ms` with zero recompilation.
- **Local Project Mode**: Supports `# local` whenever you do want the local directory activated as `--project=.`.

---

## Configuration options

### 1. Forced named environment creation (`create`)
Forces `QuickEnv` to use a specific named environment (e.g., `@science`). It creates `@science` if it does not exist and installs missing dependencies:

```julia
#!/usr/bin/env julia
using QuickEnv # create: science

using LsqFit
```

### 2. Explicit named environment fallback (`fallback`)
Searches existing named environments for a match first. If no matching environment satisfies the dependencies, it creates and bootstraps the specified fallback (e.g., `@plotting`):

```julia
#!/usr/bin/env julia
using QuickEnv # fallback: plotting

using Plots
```

---

## Understanding shared named environments

A **Shared Named Environment** in Julia (such as `@plotting` or `@data`) is an isolated package environment stored in `~/.julia/environments/`.

### Built-in vs. custom named environments
Out of the box, Julia includes the standard versioned global environment (e.g., `@v1.12`). All other named environments are custom namespaces created by the user or generated automatically by `QuickEnv`.

---

## Features

- **Import Parsing**: Reads the script on execution, identifying direct package dependencies (`using` and `import` statements) while ignoring comments and sub-imports.
- **Recursive Include Scanner**: Statically analyzes `include("path/to/file.jl")` calls to discover dependencies across included files.
- **Two-Tier Caching**: Caches script paths and modification times (`mtime`) in `~/.julia/quickenv/cache.toml` for O(1) lookups on subsequent runs.
- **Lazy Pkg Loading**: Uses Julia's internal `Base.set_active_project` for project switching during steady-state runs, avoiding the import cost of `Pkg`.
- **Bitmask Set-Cover & Manifest Stitching**: Determines minimal combinations of existing environments using bitmask operations, validates version compatibility in manifests, and creates combined `@auto_<hash>` environments.
- **Diagnostics & Typo Suggestions**: Identifies package casing discrepancies (e.g., `using cairo` -> `using Cairo`) and typos against the General Registry.
- **Self-Healing Invalidation**: Automatically clears cached script entries on unhandled exceptions via an `atexit` hook so subsequent runs re-evaluate dependencies.
- **Atomic Operations**: Employs PID-isolated temporary files and atomic POSIX replacement (`mv`) for cache and environment writes.

---

## Magic comments

QuickEnv supports configuration via inline or multiline comments.

### 1. Compact inline format
Options can be specified on the `using QuickEnv` line:

```julia
using QuickEnv # fallback: plotting, exclude: global, silent, create: data, desc: "Data analysis environment"
```

### 2. Standalone comment format
Options can also be declared on individual comment lines:

#### Forced environment creation (`QuickEnv.create`)
```julia
# QuickEnv.create: data
```

#### Fallback target (`quickenv_fallback`)
```julia
# quickenv_fallback: plotting
```

#### Custom environment description (`QuickEnv.desc` or `QuickEnv.description`)
```julia
# QuickEnv.desc: Environment with plotting and data tools
```

#### Excluded environments (`quickenv_exclude`)
```julia
# quickenv_exclude: global, broken_plotting
```
*`global` acts as a wildcard excluding standard versioned environments (e.g., `@v1.12`).*

#### Local directory environment (`# local` or `quickenv_local: true`)
Activates the script's directory as the project (equivalent to `julia --project=. script.jl`):
```julia
using QuickEnv # local
```

#### Verbose and Silent modes
- Default: Logs are output when creating environments or installing packages; steady-state matching runs quietly.
- Verbose mode:
  ```julia
  using QuickEnv # verbose
  ```
  or:
  ```bash
  export QUICKENV_VERBOSE=true
  ```
- Silent mode:
  ```julia
  using QuickEnv # silent
  ```
  or:
  ```bash
  export QUICKENV_SILENT=true
  ```

---

## Code examples

### Example A: Global environment isolation & plotting
Prevents running in the global environment and sets `@plotting` as the fallback:

```julia
#!/usr/bin/env julia
using QuickEnv # fallback: plotting, exclude: global

using Plots
using Cairo

function (@main)(args)
    gr()
    p = plot(1:10, rand(10), title="Isolated Plot")
    savefig(p, "output/plot.pdf")
    println("output/plot.pdf")
    return 0
end
```

### Example B: Dedicated named fallback & data setup
Requests `@data` as the fallback named environment:

```julia
#!/usr/bin/env julia
using QuickEnv # fallback: data, exclude: global

using DataFrames
using CSV

function (@main)(args)
    df = DataFrame(A = 1:5, B = rand(5))
    CSV.write("output/data.csv", df)
    println("output/data.csv")
    return 0
end
```

### Example C: Local files warning
When activating a shared named environment while local project files exist in the directory, QuickEnv displays an informational warning:

```julia
#!/usr/bin/env julia
using QuickEnv # fallback: plotting, exclude: global

using Plots

function (@main)(args)
    println("Running in @plotting...")
    return 0
end
```

---

## Technical architecture

QuickEnv uses an autonomous multi-stage resolution engine:
1. **O(1) Fast Script-Level Cache**: Checks file modification times (`mtime`) against `~/.julia/quickenv/cache.toml` to reuse known environments instantly.
2. **Bitmask Set-Cover Solver**: Maps dependencies to hardware bitmasks (`UInt64`) to find the minimal combination of existing named environments.
3. **Manifest Fast-Stitching (<5ms)**: Verifies transitive dependency compatibility and synthesizes compound `@auto_<hash>` environments on disk without running Pkg's SAT solver or recompiling packages.
4. **Autonomous Fallback**: Bootstraps dedicated `@auto_<hash>` environments via `Pkg.add` when new dependencies are introduced.

> For an in-depth explanation of fast stitching vs. runtime stacking (`LOAD_PATH`), bitmask scoring math, and caching internals, see **[docs/DESIGN.md](docs/DESIGN.md)**.

---

## Environment management with `jlenv`

QuickEnv includes an administrative dashboard utility at `tools/jlenv.jl` to inspect, clean, and manage shared named environments:

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

> For the full CLI command reference and shell setup guide, see **[docs/jlenv.md](docs/jlenv.md)**.

---

## Best practices & limitations

### 1. Interactive scripts vs. production packages
QuickEnv is designed for interactive exploration, data science workflows, standalone scripts, and computational tools. For production applications or published packages requiring strict long-term reproducibility, a committed `Manifest.toml` tracked in Git remains standard practice.

### 2. Static include scanning vs. dynamic includes
QuickEnv statically analyzes `include("path/to/file.jl")` calls before execution to discover dependencies across included files.
* **Limitation**: Dynamic include expressions (such as `include(joinpath(@__DIR__, ARGS[1]))`) cannot be evaluated prior to runtime.
* **Recommendation**: Declare dependencies at the top of the entry script, or use `using QuickEnv # local` for multi-file local project folders.

### 3. Submodule imports
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
