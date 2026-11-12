import core/trusted/layer_declaration
import core/trusted/solver_invocation
import core/trusted/replay_engine
import verification/solver/replay_runner
import core/crypto/hash_kernel
import core/results
import std/os
import std/strutils

proc main() =
  echo "=== Replay Runner Tests ==="

  let smtUnsat = "(set-logic QF_BV)\n(declare-const a (_ BitVec 64))\n(assert (= a #x0000000000000001))\n(assert (= a #x0000000000000002))\n(check-sat)\n"
  let si = makeSolverInvocation(
    scriptDigest = "ir-digest-001",
    solverVersion = "z3",
    solverOptionsDigest = "opt-hash-001",
    semanticProfileId = "semprof-v1",
    encodingIdentity = "axiom-ir-smt-v1",
    smtScriptDigest = sha256Hex(smtUnsat),
    smtScript = smtUnsat,
    canonicalSourceIdentity = "src-hash-foo",
    specificationIdentity = "spec-id-001",
    translationIdentityHash = "axiom-ir-smt-v1"
  )

  # T1: empty smtScript → rsUnavailable (no z3 call)
  block:
    let siEmpty = makeSolverInvocation(
      scriptDigest = "ir-digest-001",
      solverVersion = "z3",
      solverOptionsDigest = "opt-hash-001",
      semanticProfileId = "semprof-v1",
      encodingIdentity = "axiom-ir-smt-v1",
      smtScriptDigest = "",
      smtScript = ""
    )
    let status = runReplayWithZ3(siEmpty, "unsat", 5000)
    doAssert status == rsUnavailable,
      "empty smtScript must be rsUnavailable"
    echo "  OK: empty smtScript → rsUnavailable"

  # T2: digest-inconsistent (tamper smtScript, keep digest) → rsMismatch
  block:
    var tampered = si
    tampered.smtScript = "(assert true)\n(check-sat)\n"
    doAssert not verifySmtDigest(tampered),
      "verifySmtDigest must be false for tampered smtScript"
    let status = runReplayWithZ3(tampered, "unsat", 5000)
    doAssert status == rsMismatch,
      "tampered smtScript must be rsMismatch"
    echo "  OK: digest-inconsistent → rsMismatch"

  # T3: z3 availability check
  let z3Available = (findExe("z3").len > 0)
  if z3Available:
    # T3a: matching outcome → rsMatch
    block:
      let status = runReplayWithZ3(si, "unsat", 10000)
      doAssert status == rsMatch,
        "matching unsat outcome must be rsMatch when z3 is available"
      echo "  OK: matching outcome → rsMatch (z3 available)"

    # T3b: non-matching outcome → rsMismatch
    block:
      let status = runReplayWithZ3(si, "sat", 10000)
      doAssert status == rsMismatch,
        "non-matching outcome must be rsMismatch when z3 is available"
      echo "  OK: non-matching outcome → rsMismatch (z3 available)"
  else:
    # T3c: z3 unavailable → rsUnavailable for any non-empty smtScript
    block:
      let status = runReplayWithZ3(si, "unsat", 10000)
      doAssert status == rsUnavailable,
        "z3 unavailable must yield rsUnavailable"
      echo "  OK: z3 unavailable → rsUnavailable"

  echo "=== Replay Runner OK ==="

main()