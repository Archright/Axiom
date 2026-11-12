import core/trusted/layer_declaration
import core/trusted/solver_invocation
import core/trusted/replay_engine
import core/trusted/evidence_calculus
import core/results
import core/crypto/hash_kernel

proc fakeInvokeOk(smt: string, t: int): Result[string, string] =
  ok("unsat")

proc fakeInvokeErr(smt: string, t: int): Result[string, string] =
  err("z3 error")

proc fakeInvokeSat(smt: string, t: int): Result[string, string] =
  ok("sat")

proc main() =
  echo "=== Replay Engine Tests ==="

  let smtText = "(assert (<= x 100))\n(check-sat)\n"
  let si = makeSolverInvocation(
    scriptDigest = "ir-digest-001",
    solverVersion = "z3-4.8.8",
    solverOptionsDigest = "opt-hash-001",
    semanticProfileId = "semprof-v1",
    encodingIdentity = "axiom-ir-smt-v1",
    smtScriptDigest = sha256Hex(smtText),
    smtScript = smtText,
    canonicalSourceIdentity = "src-hash-foo",
    specificationIdentity = "spec-id-001",
    translationIdentityHash = "axiom-ir-smt-v1"
  )

  # T1: smtDigestConsistent true for well-formed SolverInvocation
  block:
    doAssert smtDigestConsistent(si),
      "smtDigestConsistent must be true when smtScript matches smtScriptDigest"
    echo "  OK: smtDigestConsistent true for well-formed SolverInvocation"

  # T2: smtDigestConsistent false when smtScript tampered (digest mismatch)
  block:
    var tampered = si
    tampered.smtScript = "(assert (<= x 999))\n(check-sat)\n"
    doAssert not smtDigestConsistent(tampered),
      "smtDigestConsistent must be false when smtScript is tampered"
    echo "  OK: smtDigestConsistent false for tampered smtScript"

  # T3: verifySmtDigest aliases smtDigestConsistent
  block:
    doAssert verifySmtDigest(si),
      "verifySmtDigest must return true for well-formed SolverInvocation"
    var tampered2 = si
    tampered2.smtScript = "(assert (<= x 999))\n(check-sat)\n"
    doAssert not verifySmtDigest(tampered2),
      "verifySmtDigest must return false for tampered smtScript"
    echo "  OK: verifySmtDigest consistent with smtDigestConsistent"

  # T4: replayKey is SMT-based — changing smtScriptDigest changes the key
  block:
    let si2 = makeSolverInvocation(
      scriptDigest = "ir-digest-001",
      solverVersion = "z3-4.8.8",
      solverOptionsDigest = "opt-hash-001",
      semanticProfileId = "semprof-v1",
      encodingIdentity = "axiom-ir-smt-v1",
      smtScriptDigest = "smt-script-digest-002"
    )
    doAssert si.replayKey != si2.replayKey,
      "changing smtScriptDigest must change replayKey"
    echo "  OK: smtScriptDigest change → different replayKey"

  # T5: same inputs → same replayKey
  block:
    let si2 = makeSolverInvocation(
      scriptDigest = "ir-digest-001",
      solverVersion = "z3-4.8.8",
      solverOptionsDigest = "opt-hash-001",
      semanticProfileId = "semprof-v1",
      encodingIdentity = "axiom-ir-smt-v1",
      smtScriptDigest = sha256Hex(smtText),
      smtScript = smtText,
      canonicalSourceIdentity = "src-hash-foo",
      specificationIdentity = "spec-id-001",
      translationIdentityHash = "axiom-ir-smt-v1"
    )
    doAssert si.replayKey == si2.replayKey,
      "identical inputs must produce identical replayKey"
    echo "  OK: same inputs → same replayKey"

  # T6: irIdentity differs from replayKey (hierarchical)
  block:
    doAssert si.irIdentity != si.replayKey,
      "irIdentity must differ from replayKey (hierarchical)"
    echo "  OK: irIdentity != replayKey (hierarchical)"

  # T7: irIdentity = H(scriptDigest)
  block:
    doAssert si.irIdentity == sha256Hex(si.scriptDigest),
      "irIdentity must be H(scriptDigest)"
    echo "  OK: irIdentity = H(scriptDigest)"

  # T8: runReplay with matching outcome → rsMatch (uses si.smtScript verbatim)
  block:
    let status = runReplay(si, 1000, "unsat", fakeInvokeOk)
    doAssert status == rsMatch,
      "matching outcome must be rsMatch"
    echo "  OK: matching outcome → rsMatch"

  # T9: runReplay with different outcome → rsMismatch
  block:
    let status = runReplay(si, 1000, "sat", fakeInvokeOk)
    doAssert status == rsMismatch,
      "different outcome must be rsMismatch"
    echo "  OK: different outcome → rsMismatch"

  # T10: runReplay with empty smtScript → rsUnavailable
  block:
    let siEmpty = makeSolverInvocation(
      scriptDigest = "ir-digest-001",
      solverVersion = "z3-4.8.8",
      solverOptionsDigest = "opt-hash-001",
      semanticProfileId = "semprof-v1",
      encodingIdentity = "axiom-ir-smt-v1",
      smtScriptDigest = "",
      smtScript = ""
    )
    let status = runReplay(siEmpty, 1000, "unsat", fakeInvokeOk)
    doAssert status == rsUnavailable,
      "empty smtScript must be rsUnavailable"
    echo "  OK: empty smtScript → rsUnavailable"

  # T11: runReplay with invoke error → rsUnavailable
  block:
    let status = runReplay(si, 1000, "unsat", fakeInvokeErr)
    doAssert status == rsUnavailable,
      "invoke error must be rsUnavailable"
    echo "  OK: invoke error → rsUnavailable"

  # T12: setReplayEvidence writes MATCH
  block:
    var bundle: EvidenceBundle
    setReplayEvidence(bundle, rsMatch)
    doAssert bundle.facts.replay.result == "MATCH",
      "rsMatch must write MATCH"
    doAssert bundle.facts.replay.checker == "z3",
      "checker must be z3"
    echo "  OK: setReplayEvidence rsMatch → MATCH"

  # T13: setReplayEvidence writes MISMATCH
  block:
    var bundle: EvidenceBundle
    setReplayEvidence(bundle, rsMismatch)
    doAssert bundle.facts.replay.result == "MISMATCH",
      "rsMismatch must write MISMATCH"
    echo "  OK: setReplayEvidence rsMismatch → MISMATCH"

  # T14: setReplayEvidence writes UNAVAILABLE
  block:
    var bundle: EvidenceBundle
    setReplayEvidence(bundle, rsUnavailable)
    doAssert bundle.facts.replay.result == "UNAVAILABLE",
      "rsUnavailable must write UNAVAILABLE"
    echo "  OK: setReplayEvidence rsUnavailable → UNAVAILABLE"

  # T15: replayKeyFor delegates to replayKey
  block:
    doAssert replayKeyFor(si) == si.replayKey,
      "replayKeyFor must delegate to replayKey"
    echo "  OK: replayKeyFor delegates to replayKey"

  echo "=== Replay Engine OK ==="

main()