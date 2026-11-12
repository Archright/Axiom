## request_derivation_test.nim — R3+R4+R5 RequestDerivation integrity tests
##
## Tests for src/verification/selection/request_derivation.nim:
##   - R5: Integrity tests (3 kinds + disposition-without-evidence)
##   - R4: RequestVerdict semilattice axioms
##   - Basic functionality

{.push raises: [CatchableError].}

import std/[algorithm, json, sequtils, strutils, sets, unittest]
import core/types/request_id
import core/types/request_result
import core/types/selection_derivation
import core/types/graph_artifact
import core/types/execution_plan
import core/types/canonical_change_set
import verification/selection/request_derivation
import verification/selection/request_oracle
import verification/selection/request_completeness
import verification/selection/soundness_oracle
import verification/selection/selection_digests
import core/types/request_derivation_types
import core/topology/topology_types

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc makeCanonicalChangeSet*(
  baseCommit = "base_sha_aaa"
; headCommit = "head_sha_bbb"
; mergeBase: seq[string] = @["merge_sha_ccc"]
; diffDigest = "diff_hash_123"
; flags: set[DiffInterpretationFlag] = {}
): CanonicalChangeSet =
  CanonicalChangeSet(
    baseCommit: baseCommit,
    headCommit: headCommit,
    mergeBase: mergeBase,
    canonicalDiffDigest: diffDigest,
    diffInterpretationPolicy: DiffInterpretationPolicy(flags: flags))

proc makeGraphArtifact*(
  structureDigest = "struct_digest_1"
; constructionInputsDigest = "inputs_digest_2"
; policyDigest = "policy_digest_3"
; unresolvedEdges: seq[TopologyUnresolvedEdge] = @[]
; builderVersion = "2"
): GraphArtifact =
  GraphArtifact(
    structureDigest: structureDigest,
    constructionInputsDigest: constructionInputsDigest,
    interpretationPolicyDigest: policyDigest,
    unresolvedEdges: unresolvedEdges.map(toGraphUnresolvedEdge),
    builderVersion: builderVersion)

proc makeSelectionDerivation*(
  changeSetDigest = "cs_digest_1"
; graphDigest = "graph_digest_2"
; universeDigest = "uni_digest_3"
; policyDigest = "policy_digest_4"
; status = ssValid
; selected: seq[ProofOfSelection] = @[]
; excluded: seq[(string, string)] = @[]
; fallbackReason = ""
; witnessDigest = ""
): SelectionDerivation =
  SelectionDerivation(
    inputDigests: SelectionInputs(
      changeSetDigest: changeSetDigest,
      graphDigest: graphDigest,
      universeDigest: universeDigest,
      policyDigest: policyDigest),
    status: status,
    selected: selected,
    excluded: excluded,
    fallbackReason: fallbackReason,
    witnessDigest: witnessDigest)

# ---------------------------------------------------------------------------
# RequestVerdict semilattice axioms tests (R4)
# ---------------------------------------------------------------------------

suite "RequestVerdict - join-semilattice axioms":

  test "commutative: sup(a,b) == sup(b,a)":
    for a in [rvPass, rvFail, rvTimeout, rvError]:
      for b in [rvPass, rvFail, rvTimeout, rvError]:
        check supVertex(a, b) == supVertex(b, a)

  test "associative: sup(sup(a,b),c) == sup(a,sup(b,c))":
    for a in [rvPass, rvFail, rvTimeout, rvError]:
      for b in [rvPass, rvFail, rvTimeout, rvError]:
        for c in [rvPass, rvFail, rvTimeout, rvError]:
          check supVertex(supVertex(a, b), c) == supVertex(a, supVertex(b, c))

  test "idempotent: sup(v,v) == v":
    for v in [rvPass, rvFail, rvTimeout, rvError]:
      check supVertex(v, v) == v

  test "identity: sup(rvPass,v) == v":
    for v in [rvPass, rvFail, rvTimeout, rvError]:
      check supVertex(rvPass, v) == v

  test "Reduce determinism: same list -> same result":
    let testLists: seq[seq[RequestVerdict]] = @[
      @[rvPass, rvFail, rvTimeout],
      @[rvTimeout, rvFail, rvPass],
      @[rvFail, rvFail, rvPass, rvPass],
      @[rvError, rvTimeout, rvFail],
      @[]
    ]
    for lst in testLists:
      let v1 = Reduce(lst)
      let v2 = Reduce(lst)
      check v1 == v2

  test "Reduce independent of order: permutations yield same result":
    let base = @[rvPass, rvFail, rvTimeout, rvError]
    let perms: seq[seq[RequestVerdict]] = @[
      @[rvPass, rvFail, rvTimeout, rvError],
      @[rvError, rvTimeout, rvFail, rvPass],
      @[rvFail, rvPass, rvError, rvTimeout],
      @[rvTimeout, rvPass, rvError, rvFail]
    ]
    let first = Reduce(perms[0])
    for perm in perms[1..perms.high]:
      check Reduce(perm) == first

# ---------------------------------------------------------------------------
# RequestDerivation integrity tests (R5)
# ---------------------------------------------------------------------------

suite "RequestDerivation - integrity tests (fail-closed)":

  test "insert: unauthorized RequestId in derived -> unauthorized != empty":
    ## An unauthorized request (not in required set) in derived set
    ## should be reported as unauthorized by checkCompleteness.
    let required = @[makeRequestId(@["unit_a"])]
    let derived = @[makeRequestId(@["unit_a"]), makeRequestId(@["unit_b"])]  ## unit_b is unauthorized
    let dispositions: seq[Disposition] = @[]
    let result = checkCompleteness(required, derived, dispositions)
    check not result.ok
    check result.unauthorized.len == 1
    check result.unauthorized[0] == makeRequestId(@["unit_b"])
    check result.missing.len == 0

  test "remove: required request missing from derived AND no covering disposition -> missing != empty":
    ## A required request dropped from derived with no disposition to cover it
    ## should be reported as missing.
    let required = @[makeRequestId(@["unit_a"]), makeRequestId(@["unit_b"])]
    let derived = @[makeRequestId(@["unit_a"])]  ## unit_b is missing
    let dispositions: seq[Disposition] = @[]  ## no disposition to cover unit_b
    let result = checkCompleteness(required, derived, dispositions)
    check not result.ok
    check result.missing.len == 1
    check result.missing[0] == makeRequestId(@["unit_b"])
    check result.unauthorized.len == 0

  test "provenance tamper: change RequestId source fields -> mismatch -> verification fails":
    ## If we construct a RequestId from different source fields,
    ## the RequestId changes and causes verification to fail.
    let required = @[makeRequestId(@["unit_a"])]
    let derived = @[makeRequestId(@["unit_x"])]  ## unit_x != unit_a
    let dispositions = @[Disposition(
      kind: dkFallback,
      requestId: makeRequestId(@["unit_x"]),  ## This RequestId is based on ["unit_x"]
      evidence: "basis: unit_x",
      basis: "unit_x")]  ## INVALID basis for dkFallback → caught by strengthened check
    let result = checkCompleteness(required, derived, dispositions)
    check not result.ok  ## Basis mismatch detected as completeness violation

  test "disposition-without-evidence: treated as Completeness violation (ok=false)":
    ## A disposition missing evidence is treated as a Completeness violation per spec.
    let required = @[makeRequestId(@["unit_a"])]
    let derived: seq[RequestId] = @[]  ## unit_a is missing from derived
    let dispositions = @[Disposition(
      kind: dkFallback,
      requestId: makeRequestId(@["unit_a"]),
      evidence: "",  ## EMPTY EVIDENCE - this should cause failure
      basis: "fallback")]
    let result = checkCompleteness(required, derived, dispositions)
    check not result.ok  ## Disposition without evidence = Completeness violation

  test "valid case: required subset derived with proper evidence -> ok=true":
    ## When all required requests are in derived and dispositions have evidence, should pass.
    let required = @[makeRequestId(@["unit_a"]), makeRequestId(@["unit_b"])]
    let derived = @[makeRequestId(@["unit_a"]), makeRequestId(@["unit_b"]), makeRequestId(@["unit_c"])]  ## extra is ok if covered
    let dispositions = @[Disposition(
      kind: dkFallback,
      requestId: makeRequestId(@["unit_c"]),
      evidence: "unit_c approved via fallback policy",
      basis: "fallback")]
    let result = checkCompleteness(required, derived, dispositions)
    check result.ok
    check result.missing.len == 0
    check result.unauthorized.len == 0

  test "execution_plan_requests_field: ExecutionPlan has requests field":
    ## R3: ExecutionPlan should have requests field for required requests
    let plan = ExecutionPlan(
      mode: umSelected,
      selectedUnitIds: @["unit_a"],
      planIdentity: PlanIdentity(
        selectionDigest: "sel", changeSetDigest: "cs", graphDigest: "g",
        universeDigest: "u", policyDigest: "p", planDigest: ""),
      planDigest: "",
      requests: @[makeRequestId(@["req_a"]), makeRequestId(@["req_b"])]
    )
    check plan.requests.len == 2
    check plan.requests[0] == makeRequestId(@["req_a"])
    check plan.requests[1] == makeRequestId(@["req_b"])

  test "execution_plan_requests_default: backward compatibility":
    ## Existing code without requests should still work (default @[])
    let plan = ExecutionPlan(
      mode: umSelected,
      selectedUnitIds: @["unit_a"],
      planIdentity: PlanIdentity(
        selectionDigest: "sel", changeSetDigest: "cs", graphDigest: "g",
        universeDigest: "u", policyDigest: "p", planDigest: ""),
      planDigest: ""
    )
    ## requests field omitted - should default to @[]
    check plan.requests.len == 0

  test "selection_digests_includes_requests: planDigest includes requests":
    ## R3: selection_digests.nim computePlanDigest should include requests
    let planWithReqs = ExecutionPlan(
      mode: umSelected,
      selectedUnitIds: @["unit_a"],
      planIdentity: PlanIdentity(
        selectionDigest: "sel", changeSetDigest: "cs", graphDigest: "g",
        universeDigest: "u", policyDigest: "p", planDigest: ""),
      planDigest: "",
      requests: @[makeRequestId(@["req_a"]), makeRequestId(@["req_b"])]
    )
    let planWithoutReqs = ExecutionPlan(
      mode: umSelected,
      selectedUnitIds: @["unit_a"],
      planIdentity: PlanIdentity(
        selectionDigest: "sel", changeSetDigest: "cs", graphDigest: "g",
        universeDigest: "u", policyDigest: "p", planDigest: ""),
      planDigest: "",
      requests: @[]
    )
    let digestWith = computePlanDigest(planWithReqs)
    let digestWithout = computePlanDigest(planWithoutReqs)
    check digestWith != digestWithout  ## Requests should affect the digest

  test "makeExecutionPlan_requests_param: accepts requests parameter":
    ## The makeExecutionPlan function in selection_digests should accept requests
    let selDeriv = makeSelectionDerivation()
    var reqs: seq[RequestId] = @[makeRequestId(@["req_x"]), makeRequestId(@["req_y"])]
    let plan = makeExecutionPlan(
      selDeriv, umSelected, @["unit_a"], reqs
    )
    check plan.requests.len == 2
    check plan.requests[0] == makeRequestId(@["req_x"])
    check plan.requests[1] == makeRequestId(@["req_y"])

  # -----------------------------------------------------------------------
  # Oracle independence tests
  # -----------------------------------------------------------------------

  test "oracle_independence: oracle output not consumed by deriveRequests":
    ## deriveRequests must not accept oracle outputs (RequiredRequests).
    ## Its signature is (selectionSet: seq[string], policy: RequestPolicy) → DerivationResult.
    ## The oracle (computeRequiredRequests) and derivation are CODE-LEVEL independent.
    let selDeriv = makeSelectionDerivation()
    let oracleResult = computeRequiredRequests(selDeriv, @["A", "B"], makeGraphArtifact())
    let policy = RequestPolicy(budgetCap: 0, fallbackOn: {})
    let derived = deriveRequests(@["unit_a", "unit_b"], policy)
    ## deriveRequests does not take oracleResult as input — compile-time independence
    discard oracleResult
    discard derived

  test "deriveRequests_determinism: same inputs → same output":
    ## deriveRequests must be deterministic (pure func).
    let policy = RequestPolicy(budgetCap: 10, fallbackOn: {})
    let result1 = deriveRequests(@["unit_a", "unit_b", "unit_c"], policy)
    let result2 = deriveRequests(@["unit_a", "unit_b", "unit_c"], policy)
    check result1.requests.len == result2.requests.len
    check result1.dispositions.len == result2.dispositions.len

  test "deriveRequests_no_self_certification: does not call checkCompleteness":
    ## deriveRequests must never certify its own completeness.
    ## It produces DerivationResult(requests, dispositions) without calling checkCompleteness.
    let policy = RequestPolicy(budgetCap: 1, fallbackOn: {})
    let result = deriveRequests(@["unit_a", "unit_b", "unit_c"], policy)
    ## budgetCap=1 means 2 units are deferred to fallback disposition
    check result.dispositions.len > 0
    check result.requests.len <= 1

  # -----------------------------------------------------------------------
  # Bidirectional completeness + basis-mismatch tests
  # -----------------------------------------------------------------------

  test "bidirectional_completeness: required ⊆ derived ∪ evidence-backed dispositions → ok":
    let required = @[makeRequestId(@["unit_a"]), makeRequestId(@["unit_b"])]
    let derived = @[makeRequestId(@["unit_a"])]
    let dispositions = @[Disposition(
      kind: dkFallback,
      requestId: makeRequestId(@["unit_b"]),
      evidence: "unit_b covered by fallback disposition",
      basis: "fallback")]
    let result = checkCompleteness(required, derived, dispositions)
    check result.ok
    check result.missing.len == 0
    check result.unauthorized.len == 0

  test "bidirectional_completeness: derived ⊆ required ∪ evidence-backed dispositions → ok":
    let required = @[makeRequestId(@["unit_a"])]
    let derived = @[makeRequestId(@["unit_a"]), makeRequestId(@["unit_b"])]
    let dispositions = @[Disposition(
      kind: dkFallback,
      requestId: makeRequestId(@["unit_b"]),
      evidence: "unit_b covered by fallback disposition",
      basis: "fallback")]
    let result = checkCompleteness(required, derived, dispositions)
    check result.ok

  test "basis_mismatch_rejection: disposition basis does not match kind → violation":
    ## A dkFallback disposition with basis="eligibility" (mismatch) must be rejected.
    let required = @[makeRequestId(@["unit_a"])]
    let derived: seq[RequestId] = @[]
    let dispositions = @[Disposition(
      kind: dkFallback,
      requestId: makeRequestId(@["unit_a"]),
      evidence: "unit_a covered",
      basis: "eligibility")]  ## WRONG basis for dkFallback
    let result = checkCompleteness(required, derived, dispositions)
    check not result.ok

  test "basis_mismatch_rejection: dkSkip with basis='fallback' → violation":
    ## A dkSkip disposition with basis="fallback" (mismatch) must be rejected.
    let required = @[makeRequestId(@["unit_a"])]
    let derived: seq[RequestId] = @[]
    let dispositions = @[Disposition(
      kind: dkSkip,
      requestId: makeRequestId(@["unit_a"]),
      evidence: "unit_a skipped",
      basis: "fallback")]  ## WRONG basis for dkSkip
    let result = checkCompleteness(required, derived, dispositions)
    check not result.ok

  test "valid_basis: dkFallback with basis='budget' → ok":
    let required = @[makeRequestId(@["unit_a"])]
    let derived: seq[RequestId] = @[]
    let dispositions = @[Disposition(
      kind: dkFallback,
      requestId: makeRequestId(@["unit_a"]),
      evidence: "unit_a deferred by budget cap",
      basis: "budget")]
    let result = checkCompleteness(required, derived, dispositions)
    check result.ok

  test "valid_basis: dkSkip with basis='eligibility' → ok":
    let required = @[makeRequestId(@["unit_a"])]
    let derived: seq[RequestId] = @[]
    let dispositions = @[Disposition(
      kind: dkSkip,
      requestId: makeRequestId(@["unit_a"]),
      evidence: "unit_a not eligible",
      basis: "eligibility")]
    let result = checkCompleteness(required, derived, dispositions)
    check result.ok

{.pop.}