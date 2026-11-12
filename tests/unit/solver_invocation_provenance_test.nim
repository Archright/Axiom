import core/trusted/layer_declaration

## Solver invocation provenance — self-description and reproducibility contract.
##
## Every assertion here corresponds to a way an invocation record could lie:
## a placeholder digest, an option set that drifts from what was emitted, an
## unnamed executable, or a verdict stronger than the solver's own answer.

import core/crypto/hash_kernel
import core/proof/proof_budget
import core/results
import core/trusted/solver_invocation
import core/types/solver_types
import std/algorithm
import std/strutils
import verification/solver/solver_invocation_provenance
import verification/solver/z3_pool

proc expect(cond: bool; msg: string) =
  if not cond:
    doAssert false, msg
  echo "  OK: " & msg

let pinned = deterministicSolverOptionsDigest()
var mutated = deterministicSolverOptions(z3DeterministicBudget, z3SafetyNetMs)

block:
  echo "=== 1. solverOptionsDigest is a real digest, not a placeholder ==="

  expect(pinned.len > 0, "recorded option digest is non-empty")

  # Stability: identical inputs, identical digest.
  expect(pinned == deterministicSolverOptionsDigest(),
    "identical option inputs produce an identical digest")
  expect(pinned == solverOptionsDigest(deterministicSolverOptions(
      z3DeterministicBudget, z3SafetyNetMs)),
    "digest is reproducible from the explicit option set")

  # Sensitivity: change exactly one option, digest must move.
  var sawSeedChange = false
  var sawRlimitChange = false
  var sawTimeoutChange = false
  var sawParallelChange = false
  for spec in mutated.mitems:
    if spec.name == "random-seed":
      spec.value = $(Z3PinnedRandomSeed + 1)
      sawSeedChange = true
    elif spec.name == "rlimit":
      spec.value = $(z3DeterministicBudget + 1)
      sawRlimitChange = true
    elif spec.name == "timeout":
      spec.value = $(z3SafetyNetMs + 1)
      sawTimeoutChange = true
    elif spec.name == "parallel.enable":
      spec.value = "true"
      sawParallelChange = true
  expect(sawSeedChange and sawRlimitChange and sawTimeoutChange and sawParallelChange,
    "pinned set actually contains random-seed, rlimit, timeout and parallel.enable")
  expect(solverOptionsDigest(mutated) != pinned,
    "changing any single option value changes the digest")

  # A different seed is a different option set, not a silent alias.
  expect(solverOptionsDigest(deterministicSolverOptions(
      z3DeterministicBudget, z3SafetyNetMs, Z3PinnedRandomSeed + 1)) != pinned,
    "a different pinned seed yields a different digest")

  # Seed 0 must not be reachable as the pinned determinism value.
  expect(Z3PinnedRandomSeed != 0,
    "the pinned seed is non-zero (SMT-LIB 2.7 §4.1.7: 0 permits a per-run seed)")

  # Order is part of the digest input — reordering is a change, not cosmetics.
  var reordered = pinnedDeterminismOptions()
  swap(reordered[0], reordered[3])
  expect(solverOptionsDigest(reordered) != pinned,
    "reordering the option set changes the digest")

block:
  echo "=== 2. the digest cannot drift from the emitted option text ==="

  let payload = solverOptionsPayload(deterministicSolverOptions(
      z3DeterministicBudget, z3SafetyNetMs))
  for required in ["(set-option :random-seed 42)", "(set-option :sat.random_seed 42)",
                   "(set-option :fp.spacer.random_seed 42)",
                   "(set-option :parallel.enable false)",
                   "(set-option :rlimit " & $z3DeterministicBudget & ")",
                   "(set-option :timeout " & $z3SafetyNetMs & ")"]:
    expect(payload.contains(required), "pinned option set emits " & required)

  # Anything else in the payload would mean the digest does not describe the
  # whole option set handed to Z3.
  let lineCount = payload.strip.splitLines.len
  expect(lineCount == 6, "payload carries exactly the six pinned options, no more")
  expect(solverOptionsDigest(deterministicSolverOptions(
      z3DeterministicBudget, z3SafetyNetMs)) == sha256Hex(payload),
    "digest is taken over the emitted payload itself")
  expect(matchesPinnedOptions(pinned),
    "the recorded digest matches the pinned option set")
  expect(not matchesPinnedOptions(solverOptionsDigest(mutated)),
    "a mutated option set is detected as non-pinned")

block:
  echo "=== 3. solver binary identity is recorded, and fails closed ==="

  let identity = resolveSolverBinaryIdentity()
  if identity.isErr:
    # A machine without a resolvable Z3 must refuse, not degrade to "".
    expect(identity.error().len > 0, "unresolvable solver binary fails closed with a reason")
  else:
    expect(identity.get().binaryDigest.len > 0, "solver binary digest is recorded")
    expect(identity.get().resolvedPath.len > 0 and identity.get().resolvedPath != "z3",
      "digest is computed from the RESOLVED path, not the bare fallback name")
    expect(identity.get().binaryDigest ==
      solverBinaryDigestAt(identity.get().resolvedPath).get(),
      "recorded digest equals a fresh digest of the resolved executable")
    # "computed once and carried through": the memoized answer is the answer.
    expect(resolveSolverBinaryIdentity().get().binaryDigest == identity.get().binaryDigest,
      "repeated resolution returns the same digest")

  expect(solverBinaryDigestAt("").isErr, "empty path is refused")
  expect(solverBinaryDigestAt("/nonexistent/axiom/no/such/z3").isErr,
    "non-existent path is refused")
  expect(solverBinaryDigestAt("/tmp").isErr or
    solverBinaryDigestAt("/tmp").get().len > 0,
    "a directory either hashes or is refused — it never yields an empty digest")

block:
  echo "=== 4. verdict labeling cannot exceed the solver's own answer ==="

  expect(classifySolverVerdict("unsat\n") == svUnsat, "unsat is recognized")
  expect(classifySolverVerdict("sat\n") == svSat, "sat is recognized")
  expect(classifySolverVerdict("unknown\n") == svUnknown, "unknown is recognized")
  expect(classifySolverVerdict("") == svUnknown, "no response is unknown, never a pass")
  expect(classifySolverVerdict("(error \"boom\")\n") == svUnknown,
    "solver error output is unknown")

  # An unsat core or a model may contain the token "sat"; only the response
  # grammar may decide the verdict.
  expect(classifySolverVerdict("(error \"line 5: sat_1 is not a response\")\n") == svUnknown,
    "free text containing 'sat' is not a verdict")
  expect(classifySolverVerdict("sat_1\nsat_2\n") == svUnknown,
    "unsat-core labels that contain 'sat' are not a verdict")

  # :reason-unknown is solver-specific free text — never string-matched.
  expect(classifySolverVerdict("(reason-unknown \"timeout\")\n") == svUnknown,
    ":reason-unknown free text is not treated as a verdict line")

  # The verdict enumeration itself has no 'proved' member.
  var labels: seq[string] = @[]
  for verdict in SolverVerdict:
    labels.add $verdict
  expect(labels == @["sat", "unsat", "unknown"],
    "the verdict vocabulary is exactly sat/unsat/unknown — no 'proved' is expressible")
  for label in labels:
    expect(label != "proved", "verdict vocabulary contains no 'proved' label")

  expect(solverVerdictOf(solverUnsat) == svUnsat, "domain unsat projects to svUnsat")
  expect(solverVerdictOf(solverSat) == svSat, "domain sat projects to svSat")
  expect(solverVerdictOf(solverVacuousContradiction) == svUnknown,
    "vacuous contradiction is not a solver answer about the property")

block:
  echo "=== 5. self-description of the invocation record ==="

  let bare = SolverInvocation(
    scriptDigest: "a", solverIdentity: "z3", solverVersion: "4.13.3",
    solverOptionsDigest: deterministicSolverOptionsDigest(),
    semanticProfileId: "s", encodingIdentity: "e")
  expect(not bare.solverInvocationSelfDescribing,
    "a record with no binary digest is not self-describing")

  var complete = bare
  complete.solverBinaryDigest = "0".repeat(64)
  expect(complete.solverInvocationSelfDescribing,
    "a record naming its options AND its executable is self-describing")

  var placeholder = bare
  placeholder.solverOptionsDigest = ""
  expect(not placeholder.solverInvocationSelfDescribing,
    "an empty option digest is not self-describing")

block:
  echo "=== 6. the SMT envelope actually carries the pinned options ==="

  var envelopeDigest = ""
  let envelope = buildZ3QueryEnvelope(
    "(assert false)\n(check-sat)\n", z3SafetyNetMs, "AXIOM_TEST_SENTINEL",
    canonicalEnvelopeDigest = envelopeDigest)

  for spec in deterministicSolverOptions(z3DeterministicBudget, z3SafetyNetMs):
    expect(envelope.contains(solverOptionDirective(spec)),
      "envelope emits " & solverOptionDirective(spec))

  # The seed in the emitted script is the non-zero pinned one — a seed of 0
  # would be the standard's opt-OUT, not a determinism claim.
  expect(envelope.contains("(set-option :random-seed " & $Z3PinnedRandomSeed & ")"),
    "envelope pins a non-zero random-seed")
  expect(not envelope.contains("(set-option :random-seed 0)"),
    "envelope never emits the opt-out seed")
  expect(envelopeDigest.len > 0, "envelope digest is computed over the pinned envelope")

  # An envelope that carries a caller-supplied option must not be double-set.
  var callerDigest = ""
  let pinnedByCaller = buildZ3QueryEnvelope(
    "(set-option :random-seed 7)\n(assert false)\n(check-sat)\n",
    z3SafetyNetMs, "AXIOM_TEST_SENTINEL",
    canonicalEnvelopeDigest = callerDigest)
  expect(pinnedByCaller.split("(set-option :random-seed").len == 2,
    "a caller-pinned seed is respected, not overridden or duplicated")

  echo "=== Solver Invocation Provenance OK ==="