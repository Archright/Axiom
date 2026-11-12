import std/[unittest, options, tables, strutils]
import core/trusted/verification_model_types
import core/trusted/axiom_ir_helpers
import core/trusted/symbol_table_types
import core/trusted/verification_result_types
import core/trusted/candidate_evidence
import core/contracts/z3_extraction
import core/gate/evidence_authority_gate
import verification/evidence_validator

let bv64 = irTypeBitVec64()

suite "Evidence Authority Gate — authority boundary enforcement":
  test "assertEvidenceAuthority accepts EvidenceValidator.validate":
    check assertEvidenceAuthority("EvidenceValidator.validate") == true

  test "assertEvidenceAuthority rejects raw solver paths":
    check assertEvidenceAuthority("runZ3Proof") == false
    check assertEvidenceAuthority("runZ3ProofSafe") == false
    check assertEvidenceAuthority("runLean4FormalProof") == false

  test "assertEvidenceAuthority rejects unknown producers":
    check assertEvidenceAuthority("unknownProducer") == false

  test "proofResultToCandidateEvidence produces cesSolver source":
    let pr = ProofResult(
      status: psProven,
      verificationStatus: vsInconclusive,
      counterexample: none(Table[string, string]),
      procsChecked: 0,
      procsProven: 1,
      procsViolated: 0,
      procsInconclusive: 0,
      reports: @[]
    )
    let ce = proofResultToCandidateEvidence(pr, "z3")
    check ce.source == cesSolver
    check ce.provenance.contains("solver:z3")
    check ce.provenance.contains("psProven")

  test "proofResultToCandidateEvidence carries no Safe verdict":
    let pr = ProofResult(
      status: psProven,
      verificationStatus: vsInconclusive,
      counterexample: none(Table[string, string]),
      procsChecked: 0,
      procsProven: 1,
      procsViolated: 0,
      procsInconclusive: 0,
      reports: @[]
    )
    let ce = proofResultToCandidateEvidence(pr, "z3")
    check ce.invariants.len == 0

  test "proofResultToCandidateEvidence for solver SAT (violated)":
    let pr = ProofResult(
      status: psViolated,
      verificationStatus: vsInconclusive,
      counterexample: none(Table[string, string]),
      procsChecked: 1,
      procsProven: 0,
      procsViolated: 1,
      procsInconclusive: 0,
      reports: @[]
    )
    let ce = proofResultToCandidateEvidence(pr, "z3")
    check ce.source == cesSolver
    check ce.provenance.contains("solver:z3")
    check ce.provenance.contains("psViolated")

  test "raw solver psProven alone does NOT yield vsProved without EvidenceValidator":
    let pr = ProofResult(
      status: psProven,
      verificationStatus: vsInconclusive,
      counterexample: none(Table[string, string]),
      procsChecked: 0,
      procsProven: 1,
      procsViolated: 0,
      procsInconclusive: 0,
      reports: @[]
    )
    let ce = proofResultToCandidateEvidence(pr, "z3")
    check ce.source == cesSolver
    check ce.isEmpty()

  test "EvidenceValidator.validate is the sole Safe verdict producer":
    var sem = VMSemantic()
    sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
    sem.initExprs.add(irLit(0))
    let iVar = irVar("i", bv64)
    var upd = ParallelUpdate()
    upd.addAssignment("i", irAdd(iVar, irLit(1)))
    sem.initTransition(NodeId(1), NodeId(2), irLt(iVar, irLit(10)), upd)
    sem.initObligation(irLe(iVar, irLit(11)), okImplicitSafety, SymbolOrigin(kind: sokImplicit))
    sem.logicalDomain = ldBitVec
    var st = SymbolTable()
    st.addSymbol("i", SymbolOrigin(kind: sokLoopIndex), bv64)
    let model = VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: st, sourceLocation: ""))

    let ce = candidateEvidence(cesSolver, @[("state", "(>= i 0)")], "solver:z3", "")
    let validator = newEvidenceValidator(z3Path = "z3", timeoutMs = 3000)
    let ev = validator.validate(model, ce)
    check ev.overall.status in {vsProved, vsInconclusive}

  test "unauthorized producer cannot issue Safe verdict through gate":
    let pr = ProofResult(
      status: psProven,
      verificationStatus: vsInconclusive,
      counterexample: none(Table[string, string]),
      procsChecked: 0,
      procsProven: 1,
      procsViolated: 0,
      procsInconclusive: 0,
      reports: @[]
    )
    let ce = proofResultToCandidateEvidence(pr, "z3")
    check ce.source == cesSolver
    check ce.isEmpty()
    let unauthorized = "runZ3Proof"
    check assertEvidenceAuthority(unauthorized) == false