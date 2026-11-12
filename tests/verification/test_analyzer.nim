## Tests for verification/analyzer.nim — Tier 1 hotspot module.
##
## Covers the exported `verifyCertificates` orchestrator proc:
##   - Non-existent certDir → blocking failure with missingCertificates=1
##   - Empty certDir → pipeline completes with zero trusted functions
##   - Parameter forwarding (enableSymbolic, srcRootOverride, freezeGraphCache)
##   - Report structure validity (generatedAt, certDir populated)
##
## §0.7 scope: business scenarios only. Pipeline internals tested in
## analyzer_pipeline_contract_test.nim.
## DEBT#012 — solver/analyzer test coverage.

import std/[unittest, os, strutils, times]
import verification/analyzer
import core/types/verification_types

# ═══════════════════════════════════════════════════════════════════════════════
# Test helpers
# ═══════════════════════════════════════════════════════════════════════════════

proc makeTempCertDir(): string =
  ## Create a temporary directory for certificate testing.
  let base = getTempDir() / "axiom_analyzer_test_" & $epochTime().int
  createDir(base)
  base

# ═══════════════════════════════════════════════════════════════════════════════
# Suite 1: Non-existent certDir → blocking failure
# ═══════════════════════════════════════════════════════════════════════════════

suite "verifyCertificates — missing certDir":
  test "non-existent path returns blockingFailure=true":
    let report = verifyCertificates("/tmp/axiom_nonexistent_xyz_98765")
    check report.blockingFailure == true

  test "non-existent path sets missingCertificates=1":
    let report = verifyCertificates("/tmp/axiom_nonexistent_xyz_98765")
    check report.missingCertificates == 1

  test "non-existent path does not set other failure flags":
    let report = verifyCertificates("/tmp/axiom_nonexistent_xyz_98765")
    check report.mismatchedFingerprints == 0
    check report.cycleDetected == false

  test "non-existent path returns zero trusted functions":
    let report = verifyCertificates("/tmp/axiom_nonexistent_xyz_98765")
    check report.totalTrustedFunctions == 0

# ═══════════════════════════════════════════════════════════════════════════════
# Suite 2: Empty certDir → pipeline completes gracefully
# ═══════════════════════════════════════════════════════════════════════════════

suite "verifyCertificates — empty certDir":
  test "empty directory pipeline completes without exception":
    let dir = makeTempCertDir()
    try:
      # Pipeline runs all 14 stages; empty dir must not crash
      let report = verifyCertificates(dir)
      # Report is returned (non-crash means success)
      check report.generatedAt.len > 0
    finally:
      removeDir(dir)

  test "empty directory returns non-negative counter fields":
    let dir = makeTempCertDir()
    try:
      let report = verifyCertificates(dir)
      # Pipeline may discover state from project vault; counters must be sane
      check report.totalTrustedFunctions >= 0
      check report.verifiedFunctions >= 0
      check report.redFunctions >= 0
      check report.pendingFunctions >= 0
    finally:
      removeDir(dir)

  test "empty directory returns valid generatedAt timestamp":
    let dir = makeTempCertDir()
    try:
      let report = verifyCertificates(dir)
      # generatedAt should be a non-empty ISO timestamp set by the pipeline
      check report.generatedAt.len > 0
      check 'T' in report.generatedAt
    finally:
      removeDir(dir)

# ═══════════════════════════════════════════════════════════════════════════════
# Suite 3: Parameter forwarding
# ═══════════════════════════════════════════════════════════════════════════════

suite "verifyCertificates — parameter forwarding":
  test "enableSymbolic=false (default) completes without error":
    let dir = makeTempCertDir()
    try:
      let report = verifyCertificates(dir, enableSymbolic = false)
      # Should complete; no crash means parameter was accepted
      check report.generatedAt.len > 0
    finally:
      removeDir(dir)

  test "enableSymbolic=true completes without error":
    let dir = makeTempCertDir()
    try:
      let report = verifyCertificates(dir, enableSymbolic = true)
      check report.generatedAt.len > 0
    finally:
      removeDir(dir)

  test "freezeGraphCache=true completes without error":
    let dir = makeTempCertDir()
    try:
      let report = verifyCertificates(dir, freezeGraphCache = true)
      check report.generatedAt.len > 0
    finally:
      removeDir(dir)

  test "srcRootOverride with non-existent path completes":
    # Non-existent srcRoot should not crash — stages handle missing src gracefully
    let dir = makeTempCertDir()
    try:
      let report = verifyCertificates(dir, srcRootOverride = "/tmp/axiom_nonexistent_src")
      check report.generatedAt.len > 0
    finally:
      removeDir(dir)

  test "all parameters combined completes without error":
    let dir = makeTempCertDir()
    try:
      let report = verifyCertificates(
        dir,
        enableSymbolic = true,
        srcRootOverride = "/tmp/axiom_test_src",
        freezeGraphCache = true
      )
      check report.generatedAt.len > 0
    finally:
      removeDir(dir)

# ═══════════════════════════════════════════════════════════════════════════════
# Suite 4: Report structure validity
# ═══════════════════════════════════════════════════════════════════════════════

suite "verifyCertificates — report structure":
  test "report counters are non-negative for empty dir":
    let dir = makeTempCertDir()
    try:
      let report = verifyCertificates(dir)
      check report.verifiedFunctions >= 0
      check report.redFunctions >= 0
      check report.pendingFunctions >= 0
      check report.formalProofFunctions >= 0
      check report.yellowFunctions >= 0
      check report.staleFunctions >= 0
      check report.pseudoVerifiedFunctions >= 0
      check report.verifiedAxiomFunctions >= 0
    finally:
      removeDir(dir)

  test "certificates seq is empty for empty dir":
    let dir = makeTempCertDir()
    try:
      let report = verifyCertificates(dir)
      check report.certificates.len == 0
    finally:
      removeDir(dir)

  test "cycleDetected is false for empty dir":
    let dir = makeTempCertDir()
    try:
      let report = verifyCertificates(dir)
      check report.cycleDetected == false
      check report.cyclicFunctions.len == 0
    finally:
      removeDir(dir)

  test "index values are non-negative for empty dir":
    let dir = makeTempCertDir()
    try:
      let report = verifyCertificates(dir)
      check report.architectureStabilityIndex >= 0.0
      check report.formalProofIntegrityIndex >= 0.0
      check report.axiomaticIntegrityIndex >= 0.0
      check report.averageRetryCount >= 0.0
    finally:
      removeDir(dir)
