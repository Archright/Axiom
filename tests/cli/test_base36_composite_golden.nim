import std/[unittest, os, strutils, options]

import ../../src/core/results
import ../../src/core/trusted/axiom_pragmas
import ../../src/cli/axiom_engine
import ../../src/verification/obligation/canonical_verification
import ../../src/verification/obligation/verification_decision_authority
import ../../src/infrastructure/external_ir_materializer

## base36 sizing composite — end-to-end synthesis golden.
##
## Pins the deterministic vertical slice over the external fixture
## tests/golden/base36_subject/stew/base36.nim:
##   overlay domain load → two-leg external materialization (real Nim
##   extractor + real Lean reference extractor, byte-equal IR required on
##   BOTH legs) → β-composition synthesis → census eligibility → golden
##   Lean render.
##
## NOT pinned here (deliberately): the obligation count of the composite
## census record — obligations belong to the obligation layer's own golden
## tests; this file pins the SUBJECT-binding slice (domain, EA legs, render).

proc fixtureSubjectRoot(): string =
  ## The fixture subject tree root — `tests/golden/base36_subject` — anchored
  ## to THIS test source file, not to the process CWD or the binary location
  ## (root resolution via getAppDir is undefined for a /tmp test binary; the
  ## §2.1a binding must measure the same subject bytes from any invocation
  ## directory). Mirrors the production threading: the engine passes the
  ## `--project` root (the subject repo root) into
  ## executeCanonicalVerification; here the miniature subject repo is the
  ## fixture tree itself (`stew/base36.nim` at its root), and its git
  ## identity anchor is the repo commit that versions the fixture.
  currentSourcePath().parentDir().parentDir() / "golden" / "base36_subject"

const GoldenRender = """def roundtrip_dec_enc : Int → Int → Int :=
  fun btype length => (((((length * 277) / 179) + 1) * 179) / 277)

theorem roundtrip_dec_enc_post :
  ∀ (btype : Int) (length : Int), (length ≥ 0) → (length ≤ 33297371974204966) → ((((((((length * 277) / 179) + 1) * 179) / 277) = length) ∧ ((length * 277) ≤ 9223372036854775807)) ∧ (((((((length * 277) / 179) + 1) * 179) / 277) * 179) ≤ 9223372036854775807)) := by
  intro btype length h0 h1
  omega
"""

proc fixtureResolver(root: string): ModuleContentResolver =
  result = proc(modulePath: string): Option[string] {.raises: [].} =
    try:
      some(readFile(root / modulePath))
    except CatchableError:
      none(string)

proc overlayDomainOk(): bool =
  let domainRes = loadBase36OverlayDomain()
  if domainRes.isErr:
    echo "overlay domain error: " & domainRes.error
    return false
  let domain = domainRes.get()
  check domain.modulePath == "stew/base36.nim"
  check domain.outerSymbol == "decodedLength"
  check domain.innerSymbol == "encodedLength"
  check domain.domainVar == "n"
  check domain.domainLower == 0
  check domain.domainBound == 33297371974204966'i64
  true

proc synthesizeEligibleParseBound(census: var ExternalCandidateCensus): SubjectParseBoundComponents =
  let domainRes = loadBase36OverlayDomain()
  if domainRes.isErr:
    echo "overlay domain error: " & domainRes.error
    return SubjectParseBoundComponents()
  let synth = synthesizeBase36RelationalCandidate(
    "encodedLength", domainRes.get().modulePath,
    fixtureResolver(fixtureSubjectRoot()),
    domainRes.get(), census)
  if synth.isErr:
    echo "synthesis error: " & synth.error
    return SubjectParseBoundComponents()
  if census.eligible.len != 1:
    for rec in census.records:
      echo "record: " & rec.functionName & " eligible=" & $rec.censusEligible &
        " rej=" & $rec.rejection
    return SubjectParseBoundComponents()
  census.eligible[0].parseBound

suite "base36 sizing composite — overlay domain pins":
  test "overlay domain resolves to the pinned subject pair and range":
    check overlayDomainOk()

suite "base36 sizing composite — EA legs (both original symbols)":
  test "composite is census-eligible with both EA legs agreed byte-equal":
    check overlayDomainOk()
    var census = ExternalCandidateCensus()
    let pb = synthesizeEligibleParseBound(census)
    check census.eligible.len == 1
    ## §2.1a-1/2: the legs attest the two ORIGINAL symbols (a composite name
    ## never appears in the subject source), both byte-equal.
    check pb.synthesizedComposite == true
    check pb.measuredForFuncName == "decodedLength"
    check pb.ea2MeasuredForFuncName == "encodedLength"
    check pb.eaAgreed == true
    check pb.ea2Agreed == true
    if pb.eaAgreed and pb.ea2Agreed:
      ## Byte-equal agreement ⇒ the digests of the two extractors coincide,
      ## per leg; the worker binary is content-addressed, never fabricated.
      check pb.eaNimDigest.len == 64
      check pb.eaNimDigest == pb.eaLeanDigest
      check pb.ea2NimDigest.len == 64
      check pb.ea2NimDigest == pb.ea2LeanDigest
      check pb.eaIrcheckBinaryDigest.len == 64
      check pb.eaIrcheckBinaryDigest == pb.ea2IrcheckBinaryDigest
      check pb.synthesisDerivationDigest.len == 64
    else:
      ## Fail loudly with the gate's own reasons (no silent pass).
      echo "leg1: " & pb.eaDetail
      echo "leg2: " & pb.ea2Detail

suite "base36 sizing composite — golden Lean render":
  test "β-composited definition + post theorem render is byte-stable":
    check overlayDomainOk()
    var census = ExternalCandidateCensus()
    let pb = synthesizeEligibleParseBound(census)
    check census.eligible.len == 1
    if census.eligible.len == 1:
      let rendered = renderLeanForFuncDef(census.eligible[0].funcDef)
      check rendered == GoldenRender
      if rendered != GoldenRender:
        echo "=== ACTUAL RENDER BEGIN ==="
        echo rendered
        echo "=== ACTUAL RENDER END ==="

suite "base36 sizing composite — canonical kernel acceptance":
  test "rendered composite proves through the REAL Lean kernel (vdVerified + KAA)":
    check overlayDomainOk()
    var census = ExternalCandidateCensus()
    let pb = synthesizeEligibleParseBound(census)
    check census.eligible.len == 1
    if census.eligible.len == 1:
      let ve = census.eligible[0]
      let res = executeCanonicalVerification(
        ve.funcDef, ve.entry.sourcePath, ve.entry.name, ve.entry.sourceContent,
        subjectRepoRoot = fixtureSubjectRoot(),
        preSynthesisIrDigest = "",
        parseBound = ve.parseBound)
      ## Genuine kernel ACCEPT is the only route to vdVerified (§0.9b).
      ## A REJECT here is a real kernel observation — never masked.
      check res.verdict == vdVerified
      check res.success == true
      check res.evidence == "lean_kernel_accepted"
      check res.kaaIdentity.len == 64
      check res.sealError == ""
      if res.verdict != vdVerified:
        echo "verdict=" & $res.verdict & " evidence=" & res.evidence &
          " sealError=" & res.sealError
