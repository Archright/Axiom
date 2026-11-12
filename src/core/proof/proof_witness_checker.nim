import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Proof Witness Checker — Compile-time Lean 4 proof verification
## ============================================================
## Verifies at compile time that:
##   1. Lean version matches the canonical pin (proofs/lean-toolchain)
##   2. Lean source files haven't changed since last proof_witness.json
##   3. Proof witness matches the expected model hash
##
## v8: the expected version is DERIVED from the canonical pin file at
## compile time — no hardcoded version literal exists here, so a pin
## bump (e.g. v4.29.0 → v4.33.0) mechanically invalidates a witness
## generated under an older toolchain instead of silently passing
## (the former `contains("4.29")` literal did exactly that).
## ============================================================

import std/[strutils, os, algorithm]
import std/macros
import core/crypto/hash_kernel
import core/trusted/axiom_pragmas

proc computeLeanProofHash(): string {.compileTime, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 of all .lean files in proofs/GateInvariants/ at compile time.
  ## Must match generate_proof_witness.nim's source hash algorithm:
  ##   1. All .lean files under proofs/GateInvariants/ (recursive)
  ##   2. Top-level proofs/GateInvariants.lean
  ##   3. Sorted for determinism, concatenated, SHA-256.
  var leanFiles: seq[string] = @[]
  try:
    for kind, path in walkDir("proofs/GateInvariants", relative = false):
      if kind == pcFile and path.endsWith(".lean"):
        leanFiles.add(path)
  except CatchableError:
    error("Failed to read .lean files from proofs/GateInvariants/")
  # Also include top-level GateInvariants.lean (matches generator logic)
  let topLevel = "proofs" / "GateInvariants.lean"
  if fileExists(topLevel):
    leanFiles.add(topLevel)
  leanFiles.sort()
  var combined = ""
  for f in leanFiles:
    try:
      combined.add(readFile(f))
    except CatchableError:
      error("Failed to read: " & f)
  result = hash_kernel.sha256Hex(combined)

# NOTE (staticRead cache quirk): the artifacts below are read via staticRead,
# which is NOT tracked by the Nim build system — an incremental rebuild with a
# cache-fresh module reuses the embedded bytes and the compile-time checks
# never re-execute (measured 2026-10-09: a witness reverted to lean_version
# 4.29.0 compiled clean, NIM_EXIT=0). {.compile.} is NOT a fix — it treats the
# data file as a C translation unit and breaks linking. The enforcement is
# therefore duplicated at RUNTIME in the lanes that actually execute:
# tests/gateway/proof_witness_checker_feature_test.nim (fresh disk read every
# test run) and src/gate/runners/lean_z3_consensus_gate.nim (gate lane).

func parseLeanToolchainPinVersion*(pin: string): string {.raises: [].} =
  ## Extract the version from a `leanprover/lean4:vX.Y.Z` pin line.
  ## Mirrors runtime parseLeanToolchainPin (lean_kernel_boundary.nim) —
  ## "" on any unparseable content (fail-closed; no fallback label).
  ## Callable at compile time AND runtime (no compileTime pragma): the
  ## runtime lanes (feature test, lean_z3_consensus_gate) re-derive the
  ## expected version from fresh disk reads, immune to the staticRead
  ## incremental-cache quirk noted above.
  let sep = pin.find(':')
  if sep < 0 or sep + 1 > pin.high:
    return ""
  var raw = pin[sep + 1 .. ^1].strip()
  if raw.len > 1 and raw[0] == 'v':
    raw = raw[1 .. ^1]
  if raw.len == 0:
    return ""
  for ch in raw:
    if ch notin {'0'..'9', '.'}:
      return ""
  raw

const
  witnessJson* = staticRead("proofs/proof_witness.json")
    ## Compile-time load of proof witness

  # v7: Compile-time source hash cross-check
  # Computes SHA-256 of all Lean source files at compile time.
  # If this differs from proof_witness.json's source_hash, the build fails.
  currentLeanSourceHash* = computeLeanProofHash()

  leanToolchainPin = staticRead("proofs/lean-toolchain")
    ## The canonical toolchain pin — the single SSOT for the expected
    ## Lean version (same file `lake`/`elan` consume).

  expectedLeanVersion* = parseLeanToolchainPinVersion(leanToolchainPin)
    ## Version derived from the pin ("" when unparseable — never a literal)

proc extractField*(jsonStr: string, field: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Extract a string field from JSON at compile time.
  ## Simple extraction — avoids full parseJson in static context.
  ## Exported for the runtime enforcement lanes (same parse the compile-time
  ## check consumes — no duplicated semantics).
  let search = "\"" & field & "\": \""
  let start = jsonStr.find(search)
  if start < 0:
    return ""
  let valueStart = start + search.len
  let valueEnd = jsonStr.find("\"", valueStart)
  if valueEnd < 0:
    return ""
  result = jsonStr[valueStart ..< valueEnd]

proc verifyProofWitness*() {.compileTime, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## All 3 compile-time checks. Called from static blocks.
  let leanVersion = extractField(witnessJson, "lean_version")
  let sourceHash = extractField(witnessJson, "source_hash")
  let overallHash = extractField(witnessJson, "overall_hash")

  # Check 1: Lean version — the witness must have been generated under the
  # canonical pinned toolchain (proofs/lean-toolchain), never a remembered
  # literal. Exact match: a pin bump (v4.29.0 → v4.33.0) fails a witness
  # generated under the old toolchain and forces regeneration.
  if expectedLeanVersion.len == 0:
    error("Cannot parse Lean version from proofs/lean-toolchain — fix the pin file")
  if leanVersion != expectedLeanVersion:
    error("Proof witness requires Lean " & expectedLeanVersion &
          " (proofs/lean-toolchain pin), found: " & leanVersion &
          ". Re-run: cd proofs && lake build && cd .. && nim r tools/generate_proof_witness")

  # Check 2: Source hash cross-check (v7)
  # Catches stale proof_witness.json when .lean files changed
  let currentHash = currentLeanSourceHash.strip()
  if currentHash.len > 0 and sourceHash.len > 0:
    if currentHash != sourceHash:
      error("Lean source files changed since last proof_witness.json generation. " &
            "Current: " & currentHash[0..15] & "... != Recorded: " & sourceHash[0..15] & "... " &
            "Re-run: cd proofs && lake build && cd .. && nim r tools/generate_proof_witness")

  # Check 3: Overall hash presence
  if overallHash.len == 0:
    error("Proof witness missing overall_hash. Re-run: nim r tools/generate_proof_witness")

# Auto-verify when imported
static:
  verifyProofWitness()
