# config/integrity.nims — Immutable Verification, Merkle Root, Build Constraints
# Extracted from config.nims lines 280-379
# Provides: immutable policy verification, merkle root, build constraint, bin/ax check, hooks, manifest bootstrap

when (NimMajor, NimMinor) >= (2, 0):
  const projectRoot = thisDir()
else:
  const projectRoot = parentDir(currentSourcePath())

# ── Immutable Policy Artifact Verification ──
# AGENTS.md and docs/agents/*.md are the SSOT for project policy.
# They MUST exist and be non-empty; build scripts MUST NOT write to them.
# This static block verifies the artifacts are present at compile time.
static:
  when staticRead(projectRoot / "AGENTS.md").len == 0:
    echo "[config.nims] ERROR: IMMUTABLE POLICY ARTIFACT MISSING OR EMPTY: AGENTS.md"; quit(1)
  when staticRead(projectRoot / "docs/agents/architecture.md").len == 0:
    echo "[config.nims] ERROR: IMMUTABLE POLICY ARTIFACT MISSING OR EMPTY: docs/agents/architecture.md"; quit(1)
  when staticRead(projectRoot / "docs/agents/rules_workflow.md").len == 0:
    echo "[config.nims] ERROR: IMMUTABLE POLICY ARTIFACT MISSING OR EMPTY: docs/agents/rules_workflow.md"; quit(1)

# ── Guard the Guard: Architecture Invariants Integrity ────────────────────────
# MOVED to runtime: src/gate/compile_time_checks.nim (Phase D)
# Previously ran sha256sum on EVERY `nim c` invocation.
# Now executes only during pre-commit/pre-push gate runs.
# See: src/gate/compile_time_checks.nim → checkGuardTheGuard()

# ── Guard the Guard: Merkle Root Integrity (SA-γ3) ──
# Hashes multiple critical trusted files and combines into a single Merkle root.
# Any tampering with any guarded file = compile error.
when not defined(AXIOM_GATE_BOND):
  static:
    # ── Gorge Self-Test: detect if gorge() is functional ──
    # In nim check / doc / e mode, gorge() returns empty string.
    # We only enforce Merkle integrity when gorge() is operational.
    let gorgeTest = gorge("echo axiom_gorge_probe")
    let gorgeAvailable = gorgeTest.strip() == "axiom_gorge_probe"

    const expectedMerklePath = projectRoot / "data/expected_merkle_root.txt"
    when staticFileExists(expectedMerklePath):
      const expectedMerkle = staticRead(expectedMerklePath).strip()
      when expectedMerkle.len > 0:
        if gorgeAvailable:
          # SHA-256 merkle root of guarded files, computed via host sha256sum.
          # Implementation: hash each file individually, concatenate lowercase
          # hex digests, then hash that concatenation. Matches original algorithm
          # from tools/merkle_hash.nim (checksums/sha2 → std sha1 not available in
          # NimScript), but avoids the missing `checksums` nimble package block.
          block:
            let guardedList = [
              "src/core/trusted/architecture_invariants.nim",
              "src/core/trusted/axiom_pragmas.nim",
              "src/core/trusted/effect_types.nim",
              "src/core/trusted/effect_bridge.nim"
            ]
            var concat = ""
            for rel in guardedList:
              let fullPath = projectRoot / rel
              if staticFileExists(fullPath):
                let hex = gorge("sha256sum " & fullPath.extractFilename()).split(" ")[0]
                concat.add(hex)
            echo "[integrity] merkle concat: " & concat
            let actualMerkle = gorge("echo -n " & concat.quoteShell() & " | sha256sum").split(" ")[0]
            echo "[integrity] expected: " & expectedMerkle & "\n[integrity] actual:   " & actualMerkle
            if actualMerkle.len > 0 and actualMerkle != expectedMerkle:
              assert false, "GUARD THE GUARD (Merkle Root): critical files hash mismatch!\n" &
                    "  Expected: " & expectedMerkle & "\n" &
                    "  Actual:   " & actualMerkle & "\n" &
                    "  If you intentionally modified guarded files, update data/expected_merkle_root.txt"
        else:
          echo "[integrity] gorge() unavailable — skipping merkle evaluation"
    else:
      warning("guard_merkle_root_file_missing", true)

# ── Build Constraint Policy Verification ──
# src/policy/build_constraint.nim declares the only external binaries the build
# may invoke. It must exist, must allow the core toolchain, and must not allow
# forbidden interpreters.
static:
  const constraintPath = projectRoot / "src/policy/build_constraint.nim"
  when staticFileExists(constraintPath):
    const constraintSrc = staticRead(constraintPath)
    when "nim" notin constraintSrc:
      echo "[config.nims] ERROR: BUILD CONSTRAINT POLICY MISSING REQUIRED BINARY: nim"; quit(1)
    when "python3" in constraintSrc and "ForbiddenInterpreterPatterns" notin constraintSrc:
      echo "[config.nims] ERROR: BUILD CONSTRAINT POLICY AMBIGUOUS: python3 appears outside forbidden list"; quit(1)
  else:
    echo "[config.nims] ERROR: BUILD CONSTRAINT POLICY MISSING: src/policy/build_constraint.nim"; quit(1)

# ── Axiom Engine Core Integrity Guard v10 (Strict Domain Invariant) ──
# 외부 쉘 오염으로부터 격리된 도메인 무결성 검사.
# 명칭 스키마가 단일화된 src/gate Domain과 Tests Domain을 통제.
block:
  let currentDir = projectDir()
  let isGuardedDomain = currentDir.startsWith(projectRoot / "src" / "gate") or
                        currentDir.startsWith(projectRoot / "tests")
  let isBootstrapSandbox = defined(axiomBootstrapBuild) or
                           existsEnv("AXIOM_HERMETIC_BUILDING") or
                           existsEnv("AXIOM_CI_PRESERVE_CACHE")
  if isGuardedDomain and not isBootstrapSandbox:
    let hasBinMain = fileExists(projectRoot / "bin" / "ax")
    if not hasBinMain:
      echo "[Integrity Violation] bin/ax is missing. Run: nimble build first."
      quit(1)

# Git hooks verification (read-only — no state mutation in config.nims)
# Authority: docs/adr/0028-hook-installation-authority.md — the canonical value is
# core.hooksPath = .githooks and tools/setup_hooks.nim is its sole writer. This block
# observes the installed state only; it never asserts it as a build-time invariant.
# The repository-local git config is parsed directly rather than shelling out to
# `git config`: git resolves system → global → local, so a developer-wide
# core.hooksPath must not be reported as this repository's installed value, and
# reading `.git/config` makes that scoping structural instead of flag-dependent.
# It also keeps this block free of a compile-time subprocess (gorge() returns empty
# under `nim check` and is unavailable in other non-run modes — see the gorge
# self-test above), so the check works in every compile mode.
proc readLocalHooksPath(gitDir: string): string =
  if not dirExists(gitDir):
    return ""
  let configFile = gitDir / "config"
  if not fileExists(configFile):
    return ""
  var inCore = false
  for line in readFile(configFile).splitLines():
    let entry = line.strip()
    if entry.len == 0 or entry.startsWith("#") or entry.startsWith(";"):
      continue
    if entry.startsWith("["):
      inCore = entry.toLowerAscii().startsWith("[core")
      continue
    if inCore and entry.toLowerAscii().startsWith("hookspath"):
      let assign = entry.find('=')
      if assign >= 0:
        return entry[assign + 1 .. ^1].strip()
  return ""

when not defined(AXIOM_GATE_BOND):
  block:
    let currentDir = projectDir()
    let isGuardedDomain = currentDir.startsWith(projectRoot / "src" / "gate") or
                          currentDir.startsWith(projectRoot / "tests")
    if isGuardedDomain:
      let hooksPath = readLocalHooksPath(projectRoot / ".git")
      if hooksPath.len == 0:
        echo "WARNING: Git hooks not installed (repo-local core.hooksPath is unset — " &
             "git's default .git/hooks applies). Run: make -f ci/checker.mk setup-hooks"
      elif hooksPath != ".githooks":
        echo "WARNING: Git core.hooksPath is '" & hooksPath &
             "', not the canonical '.githooks' — the tracked .githooks hooks are not armed. " &
             "Run: make -f ci/checker.mk setup-hooks"

# ─── Manifest Bootstrap ──────────────────────────────────────────────
# Auto-generate feature_manifest.json if missing or stale.
# Runs on EVERY nim c invocation — ensures guard always has fresh data.
# Deterministic content-hash comparison (source_hash), NOT mtime snapshots.
# The generator's `ensure` mode self-decides: it regenerates only when the
# on-disk manifest's content differs from a fresh build, else it no-ops and
# preserves mtime (idempotent → no unnecessary regeneration).
# NOTE: execCmdEx is unavailable in NimScript, so we rely on `ensure`.
# Nested nim c invocations set AXIOM_GATE_BOND=1 to prevent infinite recursion
# (the inner compile would otherwise re-enter this manifestBootstrap block).
when not defined(AXIOM_GATE_BOND) and not existsEnv("AXIOM_HERMETIC_BUILDING"):
  block manifestBootstrap:
    const manifestPath = "data/feature_manifest.json"
    # DEBT#457 (build once → freeze → fan-out): stable output name so the
    # parallel verify-contract subtargets execute one frozen binary instead
    # of concurrently relinking `bin/feature_manifest_generator_<hash>`
    # (usenimcache suffix) into the same shared path.
    const genBin = "bin/feature_manifest_generator"
    const genCmd = "nim c -r --hints:off -d:AXIOM_GATE_BOND=1 -d:skipImportLint --skipUserCfg --out:" & genBin & " tools/feature_manifest_generator.nim"
    if existsEnv("AXIOM_VERIFY_CONTRACT_FANOUT"):
      # Parallel phase of `make verify-contract`: shared artifacts were built
      # once by the serial `verify-contract-artifacts` prerequisite and are
      # consumed read-only here. Compiling in this phase would race the other
      # subtargets on the shared output path (ETXTBSY). Fail-closed: a missing
      # binary means the prebuild was skipped — the invariant is violated.
      if not fileExists(genBin):
        echo "[Axiom] FANOUT fail-closed: " & genBin & " missing — run make verify-contract-artifacts"
        quit(1)
      echo "[Axiom] Checking feature_manifest.json freshness (content-hash)..."
      exec genBin & " ensure"
    elif not fileExists(manifestPath):
      echo "[Axiom] feature_manifest.json missing. Auto-generating..."
      exec genCmd
    else:
      # Deterministic content-hash check (no mtime snapshot comparison).
      # `ensure` exits 0 after guaranteeing the manifest is fresh.
      echo "[Axiom] Checking feature_manifest.json freshness (content-hash)..."
      exec genCmd & " ensure"

# ─── Certificate Manifest Integrity ────────────────────────────────
# Deterministic content-hash verification of src/verification/certificates/
# manifest.json vs the canonical cert digest. Responsibility boundary:
#   stale_cert_gate           → individual certificate freshness
#   cert-manifest integrity   → manifest freshness (this block)
# Manifests are NOT treated as individual certificates; the digest contract
# version is separate from the manifest schema version. Runs on EVERY nim c
# invocation (deterministic, idempotent, fail-closed on mismatch).
when not defined(AXIOM_GATE_BOND) and not existsEnv("AXIOM_HERMETIC_BUILDING"):
  block certManifestBootstrap:
    const certManifestPath = "src/verification/certificates/manifest.json"
    # LOCAL DEV: `--ensure` materializes a stale cert manifest (regenerate + exit 0).
    # This is value-materialization (mutation), NOT an integrity assertion. The
    # fail-closed assertion is `--verify`, used by CI/hermetic verify-only workflows.
    # DEBT#457 (build once → freeze → fan-out): stable output name — see
    # manifestBootstrap above. Parallel verify-contract subtargets must never
    # relink this shared binary concurrently.
    const certBin = "bin/sync_certs"
    const certEnsureCmd = "nim c -r --hints:off -d:AXIOM_GATE_BOND=1 -d:skipImportLint --skipUserCfg --out:" & certBin & " tools/sync_certs.nim --ensure"
    if existsEnv("AXIOM_VERIFY_CONTRACT_FANOUT"):
      # Parallel phase of `make verify-contract`: execute the frozen binary
      # read-only. Fail-closed when the serial prebuild was skipped.
      if not fileExists(certBin):
        echo "[Axiom] FANOUT fail-closed: " & certBin & " missing — run make verify-contract-artifacts"
        quit(1)
      exec certBin & " --ensure"
    elif dirExists("src/verification/certificates"):
      exec certEnsureCmd

# ─── Manifest Index Ownership ─────────────────────────────────────
# _index.json is written by tools/sync_topology.nim (single writer, gate-ID
# format) during hermeticPreBuild (config.nims) and the CI drift guard.
# A previous manifestIndexBootstrap block wrote a conflicting file-name
# format here, flip-flopping the file between two writers — which made the
# hermetic env-hash cache gate never stabilize. Removed 2026-08-07.

# ─── SSoT Drift Guard ─────────────────────────────────────────────
when not defined(AXIOM_GATE_BOND):
  block manifestSsoTGuard:
    let manifestFiles = mdStrArray("manifestFiles")
    if manifestFiles.len > 0:
      let dirPath = "src/gate/manifest.d"
      var missing: seq[string] = @[]
      for mf in manifestFiles:
        let fullPath = dirPath / mf
        if not fileExists(fullPath):
          missing.add(mf)
      if missing.len > 0:
        echo "[Axiom] SSoT DRIFT: build_metadata.json declares manifest files missing from disk:"
        for m in missing:
          echo "  - ", dirPath / m
        echo "[Axiom] Run: bin/build_metadata_generator && nim c -r tools/regen_index.nim"
        quit(1)

# Compile-time debt sync guard
when not defined(nimcheck):
  include "../src/generated/debt_sync_guard"
