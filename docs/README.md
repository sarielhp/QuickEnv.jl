# QuickEnv.jl User Guide & Configuration Manual

`QuickEnv.jl` is a zero-configuration auto-bootstrapping utility that dynamically manages, matches, and activates Julia package environments. It brings a set-and-forget package management workflow to standalone `.jl` scripts.

> **Related Documentation**:
> - **[Architecture & Design Deep-Dive](DESIGN.md)**: Fast stitching vs. stacking, bitmask solver, caching internals.
> - **[Tradeoffs Analysis](tradeoffs.md)**: Pros vs. cons and startup performance comparison.
> - **[`jlenv` CLI Manual](jlenv.md)**: Command reference for environment inspection and housekeeping.

---

## Installation

Install `QuickEnv` once in your **global** Julia environment so it is accessible to all scripts:

```julia
using Pkg
Pkg.activate() # Activates global environment (e.g. @v1.12)
Pkg.add(url="https://github.com/sarielhp/QuickEnv.jl.git")
```

---

## Standard Zero-Configuration Usage

In standard usage, no configuration comments or command-line flags are required. Simply place `using QuickEnv` as the first import in your script:

```julia
#!/usr/bin/env julia
using QuickEnv
using Plots, DataFrames

function (@main)(args)
    # Your script code here...
    return 0
end
```

QuickEnv automatically inspects imports, finds or fast-stitches a matching named environment in `~/.julia/environments/`, installs any missing packages into isolated environments, and activates the project before your code runs.

---

## Optional Configuration: Magic Comments Reference

For power users who need fine-grained control over environment resolution, QuickEnv supports optional directives via inline or standalone comments. These comments are completely ignored by the standard Julia parser, making them 100% syntactically safe.

### 1. Compact Inline Format (Recommended)

Directives can be specified directly on the `using QuickEnv` line separated by commas:

```julia
using QuickEnv # fallback: plotting, exclude: global, silent, create: data, desc: "Data analysis environment"
```

---

### 2. Standalone Comment Directives

Directives can also be written on individual comment lines at the top of the file:

#### A. Forced Environment Creation (`create`)
Forces `QuickEnv` to use a specific named environment (e.g., `@science`). It creates `@science` if it does not exist and installs missing packages into it:
```julia
# QuickEnv.create: science
```
or inline:
```julia
using QuickEnv # create: science
```

#### B. Fallback Target Environment (`fallback`)
Searches existing named environments first. If no existing environment satisfies all imports, it creates and bootstraps the specified fallback named environment (e.g., `@plotting`) instead of an autonomous `@auto_<hash>` environment:
```julia
# quickenv_fallback: plotting
```
or inline:
```julia
using QuickEnv # fallback: plotting
```

#### C. Environment Description (`desc` / `description`)
Writes a human-readable description string into the target environment's `Project.toml`:
```julia
# QuickEnv.desc: Environment with plotting and data tools
```
or inline:
```julia
using QuickEnv # desc: "Data analysis tools"
```

#### D. Excluded Environments (`exclude`)
Prevents specific environments from being considered during matching. Using `global` acts as a wildcard excluding standard versioned environments (e.g., `@v1.12`):
```julia
# quickenv_exclude: global, broken_plotting
```
or inline:
```julia
using QuickEnv # exclude: global
```

#### E. Local Directory Project Mode (`# local`)
Directs QuickEnv to activate the script's local folder as the project (equivalent to `julia --project=. script.jl`):
```julia
using QuickEnv # local
```
or standalone:
```julia
# quickenv_local: true
```

#### F. Logging Verbosity (`verbose` / `silent`)
* **Default Mode**: Runs quietly when matching existing environments; prints informative notifications when creating new environments or installing packages.
* **Verbose Mode**: Prints detailed matching, candidate scoring, and timing details:
  ```julia
  using QuickEnv # verbose
  ```
  or environment variable:
  ```bash
  export QUICKENV_VERBOSE=true
  ```
* **Silent Mode**: Suppresses all non-error logging:
  ```julia
  using QuickEnv # silent
  ```
  or environment variable:
  ```bash
  export QUICKENV_SILENT=true
  ```

---

## Detailed Execution Lifecycle

When `using QuickEnv` runs in a script:
1. **Script Parsing**: Statically scans the top-level script (and statically included `.jl` files) for `using`/`import` statements and magic comments.
2. **Script-Level Cache Check ($O(1)$)**: Checks if the script path and modification timestamp (`mtime`) match a known valid environment in `~/.julia/quickenv/cache.toml`.
3. **Existing Environment Match**: Checks if any single named environment in `~/.julia/environments/` satisfies all requested packages.
4. **Bitmask Set-Cover & Fast Manifest Stitching (<5ms)**: Finds minimal compatible combinations of existing environments and synthesizes a merged `Project.toml` and `Manifest.toml` into `@auto_<hash>` without Pkg SAT solving or recompilation.
5. **Partial Stitching & Incremental Bootstrap**: Pre-stitches known package manifests and runs `Pkg.add` only for new missing dependencies.
6. **Project Activation**: Activates the resolved project via Julia's internal `Base.set_active_project`.
