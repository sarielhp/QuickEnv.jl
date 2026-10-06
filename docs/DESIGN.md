# QuickEnv.jl — Architecture & Design Deep-Dive

This document provides an in-depth explanation of `QuickEnv.jl`'s internal architecture, performance optimizations, and algorithmic design choices.

---

## Table of Contents
1. [Core Design: Fast Stitching vs. Environment Stacking](#1-core-design-fast-stitching-vs-environment-stacking)
2. [Why Fast Stitching Is Usually Fast](#2-why-fast-stitching-is-usually-fast)
3. [The Bitmask Set-Cover Engine](#3-the-bitmask-set-cover-engine)
4. [Manifest Transitive Compatibility & Synthesis](#4-manifest-transitive-compatibility--synthesis)
5. [Two-Tier State-Aware Caching](#5-two-tier-state-aware-caching)
6. [Heavy Environments & Loading Mechanics](#6-heavy-environments--loading-mechanics)
7. [Handling Uncovered Packages & Autonomous Bootstrapping](#7-handling-uncovered-packages--autonomous-bootstrapping)
8. [The Economics of Julia Environments (Why Having 100+ Environments Costs Almost Nothing)](#8-the-economics-of-julia-environments-why-having-100-environments-costs-almost-nothing)

---

## 1. Core Design: Fast Stitching vs. Environment Stacking

A common question when managing Julia environments dynamically is whether to use **runtime environment stacking** (modifying Julia's `LOAD_PATH`) or **concrete environment activation** (`Base.set_active_project`).

QuickEnv activates one fully realized, concrete environment on disk. It preserves the caller's `LOAD_PATH` by default so scripts and included helpers can load QuickEnv again. Set `QUICKENV_ISOLATE_LOAD_PATH=true` to remove versioned global-environment entries (`@v...`) while retaining explicit custom load paths.

```
Script Imports (e.g. using Plots, DataFrames)
                    │
   ┌────────────────┴────────────────┐
   ▼                                 ▼
1. Single Existing Match?         2. Multiple Compatible Envs?
   (e.g., @plotting has both)        (e.g., @plotting + @data)
   → Activate @plotting              → Fast-Stitch into unified @auto_<hash>
                                       (Validates and merges Project/Manifest;
                                        reuses valid Julia compile caches)
                                     → Activate @auto_<hash>
                                     │
                                     ▼ (if incompatible or missing)
                                  3. Bootstrap via Pkg.add
                                     (Create new env & install missing packages)
```

### Why Stacking (`LOAD_PATH`) Was Rejected:
* **Transitive Dependency Fragility**: When stacking environments, packages in lower stack layers may fail to locate their private dependencies if those dependencies are not exposed in the upper layer's manifest.
* **Tooling Incompatibility**: Standard Julia developer tools (LanguageServer, Revise, Pluto, `Pkg` operations) work reliably with single active projects, but often behave unpredictably with layered stacks.
* **No Cache Isolation**: Stacking makes deterministic cache invalidation complex because changes in any layered manifest can silently alter resolution semantics.

---

## 2. Why Fast Stitching Is Usually Fast

Creating or merging environments with standard `Pkg.add` is typically slow (taking anywhere from 5 to 60+ seconds) due to two major bottlenecks:
1. **Pkg SAT Solving**: Evaluating the entire dependency graph across General Registry constraints.
2. **Package Precompilation**: Compiling `.ji` cache files for all direct and indirect dependencies.

### Fast Stitching Bypasses Both Bottlenecks:
* **The SAT solver was already run** when the source environments (e.g., `@plotting` and `@data`) were originally created.
* **Precompiled artifacts already exist** in `~/.julia/compiled/` corresponding to the exact `git-tree-sha1` hashes recorded in those source manifests.

When QuickEnv stitches `@plotting` and `@data`:
1. **Validation**: Reads source projects and manifests, verifies their structure and Julia version, and compares complete entries for shared UUIDs.
2. **Synthesis**: Prepares a unified `Project.toml` and `Manifest.toml` in a staging directory, then installs the completed directory under a per-environment lock (atomic rename on POSIX; best-effort replacement on Windows).
3. **Compile-Cache Reuse**: Julia's code loader can reuse existing package images when their source graph, Julia version, CPU target, and runtime flags match. QuickEnv avoids invalidating those caches itself, but it cannot guarantee that a usable cache is present.

> For a detailed FAQ on Julia's precompilation caching mechanics and why standard projects unexpectedly recompile, see **[docs/faq_recompile.md](faq_recompile.md)**.

---

## 3. The Bitmask Set-Cover Engine

To find a small combination of named environments that covers a script's requested packages $P_{\text{req}}$, QuickEnv uses a time-bounded branch-and-bound solver over hardware bitmasks:

* Each required package $p_i \in P_{\text{req}}$ (up to 64 packages) is mapped to bit index $i-1$ in a `UInt64` integer.
* The target mask is set to:
  $$\text{target\_mask} = (1 \ll |P_{\text{req}}|) - 1$$
* Candidate environments are converted to `UInt64` bitmasks in $<0.1\text{ ms}$.

The objective is lexicographic: first minimize the number of source environments, then minimize extraneous direct dependencies. Compatibility is checked as candidates are added. If the one-second budget expires, the best complete cover found so far is used; if none exists, QuickEnv falls back to package resolution.

---

## 4. Manifest Transitive Compatibility & Synthesis

Before stitching environments, QuickEnv validates every source project and manifest, rejects missing or malformed metadata, requires the same Julia minor version, and compares shared manifest entries by UUID. Shared entries must be structurally identical after relative paths are normalized. This includes versions, tree hashes, repository/path identity, dependency lists, extensions, weak dependencies, and pinning metadata.

$$\forall u \in \operatorname{UUIDs}(M_A) \cap \operatorname{UUIDs}(M_B):\quad
\operatorname{normalize}(M_A[u]) = \operatorname{normalize}(M_B[u])$$

If any shared entry differs, QuickEnv rejects stitching and falls back to clean resolution. Direct dependency UUID conflicts are also rejected.

---

## 5. Two-Tier State-Aware Caching

QuickEnv persists resolution metadata in `~/.julia/quickenv/cache.toml`:

```
Execution Start
       │
       ▼
1. Script Cache Hit? (entry/include content digests and environment state match)
   ├── YES ──► Activate validated target env ──► RUN SCRIPT
   └── NO
       │
       ▼
2. Package Canonical Key Hit? (e.g., "Cairo+Plots" with valid source digests)
   ├── YES ──► Activate validated target env ──► Update Script Cache ──► RUN SCRIPT
   └── NO
       │
       ▼
3. Full Resolution / Fast Stitching / Bootstrap Pipeline
```

* **Locked Writes**: Cache read-modify-write transactions use PID locks and replacement (atomic rename on POSIX; best effort on Windows). Environment files are fully prepared in a staging directory and installed while holding a per-environment lock. Auto-environment names include package, source-state, and Julia-minor-version digests to avoid rewriting an environment when its inputs change.
* **Self-Healing Invalidation**: An `atexit` hook monitors unhandled exceptions during execution. If a script crashes on startup due to missing dependencies, its cache entry is purged to force a full re-resolution on the next run.

---

## 6. Heavy Environments & Loading Mechanics

### Does Activating a Large Environment Slow Down Script Execution?
* **No Runtime Memory Overhead**: In Julia, packages listed in an environment's `Project.toml` are **only loaded into memory when explicitly invoked** via `using` or `import`. An environment containing 100 packages incurs zero memory or execution penalty if your script only calls `using Plots`.
* **Potential Tradeoffs**: Very large environments have larger manifest files and tighter dependency bounds. QuickEnv prefers fewer source environments, then fewer extraneous direct dependencies.

---

## 7. Handling Uncovered Packages & Autonomous Bootstrapping

When a script requires packages that are not present in any existing named environment:
1. **Detection**: The set-cover engine identifies that no combination of existing environments achieves `current_cov == target_mask`.
2. **Partial Fast-Stitching (Optimization A)**: Finds the maximal compatible subset of existing environments, writes their pre-resolved manifest into `@auto_<hash>`, and runs `Pkg.add` with `PRESERVE_TIERED` only for new packages. Exact direct-package compatibility bounds discourage unnecessary changes while allowing Pkg to find a compatible solution. If completion fails, QuickEnv retries from a clean target rather than treating the partial environment as final.
3. **Autonomous Creation**: QuickEnv creates `@auto_<hash>` in `~/.julia/environments/`.
4. **Depot Enrichment**: Once created, `@auto_<hash>` becomes part of the named environment pool, making its packages available for future fast-stitching with other environments.

---

## 8. The Economics of Julia Environments (Why Having 100+ Environments Costs Almost Nothing)

Developers familiar with Python (`venv` / `conda`) or JavaScript (`node_modules`) are often hesitant to create many environments because in those ecosystems, each environment duplicates packages, binaries, and virtual copies of the interpreter—easily consuming gigabytes of disk space.

In Julia, environments operate under a **fundamentally different, content-addressed architecture**:

### 1. Global Content-Addressed Storage
Package assets are never copied into an environment. Instead, Julia stores assets globally in your depot (`~/.julia/`):
* **Package Source Trees**: Stored **once** in `~/.julia/packages/<Name>/<slug>/` keyed by `git-tree-sha1`.
* **Compiled Binary Artifacts**: Stored **once** in `~/.julia/artifacts/<hash>/`.
* **Precompiled `.ji` Binary Images**: Stored **once** in `~/.julia/compiled/v1.x/<Name>/<slug>.ji`.

### 2. An Environment Is Primarily Metadata
A named or auto-generated environment (`~/.julia/environments/@auto_<hash>`) contains strictly two plain-text files:
* `Project.toml`: Human-readable direct package names, UUIDs, and exact compatibility bounds for stitched direct dependencies.
* `Manifest.toml`: The complete dependency graph and source identities. Its size ranges from a few kilobytes to hundreds of kilobytes for large ecosystems.

### 3. The Resource Footprint:

| Total Named Environments | Disk Space Consumed | Duplicated Package Code / Binaries |
| :---: | :---: | :---: |
| **1 Environment** | Project plus manifest metadata | 0 MB |
| **10 Environments** | Roughly 10× their metadata size | 0 MB |
| **50 Environments** | Roughly 50× their metadata size | 0 MB |
| **100 Environments** | Roughly 100× their metadata size | 0 MB |

### 4. Why Many Small Environments Are Better for the Compiler
Counterintuitively, creating many small, dedicated environments via QuickEnv is significantly better for Julia than maintaining one large monolithic environment:
* **Fewer Method Invalidations**: Julia only loads and checks the packages strictly required by that script.
* **Faster Manifest Parsing**: Smaller dependency graphs generally mean less manifest parsing and validation work.
* **No Version Bound Contention**: Different scripts remain isolated and never hold each other back from using newer package versions.
