# FAQ: Why Recompilation Happens in Julia, and What QuickEnv Does About It

> **Disclaimer**: This FAQ was written by an AI agent (Gemini / Antigravity) based on discussions, questions, and feedback from the Julia Discourse community.

A frequent source of confusion among Julia developers is unexpected package precompilation. You sit down to run a script you ran yesterday—without modifying any code or running `Pkg.update`—yet Julia pauses and prints:

```text
[ Info: Precompiling Plots [91a5bcdd-...]
```

This document explains the technical mechanics behind Julia's precompilation caching, why unexpected recompilations happen in standard workflows, and how `QuickEnv.jl` eliminates them.

---

## Table of Contents
1. [How does Julia decide whether to use a precompiled binary or recompile?](#1-how-does-julia-decide-whether-to-use-a-precompiled-binary-or-recompile)
2. [Why do packages recompile even when I haven't changed my code or updated packages?](#2-why-do-packages-recompile-even-when-i-havent-changed-my-code-or-updated-packages)
3. [Doesn't `Project.toml` pin down all the dependencies my script uses?](#3-doesnt-projecttoml-pin-down-all-the-dependencies-my-script-uses)
4. [When I run `julia --project=.`, doesn't Julia automatically generate a `Manifest.toml`?](#4-when-i-run-julia---project-doesnt-julia-automatically-generate-a-manifesttoml)
5. [Why is the immediate second run fast if the first run recompiled?](#5-why-is-the-immediate-second-run-fast-if-the-first-run-recompiled)
6. [If the second run is fast, why does recompilation happen again days later?](#6-if-the-second-run-is-fast-why-does-recompilation-happen-again-days-later)
7. [Why does loading utilities like `BenchmarkTools` or `Revise` from the global environment cause recompilation?](#7-why-does-loading-utilities-like-benchmarktools-or-revise-from-the-global-environment-cause-recompilation)
8. [How does QuickEnv guarantee zero recompilation when fast-stitching environments?](#8-how-does-quickenv-guarantee-zero-recompilation-when-fast-stitching-environments)
9. [How does QuickEnv compare to DrWatson's `@quickactivate`?](#9-how-does-quickenv-compare-to-drwatsons-quickactivate)

---

## 1. How does Julia decide whether to use a precompiled binary or recompile?

When you type `using Plots`, Julia does not just check if a compiled file named `Plots.ji` exists. It checks if the compiled file matches the **exact dependency graph hash**:

* Precompiled images are stored in `~/.julia/compiled/v1.x/<PackageName>/<cache_slug>.ji`.
* The `<cache_slug>` is a cryptographic hash derived from:
  1. The exact Julia compiler version and CPU target.
  2. The exact `git-tree-sha1` content hash of the package source code.
  3. The exact versions, UUIDs, and `git-tree-sha1` hashes of **every direct and indirect (transitive) dependency**.

If even **one** deep sub-dependency in the dependency tree changes version or hash, the cache slug changes. Julia detects that no `.ji` binary exists for the current combination and triggers a recompile.

---

## 2. Why do packages recompile even when I haven't changed my code or updated packages?

In standard Julia, two primary mechanisms cause unexpected recompilations:

### A. Environment Stacking (`LOAD_PATH` Leakage)
By default, Julia initializes `LOAD_PATH` with:
```julia
LOAD_PATH = ["@", "@v#.#", "@stdlib"]
```
* `"@"` is your currently active project.
* `"@v#.#"` is your standard **global environment** (e.g. `@v1.12`).

If your script or interactive session loads a package from `@v1.x` that shares a common sub-dependency (like `Compat`, `Parsers`, or `OrderedCollections`) with your local project, but at a slightly different version, Julia cannot load two different versions of the same package into one process. The precompiled image is invalidated, forcing a recompile.

### B. Floating Sub-Dependencies in Unmanifested Projects
If you run inside a folder that has a `Project.toml` but no committed `Manifest.toml`, Julia resolves dependencies loosely against whatever is in your depot. If another project recently pulled in a newer minor patch of a sub-dependency, the resolution changes and invalidates the cached binary.

---

## 3. Doesn't `Project.toml` pin down all the dependencies my script uses?

**No.** A `Project.toml` only records **direct dependencies** and **version ranges**; it does not lock exact versions or transitive sub-dependencies.

| Property | `Project.toml` | `Manifest.toml` |
| :--- | :--- | :--- |
| **Scope** | Direct top-level packages only | Complete closed-world graph (direct + indirect) |
| **Versions** | Allowed ranges (e.g. `Plots = "1"`) | Exact pinned version (e.g. `version = "1.40.2"`) |
| **Code Identity** | None | Exact `git-tree-sha1` content hashes |
| **Guarantees Zero Recompile?** | ❌ **No** | ✅ **Yes** |

Because a package like `Plots` depends on dozens of background packages (`GR`, `ColorTypes`, `Showoff`, `FixedPointNumbers`, `Contour`, etc.) that are never listed in `Project.toml`, `Project.toml` alone cannot prevent dependency shifts.

---

## 4. When I run `julia --project=.`, doesn't Julia automatically generate a `Manifest.toml`?

**No.** Activating a project (`julia --project=.` or `Pkg.activate(".")`) **only changes a runtime pointer** (`Base.active_project()`).

* It does **not** run the package SAT solver.
* It does **not** write a `Manifest.toml` to disk.
* It does **not** download missing dependencies.

A `Manifest.toml` is only generated when you explicitly run mutating `Pkg` commands like `Pkg.instantiate()`, `Pkg.resolve()`, `Pkg.add()`, or `Pkg.update()`. If you execute `julia --project=. script.jl` in a directory with only a `Project.toml`, Julia runs unmanifested.

---

## 5. Why is the immediate second run fast if the first run recompiled?

When Julia pauses on the first run to recompile:
1. It builds a brand new `.ji` cache file for that exact combination of dependencies.
2. It saves that `.ji` file to `~/.julia/compiled/v1.x/<Package>/<new_slug>.ji`.

When you run the script a second time immediately afterward:
* The `.ji` file is sitting right on disk.
* Julia finds the matching slug in `<0.5 ms` and loads it into memory without compiling.

---

## 6. If the second run is fast, why does recompilation happen again days later?

This phenomenon is called **"Cache Ping-Pong"** (or cache eviction):

1. **Monday**: You run **Project A**. It compiles `Plots` against `Compat v4.10.0` $\to$ saves `cache_A.ji`.
2. **Tuesday**: You run **Project B** (or run a one-off script in `@v1.x`). It compiles `Plots` against `Compat v4.16.0` $\to$ saves `cache_B.ji`.
3. **Friday**: You return to **Project A**. 
   * Julia limits how many `.ji` files it keeps per package before pruning older ones.
   * If `cache_A.ji` was evicted or if your environment stack shifted, Julia cannot use `cache_B.ji`.
   * **Result**: Julia is forced to recompile `Plots` again.

---

## 7. Why does loading utilities like `BenchmarkTools` or `Revise` from the global environment cause recompilation?

Suppose:
1. Your local project (`--project=.`) uses `DataFrames.jl`, which was compiled against **`Compat.jl v4.10.0`**.
2. You have `BenchmarkTools.jl` installed globally in `@v1.x`, where it was compiled against **`Compat.jl v4.16.0`**.

When you run:
```julia
using DataFrames      # Loaded from local project (Compat v4.10.0 active)
using BenchmarkTools  # Loaded from @v1.x via LOAD_PATH stack
```
Because the active process is already committed to `Compat v4.10.0`, `BenchmarkTools`'s global precompiled image (which requires `Compat v4.16.0`) is invalid for this session. Julia must recompile `BenchmarkTools` against `Compat v4.10.0` on the fly.

---

## 8. How does QuickEnv guarantee zero recompilation when fast-stitching environments?

When `QuickEnv` combines existing environments (e.g. `@plotting` containing `Plots` and `@data` containing `DataFrames`):

1. **Transitive Hash Verification ($O(N)$)**:
   QuickEnv inspects both source manifests and verifies that every shared dependency has the **identical UUID, version, and `git-tree-sha1` hash**.
2. **Concrete Manifest Synthesis (<5 ms)**:
   QuickEnv writes a unified, concrete `Manifest.toml` into `~/.julia/environments/@auto_<hash>/`.
3. **Guaranteed Cache Slug Match**:
   Because the `git-tree-sha1` hashes in the synthesized manifest match the exact hashes used when the parent environments were originally compiled, Julia’s loader maps them to existing `.ji` cache files in `~/.julia/compiled/` with **zero recompilation**.

If there is any version incompatibility or tree-hash divergence between the environments, QuickEnv detects this, rejects fast stitching, and falls back to a clean solve rather than generating a broken manifest.

---

## 9. How does QuickEnv compare to DrWatson's `@quickactivate`?

| Feature | DrWatson (`@quickactivate`) | QuickEnv.jl (`using QuickEnv`) |
| :--- | :--- | :--- |
| **Primary Target** | Structured project repositories | Standalone, single-file scripts |
| **Directory Requirement** | Requires an existing project folder with `Project.toml` | Requires **no** project folders or local files |
| **How It Operates** | Navigates up directory tree to find root `Project.toml` and activates it | Scans imports, finds or fast-stitches matching shared named environments in `~/.julia/environments/` |
| **Global Env (`@v1.x`) Safety** | Standard | **Strictly protected** from package pollution |
| **First-Run Behavior** | Requires user to have run `Pkg.instantiate()` | Fully automatic (matching, fast-stitching, or incremental bootstrap) |
