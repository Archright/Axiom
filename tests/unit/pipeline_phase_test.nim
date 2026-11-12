## pipeline_phase_test.nim
## Semantic assertion tests for pipeline_phase.nim — the phase tagged union.
##
## Coverage:
##   - All 7 PipelinePhaseKind variants via constructors and direct construction
##   - kind() accessor for every variant
##   - Field accessors: swatArt, detCtx, detected, legislated, scribed, judged
##   - Round-trip: construct → kind() → accessor → field verification
##   - hash() determinism and discrimination
##   - fingerprint() determinism

import std/[unittest, hashes]
import verification/pipeline_phase
import verification/pipeline_state_types
import core/types/domain_types
import core/types/pipeline_core_types
import core/boundary/persona_interface

# ─── pkInit (no payload) ─────────────────────────────────────────────────────

suite "PipelinePhase — pkInit":

  test "direct construction produces pkInit":
    let p = PipelinePhase(kind: pkInit)
    check p.kind() == pkInit

  test "pkInit has no variant payload":
    let p = PipelinePhase(kind: pkInit)
    # Accessing the kind is the only valid operation; no payload to check.
    check p.kind() == pkInit

# ─── pkSwatReady ─────────────────────────────────────────────────────────────

suite "PipelinePhase — pkSwatReady":

  test "toSwatReadyPhase produces pkSwatReady":
    let art = default(SwatArtifact)
    let p = toSwatReadyPhase(art)
    check p.kind() == pkSwatReady

  test "swatArt accessor round-trip":
    var art = default(SwatArtifact)
    art.healedSource = "func safe(): int = 42"
    art.sourceChecksum = "abc123"
    let p = toSwatReadyPhase(art)
    check p.swatArt().healedSource == "func safe(): int = 42"
    check p.swatArt().sourceChecksum == "abc123"

  test "swatArt logLines round-trip":
    var art = default(SwatArtifact)
    art.logLines = @["line1", "line2", "line3"]
    let p = toSwatReadyPhase(art)
    check p.swatArt().logLines.len == 3
    check p.swatArt().logLines[0] == "line1"
    check p.swatArt().logLines[2] == "line3"

# ─── pkDetectiveReady ────────────────────────────────────────────────────────

suite "PipelinePhase — pkDetectiveReady":

  test "toDetectiveReadyPhase produces pkDetectiveReady":
    let ctx = default(DetectiveContext)
    let p = toDetectiveReadyPhase(ctx)
    check p.kind() == pkDetectiveReady

  test "detCtx accessor round-trip":
    let ctx = default(DetectiveContext)
    let p = toDetectiveReadyPhase(ctx)
    check p.detCtx().detectiveInput.cegarCounterexample == false

# ─── pkLegislatorReady ───────────────────────────────────────────────────────

suite "PipelinePhase — pkLegislatorReady":

  test "toLegislatorReadyPhase produces pkLegislatorReady":
    let det = default(DetectedState)
    let p = toLegislatorReadyPhase(det)
    check p.kind() == pkLegislatorReady

  test "detected accessor round-trip":
    var det = default(DetectedState)
    det.cegarCounterexample = true
    det.unsatCoreVars = @["x", "y"]
    let p = toLegislatorReadyPhase(det)
    check p.detected().cegarCounterexample == true
    check p.detected().unsatCoreVars == @["x", "y"]

# ─── pkScribeReady ───────────────────────────────────────────────────────────

suite "PipelinePhase — pkScribeReady":

  test "toScribeReadyPhase produces pkScribeReady":
    let leg = default(LegislatedState)
    let p = toScribeReadyPhase(leg)
    check p.kind() == pkScribeReady

  test "legislated accessor round-trip":
    var leg = default(LegislatedState)
    leg.activeInvariant = "∀ x, x >= 0"
    leg.baselineInvariant = "true"
    leg.healedSource = "func f(): int = 0"
    let p = toScribeReadyPhase(leg)
    check p.legislated().activeInvariant == "∀ x, x >= 0"
    check p.legislated().baselineInvariant == "true"
    check p.legislated().healedSource == "func f(): int = 0"

# ─── pkJudgeReady ────────────────────────────────────────────────────────────

suite "PipelinePhase — pkJudgeReady":

  test "toJudgeReadyPhase produces pkJudgeReady":
    let scr = default(ScribedState)
    let p = toJudgeReadyPhase(scr)
    check p.kind() == pkJudgeReady

  test "scribed accessor round-trip":
    var scr = default(ScribedState)
    scr.verified = true
    scr.theoremSource = "theorem safe : True := trivial"
    scr.tacticTrace = "intro; rfl"
    let p = toJudgeReadyPhase(scr)
    check p.scribed().verified == true
    check p.scribed().theoremSource == "theorem safe : True := trivial"
    check p.scribed().tacticTrace == "intro; rfl"

# ─── pkPostProcessReady ──────────────────────────────────────────────────────

suite "PipelinePhase — pkPostProcessReady":

  test "toPostProcessReadyPhase produces pkPostProcessReady":
    let judged = default(JudgedState)
    let p = toPostProcessReadyPhase(judged)
    check p.kind() == pkPostProcessReady

  test "judged accessor round-trip":
    var judged = default(JudgedState)
    judged.leanKernelVerified = true
    judged.proofDepth = 5
    judged.finalInvariant = "x > 0"
    judged.finalSource = "theorem..."
    judged.nearestDiagnostic = ""
    judged.failedReplayAttempts = 0
    let p = toPostProcessReadyPhase(judged)
    check p.judged().leanKernelVerified == true
    check p.judged().proofDepth == 5
    check p.judged().finalInvariant == "x > 0"
    check p.judged().finalSource == "theorem..."
    check p.judged().failedReplayAttempts == 0

# ─── Cross-cutting: all kinds are mutually exclusive ─────────────────────────

suite "PipelinePhase — kind discrimination":

  test "each constructor produces a distinct kind":
    let phases = [
      PipelinePhase(kind: pkInit),
      toSwatReadyPhase(default(SwatArtifact)),
      toDetectiveReadyPhase(default(DetectiveContext)),
      toLegislatorReadyPhase(default(DetectedState)),
      toScribeReadyPhase(default(LegislatedState)),
      toJudgeReadyPhase(default(ScribedState)),
      toPostProcessReadyPhase(default(JudgedState)),
    ]
    # All 7 kinds must be unique
    var kinds: set[PipelinePhaseKind] = {}
    for p in phases:
      check p.kind() notin kinds
      kinds.incl(p.kind())
    check kinds == {pkInit, pkSwatReady, pkDetectiveReady, pkLegislatorReady,
                    pkScribeReady, pkJudgeReady, pkPostProcessReady}

  test "kind() accessor matches the discriminator field directly":
    let p = toSwatReadyPhase(default(SwatArtifact))
    check p.kind == pkSwatReady  # direct field access
    check p.kind() == pkSwatReady  # accessor func

# ─── hash / fingerprint ──────────────────────────────────────────────────────

suite "PipelinePhase — hash and fingerprint":

  test "hash is deterministic for same phase":
    let p1 = PipelinePhase(kind: pkInit)
    let p2 = PipelinePhase(kind: pkInit)
    check hash(p1) == hash(p2)

  test "hash discriminates different kinds":
    let initPhase = PipelinePhase(kind: pkInit)
    let swatPhase = toSwatReadyPhase(default(SwatArtifact))
    check hash(initPhase) != hash(swatPhase)

  test "hash discriminates same kind with different payload":
    var a1 = default(SwatArtifact)
    a1.healedSource = "version A"
    var a2 = default(SwatArtifact)
    a2.healedSource = "version B"
    # SwatArtifact.logLines.len is used in hash — both have 0 logLines
    # so we add log lines to create different hashes
    a1.logLines = @["a"]
    a2.logLines = @["a", "b"]
    let p1 = toSwatReadyPhase(a1)
    let p2 = toSwatReadyPhase(a2)
    check hash(p1) != hash(p2)

  test "fingerprint is deterministic for same phase":
    let p1 = PipelinePhase(kind: pkInit)
    let p2 = PipelinePhase(kind: pkInit)
    check fingerprint(p1) == fingerprint(p2)

  test "fingerprint differs for different kinds":
    let initPhase = PipelinePhase(kind: pkInit)
    let swatPhase = toSwatReadyPhase(default(SwatArtifact))
    check fingerprint(initPhase) != fingerprint(swatPhase)

  test "fingerprint is decimal string representation of hash":
    let p = PipelinePhase(kind: pkInit)
    let fp = fingerprint(p)
    # fingerprint returns $hash(p), which is a decimal string
    check fp.len > 0
    check fp == $hash(p)
