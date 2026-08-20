### QuickEnv.jl v0.4.0 Release

A new version of **QuickEnv.jl v0.4.0** was released!

#### Key Highlights & Improvements:

- **Partial Fast Stitching (Optimization A)**: When a script requires a mix of existing and brand new packages, QuickEnv pre-stitches the known packages into the target environment in `<2ms`, then runs `Pkg.add` only on the missing packages. This saves up to 37% resolution time on cold starts and guarantees zero recompilation of base packages.
- **Enhanced Reliability & Bug Fixes**:
  - Fixed `# local` mode to use native project activation (`Base.set_active_project`) without loading `Pkg`.
  - Added cache corruption recovery to safely handle malformed cache entries.
  - Switched script cache to exact `mtime` timestamp checking.
  - Added debug logging across all error catch blocks.
- **Comprehensive Documentation Suite**:
  - `docs/DESIGN.md`: Architecture deep-dive on fast stitching vs. stacking, bitmask set-cover math, and caching internals.
  - `docs/tradeoffs.md`: Pros vs. cons analysis and startup benchmark comparison.
  - `docs/jlenv.md`: Complete CLI manual for environment inspection and housekeeping.
- **Expanded Test Suite**: 116 passing tests covering partial set-cover, mock manifest stitching, corrupted cache recovery, and diagnostics.

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
- **Release Notes**: https://github.com/sarielhp/QuickEnv.jl/releases/tag/v0.4.0
