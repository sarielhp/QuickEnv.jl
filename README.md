# QuickEnv.jl

[![Build Status](https://github.com/yourusername/QuickEnv.jl/workflows/CI/badge.svg)](https://github.com/yourusername/QuickEnv.jl/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Julia Version](https://img.shields.io/badge/julia-v1.6+-8A2BE2.svg)](https://julialang.org/)

`QuickEnv.jl` is a zero-configuration, auto-bootstrapping environment
manager for Julia scripts. It brings Pluto-like automated package
management elegance to standard standalone `.jl` scripts, dynamically
resolving and isolating dependencies without directory clutter or
manual project initialization.

---

## ⚡ Quick start:  Write the Julia program, run the Julia program

The problem is that when you run a Julia program you have to worry
about the Julia environment the program is run in. This package solves
this problem by automatically creating a local environment, installing
missing packages, and running the program in this environment. 

### The default behavior: Zero configuration 
Add QuickEnv as the first package used by your program. When the Julia
program executes it automatically activates the script's local
directory and installs all missing packages to the local environment
(i.e., bootstrapping missing packages), and then goes on to run the
program:

```julia
#!/usr/bin/env julia
using QuickEnv
using Plots

# the rest of the program ...

```

Now, just run it! Everything would just work (after installing
QuickEnv in your global environment one time [sorry]). QuickEnv would
take care of making things work by installing the missing packages in
the local environment, etc. Running the program for the second time
once the environment is setup, is well, quick.

There is an important exception to the above behavior: If QuickEnv finds any existing [named environment](#-understanding-shared-named-environments) satisfying your imports (e.g. `@plotting`), it uses it instead. That creates a convenient way to have several default environments that would fit many Julia programs.



## 📖 More on the problem and the solution

Julia developers typically manage package environments in three ways, each with distinct trade-offs:

1. **The Global Environment (`@v1.x`)**: Easy to use, but eventually leads to version conflict deadlocks ("Dependency Hell") as different packages declare conflicting version constraints.

2. **Local Directory Projects (`--project=.`)**: Highly reproducible,
   but creates massive file clutter and repetitive setup overhead for
   single-file scripts or quick calculations. Furthermore, it results
   in huge disk footprint and compile-time bloat due to redundant
   package downloads and precompilations.

3. **Shared Named Environments (`@plotting`, `@data`)**: The hybrid solution. Grouping related workflows into shared, globally accessible environments.

**QuickEnv.jl is an automation layer on top of named and local environments.**

When you place `using QuickEnv` at the top of a script, it scans your code imports on-the-fly and automatically resolves them:
- **First Choice**: Finds and activates an existing global **named environment** that already satisfies your script's imports (saving disk space and compile time).
- **Fallback (Explicit)**: Creates and activates a specified named environment (e.g. `@plotting`) and auto-installs missing packages.
- **Fallback (Default)**: Automatically isolates the script into its **local directory**, creates a clean local project, downloads dependencies, and runs the script in it.

---

## Slow start

Get started by simply placing `using QuickEnv` at the top of your scripts. You can run in zero-configuration mode, force a specific [named environment](#-understanding-shared-named-environments) to be created and managed, or specify a [named environment](#-understanding-shared-named-environments) fallback.

### 1. Forced named environment creation (`create`)
Forces `QuickEnv` to use the `@science` [named environment](#-understanding-shared-named-environments). It creates `@science` if it's missing, and automatically installs the required package dependencies:

```julia
#!/usr/bin/env julia
using QuickEnv # create: science

using LsqFit
```

### 2. Explicit named environment fallback (`fallback`)

Searches your existing custom [named environments](#-understanding-shared-named-environments) for a match first. If no matching environment satisfies your dependencies, it falls back to creating and bootstrapping the 
[named environment](#-understanding-shared-named-environments) (in this specific case  `@plotting`):

```julia
#!/usr/bin/env julia
using QuickEnv # fallback: plotting

using Plots
```

---

## 🧠 Understanding shared named environments

A **Shared Named Environment** in Julia (such as say `@plotting` or
say `@data` [these do not exist by default - you have to create them]) is a globally
accessible, isolated package environment stored in your home directory
under `~/.julia/environments/`.

### Are there default named environments in Julia?
No. Out of the box, Julia does not ship with any pre-made named environments (like `@plotting` or `@data`). Those are completely custom namespaces.

The only built-in shared environment provided by Julia is the standard versioned global environment (e.g., `@v1.12` or `@v1.10`), which is activated by default when starting Julia without a project directory. Any other named environment must be created by you (or automatically bootstrapped by `QuickEnv.jl` on demand).

To understand why they are highly useful, it is helpful to compare the
three package management paradigms in Julia:

### 1. The global environment (`@v1.x`)
- **How it works**: By default, if you run Julia without specifying a project directory, packages are installed in the global scope.

- **The Problem**: Installing all packages globally eventually leads to **"Dependency Hell"**—conflicts where one package requires `DataFrames v0.22` while another requires `DataFrames v1.0`. The package manager will lock up and refuse to install or update packages.

### 2. Local directory projects (`--project=.`)
- **How it works**: Tracks package dependencies inside a specific project folder using `Project.toml` and `Manifest.toml` files.
- **The Problem**: While ideal for shared repositories, it creates **directory clutter** and **massive disk/compilation overhead** for one-off calculations or single scripts. You are forced to create a new folder and wait for packages to compile redundantly for every script.

### 3. Shared named environments (the hybrid solution)
- **How it works**: You group related packages into named, globally accessible scopes (like `@plotting` for graphics, or `@data` for data handling).
- **The Benefit**: They are the perfect compromise. 
  - **No Conflict**: Keeps your global scope clean, avoiding dependency deadlocks.
  - **No Clutter**: No need to create folders or project files for every standalone script.
  - **Instant Load**: Since packages are resolved once in the shared named environment, your scripts **compile and load instantly** on subsequent runs.

---

## 🚀 Key features

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

## 🛠️ Declarative magic comments

`QuickEnv.jl` supports declarative magic comments to customize loading behaviors. These can be defined in two formats:

1. **Compact Inline Format (Recommended)**: Declared entirely on the `using QuickEnv` import line.
2. **Standalone Multiline Format**: Declared as separate comments at the top of the file.

### A. Compact inline format (recommended)
You can declare fallback named environments, exclusions, quiet flags, and forced environment creation all on the same line as your import:

```julia
using QuickEnv # fallback: plotting, exclude: global, silent, create: data
```

### B. Standalone multiline format
You can also declare these options on individual lines before the package loads:

#### 1. Forced environment creation (`QuickEnv.create`)
Forces `QuickEnv` to use and manage a specific named environment. 
```julia
# QuickEnv.create: data
```
*Behavior*:
- If `@data` exists and already contains all required packages, `QuickEnv` simply activates and runs in it (respecting silent mode if requested).
- If `@data` is missing or lacks any required packages, **silent mode is temporarily disabled**, a detailed description of the modifications is printed, and `Pkg.add` executes to install the missing dependencies automatically.

#### 2. Fallback target (`quickenv_fallback`)
```julia
# quickenv_fallback: plotting
```
*If `@plotting` does not exist or lacks the required packages, `QuickEnv` will create `@plotting` and run `Pkg.add` to resolve all missing dependencies automatically.*

#### 3. Forbidden environments (`quickenv_exclude`)
```julia
# quickenv_exclude: global, broken_plotting, experimental_ml
```
*Note: The keyword `global` acts as a wildcard excluding standard versioned global environments (e.g., `@v1.12`).*

#### 3. Silent execution (`quickenv_silent`)
```julia
# quickenv_silent: true
```
*Completely suppresses all `QuickEnv` and `Pkg` environment activation logs during load time.*

---

## 💻 Code examples

### Example A: Global environment isolation & plotting (unified inline format)
This script prevents itself from running in the global environment, sets `@plotting` as the fallback environment, and executes completely silently:

```julia
#!/usr/bin/env julia
using QuickEnv # fallback: plotting, exclude: global, silent

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

### Example B: Dedicated named fallback & data setup (unified inline format)
This script requests a dedicated named environment `@data`. If no environment currently contains both `DataFrames` and `CSV`, it will automatically create `@data`, download/compile the packages, and run completely silently:

```julia
#!/usr/bin/env julia
using QuickEnv # fallback: data, exclude: global, silent

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

## ⚙️ Technical architecture and specifications

### 1. Script parsing logic
`QuickEnv.jl` reads the running script line-by-line before other packages load. It uses a clean and exact regex parser that:
- Removes trailing or inline comments to prevent false parsing.
- Handles Julia's standard colon import syntax (`using Module: item1, item2`). By splitting on the first colon (`:`), it correctly identifies `Module` as the package dependency and ignores the imported sub-items (e.g., types or functions starting with an uppercase letter).
- Extracts aliases correctly (e.g., `import Package as PkgAlias`).

### 2. Environment matching & filtering
- Scans `DEPOT_PATH[1]/environments/` for active subdirectories containing a `Project.toml` file.
- Reads `deps` maps to locate satisfying package lists.
- Filters matches using the `quickenv_exclude` lists and automatically strips standard versioned environments if an explicit `quickenv_fallback` is provided.
- Prioritizes custom user-named environments over global ones to ensure high structural isolation.

### 3. Bootstrap activation
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
2. Create your feature branch (`git checkout -b feature/NewFeature`).
3. Commit your changes (`git commit -m 'Add some NewFeature'`).
4. Push to the branch (`git push origin feature/NewFeature`).
5. Open a Pull Request.

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.
