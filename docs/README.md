# QuickEnv.jl User Guide

`QuickEnv.jl` is a zero-configuration auto-bootstrapping utility package that dynamically manages, matches, and activates Julia environments. It is designed to bring Pluto-like automatic package management elegance to standard standalone `.jl` scripts.

> **Related Documentation**:
> - **[Architecture & Design Deep-Dive](DESIGN.md)**: Fast stitching vs. stacking, bitmask solver, caching internals.
> - **[Tradeoffs Analysis](tradeoffs.md)**: Pros vs. cons and startup performance comparison.
> - **[`jlenv` CLI Manual](jlenv.md)**: Command reference for environment inspection and housekeeping.

---

## Features

- **Automated Named Environment Matching**: Scans your running script for `using`/`import` statements and matches them against existing named environments globally (under `~/.julia/environments/`).
- **Disk-Space & Compile Time Saving**: Reuses globally compiled packages rather than forcing package reinstalls/compilations inside local directories for every quick script.
- **Fast Compound Stitching & Bitmask Set-Cover**: Autonomously discovers minimal combinations of environments covering dependencies and stitches them into `@auto_<hash>` in <5ms without recompilation.
- **State-Aware & Script-Level Caching**: O(1) cache lookup based on script modification times (`mtime`) and dependency hashes in `~/.julia/quickenv/cache.toml`.
- **Smart Typo & Casing Diagnostics**: Checks unregistered imports against local environments, stdlibs, and the General Registry to suggest fixes (e.g. `using cairo` -> `using Cairo`).
- **Forced Environment Management (`QuickEnv.create`)**: Forces `QuickEnv` to use and manage a specific named environment, automatically creating it or adding missing dependencies.
- **Custom Environment Descriptions**: Easily set or update environment descriptions via `desc: "..."` or `# QuickEnv.desc: ...`.
- **Dynamic Fallbacks**: Supports explicitly declaring a fallback environment to compile inside if no current environments satisfy the script's imports.
- **Automatic Bootstrapping**: If no matching named environments exist, it creates an autonomous `@auto_<hash>` environment (or fallback named environment) and installs missing package dependencies using `Pkg.add`.
- **Exclusion Filters**: Supports custom comments to restrict specific environments or standard global ones from being used.
- **Silent & Verbose Modes**: Silent by default on matching runs; configure logging level via `# silent` or `# verbose`.

---

## Installation

Add `QuickEnv` to your **global** Julia environment so it can be loaded from any script:

```julia
using Pkg
Pkg.activate() # Activates global env (e.g. @v1.12)
Pkg.add(url="https://github.com/sarielhp/QuickEnv.jl.git")
```

---

## Magic Comments Syntax

You can configure `QuickEnv` directly inside the comments of your Julia script. These comments are completely ignored by the standard Julia parser, making them 100% syntactically safe and standard.

### 1. Compact Inline Format (Recommended)
You can declare fallback named environments, exclusions, descriptions, verbosity flags, and forced environment creation all on the same line as your import:

```julia
using QuickEnv # fallback: plotting, exclude: global, silent, create: data, desc: "Data analysis environment"
```

### 2. Standalone Multiline Format
You can also declare these options on individual lines before the package loads:

- **Forced environment**: `# QuickEnv.create: data`
- **Fallback target**: `# quickenv_fallback: plotting`
- **Exclusions**: `# quickenv_exclude: global, broken_plotting`
- **Environment description**: `# QuickEnv.desc: Data analysis tools`
- **Local directory mode**: `using QuickEnv # local`
- **Silent Mode**: `# quickenv_silent: true` or `# silent`
- **Verbose Mode**: `# quickenv_verbose: true` or `# verbose`

*Note on `QuickEnv.create` behavior: If the target environment already satisfies all dependencies, it runs silently (if requested). If any packages are missing and need to be installed, a description of the setup is printed before `Pkg` modifies the environment.*

---

## Usage Example

Simply place `using QuickEnv` at the very beginning of your Julia scripts:

```julia
using QuickEnv # fallback: plotting, exclude: global

using Plots
using Cairo

function (@main)(args)
    # Your script code here...
    return 0
end
```

### How it executes under the hood:
1. `using QuickEnv` runs.
2. `QuickEnv`'s `__init__()` scans the script for imported packages (`Plots` and `Cairo`), the fallback request (`plotting`), and the exclusion rules (`global` is excluded).
3. It finds or fast-stitches a matching named environment (e.g., `@plotting` or `@auto_<hash>`) and dynamically updates Julia's active project.
4. Subsequent lines like `using Plots` load instantly using the activated environment.
5. If no matching environment existed, it automatically bootstraps `@plotting` and installs `Plots` and `Cairo` before executing the rest of the script.
