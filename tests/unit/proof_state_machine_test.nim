## Unit tests for proof_state_machine.nim — state machine transitions.
## Uses custom main() pattern to avoid unittest framework cleanup crashes.

import std/[options, strutils]
import core/trusted/axiom_ir_helpers
import verification/obligation/obligation_types
import verification/obligation/obligation_ir
import verification/obligation/no_obligation_provenance
import verification/obligation/proof_state_machine

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  template checkErr(name: string, result: untyped) =
    check(name):
      assert not result.isOk, name & " should be Err"

  # ── Fixtures (top-level so all checks can reference them) ──

  let candidateOutcome = makeCandidate("test-source")
  let emptyGen = makeNoApplicable(
    makeNoApplicableProvenance(@[], "obs:division", @["no div ops found"])
  )
  let unsupportedGen = makeUnsupported(usScopedRecursiveHeapNotModeled)
  let illFormedGen = makeIllFormed(ifTypeMismatch)
  let neObligations = makeLightNonEmpty(@[
    VerificationObligation(
      id: "abc123", kind: okSafetyDiv, subject: "x",
      assumptions: "x != 0", predicate: "x != 0",
      proposition: irUnaryOp(uoNot, irBinOp(boEq, irVar("x", irTypeBitVec64()), IRExpr(typ: irTypeBitVec64(), kind: irLit, litVal: 0))),
      derivationRule: "obs:division", provenance: "gen"
    )
  ])
  let generatedGen = makeGenerated(neObligations)

  let analyzedOutcome = ObligationOutcome(phase: ppAnalyzed, terminal: none(ProofTerminal), detail: "")
  let decisionOutcome = ObligationOutcome(phase: ppObligationDecision, terminal: none(ProofTerminal), detail: "")
  let attemptedOutcome = ObligationOutcome(phase: ppProofAttempted, terminal: none(ProofTerminal), detail: "")
  let provedOutcome = ObligationOutcome(phase: ppTerminal, terminal: some(ptProved), detail: "")
  let inconclusiveOutcome = ObligationOutcome(phase: ppTerminal, terminal: some(ptInconclusive), detail: "")

  echo "=== Proof State Machine — Transition Tests ==="

  # ── C0: Empty obligations canonical form ───────────────

  echo "--- C0 Invariants ---"

  check "C0: terminal noApplicable is canonical empty":
    let o = ObligationOutcome(phase: ppTerminal, terminal: some(ptNoApplicableObligation))
    assert isCanonicalEmpty(o), "terminal noApplicable should be canonical empty"

  check "C0: candidate is NOT canonical empty":
    assert not isCanonicalEmpty(candidateOutcome),
      "candidate should not be canonical empty"

  check "C0: terminal proved is NOT canonical empty":
    assert not isCanonicalEmpty(ObligationOutcome(
      phase: ppTerminal, terminal: some(ptProved), detail: "")),
      "proved should not be canonical empty"

  check "C0: terminal unsupported is NOT canonical empty":
    assert not isCanonicalEmpty(ObligationOutcome(
      phase: ppTerminal, terminal: some(ptUnsupported), detail: "")),
      "unsupported should not be canonical empty"

  check "C0: terminal illFormed is NOT canonical empty":
    assert not isCanonicalEmpty(ObligationOutcome(
      phase: ppTerminal, terminal: some(ptIllFormed), detail: "")),
      "illFormed should not be canonical empty"

  check "C0: terminal inconclusive is NOT canonical empty":
    assert not isCanonicalEmpty(ObligationOutcome(
      phase: ppTerminal, terminal: some(ptInconclusive), detail: "")),
      "inconclusive should not be canonical empty"

  check "C0: terminal invalidArtifact is NOT canonical empty":
    assert not isCanonicalEmpty(ObligationOutcome(
      phase: ppTerminal, terminal: some(ptInvalidArtifact), detail: "")),
      "invalidArtifact should not be canonical empty"

  # ── Invalid transitions: candidate → proofAttempted ────

  echo "--- Invalid Transitions ---"

  check "reject: candidate → attemptProof (direct)":
    let r = attemptProof(candidateOutcome)
    assert not r.isOk, "candidate → attemptProof must be rejected"

  check "reject: candidate → settleProof (direct)":
    let r = settleProof(candidateOutcome, peSettleProved)
    assert not r.isOk, "candidate → settleProof must be rejected"

  check "reject: terminal → analyze":
    let r = analyze(provedOutcome)
    assert not r.isOk, "terminal → analyze must be rejected"

  check "reject: terminal → decideObligations":
    let r = decideObligations(provedOutcome, generatedGen)
    assert not r.isOk, "terminal → decideObligations must be rejected"

  check "reject: terminal → attemptProof":
    let r = attemptProof(provedOutcome)
    assert not r.isOk, "terminal → attemptProof must be rejected"

  check "reject: terminal → settleProof":
    let r = settleProof(provedOutcome, peSettleProved)
    assert not r.isOk, "terminal → settleProof must be rejected"

  # ── Invalid transitions: wrong phase ──────────────────────

  echo "--- Phase-Gate Rejections ---"

  check "reject: analyzed → attemptProof":
    let r = attemptProof(analyzedOutcome)
    assert not r.isOk, "analyzed → attemptProof must be rejected"

  check "reject: analyzed → settleProof":
    let r = settleProof(analyzedOutcome, peSettleProved)
    assert not r.isOk, "analyzed → settleProof must be rejected"

  check "reject: obligationDecision → analyze":
    let r = analyze(decisionOutcome)
    assert not r.isOk, "obligationDecision → analyze must be rejected"

  check "reject: proofAttempted → analyze":
    let r = analyze(attemptedOutcome)
    assert not r.isOk, "proofAttempted → analyze must be rejected"

  check "reject: proofAttempted → decideObligations":
    let r = decideObligations(attemptedOutcome, generatedGen)
    assert not r.isOk, "proofAttempted → decideObligations must be rejected"

  # ── Valid transitions: full pipeline ────────────────────

  echo "--- Valid Transitions ---"

  check "analyze: Candidate → Analyzed":
    let r = analyze(candidateOutcome)
    assert r.isOk, "analyze should succeed"
    assert r.value.phase == ppAnalyzed, "phase should be Analyzed"
    assert r.value.terminal.isNone, "analyzed has no terminal"

  check "decideObligations: Analyzed → ObligationDecision (generated)":
    let r = decideObligations(analyzedOutcome, generatedGen)
    assert r.isOk, "decide should succeed for generated"
    assert r.value.phase == ppObligationDecision, "phase should be ObligationDecision"
    assert r.value.terminal.isNone, "generated has no terminal"

  check "decideObligations: Analyzed → Terminal (noApplicable)":
    let r = decideObligations(analyzedOutcome, emptyGen)
    assert r.isOk, "decide should succeed for noApplicable"
    assert r.value.phase == ppTerminal, "phase should be Terminal"
    assert r.value.terminal.isSome, "noApplicable should have terminal"
    assert r.value.terminal.get == ptNoApplicableObligation, "should be ptNoApplicableObligation"

  check "decideObligations: Analyzed → Terminal (unsupported)":
    let r = decideObligations(analyzedOutcome, unsupportedGen)
    assert r.isOk, "decide should succeed for unsupported"
    assert r.value.phase == ppTerminal, "phase should be Terminal"
    assert r.value.terminal.get == ptUnsupported, "should be ptUnsupported"

  check "decideObligations: Analyzed → Terminal (illFormed)":
    let r = decideObligations(analyzedOutcome, illFormedGen)
    assert r.isOk, "decide should succeed for illFormed"
    assert r.value.phase == ppTerminal, "phase should be Terminal"
    assert r.value.terminal.get == ptIllFormed, "should be ptIllFormed"

  check "attemptProof: ObligationDecision → ProofAttempted":
    let r = attemptProof(decisionOutcome)
    assert r.isOk, "attemptProof should succeed"
    assert r.value.phase == ppProofAttempted, "phase should be ProofAttempted"
    assert r.value.terminal.isNone, "proofAttempted has no terminal"

  check "settleProof: ProofAttempted → Terminal (proved)":
    let r = settleProof(attemptedOutcome, peSettleProved)
    assert r.isOk, "settleProof should succeed"
    assert r.value.phase == ppTerminal, "phase should be Terminal"
    assert r.value.terminal.get == ptProved, "should be ptProved"
    assert r.value.reason.isNone, "proved carries no typed reason"

  check "settleProof: ProofAttempted → Terminal (refuted)":
    let r = settleProof(attemptedOutcome, peSettleRefuted)
    assert r.isOk, "settleProof should succeed"
    assert r.value.phase == ppTerminal, "phase should be Terminal"
    assert r.value.terminal.get == ptRefuted, "should be ptRefuted"
    assert r.value.reason.isNone, "refuted carries no typed reason"

  check "settleProof: ProofAttempted → Terminal (inconclusive/error)":
    let err = InternalError(code: "TIMEOUT", detail: "solver timed out after 30s")
    let r = settleProof(attemptedOutcome, peSettleError, err)
    assert r.isOk, "settleProof should succeed for error"
    assert r.value.phase == ppTerminal, "phase should be Terminal"
    assert r.value.terminal.get == ptInconclusive, "should be ptInconclusive"
    assert r.value.reason.get.inconclusive.get == irUnknown,
      "default inconclusive reason should be irUnknown"
    assert r.value.detail.contains("TIMEOUT"), "detail should contain error code"

  check "settleProof: ProofAttempted → Terminal (inconclusive, timeout reason)":
    let err = InternalError(code: "TIMEOUT", detail: "solver timed out after 30s")
    let r = settleProof(attemptedOutcome, peSettleError, err, inconclusiveReason = irTimeout)
    assert r.isOk, "settleProof should succeed for error"
    assert r.value.phase == ppTerminal, "phase should be Terminal"
    assert r.value.terminal.get == ptInconclusive, "should be ptInconclusive"
    assert r.value.reason.get.inconclusive.get == irTimeout,
      "should carry irTimeout"
    assert r.value.detail.contains("TIMEOUT"), "detail should contain error code"

  check "settleProof: ProofAttempted → Terminal (invalidArtifact, parse error)":
    let r = settleProof(attemptedOutcome, peSettleInvalidArtifact,
      artifactReason = arParseError)
    assert r.isOk, "settleProof should succeed for invalid artifact"
    assert r.value.phase == ppTerminal, "phase should be Terminal"
    assert r.value.terminal.get == ptInvalidArtifact, "should be ptInvalidArtifact"
    assert r.value.reason.get.artifact.get == arParseError,
      "should carry arParseError"
    assert r.value.detail.contains("arParseError"), "detail should name the reason"

  check "settleProof: ProofAttempted → Terminal (invalidArtifact, kernel rejected)":
    let err = InternalError(code: "KERNEL_REJECT", detail: "type mismatch at step 7")
    let r = settleProof(attemptedOutcome, peSettleInvalidArtifact, err,
      artifactReason = arKernelRejected)
    assert r.isOk, "settleProof should succeed for invalid artifact"
    assert r.value.phase == ppTerminal, "phase should be Terminal"
    assert r.value.terminal.get == ptInvalidArtifact, "should be ptInvalidArtifact"
    assert r.value.reason.get.artifact.get == arKernelRejected,
      "should carry arKernelRejected"
    assert r.value.detail.contains("KERNEL_REJECT"), "detail should carry error info"

  # ── Full pipeline ───────────────────────────────────────

  echo "--- Full Pipeline ---"

  check "full pipeline: generated → proved":
    let r = runPipeline(generatedGen, peSettleProved)
    assert r.isOk, "pipeline should succeed"
    let final = r.value
    assert final.phase == ppTerminal, "final phase should be Terminal"
    assert final.terminal.get == ptProved, "should be ptProved"

  check "full pipeline: noApplicable → stops at terminal":
    let r = runPipeline(emptyGen)
    assert r.isOk, "pipeline should succeed"
    let final = r.value
    assert final.phase == ppTerminal, "final phase should be Terminal"
    assert final.terminal.get == ptNoApplicableObligation, "should be ptNoApplicableObligation"

  check "full pipeline: unsupported → stops at terminal":
    let r = runPipeline(unsupportedGen)
    assert r.isOk, "pipeline should succeed"
    let final = r.value
    assert final.phase == ppTerminal, "final phase should be Terminal"
    assert final.terminal.get == ptUnsupported, "should be ptUnsupported"

  check "full pipeline: illFormed → stops at terminal":
    let r = runPipeline(illFormedGen)
    assert r.isOk, "pipeline should succeed"
    let final = r.value
    assert final.phase == ppTerminal, "final phase should be Terminal"
    assert final.terminal.get == ptIllFormed, "should be ptIllFormed"

  check "full pipeline: generated → inconclusive (backend error)":
    let err = InternalError(code: "INTERNAL_ERROR", detail: "CHC solver crashed")
    let r = runPipeline(generatedGen, peSettleError, err)
    assert r.isOk, "pipeline should succeed"
    let final = r.value
    assert final.phase == ppTerminal, "final phase should be Terminal"
    assert final.terminal.get == ptInconclusive, "should be ptInconclusive"
    assert final.detail.contains("INTERNAL_ERROR"), "detail should contain error code"

  check "full pipeline: generated → inconclusive (timeout reason)":
    let err = InternalError(code: "TIMEOUT", detail: "solver timed out after 30s")
    let r = runPipeline(generatedGen, peSettleError, err, inconclusiveReason = irTimeout)
    assert r.isOk, "pipeline should succeed"
    let final = r.value
    assert final.phase == ppTerminal, "final phase should be Terminal"
    assert final.terminal.get == ptInconclusive, "should be ptInconclusive"
    assert final.reason.get.inconclusive.get == irTimeout,
      "should carry irTimeout"

  check "full pipeline: generated → invalidArtifact (elaboration error)":
    let r = runPipeline(generatedGen, peSettleInvalidArtifact,
      artifactReason = arElaborationError)
    assert r.isOk, "pipeline should succeed"
    let final = r.value
    assert final.phase == ppTerminal, "final phase should be Terminal"
    assert final.terminal.get == ptInvalidArtifact, "should be ptInvalidArtifact"
    assert final.reason.get.artifact.get == arElaborationError,
      "should carry arElaborationError"
    assert final.detail.contains("arElaborationError"), "detail should name the reason"

  check "full pipeline: non-generated never fabricates artifact reason":
    let r = runPipeline(emptyGen, peSettleInvalidArtifact)
    assert r.isOk, "pipeline should succeed"
    let final = r.value
    assert final.phase == ppTerminal, "final phase should be Terminal"
    assert final.terminal.get == ptNoApplicableObligation,
      "non-generated path stops before settle"
    assert final.reason.isNone, "non-generated terminal carries no reason"

  # ── Phase/terminal consistency ──────────────────────────

  echo "--- Phase/Terminal Consistency ---"

  check "generated result: phase=ObligationDecision, terminal=none":
    let r = decideObligations(analyzedOutcome, generatedGen)
    assert r.isOk
    let final = r.value
    assert final.phase == ppObligationDecision, "generated phase should be ObligationDecision"
    assert final.terminal.isNone, "generated terminal should be none"

  check "noApplicable result: phase=Terminal, terminal=Some(noApplicable)":
    let r = decideObligations(analyzedOutcome, emptyGen)
    assert r.isOk
    let final = r.value
    assert final.phase == ppTerminal, "noApplicable phase should be Terminal"
    assert final.terminal.isSome, "noApplicable should have terminal"
    assert final.terminal.get == ptNoApplicableObligation, "should be ptNoApplicableObligation"

  check "unsupported result: phase=Terminal, terminal=Some(unsupported)":
    let r = decideObligations(analyzedOutcome, unsupportedGen)
    assert r.isOk
    let final = r.value
    assert final.phase == ppTerminal, "unsupported phase should be Terminal"
    assert final.terminal.isSome, "unsupported should have terminal"
    assert final.terminal.get == ptUnsupported, "should be ptUnsupported"

  check "illFormed result: phase=Terminal, terminal=Some(illFormed)":
    let r = decideObligations(analyzedOutcome, illFormedGen)
    assert r.isOk
    let final = r.value
    assert final.phase == ppTerminal, "illFormed phase should be Terminal"
    assert final.terminal.isSome, "illFormed should have terminal"
    assert final.terminal.get == ptIllFormed, "should be ptIllFormed"

  # ── Back-to-back invalid: terminal → anything ──────────

  echo "--- Terminal Lockout ---"

  check "terminal proved → analyze rejected":
    checkErr("terminal → analyze", analyze(provedOutcome))

  check "terminal proved → decideObligations rejected":
    checkErr("terminal → decide", decideObligations(provedOutcome, generatedGen))

  check "terminal proved → attemptProof rejected":
    checkErr("terminal → attemptProof", attemptProof(provedOutcome))

  check "terminal proved → settleProof rejected":
    checkErr("terminal → settleProof", settleProof(provedOutcome, peSettleProved))

  check "terminal inconclusive → analyze rejected":
    checkErr("terminal inconclusive → analyze", analyze(inconclusiveOutcome))

  # ── Summary ──────────────────────────────────────────────

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

when isMainModule:
  main()
