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

### What's New in v0.4.1:

1. **Zero Configuration by Default**: No magic comments, no CLI flags, and no manual environment tracking required. Standard `using` statements are all you write. (Comments remain strictly optional for power-users who want to force specific named overrides).
2. **Autonomous Fast Stitching (<5 ms)**: If your script needs `Plots` and `DataFrames` and you already have environments containing them, QuickEnv automatically synthesizes a merged `Project.toml` and `Manifest.toml` on disk in `<5 ms` with **zero recompilation** and without modifying your global `@v1.x` environment.
3. **Partial Fast Stitching for Cold Starts**: If new packages are needed, QuickEnv pre-stitches the known base packages and runs `Pkg.add` only on the missing dependencies, speeding up resolution by up to ~37% and preventing base package recompilation cascades.
4. **Compounding Cross-Script Reuse**: Every script you run enriches your local environment pool. Future scripts with overlapping dependencies launch in `<1 ms` with zero download, solve, or precompile overhead.
5. **Lightweight Resource Footprint**: The steady-state runtime overhead is only **~47 ms** on cached runs, and each environment uses just **~3 KB** of disk space (Julia stores packages and binaries globally once; environments are just tiny text pointers).
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
