## Axiom Gate Memo — Build Environment Hash Computation
## Extracted from gate_memo.nim for readability.
##
## Provides split build-env hashing (code vs env vars) with thread-local caching.
## computeBuildEnvHash combines both in original interleaved order for backward compat.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/os
import std/osproc
import std/strutils
import checksums/sha2
import core/trusted/env_access
import core/axiom_pragmas

# =============================================================================
# Split Build Environment Hash Cache
# =============================================================================
# The build environment hash is split into code-related and env-var components
# for selective cache invalidation. computeBuildEnvHash combines both in the
# original interleaved order for backward compatibility (identical output).
#
# Previously computeBuildEnvHash() called execProcess("nim dumpConfig") on EVERY
# invocation — O(N) subprocess spawns across N gate cache checks. Now: compute
# once at first call, cache in thread-local storage for the process lifetime.
# Uses runtime hashing (not staticExec) to avoid host-dependency staleness:
# the hash reflects the ACTUAL runtime environment, not the compile-time host.
# =============================================================================

type
  BuildEnvPart* = tuple[category: string, hash: string]

var cachedBuildEnvParts {.threadvar.}: seq[BuildEnvPart]
var buildEnvPartsCacheValid {.threadvar.}: bool

var cachedCodeHash {.threadvar.}: string
var codeHashCacheValid {.threadvar.}: bool

var cachedEnvVarHash {.threadvar.}: string
var envVarCacheValid {.threadvar.}: bool

var cachedBuildEnvHash {.threadvar.}: string
var buildEnvCacheValid {.threadvar.}: bool

var cachedToolchainSalt {.threadvar.}: string
var toolchainSaltValid {.threadvar.}: bool

# ---------------------------------------------------------------------------
# Internal: compute all hash parts in original interleaved order (cached)
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc ensureBuildEnvPartsComputed(repoRoot: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute all build environment hash parts in the original interleaved order.
  ## Results are tagged by category ("code" or "env") and cached for sub-function use.
  if buildEnvPartsCacheValid:
    return
  var parts: seq[BuildEnvPart] = @[]
  # Code-related: config files, compiler identity, platform
  let configNimsPath = repoRoot / "config.nims"
  if fileExists(configNimsPath):
    parts.add(("code", $secureHash(Sha_256, readFile(configNimsPath))))
  let nimblePath = repoRoot / "axiom.nimble"
  if fileExists(nimblePath):
    parts.add(("code", $secureHash(Sha_256, readFile(nimblePath))))
  # REMOVED: architecture_debt.json — project-level data file that changes
  # frequently but does not affect gate execution logic. Including it in
  # buildEnvHash caused unnecessary global cache invalidation (58 gates).
  parts.add(("code", $secureHash(Sha_256, NimVersion)))
  parts.add(("code", $secureHash(Sha_256, hostOS)))
  parts.add(("code", $secureHash(Sha_256, hostCPU)))
  # Phase 4 CAS hardening: OS identity (replaces compile-time gorge("uname -r"))
  parts.add(("code", $secureHash(Sha_256, hostOS & "-" & hostCPU)))
  # Phase 4 CAS hardening: runtime env vars that affect gate execution
  let axiomJobs = getAxiomEnv(evJobs, "0")
  parts.add(("env", $secureHash(Sha_256, axiomJobs)))
  let axiomTimeoutSla = getAxiomEnv(evTimeoutSla)
  parts.add(("env", $secureHash(Sha_256, axiomTimeoutSla)))
  let axiomGateBond = getAxiomEnv(evGateBond, "0")
  parts.add(("env", $secureHash(Sha_256, axiomGateBond)))
  # Phase 5 hermetic: nim --version captures compiler identity (replaces dumpConfig subprocess).
  # dumpConfig was O(N) per gate; nim --version is ~10ms once. Compile flags are captured
  # via config.nims hash above, making dumpConfig redundant for cache invalidation.
  let nimExe = findExe("nim")
  if nimExe.len > 0:
    let nimVersionOutput = execProcess(nimExe & " --version 2>&1 | head -1")
    parts.add(("code", $secureHash(Sha_256, nimVersionOutput.strip())))
    # Nim stdlib hash (stdlib updates change runtime behavior)
    let libPath = nimExe.parentDir() / "lib" / "system.nim"
    if fileExists(libPath):
      parts.add(("code", $secureHash(Sha_256, readFile(libPath))))
    else:
      parts.add(("code", $secureHash(Sha_256, "no-lib")))
  else:
    parts.add(("code", $secureHash(Sha_256, "no-nim")))
  cachedBuildEnvParts = parts
  buildEnvPartsCacheValid = true

# ---------------------------------------------------------------------------
# Public: split hash functions
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeCodeHash*(repoRoot: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 of code-related build environment parts only.
  ## Includes: config.nims, axiom.nimble, NimVersion, hostOS, hostCPU,
  ## nim --version, system.nim. Cached at runtime.
  if codeHashCacheValid:
    return cachedCodeHash
  ensureBuildEnvPartsComputed(repoRoot)
  var parts: seq[string] = @[]
  for p in cachedBuildEnvParts:
    if p.category == "code":
      parts.add(p.hash)
  cachedCodeHash = $secureHash(Sha_256, parts.join(""))
  codeHashCacheValid = true
  cachedCodeHash

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeEnvVarHash*(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 of environment variable parts only.
  ## Includes: AXIOM_JOBS, AXIOM_TIMEOUT_SLA, AXIOM_GATE_BOND. Cached at runtime.
  if envVarCacheValid:
    return cachedEnvVarHash
  ensureBuildEnvPartsComputed("")
  var parts: seq[string] = @[]
  for p in cachedBuildEnvParts:
    if p.category == "env":
      parts.add(p.hash)
  cachedEnvVarHash = $secureHash(Sha_256, parts.join(""))
  envVarCacheValid = true
  cachedEnvVarHash

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeToolchainSalt*(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute a toolchain salt for cache layout versioning.
  ## Includes schema version to force cache invalidation on layout changes.
  ## Cached at runtime — first call computes, subsequent calls return cached result.
  if toolchainSaltValid:
    return cachedToolchainSalt
  let schemaVer = "v2"
  let nimExe = findExe("nim")
  let nimVer = if nimExe.len > 0:
    execProcess(nimExe & " --version 2>&1 | head -1").strip()
  else:
    "no-nim"
  cachedToolchainSalt = $secureHash(Sha_256, schemaVer & nimVer)
  toolchainSaltValid = true
  cachedToolchainSalt

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeBuildEnvHash*(repoRoot: string): string {.raises: [].}=
  ## Compute SHA-256 of build environment. Cached at runtime — first call computes,
  ## subsequent calls return cached result (zero overhead).
  ## Backward compatible: identical output to pre-split version.
  ## Internally delegates to ensureBuildEnvPartsComputed and combines code + env parts.
  if buildEnvCacheValid:
    return cachedBuildEnvHash
  ensureBuildEnvPartsComputed(repoRoot)
  # Original interleaved order for backward compatibility
  var parts: seq[string] = @[]
  for p in cachedBuildEnvParts:
    parts.add(p.hash)
  cachedBuildEnvHash = $secureHash(Sha_256, parts.join(""))
  buildEnvCacheValid = true
  cachedBuildEnvHash

