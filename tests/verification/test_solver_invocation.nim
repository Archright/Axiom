import core/trusted/layer_declaration
import core/trusted/solver_invocation

proc main() =
  echo "=== SolverInvocation Deterministic Replay Key ==="

  let si = makeSolverInvocation(
    scriptDigest = "abc123",
    solverVersion = "z3-4.8.8",
    solverOptionsDigest = "opt-hash-001",
    semanticProfileId = "semprof-v1",
    encodingIdentity = "ir2smt-v1"
  )

  let key1 = si.replayKey

  # Same fields → same replayKey
  block:
    let si2 = makeSolverInvocation(
      scriptDigest = "abc123",
      solverVersion = "z3-4.8.8",
      solverOptionsDigest = "opt-hash-001",
      semanticProfileId = "semprof-v1",
      encodingIdentity = "ir2smt-v1"
    )
    let key2 = si2.replayKey
    doAssert key1 == key2,
      "identical SolverInvocation must produce identical replayKey"
    echo "  OK: same fields → same replayKey"

  # smtScriptDigest change → different replayKey
  block:
    let si3 = makeSolverInvocation(
      scriptDigest = "abc123",
      solverVersion = "z3-4.8.8",
      solverOptionsDigest = "opt-hash-001",
      semanticProfileId = "semprof-v1",
      encodingIdentity = "ir2smt-v1",
      smtScriptDigest = "def456"
    )
    doAssert si.replayKey != si3.replayKey,
      "smtScriptDigest change must change replayKey"
    echo "  OK: smtScriptDigest change → different replayKey"

  # solverOptionsDigest change → different replayKey
  block:
    let si4 = makeSolverInvocation(
      scriptDigest = "abc123",
      solverVersion = "z3-4.8.8",
      solverOptionsDigest = "opt-hash-002",
      semanticProfileId = "semprof-v1",
      encodingIdentity = "ir2smt-v1"
    )
    doAssert si.replayKey != si4.replayKey,
      "solverOptionsDigest change must change replayKey"
    echo "  OK: solverOptionsDigest change → different replayKey"

  # semanticProfileId change → different replayKey
  block:
    let si5 = makeSolverInvocation(
      scriptDigest = "abc123",
      solverVersion = "z3-4.8.8",
      solverOptionsDigest = "opt-hash-001",
      semanticProfileId = "semprof-v2",
      encodingIdentity = "ir2smt-v1"
    )
    doAssert si.replayKey != si5.replayKey,
      "semanticProfileId change must change replayKey"
    echo "  OK: semanticProfileId change → different replayKey"

  # solverVersion change → different replayKey
  block:
    let si6 = makeSolverInvocation(
      scriptDigest = "abc123",
      solverVersion = "z3-4.8.9",
      solverOptionsDigest = "opt-hash-001",
      semanticProfileId = "semprof-v1",
      encodingIdentity = "ir2smt-v1"
    )
    doAssert si.replayKey != si6.replayKey,
      "solverVersion change must change replayKey"
    echo "  OK: solverVersion change → different replayKey"

  # Default solverIdentity = "z3" and env = ""
  block:
    doAssert si.solverIdentity == "z3",
      "default solverIdentity must be 'z3'"
    doAssert si.env == "",
      "default env must be empty string"
    echo "  OK: defaults (solverIdentity='z3', env='')"

  echo "=== SolverInvocation OK ==="

main()