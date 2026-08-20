# QuickEnv.jl — To-Do & Roadmap

## Optimization A: Partial Fast Stitch + Incremental `Pkg.add` [COMPLETED]

### 1. Concept Overview
When a script requests a set of packages $P_{\text{req}}$ that cannot be 100% covered by any single environment or exact union of existing environments, QuickEnv currently falls back to resolving all of $P_{\text{req}}$ from scratch via `Pkg.add`.

**Optimization A** enhances this by performing a **maximal partial fast stitch** of the known subset $P_{\text{known}} \subset P_{\text{req}}$ followed by an **incremental `Pkg.add`** for only the remaining missing packages $P_{\text{new}} = P_{\text{req}} \setminus P_{\text{known}}$.

---

### 2. Algorithmic Constraints & Requirements

1. **Strict Subset / Non-Polluting Containment**:
   * Candidate environments considered for the partial cover should only be included if their direct dependency sets are strictly contained within $P_{\text{req}}$ (i.e. $P_{\text{cand}} \subseteq P_{\text{req}}$), or if their extraneous package count is zero/minimal.
   * This ensures the partial stitch does not pull in unrelated heavy packages that could constrain version resolution for the new packages $P_{\text{new}}$.

2. **Greedy Seed Initialization**:
   * The partial set-cover solver should start with a greedy heuristic: pick the compatible candidate environment covering the largest number of uncovered packages in $P_{\text{req}}$.
   * Iteratively greedily select subsequent compatible environments that cover the remaining uncovered packages.
   * Because $n \le 64$ with bitmask operations, greedy initialization + bitmask verification executes in $<1\text{ ms}$.

3. **Incremental Bootstrapping Pipeline**:
   * **Step 1**: Find maximal subset cover $P_{\text{known}}$ using bitmasks.
   * **Step 2**: If $|P_{\text{known}}| \ge 2$ (or a single compatible environment covers a substantial portion of $P_{\text{req}}$):
     * Synthesize and write the partial `Project.toml` and `Manifest.toml` for `@auto_<hash>`.
     * Check manifest compatibility across the selected covering environments.
   * **Step 3**: Activate `@auto_<hash>` and execute `Pkg.add(P_{\text{new}})` for only the remaining missing packages.
     * The pre-populated `Manifest.toml` acts as a constraint set for Pkg's SAT solver, drastically speeding up resolution and preventing recompilation of $P_{\text{known}}$.
   * **Step 4**: Update cache (`cache.toml`) mapping $P_{\text{req}} \to @\text{auto\_}\langle\text{hash}\rangle$.

---

## Technical Considerations

### 1. Heavy Existing Environments vs. Dedicated Minimal Environments
* **Package Loading Mechanics in Julia**:
  * Julia's runtime only loads package code into memory when `using Foo` or `import Foo` is executed. Unused packages listed in `Project.toml` do not add runtime memory overhead.
* **When Heavy Environments Hurt**:
  * **Manifest / Project Parse Overhead**: Very large manifests take slightly longer to parse.
  * **Version Constraint Bottlenecks**: A mega-environment with 100 packages may have old upper bounds (`[compat]`) that prevent installing modern versions of new packages.
* **Proposed Heuristic**:
  * Prioritize clean, minimal modular environments over large monolithic environments when computing set covers.
  * Add a configurable threshold (or `# QuickEnv.clean: true` option) to force dedicated clean environment creation if the matching environment's extraneous package ratio is too high.

### 2. Caching Behavior for Shared / Larger Environments
* When a larger matching environment `@mega` is chosen for a smaller script $P_{\text{small}}$, QuickEnv records:
  1. **Package Cache**: $P_{\text{small}} \to @\text{mega}$ in `cache.toml`.
  2. **Script Cache**: `script_path` (with `mtime`) $\to @\text{mega}$.
* On subsequent executions of that script, QuickEnv hits the fast path via `check_script_cache_hit` in $O(1)$ time ($<0.1\text{ ms}$), completely bypassing set-cover evaluation and file parsing.
