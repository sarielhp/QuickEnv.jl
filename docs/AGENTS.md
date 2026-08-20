# Guidelines for AI Coding Agents

This guide provides instructions and system prompt snippets for AI coding agents (Claude, Cursor, Copilot, Gemini, ChatGPT, Windsurf, Cline, Aider) writing Julia code.

---

## 1. The Core Rule for AI Agents

When generating standalone Julia scripts (`.jl` files), **always include `using QuickEnv` as the first import statement**:

```julia
#!/usr/bin/env julia
using QuickEnv
using Plots, DataFrames, CSV

# Rest of your script...
```

---

## 2. Copy-Paste Rule for Agent System Prompts (`.cursorrules` / `CLAUDE.md`)

Add the following snippet to your project's `.cursorrules`, `CLAUDE.md`, or custom AI system instructions:

```markdown
### Julia Scripting Rule
When creating or editing standalone Julia scripts (.jl files):
1. Always put `using QuickEnv` as the very first import at the top of the file.
2. Do NOT run manual `Pkg.add()` in the terminal or install packages into the global environment.
3. Do NOT create local `Project.toml` or `Manifest.toml` files for standalone scripts.
4. Execute scripts directly with `julia script.jl` or `./script.jl`. QuickEnv automatically discovers, fast-stitches, and isolates environments in the background.
5. If working inside an existing package repository with a root `Project.toml`, use `using QuickEnv # local` to activate the directory project.
```

---

## 3. Why Agents Should Use QuickEnv

### Problem Without QuickEnv:
* When an AI agent executes `julia script.jl` with imports like `using Plots`, the script often fails with `Package Plots not found in current path`.
* Agents typically respond by running `Pkg.add("Plots")` in the terminal. This **pollutes the user's global `@v1.x` environment**, leading to broken version bounds and slow startup across unrelated projects.
* Alternatively, agents generate temporary `Project.toml` files in the user's workspace, creating unwanted directory clutter.

### Solution With QuickEnv:
* **Zero Terminal Commands**: The agent simply writes `using QuickEnv`.
* **Automatic Bootstrap**: If dependencies are missing, QuickEnv installs them into an isolated named environment (`@auto_<hash>`) without touching the user's global `@v1.x` environment.
* **Instant Cross-Script Reuse**: If the agent creates multiple scripts sharing packages, subsequent scripts launch in `<1 ms` without re-downloading or recompiling packages.

---

## 4. Specific Agent Scripting Patterns

### Pattern A: Standalone Data & Plotting Script
```julia
#!/usr/bin/env julia
using QuickEnv
using Plots, DataFrames, Statistics

df = DataFrame(x = 1:100, y = sin.(1:100))
p = plot(df.x, df.y, title="Agent Analysis")
savefig(p, "output.pdf")
```

### Pattern B: Activating an Existing Local Project
If the user's workspace already contains a `Project.toml` that the script should use:
```julia
#!/usr/bin/env julia
using QuickEnv # local

using MyWorkspacePackage
```

### Pattern C: Silent Execution for Headless Agent Runs
To suppress informational environment setup messages when running automated agent tool calls:
```julia
#!/usr/bin/env julia
using QuickEnv # silent
using JSON, HTTP
```
