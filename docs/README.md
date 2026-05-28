# QuickEnv.jl

`QuickEnv.jl` is a zero-configuration auto-bootstrapping utility package that dynamically manages, matches, and activates Julia environments. It is designed to bring Pluto-like automatic package management elegance to standard standalone `.jl` scripts.

---

## Features

- **Automated Named Environment Matching**: Scans your running script for `using`/`import` statements and matches them against existing named environments globally (under `~/.julia/environments/`).
- **Disk-Space & Compile Time Saving**: Reuses globally compiled packages rather than forcing package reinstalls/compilations inside local directories for every quick script.
- **Dynamic Fallbacks**: Supports explicitly declaring a fallback environment to compile inside if no current environments satisfy the script's imports.
- **Automatic Bootstrapping**: If no matching named environments exist, it creates a local project environment in the script's folder (or fallback named environment) and automatically installs all missing package dependencies using `Pkg.add`.
- **Exclusion Filters**: Supports custom comments to restrict specific environments or standard global ones from being used.

---

## Installation

Add `QuickEnv` to your **global** Julia environment so it can be loaded from any script:

```julia
using Pkg
Pkg.activate() # Activates global env (e.g. @v1.12)
Pkg.develop(path="/home/sariel/prog/26/misc/julia_envs/QuickEnv")
```

---

## Magic Comments Syntax

You can configure `QuickEnv` directly inside the comments of your Julia script. These comments are completely ignored by the standard Julia parser, making them 100% syntactically safe and standard.

### 1. Declaring a Fallback Environment
If no existing named environment satisfies the dependencies, force `QuickEnv` to activate (and create if missing) a specific named environment:

```julia
# quickenv_fallback: plotting
```

### 2. Excluding Environments
To prevent your script from running in a "dirty" global environment, or to bypass broken environments, declare exclusions as a comma-separated list:

```julia
# quickenv_exclude: global, broken_plotting
```
*Note: Using the keyword `global` excludes all standard versioned environments like `@v1.12`.*

---

## Usage Example

Simply place `using QuickEnv` at the very beginning of your Julia scripts:

```julia
# quickenv_fallback: plotting
# quickenv_exclude: global

using QuickEnv
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
3. It finds a matching named environment (e.g., `@plotting`) and dynamically updates Julia's `LOAD_PATH`.
4. Subsequent lines like `using Plots` load instantly using the activated `@plotting` environment.
5. If `@plotting` did not exist, it would automatically create `@plotting` and run `Pkg.add(["Plots", "Cairo"])` before executing the rest of the script.
