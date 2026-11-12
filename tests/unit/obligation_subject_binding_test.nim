# obligation_subject_binding_test.nim — I1 subject-bound obligation identity
#
# Cites:
#   - docs/spec/obligation_semantics.md §2.1a — Subject-Bound Obligation
#     Identity (evidence-facing id). The 5-tuple id names WHAT is claimed;
#     the bound id additionally names WHICH lowered subject semantics the
#     claim is about, so a shadow model cannot attach.
#   - identity_collision_test.nim — component-injectivity precedent: any
#     semantic input change must change the identity.
#
# Execution: nim c --hints:off -r --path:src tests/unit/obligation_subject_binding_test.nim

import std/[unittest, os, strutils, options]

import ../../src/core/results
import ../../src/core/crypto/hash_kernel
import ../../src/core/trusted/axiom_ir
import ../../src/core/trusted/axiom_ir_helpers
import ../../src/verification/obligation/obligation_types
import ../../src/verification/obligation/identity
import ../../src/verification/obligation/kernel_acceptance_authority
import ../../src/verification/obligation/lean_kernel_boundary

proc gitRef40(): string =
  sha256Hex("git")[0 .. 39]

proc validBinding(): ObligationSubjectBinding =
  ObligationSubjectBinding(
    obligationTupleId: sha256Hex("tuple"),
    subjectTreeMerkleRoot: sha256Hex("tree"),
    subjectModuleSha256: sha256Hex("module-bytes"),
    subjectGitRef: gitRef40(),
    pnodeCanonicalV2Digest: "sha256:v2:nim-pnode-canonical-v2:" & sha256Hex("pnode"),
    irDigest: sha256Hex("ir"),
    eaNimDigest: sha256Hex("ea-nim"),
    eaLeanDigest: sha256Hex("ea-lean"),
    eaIrcheckBinaryDigest: sha256Hex("ircheck-bin"),
    eaAgreed: true,
    completenessRecordDigest: sha256Hex("completeness"),
    leanSourceHash: sha256Hex("lean-source"),
    toolchainFingerprint: sha256Hex("toolchain")
  )

proc shadowSubjectFuncDef(bodyConst: int64): IRFuncDef =
  ## Two subjects sharing name/signature/postcondition but differing in body —
  ## the shadow-model shape: same 5-tuple, different lowering.
  IRFuncDef(
    name: "encodedLength",
    params: @[IRFuncParam(name: "n", ty: irTypeBitVec64(), constraint: none(IRExpr))],
    retType: irTypeBitVec64(),
    body: irBinOp(boAdd, irVar("n", irTypeBitVec64()), irLit(bodyConst)))

# ==========================================================================
# Suite 1 — bound identity: determinism + per-component injectivity
# ==========================================================================

suite "I1 — bound obligation identity is deterministic and component-complete":

  test "same binding → same id, 64 hex":
    let id1 = computeBoundObligationId(validBinding())
    let id2 = computeBoundObligationId(validBinding())
    check id1 == id2
    check id1.len == 64

  test "changing any bound component changes the id":
    let base = validBinding()
    let baseId = computeBoundObligationId(base)
    var m: ObligationSubjectBinding
    m = base; m.obligationTupleId = sha256Hex("tuple-2")
    check computeBoundObligationId(m) != baseId
    m = base; m.subjectTreeMerkleRoot = sha256Hex("tree-2")
    check computeBoundObligationId(m) != baseId
    m = base; m.subjectModuleSha256 = sha256Hex("module-bytes-2")
    check computeBoundObligationId(m) != baseId
    m = base; m.subjectGitRef = gitRef40()[1 .. ^1] & "0"
    check computeBoundObligationId(m) != baseId
    m = base; m.pnodeCanonicalV2Digest = base.pnodeCanonicalV2Digest & "-x"
    check computeBoundObligationId(m) != baseId
    m = base; m.irDigest = sha256Hex("ir-2")
    check computeBoundObligationId(m) != baseId
    m = base; m.eaNimDigest = sha256Hex("ea-nim-2")
    check computeBoundObligationId(m) != baseId
    m = base; m.eaLeanDigest = sha256Hex("ea-lean-2")
    check computeBoundObligationId(m) != baseId
    m = base; m.eaIrcheckBinaryDigest = sha256Hex("ircheck-bin-2")
    check computeBoundObligationId(m) != baseId
    m = base; m.eaAgreed = false
    check computeBoundObligationId(m) != baseId
    m = base; m.completenessRecordDigest = sha256Hex("completeness-2")
    check computeBoundObligationId(m) != baseId
    m = base; m.leanSourceHash = sha256Hex("lean-source-2")
    check computeBoundObligationId(m) != baseId
    m = base; m.toolchainFingerprint = sha256Hex("toolchain-2")
    check computeBoundObligationId(m) != baseId

# ==========================================================================
# Suite 2 — fail-closed: "" is not an identity
# ==========================================================================

suite "I1 — bound identity is fail-closed on missing/malformed components":

  test "empty binding yields no identity":
    check computeBoundObligationId(default(ObligationSubjectBinding)) == ""

  test "any absent required component yields no identity":
    var m: ObligationSubjectBinding
    m = validBinding(); m.obligationTupleId = ""
    check computeBoundObligationId(m) == ""
    m = validBinding(); m.subjectTreeMerkleRoot = ""
    check computeBoundObligationId(m) == ""
    m = validBinding(); m.subjectModuleSha256 = ""
    check computeBoundObligationId(m) == ""
    m = validBinding(); m.subjectGitRef = ""
    check computeBoundObligationId(m) == ""
    m = validBinding(); m.pnodeCanonicalV2Digest = ""
    check computeBoundObligationId(m) == ""
    m = validBinding(); m.irDigest = ""
    check computeBoundObligationId(m) == ""
    m = validBinding(); m.eaNimDigest = ""
    check computeBoundObligationId(m) == ""
    m = validBinding(); m.eaLeanDigest = ""
    check computeBoundObligationId(m) == ""
    m = validBinding(); m.eaIrcheckBinaryDigest = ""
    check computeBoundObligationId(m) == ""
    m = validBinding(); m.completenessRecordDigest = ""
    check computeBoundObligationId(m) == ""
    m = validBinding(); m.leanSourceHash = ""
    check computeBoundObligationId(m) == ""
    m = validBinding(); m.toolchainFingerprint = ""
    check computeBoundObligationId(m) == ""

  test "malformed digests yield no identity":
    var m: ObligationSubjectBinding
    m = validBinding(); m.irDigest = "zzzz-not-hex"
    check computeBoundObligationId(m) == ""
    m = validBinding(); m.subjectGitRef = "0123456789abcdef"  # wrong length
    check computeBoundObligationId(m) == ""
    m = validBinding(); m.subjectModuleSha256 = toUpperAscii(sha256Hex("x"))
    check computeBoundObligationId(m) == ""

# ==========================================================================
# Suite 3 — shadow-model non-attachability (the reason the binding exists)
# ==========================================================================

suite "I1 — a shadow model cannot produce or attach to the subject's id":

  test "same 5-tuple, different lowering: 5-tuple id collides, bound id does not":
    ## The shadow attack against the 5-tuple id: subject A and its shadow B
    ## share name/kind/assumptions/predicate/derivationRule, so the 5-tuple
    ## id is identical — evidence sealed under it attaches to both.
    let subject = "stew/base36.nim::encodedLength"
    let kind = okContractPost
    let assumptions = ""
    let predicate = "fixed-canonical-predicate"
    let rule = "obs:contract"
    let tupleIdA = computeObligationId(subject, kind, assumptions, predicate, rule)
    let tupleIdB = computeObligationId(subject, kind, assumptions, predicate, rule)
    check tupleIdA == tupleIdB

    ## The bound id separates them: the IR digest (and only it) differs.
    let funcA = shadowSubjectFuncDef(1)
    let funcB = shadowSubjectFuncDef(2)
    let irA = sha256Hex(serializeIRFuncDef(funcA))
    let irB = sha256Hex(serializeIRFuncDef(funcB))
    check irA != irB

    var bindingA = validBinding()
    bindingA.obligationTupleId = tupleIdA
    bindingA.irDigest = irA
    var bindingB = bindingA
    bindingB.irDigest = irB
    let boundA = computeBoundObligationId(bindingA)
    let boundB = computeBoundObligationId(bindingB)
    check boundA.len == 64
    check boundB.len == 64
    check boundA != boundB

# ==========================================================================
# Suite 4 — evidence seal gate: newCanonicalLeanEvidenceBound
# ==========================================================================

suite "I1 — evidence can only be sealed under an id that names the subject":

  test "fully consistent subject binding still cannot fabricate evidence " &
       "without the KAA authority chain":
    ## There is no test-side receipt forgery path (private constructor); a
    ## default KAA must be rejected even when every subject-side component
    ## is internally consistent.
    let funcA = shadowSubjectFuncDef(1)
    var binding = validBinding()
    binding.irDigest = sha256Hex(serializeIRFuncDef(funcA))
    let leanSource = "def encodedLength : Int := 1\ntheorem encodedLength_post : 1 = 1 := rfl\n"
    binding.leanSourceHash = sha256Hex(leanSource)
    let id = computeBoundObligationId(binding)
    check id.len == 64
    let sealed = newCanonicalLeanEvidenceBound(
      obligationId = id,
      binding = binding,
      funcDef = funcA,
      proposition = "post",
      leanSource = leanSource,
      kaa = default(KernelAcceptanceAttestation),
      toolchainFingerprint = binding.toolchainFingerprint,
      executionContractDigest = sha256Hex("contract"))
    check sealed.isErr

  test "binding.irDigest is re-measured against the actual funcDef":
    let funcA = shadowSubjectFuncDef(1)
    var binding = validBinding()
    binding.irDigest = sha256Hex("forged-ir-digest")
    let sealed = newCanonicalLeanEvidenceBound(
      obligationId = sha256Hex("anything"),
      binding = binding,
      funcDef = funcA,
      proposition = "post",
      leanSource = "source",
      kaa = default(KernelAcceptanceAttestation),
      toolchainFingerprint = binding.toolchainFingerprint,
      executionContractDigest = sha256Hex("contract"))
    check sealed.isErr
    check sealed.error.contains("irDigest")

  test "obligationId that is not the recomputed bound identity is refused":
    let funcA = shadowSubjectFuncDef(1)
    var binding = validBinding()
    binding.irDigest = sha256Hex(serializeIRFuncDef(funcA))
    let sealed = newCanonicalLeanEvidenceBound(
      obligationId = sha256Hex("unrelated-id"),
      binding = binding,
      funcDef = funcA,
      proposition = "post",
      leanSource = "source",
      kaa = default(KernelAcceptanceAttestation),
      toolchainFingerprint = binding.toolchainFingerprint,
      executionContractDigest = sha256Hex("contract"))
    check sealed.isErr
    check sealed.error.contains("shadow-model")

  test "incomplete binding yields no identity and is refused":
    let funcA = shadowSubjectFuncDef(1)
    var binding = validBinding()
    binding.irDigest = sha256Hex(serializeIRFuncDef(funcA))
    binding.completenessRecordDigest = ""
    let sealed = newCanonicalLeanEvidenceBound(
      obligationId = "whatever",
      binding = binding,
      funcDef = funcA,
      proposition = "post",
      leanSource = "source",
      kaa = default(KernelAcceptanceAttestation),
      toolchainFingerprint = binding.toolchainFingerprint,
      executionContractDigest = sha256Hex("contract"))
    check sealed.isErr
    check sealed.error.contains("fail-closed")

  test "hand-written Lean source cannot attach: bound identity names the " &
       "rendered source, not the shadow source":
    ## The identity was computed over the rendered source's hash; sealing
    ## evidence whose source bytes differ (hand-written definition, stdlib
    ## stand-in, LLM-generated theorem) must fail the leanSourceHash gate.
    let funcA = shadowSubjectFuncDef(1)
    var binding = validBinding()
    binding.irDigest = sha256Hex(serializeIRFuncDef(funcA))
    let renderedSource = "def encodedLength (n : Int) : Int := n + 1\n"
    binding.leanSourceHash = sha256Hex(renderedSource)
    let id = computeBoundObligationId(binding)
    let handWritten = "theorem shadowLength : True := trivial\n"
    let sealed = newCanonicalLeanEvidenceBound(
      obligationId = id,
      binding = binding,
      funcDef = funcA,
      proposition = "post",
      leanSource = handWritten,
      kaa = default(KernelAcceptanceAttestation),
      toolchainFingerprint = binding.toolchainFingerprint,
      executionContractDigest = sha256Hex("contract"))
    check sealed.isErr
    check sealed.error.contains("leanSourceHash")

  test "toolchain mismatch between binding and measured execution is refused":
    let funcA = shadowSubjectFuncDef(1)
    var binding = validBinding()
    binding.irDigest = sha256Hex(serializeIRFuncDef(funcA))
    let renderedSource = "def encodedLength (n : Int) : Int := n + 1\n"
    binding.leanSourceHash = sha256Hex(renderedSource)
    let sealed = newCanonicalLeanEvidenceBound(
      obligationId = computeBoundObligationId(binding),
      binding = binding,
      funcDef = funcA,
      proposition = "post",
      leanSource = renderedSource,
      kaa = default(KernelAcceptanceAttestation),
      toolchainFingerprint = sha256Hex("other-toolchain"),
      executionContractDigest = sha256Hex("contract"))
    check sealed.isErr
    check sealed.error.contains("toolchainFingerprint")

# ==========================================================================
# Suite 5 — evaluation-implementation digest (lowering code inside identity)
# ==========================================================================

suite "I1 — evaluation implementation digest binds the lowering code":

  test "measured digests equal the actual file contents (repo-root anchor)":
    let measured = measureEvaluationImplementationDigests()
    check measured.pnodeToCanon == sha256Hex(readFile("src/core/trusted/pnode_to_canon.nim"))
    check measured.astToIr == sha256Hex(readFile("src/core/trusted/ast_to_ir.nim"))
    check measured.leanRenderer == sha256Hex(readFile("src/core/trusted/ir_to_lean.nim"))
    check measured.denotationLean == sha256Hex(readFile("proofs/IR/Denotation.lean"))
    check measured.pnodeToCanon.len == 64

  test "evaluation implementation digest is deterministic and injective per field":
    let d = measureEvaluationImplementationDigests()
    let d2 = measureEvaluationImplementationDigests()
    check evaluationImplementationDigest(d) == evaluationImplementationDigest(d2)
    var m = d
    m.astToIr = sha256Hex("widened-semantics")
    check evaluationImplementationDigest(m) != evaluationImplementationDigest(d)

  test "bound bundle fingerprint folds the evaluation implementation in":
    let tf = sha256Hex("toolchain")
    let deps = @["dep-a", "dep-b"]
    let evalImpl = sha256Hex("eval-impl")
    let withEval = computeSemanticBundleFingerprintBound(tf, deps, evalImpl)
    let withoutEval = computeSemanticBundleFingerprint(tf, deps)
    check withEval.len == 64
    check withEval != withoutEval
    check computeSemanticBundleFingerprintBound(tf, deps, sha256Hex("eval-impl-2")) != withEval

  test "a semantics-widening edit to the lowering code changes the bundle digest":
    ## Lowering content measured from a sandbox tree; editing one lowering
    ## file there must change the measured bundle digest — old evidence
    ## cannot be reused under the new semantics.
    let tmpBase = getTempDir() / ("axiom_i1_binding_" & $getCurrentProcessId())
    createDir(tmpBase / "src" / "core" / "trusted")
    createDir(tmpBase / "proofs" / "IR")
    try:
      let leanBin = tmpBase / "lean_bin"
      writeFile(leanBin, "lean-binary-content")
      writeFile(tmpBase / "src" / "core" / "trusted" / "pnode_to_canon.nim", "lowering-v1")
      writeFile(tmpBase / "src" / "core" / "trusted" / "ast_to_ir.nim", "lowering-v1")
      writeFile(tmpBase / "src" / "core" / "trusted" / "ir_to_lean.nim", "lowering-v1")
      writeFile(tmpBase / "proofs" / "IR" / "Denotation.lean", "denotation-v1")
      writeFile(tmpBase / "lean-toolchain", "leanprover/lean4:v4.33.0\n")

      let origCwd = getCurrentDir()
      try:
        setCurrentDir(tmpBase)
        let measured = measureEvaluationImplementationDigests()
        check measured.pnodeToCanon == sha256Hex("lowering-v1")
        let digestBefore = computeBundleDigest(leanBin, "", 120_000, "lake env lean")
        writeFile(tmpBase / "src" / "core" / "trusted" / "pnode_to_canon.nim",
                  "lowering-v2-widened")
        let digestAfter = computeBundleDigest(leanBin, "", 120_000, "lake env lean")
        check digestBefore.len == 64
        check digestAfter.len == 64
        check digestBefore != digestAfter
      finally:
        setCurrentDir(origCwd)
    finally:
      removeDir(tmpBase)

# ==========================================================================
# Suite 6 — honest toolchain fingerprint (no hardcoded version labels)
# ==========================================================================

suite "I1 — toolchain fingerprint segments are measured, not labeled":

  test "lean pin is parsed from manifest content; unmeasurable pin is empty":
    check parseLeanToolchainPin("leanprover/lean4:v4.33.0\n") == "lean-4.33.0"
    check parseLeanToolchainPin("leanprover/lean4:v4.34.1\n") == "lean-4.34.1"
    check parseLeanToolchainPin("") == ""
    check parseLeanToolchainPin("no-version-separator") == ""
    check parseLeanToolchainPin("leanprover/lean4:vX.Y\n") == ""

  test "bundle digest is deterministic and independent of hardcoded labels":
    let tmpBase = getTempDir() / ("axiom_i1_label_" & $getCurrentProcessId())
    createDir(tmpBase)
    try:
      let leanBin = tmpBase / "lean_bin"
      writeFile(leanBin, "lean-binary-content")
      let origCwd = getCurrentDir()
      try:
        setCurrentDir(tmpBase)
        let d1 = computeBundleDigest(leanBin, "", 120_000, "lake env lean")
        let d2 = computeBundleDigest(leanBin, "", 120_000, "lake env lean")
        check d1 == d2
        check d1.len == 64
        ## The old label composition must not be reproducible: the measured
        ## payload differs from the legacy sha256("nim-2.2.10|lean-4.33.0|...").
        check d1 != sha256Hex("nim-2.2.10|lean-4.33.0|lake env lean|120000")
      finally:
        setCurrentDir(origCwd)
    finally:
      removeDir(tmpBase)

# ==========================================================================
# Suite 7 — single-origin claim-carrier mode (base32 rem §3 D2)
# ==========================================================================
## Cites:
##   - docs/spec/nim_stew_base32_rem_binding_contract.md §3 D2 — the claim
##     CARRIER is sealed through ONE extraction-agreement leg for its single
##     original symbol plus the deterministic derivation digest; the ea2 slot
##     MUST be empty (a filled second leg is a fabricated measurement).
##   - docs/spec/obligation_semantics.md §2.1a — mode non-conflation: the
##     three binding modes never share a payload shape.

proc claimCarrierBinding(): ObligationSubjectBinding =
  var b = validBinding()
  b.synthesisDerivationDigest =
    sha256Hex("term-splice-v1|rule=decodedLength_rem_range|symbol=decodedLength")
  b.claimCarrierSingleOrigin = true
  b

suite "I1 — single-origin claim carrier binds ONE leg and an empty ea2 slot":

  test "canonical single-origin binding yields a deterministic 64-hex id":
    let id1 = computeBoundObligationId(claimCarrierBinding())
    let id2 = computeBoundObligationId(claimCarrierBinding())
    check id1 == id2
    check id1.len == 64

  test "derivation digest without the carrier flag is composite — missing " &
       "second leg fails closed":
    ## Mode non-conflation: the flag selects carrier mode; the same derivation
    ## digest without it DEMANDS the two-leg composite set, whose absence fails
    ## closed — the modes are never silently conflated.
    var composite = claimCarrierBinding()
    composite.claimCarrierSingleOrigin = false
    check computeBoundObligationId(composite) == ""
    composite.ea2NimDigest = sha256Hex("ea2-nim")
    composite.ea2LeanDigest = sha256Hex("ea2-lean")
    composite.ea2IrcheckBinaryDigest = sha256Hex("ea2-bin")
    check computeBoundObligationId(composite).len == 64
    ## And the completed composite id is distinct from the carrier id —
    ## identical components under different modes never share an identity.
    check computeBoundObligationId(composite) !=
          computeBoundObligationId(claimCarrierBinding())

  test "single-origin id is distinct from the two-leg composite id":
    var composite = claimCarrierBinding()
    composite.claimCarrierSingleOrigin = false
    composite.ea2NimDigest = sha256Hex("ea2-nim")
    composite.ea2LeanDigest = sha256Hex("ea2-lean")
    composite.ea2IrcheckBinaryDigest = sha256Hex("ea2-bin")
    check computeBoundObligationId(composite).len == 64
    check computeBoundObligationId(composite) !=
          computeBoundObligationId(claimCarrierBinding())

  test "missing or malformed derivation digest yields no identity":
    var m = claimCarrierBinding()
    m.synthesisDerivationDigest = ""
    check computeBoundObligationId(m) == ""
    m = claimCarrierBinding()
    m.synthesisDerivationDigest = "zzzz-not-hex"
    check computeBoundObligationId(m) == ""

  test "a filled ea2 slot yields no identity — a fabricated second leg is theater":
    var m = claimCarrierBinding()
    m.ea2NimDigest = sha256Hex("ea2-nim")
    check computeBoundObligationId(m) == ""
    m = claimCarrierBinding()
    m.ea2LeanDigest = sha256Hex("ea2-lean")
    check computeBoundObligationId(m) == ""
    m = claimCarrierBinding()
    m.ea2IrcheckBinaryDigest = sha256Hex("ea2-bin")
    check computeBoundObligationId(m) == ""

  test "derivation digest is an injective component of the carrier id":
    let base = claimCarrierBinding()
    let baseId = computeBoundObligationId(base)
    var m = base
    m.synthesisDerivationDigest =
      sha256Hex("term-splice-v1|rule=other_rule|symbol=decodedLength")
    check computeBoundObligationId(m) != baseId

  test "per-component injectivity holds in carrier mode too":
    let base = claimCarrierBinding()
    let baseId = computeBoundObligationId(base)
    var m: ObligationSubjectBinding
    m = base; m.eaAgreed = false
    check computeBoundObligationId(m) != baseId
    m = base; m.leanSourceHash = sha256Hex("lean-source-2")
    check computeBoundObligationId(m) != baseId
    m = base; m.toolchainFingerprint = sha256Hex("toolchain-2")
    check computeBoundObligationId(m) != baseId
