import std/[unittest, json, os, strutils]
import ../../src/core/results
import ../../src/core/utils/repo_root
import ../../src/core/trusted/specification_artifact
import ../../src/core/trusted/evidence_calculus
import ../../src/core/trusted/assurance_profile
import ../../src/core/trusted/claim_authority
import ../../src/verification/lean_lsp_protocol
import ../../src/verification/obligation/kernel_acceptance_authority
import ../../src/verification/obligation/verification_decision_authority
import ../../src/verification/obligation/canonical_verification
import ../../src/verification/obligation/lean_kernel_boundary
import ../../src/verification/obligation/lean_evidence

## S0/I4/I5 acceptance tests — docs/spec/base36_sizing_binding_contract.md §7.
##
## Opacity note: receipts are obtained ONLY through the canonical sink
## `canonicalLeanKernelCheck` (real Lean kernel execution) — same discipline
## as test_evidence_truth_boundary.nim. The sorry-bearing artifacts here are
## genuine: Lean accepts `sorry` with exit 0, which is exactly the
## over-grading risk the canonical policy change closes (I4).

proc trivialTheoremSource(name: string): string =
  "theorem " & name & " : True := trivial\n"

proc sinkReceipt(name: string): Result[LeanKernelCheckReceipt, string] =
  canonicalLeanKernelCheck(trivialTheoremSource(name))

proc overlayNode(): JsonNode =
  parseJson(readFile(repoRootConst() / "config" / "spec" /
                     "base36_sizing_relational_spec.json"))

proc claimCtx(spec: SpecificationArtifact; signal: ClaimSignal): ClaimContext =
  var bundle: EvidenceBundle
  bundle.specificationArtifact = spec
  bundle.facts.solver.solverIdentity = "z3"
  bundle.facts.solver.smtHash = "abc123"
  ClaimContext(
    subjectId: "stew/base36.nim", sourceIdentity: "h", specification: spec,
    semanticProfileId: spec.specIdentity, obligationGenerated: true,
    supported: true, dependenciesSatisfied: true, proofSignal: signal,
    evidenceBundle: bundle, policyId: "apV1")

suite "I4 — canonical verification policy (contract §5)":

  test "A6: canonicalVerificationPolicy is the committed contract policy":
    let policy = canonicalVerificationPolicy()
    check policy.allowedAxioms.len == LeanAxiomAllowlist.len
    for a in LeanAxiomAllowlist:
      check a in policy.allowedAxioms
    check policy.sorryPolicy == spForbid

  test "positive control: canonical policy verifies a clean KAA":
    let receipt = sinkReceipt("base36ContractOk").get()
    let kaa = bindReceipt(receipt).get()
    check evaluate(kaa, canonicalVerificationPolicy()) == vdVerified

  test "A2: sorry-bearing KAA is rejected by the canonical policy":
    let receipt = sinkReceipt("base36ContractSorryUnit").get()
    let kaa = bindReceipt(receipt,
                          axioms = @["sorryAx"],
                          sorryScan = @["sorry", "declaration uses 'sorry'"]).get()
    check evaluate(kaa, canonicalVerificationPolicy()) == vdPolicyRejected

  test "A2 end-to-end: a real sorry artifact yields a sorryAx profile and is rejected":
    let sorrySource = "theorem base36ContractSorryReal : True := by sorry\n"
    let receiptR = canonicalLeanKernelCheck(sorrySource)
    check receiptR.isOk()  # Lean accepts sorry with exit 0 — the risk I4 closes
    let receipt = receiptR.get()
    let probeSource = sorrySource & "\n#print axioms " &
                      receipt.receiptTheoremIdentity & "\n"
    let (probeOut, probeExit) = runLeanProbe(probeSource, "_axioms", 120_000)
    check probeExit == 0
    let axiomProfile = parseAxiomProfile(probeOut)
    check "sorryAx" in axiomProfile
    let scan = scanSorryMarkers(sorrySource, receipt.receiptKernelObservation)
    check scan.len > 0
    let kaa = bindReceipt(receipt, axiomProfile, scan).get()
    check kaa.kaaSorryScan().len > 0
    check evaluate(kaa, canonicalVerificationPolicy()) == vdPolicyRejected

  test "A3: an empty allowlist rejects an axiom-bearing KAA (never silently skips)":
    let receipt = sinkReceipt("base36ContractEmptyAllow").get()
    let kaa = bindReceipt(receipt, axioms = @["propext"]).get()
    let policy = VerificationPolicy(allowedAxioms: @[], sorryPolicy: spForbid)
    check evaluate(kaa, policy) == vdPolicyRejected
    check policySatisfied(kaa, policy) == false

  test "A3: an empty allowlist still qualifies a KAA with no observed axioms":
    let receipt = sinkReceipt("base36ContractEmptyClean").get()
    let kaa = bindReceipt(receipt).get()
    check evaluate(kaa, VerificationPolicy(allowedAxioms: @[],
                                           sorryPolicy: spForbid)) == vdVerified

  test "A4: spAllow caps a sorry-bearing KAA at Candidate (doc == code)":
    let receipt = sinkReceipt("base36ContractSpAllow").get()
    let kaa = bindReceipt(receipt, sorryScan = @["sorry"]).get()
    let policy = VerificationPolicy(allowedAxioms: @["propext"], sorryPolicy: spAllow)
    check evaluate(kaa, policy) == vdCandidate
    check evaluate(kaa, policy) != vdVerified
    check policySatisfied(kaa, policy) == false

  test "A4: spIgnore (deprecated) follows the spAllow cap":
    let receipt = sinkReceipt("base36ContractSpIgnore").get()
    let kaa = bindReceipt(receipt, sorryScan = @["sorry"]).get()
    check evaluate(kaa, VerificationPolicy(allowedAxioms: @["propext"],
                                           sorryPolicy: spIgnore)) == vdCandidate

  test "A4: a clean KAA under spAllow still qualifies (cap is sorry-precise)":
    let receipt = sinkReceipt("base36ContractCleanAllow").get()
    let kaa = bindReceipt(receipt).get()
    check evaluate(kaa, VerificationPolicy(allowedAxioms: @[],
                                           sorryPolicy: spAllow)) == vdVerified

  test "scanSorryMarkers measures artifact and kernel markers":
    check scanSorryMarkers("theorem t : True := trivial", "").len == 0
    check scanSorryMarkers("theorem t : True := by sorry",
                           "warning: declaration uses 'sorry'") ==
      @["sorry", "declaration uses 'sorry'"]
    check scanSorryMarkers("theorem t : True := trivial",
                           "declaration uses 'sorry'") ==
      @["declaration uses 'sorry'"]

suite "I5 — out-of-tree soExplicit overlay (contract §2)":

  test "A5: the committed overlay loads as an authorized soExplicit spec":
    let loaded = explicitSpecFromOverlay(overlayNode())
    check loaded.isOk()
    let spec = loaded.get()
    check spec.origin == soExplicit
    check isAuthorizedForVerification(spec.origin)
    check spec.canonicalSpecIR.len == 6
    check "decodedLength(encodedLength(n)) == n" in spec.canonicalSpecIR
    check "0 <= n" in spec.canonicalSpecIR
    check "n <= 33297371974204966" in spec.canonicalSpecIR

  test "A5: a tampered overlay origin fails closed (cannot mint soMined authority)":
    var node = overlayNode()
    node["specOrigin"] = %"soMined"
    check explicitSpecFromOverlay(node).isErr()

  test "A5: a mined/LLM spec still yields NOT PROVED (clNoSpecification)":
    let spec = explicitSpecFromOverlay(overlayNode()).get()
    let mined = SpecificationArtifact(
      canonicalSpecIR: spec.canonicalSpecIR,
      origin: soMined, ruleId: spec.ruleId, ruleVersion: spec.ruleVersion)
    check not isAuthorizedForVerification(mined.origin)
    check deriveClaim(claimCtx(mined, psUnsat), apV1).outcome == clNoSpecification

  test "A5: the explicit overlay spec is authorized through deriveClaim":
    let spec = explicitSpecFromOverlay(overlayNode()).get()
    check deriveClaim(claimCtx(spec, psUnsat), apV1).outcome == clProved
