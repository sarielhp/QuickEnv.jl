# FAQ: Why Recompilation Happens in Julia, and What QuickEnv Does About It

> **Disclaimer**: This FAQ was written by an AI agent (Gemini / Antigravity) based on discussions, questions, and feedback from the Julia Discourse community.

A frequent source of confusion in Julia is unexpected package precompilation—pausing on scripts you ran yesterday even without code changes or `Pkg.update`:

```text
[ Info: Precompiling Plots [91a5bcdd-...]
```

This FAQ explains why this happens in standard Julia and how `QuickEnv.jl` prevents it.

---

## Table of Contents
1. [How does Julia decide whether to recompile a package?](#1-how-does-julia-decide-whether-to-recompile-a-package)
2. [Why do packages recompile when I haven't changed code or updated packages?](#2-why-do-packages-recompile-when-i-havent-changed-code-or-updated-packages)
3. [Doesn't `Project.toml` pin down all dependencies?](#3-doesnt-projecttoml-pin-down-all-dependencies)
4. [When I run `julia --project=.`, doesn't Julia generate a `Manifest.toml`?](#4-when-i-run-julia---project-doesnt-julia-generate-a-manifesttoml)
5. [Why is the immediate second run fast if the first run recompiled?](#5-why-is-the-immediate-second-run-fast-if-the-first-run-recompiled)
6. [If the second run is fast, why does recompilation happen again days later?](#6-if-the-second-run-is-fast-why-does-recompilation-happen-again-days-later)
7. [Why does loading tools like `BenchmarkTools` or `Revise` from the global environment cause recompilation?](#7-why-does-loading-tools-like-benchmarktools-or-revise-from-the-global-environment-cause-recompilation)
8. [How does QuickEnv guarantee zero recompilation during fast stitching?](#8-how-does-quickenv-guarantee-zero-recompilation-during-fast-stitching)
9. [How does QuickEnv compare to DrWatson's `@quickactivate`?](#9-how-does-quickenv-compare-to-drwatsons-quickactivate)
10. [How do I intentionally update packages in QuickEnv environments?](#10-how-do-i-intentionally-update-packages-in-quickenv-environments)

---

## 1. How does Julia decide whether to recompile a package?

Julia precompilation images (`.ji` and native `.so`/`.dylib` files in `~/.julia/compiled/v1.x/`) are keyed by a **cryptographic cache slug** derived from:
1. Exact Julia compiler version and CPU target.
2. The `git-tree-sha1` content hash of the package source code.
3. The exact UUIDs, versions, and `git-tree-sha1` hashes of **all direct and transitive dependencies**.

If **any** sub-dependency in the dependency tree changes version or hash, the cache key changes, and Julia must recompile.

---

## 2. Why do packages recompile when I haven't changed code or updated packages?

Two main reasons:

### A. Environment Stacking (`LOAD_PATH` Leakage)
Julia's default search path is `LOAD_PATH = ["@", "@v#.#", "@stdlib"]`.
* If `--project` is omitted, `"@"` is empty, and Julia runs directly in `"@v#.#"` (global environment).
* When loading packages across stack layers, any version mismatch in a shared sub-dependency (like `Compat` or `Parsers`) invalidates the precompiled image.

### B. Unmanifested Projects (Floating Sub-Dependencies)
Running with only a `Project.toml` (no `Manifest.toml`) allows sub-dependencies to float. If another project installs a newer sub-dependency version into your depot, resolution changes and triggers a recompile.

---

## 3. Doesn't `Project.toml` pin down all dependencies?

**No.** `Project.toml` only records **direct dependencies** and **version ranges**.

| File | Scope | Versions | Pinned Content Hashes? | Prevents Recompiles? |
| :--- | :--- | :--- | :---: | :---: |
| **`Project.toml`** | Direct packages only | Allowed ranges (`Plots = "1"`) | ❌ No | ❌ **No** |
| **`Manifest.toml`** | Complete graph (direct + indirect) | Exact version (`1.40.2`) | ✅ Yes (`git-tree-sha1`) | ✅ **Yes** |

Background dependencies (`GR`, `ColorTypes`, `Showoff`, etc.) are omitted from `Project.toml` and can drift unless locked by a `Manifest.toml`.

---

## 4. When I run `julia --project=.`, doesn't Julia generate a `Manifest.toml`?

**No.** Activating a project only changes the active project pointer (`Base.active_project()`). It does not run the solver or create a `Manifest.toml`. 

A `Manifest.toml` is written **only** when explicitly executing `Pkg.instantiate()`, `Pkg.resolve()`, `Pkg.add()`, or `Pkg.update()`.

---

## 5. Why is the immediate second run fast if the first run recompiled?

On the first run, Julia builds the missing `.ji` binary and writes it to `~/.julia/compiled/`. On the immediate second run, Julia finds that exact binary on disk in `<0.5 ms` and loads it directly.

---

## 6. If the second run is fast, why does recompilation happen again days later?

**Cache Eviction / Version Drift ("Cache Ping-Pong")**:
1. **Monday**: Project A compiles `Plots` against `Compat v4.10.0` $\to$ creates `cache_A.ji`.
2. **Tuesday**: Project B compiles `Plots` against `Compat v4.16.0` $\to$ creates `cache_B.ji`.
3. **Friday**: Returning to Project A, if `cache_A.ji` was evicted or `@v1.x` dependencies shifted, Julia cannot use `cache_B.ji` and must recompile.

---

## 7. Why does loading tools like `BenchmarkTools` or `Revise` from the global environment cause recompilation?

```text
Local Project:  DataFrames.jl ──────► Compat.jl v4.10.0 (Loaded)
                                           ▲
                                    Version Collision!
                                           ▼
Global @v1.x:   BenchmarkTools.jl ──► Compat.jl v4.16.0 (Precompiled against)
```

Because a single Julia process cannot load two different versions of `Compat.jl`, `BenchmarkTools`'s global precompiled cache is invalid in this session and must be recompiled on the fly against `Compat v4.10.0`.

---

## 8. How does QuickEnv guarantee zero recompilation during fast stitching?

1. **Transitive Hash Validation ($O(N)$)**: Verifies that all shared dependencies between source environments have identical UUIDs, versions, and `git-tree-sha1` hashes in `<2 ms`.
2. **Concrete Manifest Synthesis**: Writes a complete, locked `Manifest.toml` to disk in `~/.julia/environments/@auto_<hash>/`.
3. **Exact Cache Matching**: Because `git-tree-sha1` hashes match the parent environments, Julia loads the existing `.ji` cache files immediately.

*(If a dependency conflict exists, QuickEnv rejects fast stitching and falls back to a clean solve).*

---

## 9. How does QuickEnv compare to DrWatson's `@quickactivate`?

| Feature | DrWatson (`@quickactivate`) | QuickEnv.jl (`using QuickEnv`) |
| :--- | :--- | :--- |
| **Target** | Structured project repositories | Standalone single-file scripts |
| **Requirements** | Project directory with `Project.toml` | **None** (zero files or setup) |
| **Mechanism** | Finds root folder and calls `activate` | Fast-stitches shared environments in `~/.julia/environments/` |
| **Global `@v1.x`** | Standard | **Strictly protected** from package pollution |
| **First Run** | Requires manual `Pkg.instantiate()` | Fully automatic |

---

## 10. How do I intentionally update packages in QuickEnv environments?

To update packages in auto-generated environments to newer upstream versions:
```bash
# Clean up auto-generated environments and reset cache
./tools/jlenv.jl prune
```
On the next script execution, QuickEnv rebuilds the environment with the latest compatible package versions.
