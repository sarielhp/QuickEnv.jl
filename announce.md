# QuickEnv.jl v0.4.1 — Release Announcement

**QuickEnv.jl v0.4.1: Now 100% Autonomous & Zero-Configuration**

Following the feedback from this thread, **QuickEnv v0.4.1** has been restructured and is now officially released in the General Registry. 

The most important change: **You no longer need to configure named environments or write special comments.**

### Standard Zero-Config Workflow
Simply add `using QuickEnv` as the first line of your script:

```julia
#!/usr/bin/env julia
using QuickEnv
using Plots, DataFrames, CSV

# Your script runs immediately...
```

### What's New in v0.5.0:

1. **Zero Configuration by Default**: No magic comments, no CLI flags, and no manual environment tracking required. Standard `using` statements are all you write. (Comments remain strictly optional for power-users who want to force specific named overrides).
2. **Autonomous Fast Stitching**: If your script needs `Plots` and `DataFrames` and you already have compatible environments containing them, QuickEnv can synthesize a merged `Project.toml` and `Manifest.toml` without invoking Pkg's resolver or modifying your global `@v1.x` environment. Julia reuses compile caches when they remain valid.
3. **Partial Fast Stitching for Cold Starts**: If new packages are needed, QuickEnv pre-stitches the known base packages and asks `Pkg.add` to add only the missing dependencies. The published benchmark measured a ~37% resolution improvement; Pkg may still adjust versions or precompile when required.
4. **Compounding Cross-Script Reuse**: Every successfully created environment enriches your local environment pool. Future scripts with overlapping dependencies can reuse resolution metadata and compatible compile caches.
5. **Lightweight Resource Footprint**: The measured steady-state runtime overhead is about **47 ms** on the published benchmark. Environments store project/manifest metadata while Julia shares package sources, artifacts, and compile caches globally.
6. **Detailed Architecture Documentation**: For those interested in the underlying mechanics (why we chose manifest synthesis over `LOAD_PATH` stacking, the bitmask set-cover solver math, and atomic cache writes), see the newly added **[Design Deep-Dive](https://github.com/sarielhp/QuickEnv.jl/blob/main/docs/DESIGN.md)** and **[Tradeoffs Analysis](https://github.com/sarielhp/QuickEnv.jl/blob/main/docs/tradeoffs.md)**.

---

### Installation / Update:
```julia
using Pkg
Pkg.update("QuickEnv") # or Pkg.add("QuickEnv")
```

- **GitHub Repository**: https://github.com/sarielhp/QuickEnv.jl
- **Design & Architecture**: https://github.com/sarielhp/QuickEnv.jl/blob/main/docs/DESIGN.md
- **Tradeoffs & Startup Benchmarks**: https://github.com/sarielhp/QuickEnv.jl/blob/main/docs/tradeoffs.md
- **AI Coding Agent Guide**: https://github.com/sarielhp/QuickEnv.jl/blob/main/docs/AGENTS.md
