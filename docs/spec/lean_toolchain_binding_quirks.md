# Lean Toolchain Binding Quirks

## QUIRK: staticRead artifacts are invisible to the Nim incremental build

### Problem

`src/core/proof/proof_witness_checker.nim` embeds two build artifacts via
`staticRead` (`proofs/proof_witness.json`, `proofs/lean-toolchain`) and
verifies them in a compile-time `static:` block. Nim's build system does NOT
track `staticRead` files as dependencies: when the module itself is
cache-fresh, an incremental rebuild reuses the embedded bytes and the
compile-time checks never re-execute. Measured 2026-10-09 — a witness
reverted to `lean_version 4.29.0` (pin is `v4.33.0`) compiled clean,
`nim c` exit 0.

### Non-fix

`{.compile: "<file>".}` is NOT a remedy for data files: it registers the file
as a C translation unit (Nim runs gcc on `proofs/proof_witness.json`) and
breaks the link step.

### Resolution

The enforcement is duplicated at runtime in the lanes that actually execute:

1. `tests/gateway/proof_witness_checker_feature_test.nim` imports the checker
   (without the import the compile-time `static:` block never ran anywhere —
   observed) AND re-reads both artifacts from disk on every test run,
   asserting `witness.lean_version == pin version` through the same exported
   parse helpers.
2. `src/gate/runners/lean_z3_consensus_gate.nim` `checkProofWitness` compares
   the witness `lean_version` against `proofs/lean-toolchain` and fails closed
   on drift.
3. The compile-time check itself remains authoritative for fresh builds
   (CI, clean checkouts): the expected version is DERIVED from the pin —
   no version literal exists in the checker.

## QUIRK(DEBT#427): elan shim pitfall

### Problem

The `canonicalLeanKernelCheck` proc in `src/verification/obligation/lean_kernel_boundary.nim`
previously had two determinism bugs:

1. **Wrong binary hashed for `executableDigest`**: The code resolved `findExe("lake")` and
   hashed the **lake** binary, not the **lean** kernel binary that actually performs
   verification. Two runs with the same lake binary but different lean toolchains would
   produce identical `executableDigest` values despite different kernel behavior.

2. **Hardcoded toolchain fingerprint**: The `toolchainFingerprint` was computed as
   `sha256("nim-2.2.10|lean-4.33.0|<cmd>|<timeout>")` — a hardcoded label that ignores
   the actual binary content and manifest state. Runs claiming the same execution contract
   could produce different kernel observations if the underlying binaries changed.

   **Resolution (2026-10-06)**: `computeBundleDigest`
   (`src/verification/obligation/lean_kernel_boundary.nim`) now MEASURES the
   composition — `nim-` & `$NimVersion` (the compiler that built the binary), the
   lean pin parsed from the actual manifest content, the hermetic Z3 version,
   `hostPlatformId`, `$sizeof(int)`, and the content digests of the four lowering
   modules (`evaluationImplementationDigest`) — and never fabricates a label:
   an unmeasurable component yields `""` and fails the binding closed. The
   composition is normative in `docs/spec/obligation_semantics.md` §2.1a.

### Root Cause: elan shim layout

The elan toolchain manager installs shims in `~/.elan/bin/`:

- `~/.elan/bin/lean` → symlink → `~/.elan/toolchains/leanprover--lean4---v4.29.0/bin/lean`
  (Lean 4.29.0 — the **wrong** version for this project)
- `~/.elan/bin/lake` → real lake 4.33.0 binary

The **real** lean kernel that `lake env lean` invokes is resolved through the project's
`lean-toolchain` pin (`leanprover/lean4:v4.33.0`):

- `~/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean` (Lean 4.33.0)

Bare `findExe("lean")` or the PATH `lean` resolves to the 4.29 shim, not the 4.33
kernel that `lake env lean` actually uses.

### Resolution (Phase 1)

The fix binds the fingerprint to **measured content** instead of hardcoded labels:

1. **Real lean binary resolution**: `resolveLeanBinaryPath()` prefers `lake env which lean`
   (which queries the lake environment and returns the correct toolchain binary), then
   falls back to `elan which lean`, and finally to `dirname(findExe lake)/lean`. It never
   uses the bare PATH `lean` which may be the wrong shim.

2. **Measured bundle digest**: `computeBundleDigest()` computes a SHA-256 that binds:
   - The resolved lean kernel binary content
   - The resolved lake binary content
   - `lean-toolchain` content (root + proofs/)
   - `lake-manifest.json` content (root + proofs/)
   - `lakefile.toml` content

3. **`executableDigest`** now hashes the real lean kernel binary (not the lake binary).

4. **`toolchainFingerprint`** now includes the measured content hashes, making it
   deterministic and content-addressed.

### Why `readFile` resolves symlinks correctly

Nim's `readFile` follows symlinks — it reads the content of the target file, not the
symlink itself. So even if `lake env which lean` returns a path through symlinks,
`readFile` will hash the real binary content.

### References

- `src/verification/obligation/lean_kernel_boundary.nim` — the fixed proc
- `data/debt_registry.json` — DEBT#427 entry
- `AGENTS.md` §0.5c — QUIRK marker convention
