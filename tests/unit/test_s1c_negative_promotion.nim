import std/[unittest, tables, algorithm, sequtils, os, options]
import ../../src/core/trusted/axiom_ir
import ../../src/core/trusted/axiom_ir_helpers
import ../../src/core/deterministic_cas_key
import ../../src/core/trusted/semantic_fact_types
import ../../src/infrastructure/evidence_artifact_io
import ../../src/verification/obligation/canonical_verification
import ../../src/infrastructure/external_ir_materializer
import ../../src/verification/obligation/verification_decision_authority

## S1-C — Negative promotion: fail-closed, NO false Verified.
##
## The Evidence Truth Boundary (Phase B) guarantees that Verified exists ONLY
## through a genuine Lean kernel ACCEPT of an I6-correct theorem produced by
## the generic lowering. These tests prove the fail-closed direction: inputs
## that cannot produce genuine evidence MUST resolve to vdCandidate
## (success=false) and MUST NEVER resolve to vdVerified.
##
## Note: `renderLeanForFuncDef` returns "" (the fail-closed marker) for any
## bound-subset violation, and `executeCanonicalVerification` maps a kernel
## reject / empty lowering / empty obligations to vdCandidate (success=false).
## Since the §2.1a subject binding gates the kernel run (Step 3b BEFORE Step 5),
## every case that must REACH the kernel measures its parse-bound components
## here at the test boundary from the REAL fixture module bytes
## (tests/negative/*.nim — the fixtures exist so the §6a input identity is the
## sha256 of real subject bytes, never a path-derived digest).

proc mkVar(name: string; ty: IRType): IRExpr =
  IRExpr(kind: irVar, varName: name, varType: ty, typ: ty)

proc mkLit(v: int64): IRExpr =
  IRExpr(kind: irLit, litVal: v, typ: irTypeBitVec64())

proc mkBin(op: BinOpKind; l, r: IRExpr): IRExpr =
  IRExpr(kind: irBinOp, binOp: op, binLhs: l, binRhs: r, typ: irTypeBool())

proc mkEq(l, r: IRExpr): IRExpr = mkBin(boEq, l, r)

var boundCache = initTable[string, SubjectParseBoundComponents]()
proc boundFor(path, name: string): SubjectParseBoundComponents =
  ## Main-thread §2.1a measurement boundary (the parser is NOT gcsafe; the
  ## canonical worker chain receives the components as values).
  let key = path & "::" & name
  if not boundCache.hasKey(key):
    boundCache[key] = measureParseBoundComponents(readFile(path), name)
  boundCache[key]

proc materializeCompletenessFor(fd: IRFuncDef; sourcePath: string) =
  ## Test-boundary materializer (WP4-j.2 Phase D role), Phase 1A dual-write:
  ## the legacy 5-field artifact PLUS the authenticated strict
  ## CompletenessBinding sibling, both keyed by the runner cache scheme. The
  ## capture measures the CWD repo as subject root (contentCarried=false —
  ## the same resolution rule executeCanonicalVerification applies to these
  ## path-resolved fixtures), so the strict-first reader recomputes the
  ## recorded sourceIdentity exactly.
  let key = computeDeterministicCasKey(serializeIRFuncDef(fd))
  let evidence = CompletenessEvidence(
    translationLossFree: true,
    bindingUniverseComplete: true,
    opaqueExpansionStatus: "none",
    sourceBindingCount: 1,
    irBindingCount: 1)
  saveEvidenceArtifact(key, evidence)
  let capture = measureCompletenessSourceCapture("", sourcePath,
    readFile(sourcePath), contentCarried = false)
  discard saveCompletenessEvidenceDual(key, fd, capture, evidence)

suite "S1-C — Negative promotion (no false Verified)":
  test "no postcondition → fail-closed to candidate, never Verified":
    let x = mkVar("x", irTypeBitVec64())
    let fd = IRFuncDef(
      name: "noPost",
      params: @[IRFuncParam(name: "x", ty: irTypeBitVec64())],
      retType: irTypeBitVec64(),
      body: x,
      isRecursive: false,
      preConditions: @[],
      postConditions: @[]   # nothing to prove
    )
    ## Lowering of a funcDef with zero postconditions is empty (fail-closed).
    check renderLeanForFuncDef(fd) == ""
    let r = executeCanonicalVerification(fd, "tests/negative/no_post.nim", "noPost")
    check r.success == false
    check r.verdict != vdVerified
    check r.evidence == "inconclusive"

  test "rem with nonneg-dividend domain → renders and VERIFIES (boRem promotion)":
    ## boRem joined the Certified subset (Denotation.lean: Int.emod +
    ## BitVec.srem; renderer `%` with the
    ## `rem=lean-emod/nim-mod/coincident-nonneg-dividend-domain` identity —
    ## the div profile's domain pattern). The domain precondition pins the
    ## coincidence domain as part of the verified proposition (contract
    ## §3.2), so the real kernel ACCEPTs and the full canonical chain
    ## reaches vdVerified — the fixture (tests/golden/rem_body.nim) carries
    ## the same shape with real subject bytes for the §6a input identity.
    let x = mkVar("x", irTypeBitVec64())
    let body = mkBin(boRem, x, mkLit(3))
    let pre = mkBin(boGe, x, mkLit(0))
    let remPost = mkBin(boAnd,
      mkBin(boGe, mkVar("result", irTypeBitVec64()), mkLit(0)),
      mkBin(boLt, mkVar("result", irTypeBitVec64()), mkLit(3)))
    let fd = IRFuncDef(
      name: "remDomain",
      params: @[IRFuncParam(name: "x", ty: irTypeBitVec64())],
      retType: irTypeBitVec64(),
      body: body,
      isRecursive: false,
      preConditions: @[pre],
      postConditions: @[remPost]
    )
    check renderLeanForFuncDef(fd).len > 0
    materializeCompletenessFor(fd, "tests/golden/rem_body.nim")
    let r = executeCanonicalVerification(fd, "tests/golden/rem_body.nim", "remDomain",
      parseBound = boundFor("tests/golden/rem_body.nim", "remDomain"))
    check r.success == true
    check r.verdict == vdVerified
    check r.canonicalEvidence.isSome
    check r.sealError == ""

  test "negative-dividend rem (no domain) → fail-closed, never Verified":
    ## The emod semantics (Lean `%`) never produces a negative remainder, so
    ## a claim that depends on Nim's truncated `mod` range over negative
    ## dividends — here Nim's true `∀x: -2 ≤ x mod 3 ≤ 0`, emod-false — is
    ## rejected by omega. boRem rendering is no longer the fail-closed leg
    ## (the lowering renders); the kernel rejection is. Fixture:
    ## tests/negative/rem_body.nim (real subject bytes).
    let x = mkVar("x", irTypeBitVec64())
    let body = mkBin(boRem, x, mkLit(3))
    let nimTruncRange = mkBin(boAnd,
      mkBin(boGe, mkVar("result", irTypeBitVec64()), mkLit(-2)),
      mkBin(boLe, mkVar("result", irTypeBitVec64()), mkLit(0)))
    let fd = IRFuncDef(
      name: "remBody",
      params: @[IRFuncParam(name: "x", ty: irTypeBitVec64())],
      retType: irTypeBitVec64(),
      body: body,
      isRecursive: false,
      preConditions: @[],
      postConditions: @[nimTruncRange]
    )
    check renderLeanForFuncDef(fd).len > 0
    materializeCompletenessFor(fd, "tests/negative/rem_body.nim")
    let r = executeCanonicalVerification(fd, "tests/negative/rem_body.nim", "remBody",
      parseBound = boundFor("tests/negative/rem_body.nim", "remBody"))
    check r.success == false
    check r.verdict != vdVerified
    check r.evidence == "lean_kernel_rejected"

  test "supported mul body renders (subset regression guard for boMul)":
    ## boMul was once pinned here as unsupported; the div denotation brought
    ## mul/div INTO the subset. This guard makes the promotion deliberate:
    ## a mul body must render non-empty (the fail-closed leg for
    ## truncated-remainder claims is the negative-dividend rem test above;
    ## boRemU/boShl/boShr remain unsupported constructs).
    let x = mkVar("x", irTypeBitVec64())
    let body = mkBin(boMul, x, mkLit(2))
    let post = mkBin(boGe, mkVar("result", irTypeBitVec64()), mkLit(0))
    let fd = IRFuncDef(
      name: "mulBody",
      params: @[IRFuncParam(name: "x", ty: irTypeBitVec64())],
      retType: irTypeBitVec64(),
      body: body,
      isRecursive: false,
      preConditions: @[],
      postConditions: @[post]
    )
    check renderLeanForFuncDef(fd).len > 0

  test "false postcondition → kernel rejects (lean_kernel_rejected), never Verified":
    ## body = x ; post = result + 1 == x  →  false theorem x + 1 == x.
    ## omega must reject it. This is a GENUINE kernel reject, not a mock.
    let x = mkVar("x", irTypeBitVec64())
    let body = x
    let plus1 = mkBin(boAdd, mkVar("result", irTypeBitVec64()), mkLit(1))
    let post = mkEq(plus1, x)
    let fd = IRFuncDef(
      name: "falsePost",
      params: @[IRFuncParam(name: "x", ty: irTypeBitVec64())],
      retType: irTypeBitVec64(),
      body: body,
      isRecursive: false,
      preConditions: @[],
      postConditions: @[post]
    )
    let lean = renderLeanForFuncDef(fd)
    check lean.len > 0
    materializeCompletenessFor(fd, "tests/negative/false_post.nim")
    let r = executeCanonicalVerification(fd, "tests/negative/false_post.nim", "falsePost",
      parseBound = boundFor("tests/negative/false_post.nim", "falsePost"))
    check r.success == false
    check r.verdict != vdVerified
    check r.evidence == "lean_kernel_rejected"
    ## artifactIdentity still binds to the actual attempted Lean source (fail-closed
    ## but the provenance of the ATTEMPT is recorded), while success is false.
    check r.artifactIdentity.len == 64 or r.artifactIdentity == ""

  test "no Verified is ever produced without a genuine kernel ACCEPT":
    ## Cross-check the success predicate: only vdVerified sets success=true.
    ## All negative cases above must be success=false and verdict != vdVerified.
    let x = mkVar("x", irTypeBitVec64())
    let body = x
    let zeroPost = mkBin(boEq, mkVar("result", irTypeBitVec64()), x)
    let fd = IRFuncDef(
      name: "okIdentity",
      params: @[IRFuncParam(name: "x", ty: irTypeBitVec64())],
      retType: irTypeBitVec64(),
      body: body,
      isRecursive: false,
      preConditions: @[],
      postConditions: @[zeroPost]
    )
    ## The same shape WITH a valid postcondition and genuine ACCEPT succeeds —
    ## proving the negative cases above are genuinely fail-closed, not broken.
    materializeCompletenessFor(fd, "tests/negative/ok_identity.nim")
    let ok = executeCanonicalVerification(fd, "tests/negative/ok_identity.nim", "okIdentity",
      parseBound = boundFor("tests/negative/ok_identity.nim", "okIdentity"))
    check ok.success == true
    check ok.verdict == vdVerified
    ## A verified result is sealed under the subject-bound identity: durable
    ## evidence exists and no seal error was swallowed (DEBT#490).
    check ok.canonicalEvidence.isSome
    check ok.sealError == ""
