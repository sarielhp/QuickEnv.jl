# QuickEnv.jl

[![Build Status](https://github.com/sarielhp/QuickEnv.jl/workflows/CI/badge.svg)](https://github.com/sarielhp/QuickEnv.jl/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Julia Version](https://img.shields.io/badge/julia-v1.6+-8A2BE2.svg)](https://julialang.org/)

`QuickEnv.jl` automatically handles all the environment setup required to run your Julia scripts.

After installing `QuickEnv` once in your global environment, simply add `using QuickEnv` to the top of your file. From that point on, execution is completely seamless: QuickEnv inspects your script's imports, finds or creates a matching environment, installs any missing packages, and activates everything transparently before your code runs.

Just execute your script—QuickEnv takes care of the setup behind the scenes, eliminating the usual environment tedium in Julia.

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
- If no existing environment matches, QuickEnv creates a dedicated named environment (`@auto_<hash>`), installs any missing packages via `Pkg.add`, and activates it.
- Everything runs transparently, and subsequent runs reuse cached resolution for near-zero startup overhead.

---

## Problem and approach

Julia package environments typically follow one of three approaches:

1. **Global Environment (`@v1.x`)**: Straightforward to use initially, but can lead to version conflicts across unrelated scripts over time.
2. **Local Directory Projects (`--project=.`)**: Provides project isolation, but creates local `Project.toml` and `Manifest.toml` files for one-off scripts and duplicates package downloads and precompilations.
3. **Shared Named Environments (`@plotting`, `@data`)**: Stores reusable environments under `~/.julia/environments/`, but requires manually passing `--project=@env` flags on every run.

**QuickEnv automates named and local environment selection:**

- **First Choice**: Finds and activates an existing global **named environment** that satisfies the script's imports.
- **Compound Stitching**: If multiple environments together cover all dependencies (e.g. `@plotting` + `@data`), QuickEnv validates their manifest compatibility and stitches them into a combined `@auto_<hash>` environment without recompilation.
- **Fallback (Explicit)**: Creates and activates a specified named environment (e.g. `@plotting`) and installs missing packages.
- **Fallback (Default)**: Creates an autonomous named environment (`@auto_<hash>`) in `~/.julia/environments/` and installs dependencies.
- **Local Project Mode**: Can be directed via `# local` to activate the script's local folder as a standard project.

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

## Installation

Install `QuickEnv` in your **global** Julia environment:

```julia
using Pkg
Pkg.activate()  # Activate standard global environment (e.g., @v1.12)
Pkg.add(url="https://github.com/sarielhp/QuickEnv.jl.git")
```

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

### 1. Script parsing
QuickEnv scans the script line-by-line prior to package loading:
- Strips comments.
- Handles colon syntax (`using Module: symbol1, symbol2`), extracting `Module`.
- Extracts root packages from submodule imports (`using HTTP.WebSockets` -> `HTTP`).
- Recursively parses local `include("...")` calls.

### 2. Environment matching & filtering
- Scans `DEPOT_PATH[1]/environments/` for directories containing `Project.toml`.
- Reads dependency maps from project files.
- Filters out environments matching exclusion patterns.
- Evaluates candidate subsets using bitmask set-cover.

### 3. Manifest compatibility and stitching
- Parses `Manifest.toml` files of candidate environments.
- Checks that shared direct and transitive dependencies share identical UUIDs, versions, and git tree hashes.
- Writes combined `Project.toml` and `Manifest.toml` files into `~/.julia/environments/@auto_<hash>`.

---

## The `jlenv.jl` CLI tool

A management script is included at `tools/jlenv.jl`.

### Commands

```bash
# List all environments and descriptions
./tools/jlenv.jl list

# Check compatibility between environments
./tools/jlenv.jl check-compat @plotting @data

# Merge multiple environments into a new named environment
./tools/jlenv.jl merge @plotting_data @plotting @data

# View resolution cache
./tools/jlenv.jl cache list

# Show registered packages in an environment
./tools/jlenv.jl show @plotting

# Add packages to an environment
./tools/jlenv.jl add @plotting DataStructures DataFrames

# Set or update environment description
./tools/jlenv.jl describe @plotting "Plotting environment with Plots.jl and Cairo"

# Create an environment from a Julia script
./tools/jlenv.jl create @math_env solve_inequality.jl

# Find environments that satisfy a script
./tools/jlenv.jl match plot_inequality.jl

# Run a Julia script in a matching named environment
./tools/jlenv.jl mrun plot_inequality.jl

# Run a Julia script in a specified named environment
./tools/jlenv.jl run @plotting plot_inequality.jl

# Launch Julia REPL in a named environment
./tools/jlenv.jl repl @plotting

# Delete a named environment
./tools/jlenv.jl rm @test_env

# Search General Registry for a package
./tools/jlenv.jl search DataStructures
```

---

## Design considerations, best practices & limitations

### 1. Exploration vs. production
QuickEnv is intended for interactive exploration, data workflows, standalone tools, and script execution. For production systems or published packages requiring strict reproducibility, a committed `Manifest.toml` tracked in Git remains standard practice.

### 2. Static include scanning vs. dynamic includes
QuickEnv statically parses entry scripts and follows static `include("path/to/file.jl")` calls.
- **Limitation**: Dynamic include expressions (such as `include(joinpath(@__DIR__, ARGS[1]))`) cannot be evaluated before runtime.
- **Recommendation**: Declare package dependencies at the top of the entry script, or use `using QuickEnv # local` for multi-file local project directories.

### 3. Nested package imports
Submodule imports (such as `using HTTP.WebSockets` or `import DataFrames.DataFrame`) are automatically parsed and mapped to the parent registered package (`HTTP`, `DataFrames`).

### 4. Failure handling & concurrency
- **Self-Healing Cache**: If a script exits with an unhandled exception, QuickEnv invalidates the script's cache entry, prompting a full re-resolution on the next run.
- **Atomic Writes**: Cache updates and compound environment files are written to PID-isolated temporary files before atomic replacement (`mv`), avoiding partial writes during concurrent script execution.

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
