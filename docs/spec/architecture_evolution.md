# Architecture Evolution: Gate Registry Migration

## Background

Subagent 4 (Wave 2) attempted to migrate gate runners from a centralized registry
to a **self-registration** model. The approach was to inject `const gateConfig*`
and `static: registerGate(...)` calls into each runner file using Python helper
scripts (`tools/add_gate_config*.py`).

## Failure Analysis

### 1. Python Script Mis-Parses Nim Indentation

Nim uses indentation-based `const` blocks. The Python scripts used regex and
line-by-line text manipulation to insert new constant blocks into runner files.
This approach failed because:

- Nim's `const` blocks are terminated by dedent, not by explicit delimiters.
- The scripts split `const` blocks incorrectly, orphaning subsequent constants.
- At least **9 runner files** were corrupted with syntax errors:
  - `language_ban_gate.nim`
  - `binary_artifact_gate.nim`
  - `cast_nosideeffect_doc_gate.nim`
  - `core_invariant_gate.nim`
  - `debt_scan_gate.nim`
  - `forwarding_stub_cycle_gate.nim`
  - `hotspot_enforcement_gate.nim`
  - `import_encapsulation_gate.nim`
  - `intent_gate.nim`

### 2. Self-Registration Design Was Incomplete

Even if the injection had succeeded, the design was architecturally flawed:

- `gate_registry.nim` never consumed the compile-time `registry` written by
  `registerGate(...)`. The registration call wrote data, but no code read it back.
- Nim's compile-time VM does not share state between modules. Each module's
  `static:` block runs in isolation. A `registerGate` in one module cannot
  write to a variable in another module at compile time.
- Cross-module compile-time state requires `compileOption("cmd")` tricks or
  `gorge`/`staticRead` to pass data — which is exactly what the replacement
  design uses.

### 3. Recovery

All corrupted runner files were reverted to their HEAD state. The Python helper
scripts were deleted. The project was restored to a clean baseline.

## Decision: Build-Time Discovery

The project pivoted from code injection to **Build-Time Discovery**:

| Aspect | Self-Registration (Rejected) | Build-Time Discovery (Adopted) |
|--------|------------------------------|--------------------------------|
| Metadata source | Injected into runner `.nim` files | `src/gate/manifest.d/*.json` (per-gate files) |
| Runner discovery | N/A (injected) | `gorge("ls src/gate/runners/*.nim")` at compile time |
| Registry construction | `static: registerGate(...)` in each runner | `staticRead` + `parseJson` in `gate_registry.nim` |
| Separation of concerns | Runner files contain both logic AND metadata | Runner files contain only implementation |
| Fragility | High: regex/indentation parsing | Low: JSON is machine-parseable |
| Compile-time state | Cross-module sharing is impossible | `gorge` + `staticRead` are deterministic |

### How It Works

1. **Manifest**: `src/gate/manifest.d/*.json` is the SSOT for gate metadata
   (id, name, layer, entry, stages, weight, etc.). Each gate has its own JSON
   file; `_index.json` lists all filenames. The old monolithic `gate_manifest.json`
   has been deleted.

2. **Compile-time loading**: `gate_codegen.nim` uses `slurp()` to embed each
   gate's JSON at compile time, then `parseJson` + iteration to build
   `AllGatesSorted: seq[GateConfig]` in `gate_registry.nim`.

3. **Runner discovery**: `gorge("ls src/gate/runners/*.nim 2>/dev/null || true")`
   discovers runner files at compile time. During `nim check` the shell is
   unavailable (gorge returns empty), so runner checks are gracefully skipped.
   During `nim c`, full bidirectional verification runs.

4. **Architecture assertions**: Compile-time `static:` blocks verify:
   - Every manifest entry with a `src/gate/runners/` entry has a `.nim` file.
   - Every gate-like runner file has a manifest entry.
   - L1 Meta gates never reference L0 entry points.
   - Heavy gates never run in pre-commit.
   - Sort stability, unique IDs, etc.

## Lessons for Future Agents

1. **Do not use regex/indentation-based scripts to inject code into Nim source.**
   Nim's indentation grammar is fragile under text manipulation. The compiler
   is the only reliable parser.

2. **Prefer declarative metadata files over mutating existing source.**
   A JSON manifest is trivially parseable, diffable, and auditable. Injecting
   metadata into source files couples metadata to implementation.

3. **Verify every file with `nim check` immediately after automated edits.**
   Automated code generation MUST be followed by compilation verification.
   Syntax errors in gate runners can silently break the entire quality chain.

4. **Compile-time self-registration across modules in Nim is not feasible.**
   Nim's compile-time VM runs `static:` blocks per-module in isolation. There
   is no shared compile-time state between modules. External manifest + scan
   (`staticRead` + `gorge`) is the correct pattern for build-time discovery.
