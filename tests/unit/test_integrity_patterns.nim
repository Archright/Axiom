## Unit tests for src/core/debt/integrity_patterns.nim
##
## Validates: keyword→pattern mapping, policy verdict logic,
## and DebtObservation conversion. No Debt objects are created here.

import std/unittest
import core/debt/integrity_patterns
import core/types/debt_types

suite "IntegrityPatterns - detectIntegrityPatterns":

  test "bypass keyword maps to oipBypass":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  bypass the gate check"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    check obs[0].pattern == oipBypass
    check obs[0].semanticIdentity == "oipBypass"

  test "fallback keyword maps to oipFallback":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  use fallback solver"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    check obs[0].pattern == oipFallback
    check obs[0].semanticIdentity == "oipFallback"

  test "AXIOM_BYPASS keyword maps to oipBypass":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  AXIOM_BYPASS emergency override"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    check obs[0].pattern == oipBypass

  test "EMERGENCY_NO_VERIFY keyword maps to oipBypass":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  EMERGENCY_NO_VERIFY bypass"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    check obs[0].pattern == oipBypass

  test "skipped keyword maps to oipSkip":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  this test is skipped"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    check obs[0].pattern == oipSkip

  test "exemption keyword maps to oipExemption":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  certified exempt from this check"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    check obs[0].pattern == oipExemption

  test "manual_override keyword maps to oipManualOverride":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  manual_override applied"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    check obs[0].pattern == oipManualOverride

  test "uncertified keyword maps to oipUncertifiedPath":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  uncertified path taken"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    check obs[0].pattern == oipUncertifiedPath

  test "noncanonical keyword maps to oipNonCanonical":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  noncanonical format used"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    check obs[0].pattern == oipNonCanonical

  test "best-effort keyword maps to oipUncertifiedPath":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  best-effort execution"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    check obs[0].pattern == oipUncertifiedPath

  test "shadow execution keyword maps to oipUncertifiedPath":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  shadow execution mode"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    check obs[0].pattern == oipUncertifiedPath

  test "no match on clean line":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  this is a normal line of code"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 0

  test "comment lines are stripped and bypass keyword in comment is ignored":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "# bypass this comment\n  normal code"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 0

  test "empty lines are skipped":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "\n\n  fallback\n\n"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    check obs[0].pattern == oipFallback

suite "IntegrityPatterns - evaluateIntegrityPolicy":

  test "hard bypass + no evidence → ipvUnverified (no evidence to judge)":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  bypass the gate"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    let eval = evaluateIntegrityPolicy(obs[0], declared = false, assuranceTier = "", evidenceIds = @[])
    check eval.verdict == ipvUnverified

  test "hard bypass + undeclared + evidence → ipvViolation":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  bypass the gate"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    let eval = evaluateIntegrityPolicy(obs[0], declared = false, assuranceTier = "", evidenceIds = @["ev-001"])
    check eval.verdict == ipvViolation

  test "hard bypass + declared → ipvAcceptable":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  bypass the gate"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    let eval = evaluateIntegrityPolicy(obs[0], declared = true, assuranceTier = "high", evidenceIds = @["ev-001"])
    check eval.verdict == ipvAcceptable

  test "declared with token acceptance → ipvAcceptable":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  fallback to legacy path"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    let eval = evaluateIntegrityPolicy(obs[0], declared = true, assuranceTier = "critical", evidenceIds = @["ev-001"])
    check eval.verdict == ipvAcceptable

  test "no evidence → ipvUnverified":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  bypass the gate"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    let eval = evaluateIntegrityPolicy(obs[0], declared = false, assuranceTier = "", evidenceIds = @[])
    check eval.verdict == ipvUnverified

  test "warning fallback for undeclared non-hard pattern":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  noncanonical format used"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    let eval = evaluateIntegrityPolicy(obs[0], declared = false, assuranceTier = "", evidenceIds = @["ev-001"])
    check eval.verdict == ipvWarning

suite "IntegrityPatterns - toDebtObservation":

  test "toDebtObservation maps to okAstPattern kind":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  bypass the gate"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    let debtObs = toDebtObservation(obs[0], "snap-001", "2026-08-15T13:32:08Z", "nim-2.2.10")
    check debtObs.kind == okAstPattern
    check debtObs.subject == collector.ruleSetHash
    check debtObs.semanticIdentity == "oipBypass"
    check debtObs.snapshotId == "snap-001"
    check debtObs.observedAt == "2026-08-15T13:32:08Z"
    check debtObs.toolchainContext == "nim-2.2.10"

  test "toDebtObservation observationId is a valid sha256Ref":
    let collector = staticCollector("v1", "rulehash-001")
    let source = "  bypass the gate"
    let obs = detectIntegrityPatterns(source, collector)
    check obs.len == 1
    let debtObs = toDebtObservation(obs[0], "snap-001", "2026-08-15T13:32:08Z", "nim-2.2.10")
    check isValidSha256Ref(debtObs.observationId)
