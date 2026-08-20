### QuickEnv.jl v0.4.1 Release

A new version of **QuickEnv.jl v0.4.1** was released!

#### Key Highlights & Improvements:

- **Set-and-Forget Architecture**: Effortless automatic environment management with minimal overhead: **~47 ms** on cached runs and **~3 KB** per environment.
- **Partial Fast Stitching (Optimization A)**: Pre-stitches known dependency manifests into target environments in `<2ms`, running `Pkg.add` only on missing packages to speed up cold resolution by up to 37% with zero recompilation cascades.
- **Enhanced Reliability & Bug Fixes**:
  - Native local project activation (`# local`) without loading `Pkg`.
  - Hardened cache corruption recovery and exact timestamp comparisons.
  - Complete error traceability with structured debug logging.
- **Modular Documentation Suite**:
  - `docs/DESIGN.md`: Architecture deep-dive on set-cover math, fast stitching, and environment economics.
  - `docs/tradeoffs.md`: Objective startup performance benchmarks and comparisons.
  - `docs/jlenv.md`: Complete CLI manual for environment inspection and housekeeping.

#### Quick Start:

Install once in your global environment:
```julia
using Pkg; Pkg.add(url="https://github.com/sarielhp/QuickEnv.jl.git")
```

Then add `using QuickEnv` at the top of any standalone script:
```julia
#!/usr/bin/env julia
using QuickEnv
using Plots, DataFrames

# Your code here...
```

- **GitHub Repository**: https://github.com/sarielhp/QuickEnv.jl
- **Release Notes**: https://github.com/sarielhp/QuickEnv.jl/releases/tag/v0.4.1
