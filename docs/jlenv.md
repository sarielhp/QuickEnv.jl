# `jlenv` — Julia Named Environment CLI Utility

`tools/jlenv.jl` is a colorful command-line utility for inspecting, managing, and maintaining Julia shared named environments (`~/.julia/environments/`).

---

## The Role of `jlenv` in Modern QuickEnv

In earlier versions of `QuickEnv`, `jlenv` was used to manually match and launch scripts. With modern `QuickEnv.jl` (v0.3+), all matching, bitmask set-covering, manifest stitching, and bootstrapping happen automatically when you write `using QuickEnv` in your script.

Today, `jlenv` serves as an **administrative dashboard and housekeeping utility** (similar to `docker system prune` or `git status`):
* **Housekeeping**: Pruning auto-generated `@auto_<hash>` environments and clearing stale caches.
* **Inspection**: Listing all environments, descriptions, and installed packages.
* **REPL Launching**: Instantly opening a Julia REPL in any named environment.

---

## Quick Setup (Optional Shell Alias)

You can run `jlenv` directly or alias it in your shell configuration (`~/.bashrc` or `~/.zshrc`):

```bash
alias jlenv="/path/to/QuickEnv.jl/tools/jlenv.jl"
```

---

## Command Reference

### 1. Housekeeping & Cache Management

#### Prune auto-generated environments & clear cache
Removes all temporary `@auto_*` stitched environments from `~/.julia/environments/` and resets the resolution cache in `~/.julia/quickenv/cache.toml`:
```bash
./tools/jlenv.jl prune
```

#### Inspect resolution cache
Views all package-to-environment mappings and fast script-level lookup entries:
```bash
./tools/jlenv.jl cache list
```

#### Clear resolution cache
Clears `~/.julia/quickenv/cache.toml` without deleting environments:
```bash
./tools/jlenv.jl cache clean
```

#### Delete a named environment
Permanently deletes a custom named environment:
```bash
./tools/jlenv.jl rm @old_env
```

---

### 2. Inspection & Exploration

#### List all shared named environments
Displays all named environments in `~/.julia/environments/` with their descriptions:
```bash
./tools/jlenv.jl list
```

#### Show packages in an environment
Inspects the direct dependencies and package UUIDs inside a specific environment:
```bash
./tools/jlenv.jl show @plotting
```

#### Search General Registry for a package
Fuzzy-searches reachable Julia registries for package names:
```bash
./tools/jlenv.jl search DataFrames
```

---

### 3. Environment Creation & Modification

#### Set or update environment description
Writes a human-readable description into an environment's `Project.toml`:
```bash
./tools/jlenv.jl describe @plotting "Plotting environment with Plots.jl and Cairo"
```

#### Add packages to a named environment
Installs packages directly into a shared named environment:
```bash
./tools/jlenv.jl add @plotting DataStructures CSV
```

#### Create environment from a script's dependencies
Parses a `.jl` script and creates a new named environment containing all its imported packages:
```bash
./tools/jlenv.jl create @science_env analyze.jl
```

#### Fast-stitch / merge environments via CLI
Manually merges multiple existing environments into a target environment (uses fast manifest stitching if compatible, or falls back to joint `Pkg` resolution):
```bash
./tools/jlenv.jl merge @science @plotting @data
```

#### Check manifest compatibility
Checks whether two or more named environments share identical transitive dependency versions and tree hashes:
```bash
./tools/jlenv.jl check-compat @plotting @data
```

---

### 4. Interactive & Script Execution

#### Launch Julia REPL in an environment
Opens an interactive REPL with the target named environment active (equivalent to `julia --project=@env`):
```bash
./tools/jlenv.jl repl @plotting
```

#### Run a script in a named environment
Runs a Julia script inside a specified named environment, passing any extra arguments:
```bash
./tools/jlenv.jl run @plotting plot_results.jl --interactive
```

#### Match and run a script
Finds existing environments that satisfy the script's imports and executes the script:
```bash
./tools/jlenv.jl mrun script.jl
```
*(Note: If your script includes `using QuickEnv`, simply running `julia script.jl` is preferred, as QuickEnv handles this autonomously).*
