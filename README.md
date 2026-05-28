# QuickEnv.jl

[![Build Status](https://github.com/yourusername/QuickEnv.jl/workflows/CI/badge.svg)](https://github.com/yourusername/QuickEnv.jl/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Julia Version](https://img.shields.io/badge/julia-v1.6+-8A2BE2.svg)](https://julialang.org/)

`QuickEnv.jl` is a zero-configuration, auto-bootstrapping environment manager for Julia scripts. It brings Pluto-like automated package management elegance to standard standalone `.jl` scripts, dynamically resolving and isolating dependencies without directory clutter or manual project initialization.

---

## 📖 The Problem and the Solution

Julia developers typically manage package environments in three ways, each with distinct trade-offs:

1. **The Global Environment (`@v1.x`)**: Easy to use, but eventually leads to version conflict deadlocks ("Dependency Hell") as different packages declare conflicting version constraints.
2. **Local Directory Projects (`--project=.`)**: Highly reproducible, but creates massive file clutter and repetitive setup overhead for single-file scripts or quick calculations. Furthermore, it results in huge disk footprint and compile-time bloat due to redundant package downloads and precompilations.
3. **Shared Named Environments (`@plotting`, `@data`)**: The hybrid solution. Grouping related workflows into shared, globally accessible environments.

**QuickEnv.jl is the ultimate automation layer on top of named and local environments.**

When you place `using QuickEnv` at the top of a script, it scans your code imports on-the-fly and automatically resolves them:
- **First Choice**: Finds and activates an existing global **named environment** that already satisfies your script's imports (saving disk space and compile time).
- **Fallback (Explicit)**: Creates and activates a specified named environment (e.g. `@plotting`) and auto-installs missing packages.
- **Fallback (Default)**: Automatically isolates the script into its **local directory**, creates a clean local project, downloads dependencies, and runs the script in it.

---

## 🚀 Key Features

- **Implicit Code Parsing**: Reads your script on load, identifying exact imported packages (`using` and `import` statements), while ignoring comments and sub-imports.
- **Zero-Config Matching**: Scans named global environments (located in `~/.julia/environments/`) and activates the first matching environment in milliseconds.
- **Auto-Bootstrapping**: If no matching named environment exists, it automatically executes a headless installation (`Pkg.add`) of missing packages in the local directory or fallback named environment.
- **Declarative Magic Comments**: Allows configure-by-comment rules directly in the file (e.g., fallback targets, environment exclusions) without syntactically altering standard Julia parsing.
- **Low-Overhead**: Built exclusively on Julia's standard libraries (`Pkg` and `TOML`). Compiles and runs in under 10ms.

---

## 📦 Installation

To make `QuickEnv` accessible to any script on your machine, install it in your **global** Julia environment:

```julia
using Pkg
Pkg.activate()  # Activate standard global environment (e.g., @v1.12)
Pkg.add(url="https://github.com/yourusername/QuickEnv.jl.git")
```

---

## 🛠️ Declarative Magic Comments

`QuickEnv.jl` supports magic comments at the top of your scripts. These comments are treated as standard comments by Julia but parsed as declarative metadata by `QuickEnv.jl`.

### 1. Fallback Target (`quickenv_fallback`)
Specify a named environment to activate and bootstrap if no existing environments satisfy the package requirements:

```julia
# quickenv_fallback: plotting
```
*If `@plotting` does not exist or lacks the required packages, `QuickEnv` will create `@plotting` and run `Pkg.add` to resolve all missing dependencies automatically.*

### 2. Forbidden Environments (`quickenv_exclude`)
Exclude specific environments (such as a dirty global scope or broken experimental environments) from being matched:

```julia
# quickenv_exclude: global, broken_plotting, experimental_ml
```
*Note: The keyword `global` acts as a wildcard excluding standard versioned global environments (e.g., `@v1.12`).*

---

## 💻 Code Examples

### Example A: Global Environment Isolation (Bypassing Global Scope)
This script prevents itself from running in the global environment. If no custom named environment matches, it automatically isolates and compiles in the script's local directory:

```julia
#! /bin/env julial
# quickenv_exclude: global

using QuickEnv
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

### Example B: Dedicated Named Fallback
This script requests a dedicated named environment `@data`. If no environment currently contains both `DataFrames` and `CSV`, it will automatically create `@data`, download/compile the packages, and run:

```julia
#! /bin/env julial
# quickenv_fallback: data
# quickenv_exclude: global

using QuickEnv
using DataFrames
using CSV

function (@main)(args)
    df = DataFrame(A = 1:5, B = rand(5))
    CSV.write("output/data.csv", df)
    println("output/data.csv")
    return 0
end
```

---

## ⚙️ Technical Architecture and Specifications

### 1. Script Parsing Logic
`QuickEnv.jl` reads the running script line-by-line before other packages load. It uses an incredibly clean and exact regex parser that:
- Removes trailing or inline comments to prevent false parsing.
- Handles Julia's standard colon import syntax (`using Module: item1, item2`). By splitting on the first colon (`:`), it correctly identifies `Module` as the package dependency and ignores the imported sub-items (e.g., types or functions starting with an uppercase letter).
- Extracts aliases correctly (e.g., `import Package as PkgAlias`).

### 2. Environment Matching & Filtering
- Scans `DEPOT_PATH[1]/environments/` for active subdirectories containing a `Project.toml` file.
- Reads `deps` maps to locate satisfying package lists.
- Filters matches using the `quickenv_exclude` lists and automatically strips standard versioned environments if an explicit `quickenv_fallback` is provided.
- Prioritizes custom user-named environments over global ones to ensure high structural isolation.

### 3. Bootstrap Activation
- Calls `Pkg.activate(env, shared=true)` dynamically inside the session's precompilation initialization (`__init__()`).
- Dynamically updates Julia's internal `LOAD_PATH` on the fly.
- Inspects the active project's dependencies, identifies missing packages, and triggers programmatic headless installation (`Pkg.add`).

---

## 🧪 Testing

To run the full test suite and verify metadata parsing, environment matching, and filtering logic:

```bash
julia --project=QuickEnv QuickEnv/test/runtests.jl
```

---

## 🤝 Contributing

Contributions, bug reports, and pull requests are highly welcome!
1. Fork this repository.
2. Create your feature branch (`git checkout -b feature/AmazingFeature`).
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.
