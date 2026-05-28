# QuickEnv.jl

[![Build Status](https://github.com/yourusername/QuickEnv.jl/workflows/CI/badge.svg)](https://github.com/yourusername/QuickEnv.jl/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Julia Version](https://img.shields.io/badge/julia-v1.6+-8A2BE2.svg)](https://julialang.org/)

`QuickEnv.jl` is a zero-configuration, auto-bootstrapping environment manager for Julia scripts. It automates package management for standard standalone `.jl` scripts, dynamically resolving and isolating dependencies without directory clutter or manual project initialization.

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

Now, just run it. After installing `QuickEnv` once in your global environment, it automatically resolves and installs any missing packages in the local environment. Subsequent runs execute quickly once the environment is set up.

There is an important exception to the above behavior: If QuickEnv finds any existing [named environment](#-understanding-shared-named-environments) satisfying your imports (e.g. `@plotting`), it uses it instead. That creates a convenient way to have several default environments that would fit many Julia programs.



## 📖 More on the problem and the solution

Julia developers typically manage package environments in three ways, each with distinct trade-offs:

1. **The Global Environment (`@v1.x`)**: Easy to use, but eventually leads to version conflict deadlocks ("Dependency Hell") as different packages declare conflicting version constraints.

2. **Local Directory Projects (`--project=.`)**: Reproducible, but creates directory clutter and repetitive setup overhead for single-file scripts or quick calculations. Furthermore, it results in additional disk space usage and compile-time overhead due to redundant package downloads and precompilations.

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

To understand their role, it is helpful to compare the three package management paradigms in Julia:

### 1. The global environment (`@v1.x`)
- **How it works**: By default, if you run Julia without specifying a project directory, packages are installed in the global scope.

- **The Problem**: Installing all packages globally eventually leads to **"Dependency Hell"**—conflicts where one package requires `DataFrames v0.22` while another requires `DataFrames v1.0`. The package manager will lock up and refuse to install or update packages.

### 2. Local directory projects (`--project=.`)
- **How it works**: Tracks package dependencies inside a specific project folder using `Project.toml` and `Manifest.toml` files.
- **The Problem**: While ideal for shared repositories, it creates directory clutter and disk/compilation overhead for one-off calculations or single scripts. You are forced to create a new folder and compile packages redundantly for each script.

### 3. Shared named environments (the hybrid solution)
- **How it works**: You group related packages into named, globally accessible scopes (like `@plotting` for graphics, or `@data` for data handling).
- **The Benefit**: They offer a compromise:
  - **No Conflict**: Keeps your global scope clean, avoiding dependency deadlocks.
  - **No Clutter**: No need to create folders or project files for standalone scripts.
  - **Instant Load**: Since packages are resolved once in the shared named environment, your scripts compile and load quickly on subsequent runs.
- **The Problem**: To run a script inside a shared named environment, you must manually remember its name and explicitly pass it on the command line every single time (e.g., `julia --project=@plotting script.jl`). If you forget to include the flag, the script runs in the wrong environment (usually the global scope).

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
You can declare fallback named environments, exclusions, silent flags, forced environment creation, and descriptions (using either `desc` or `description`) all on the same line as your import:

```julia
using QuickEnv # fallback: plotting, exclude: global, silent, create: data, desc: "Data science environment with Plots.jl"
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

#### 3. Custom environment description (`QuickEnv.desc` or `QuickEnv.description`)
Sets or updates the custom description for the activated environment's `Project.toml` (which will be displayed in `jlenv list`):
```julia
# QuickEnv.desc: Custom environment with plotting packages and utility helpers
```

#### 4. Forbidden environments (`quickenv_exclude`)
```julia
# quickenv_exclude: global, broken_plotting, experimental_ml
```
*Note: The keyword `global` acts as a wildcard excluding standard versioned global environments (e.g., `@v1.12`).*

#### 5. Silent execution (`quickenv_silent` or `QUICKENV_SILENT` environment variable)
You can suppress all `QuickEnv` and `Pkg` environment activation logs during load time either by using a magic comment:
```julia
# quickenv_silent: true
```
Or by setting the system environment variable globally in your shell:
```bash
export QUICKENV_SILENT=true
```

---

## 💻 Code examples

### Example A: Global environment isolation & plotting (unified inline format)
This script prevents itself from running in the global environment, sets `@plotting` as the fallback environment, and executes silently:

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
This script requests a dedicated named environment `@data`. If no environment currently contains both `DataFrames` and `CSV`, it will automatically create `@data`, download/compile the packages, and run silently:

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

### Example C: Named environment with local files warning (non-silent mode)
This script requests the custom named environment `@plotting` without specifying the `silent` flag. If a local `Project.toml` or `Manifest.toml` exists in the script's directory, `QuickEnv` will alert you with a warning that the local directory configuration is being ignored in favor of the shared named environment:

```julia
#!/usr/bin/env julia
using QuickEnv # fallback: plotting, exclude: global

using Plots

function (@main)(args)
    println("Running script in named environment @plotting...")
    return 0
end
```

*Output (if local `Project.toml` exists in the script directory)*:
```log
┌ Warning: QuickEnv: Local Project.toml or Manifest.toml exists in the script's directory, but is being ignored because named environment @plotting is activated. QuickEnv tip... To silence this msg add magic comment: 'using QuickEnv  # silent'
└ @ QuickEnv ~/.julia/packages/QuickEnv/.../QuickEnv.jl
Running script in named environment @plotting...
```

---

## ⚙️ Technical architecture and specifications

### 1. Script parsing logic
`QuickEnv.jl` reads the running script line-by-line before other packages load. It uses a regex parser that:
- Removes trailing or inline comments to prevent incorrect parsing.
- Handles Julia's standard colon import syntax (`using Module: item1, item2`). By splitting on the first colon (`:`), it correctly identifies `Module` as the package dependency and ignores the imported sub-items (e.g., types or functions starting with an uppercase letter).
- Extracts aliases correctly (e.g., `import Package as PkgAlias`).

### 2. Environment matching & filtering
- Scans `DEPOT_PATH[1]/environments/` for active subdirectories containing a `Project.toml` file.
- Reads `deps` maps to locate satisfying package lists.
- Filters matches using the `quickenv_exclude` lists and automatically strips standard versioned environments if an explicit `quickenv_fallback` is provided.
- Prioritizes custom user-named environments over global ones to ensure structural isolation.

### 3. Bootstrap activation
- Calls `Pkg.activate(env, shared=true)` dynamically inside the session's precompilation initialization (`__init__()`).
- Dynamically updates Julia's internal `LOAD_PATH` on the fly.
- Inspects the active project's dependencies, identifies missing packages, and triggers programmatic headless installation (`Pkg.add`).

---

## 📂 Reference examples

You can find the runnable scripts in the [examples/](examples/) directory:

- [example_plotting.jl](examples/example_plotting.jl): Demonstrates plotting using the `@plotting` named environment. Uses the `gr()` backend and Cairo to export a PDF plot to `output/plot.pdf`.
- [example_data.jl](examples/example_data.jl): Demonstrates data handling using the `@data` named environment. Automatically creates the environment and silently installs `DataFrames.jl` and `CSV.jl` to write to `output/data.csv`.
- [example_science.jl](examples/example_science.jl): Demonstrates forced environment creation using the `# create: science` magic comment. Automatically installs `SpecialFunctions.jl` and `LsqFit.jl` to perform a non-linear curve fit and export the result to `output/science_plot.pdf`.
- [example_warning.jl](examples/example_warning.jl): Demonstrates the ignored local files warning interactively by automatically creating and cleaning up a dummy local Project.toml.

---

## 🧪 Testing

To run the test suite and verify metadata parsing, environment matching, and filtering logic:

```bash
julia --project=QuickEnv QuickEnv/test/runtests.jl
```

---

## 🤝 Contributing

Contributions, bug reports, and pull requests are welcome.
1. Fork this repository.
2. Create your feature branch (`git checkout -b feature/NewFeature`).
3. Commit your changes (`git commit -m 'Add some NewFeature'`).
4. Push to the branch (`git push origin feature/NewFeature`).
5. Open a Pull Request.

---

## 🛠️ The `jlenv.jl` CLI Tool

To make managing your custom named environments and scripts effortless, `QuickEnv` includes a colorful, standalone command-line tool located under `tools/jlenv.jl`. 

### Key Features

* **Environment Directory Listing (`list`)**: Displays all your named environments along with custom description headers.
* **Environment Inspection (`show`)**: Shows all registered packages and direct dependencies for a specified environment.
* **Automatic Creation (`create`)**: Automatically scans a standalone Julia script for imported packages, creates a new named environment, and installs all the dependencies.
* **Smart Matching & Running (`match` / `mrun`)**: Finds existing custom environments satisfying a script's dependencies, or directly executes the script inside a matching environment.
* **General Registry Search (`search`)**: Fast, in-process search of the official Julia General Registry for any package query.

### Usage and Subcommands

```bash
# List all environments and descriptions
./tools/jlenv.jl list

# Show registered packages in an environment
./tools/jlenv.jl show @plotting

# Add packages to an environment
./tools/jlenv.jl add @plotting DataStructures DataFrames

# Add/change the description of an environment
./tools/jlenv.jl describe @plotting "Plotting environment with Plots.jl and Cairo"

# Create an environment from a Julia script
./tools/jlenv.jl create @math_env solve_inequality.jl

# Find environments that can run a script
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

Like other standalone scripts managed by `QuickEnv.jl`, the CLI tool automatically bootstraps its own dependencies (such as `Crayons.jl` for beautiful, terminal-independent coloring) on its first run under zero-configuration named environment isolation.

---

## Disclaimer

Most the package was written using antigravity-cli. However, I (a real
human) reviewed the code and it seems OK to me. This is hopefully a
useful package and not just AI generated junk. I would of course
handle any bugs/issues.


## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.
