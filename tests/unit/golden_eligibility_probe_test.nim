## F3 probe — measure decodedLength against the golden-registration pipeline.
##
## This test mirrors the golden external-subject registration exactly:
## parse subject → find decodedLength → pnodeToCanon → axiomBodyCanon →
## serializeIRFuncDef → register with origin=soExternalSubject
## → generateCanonicalObligations → inVerifiedFragmentV1 →
## classifyCandidateEligibility → isFrontierSelectionEligible → assessAdmissibility.
## The registry fact it mirrors is `synthesizeExternalEntry` in
## src/infrastructure/external_ir_materializer.nim:177-202.
##
## SUBJECT — the in-repo inline fixture below, never a path on one developer's
## disk. What the observer reads out of the subject is exactly two things:
##   parseStringAST            → the module parses
##   findFuncDefP "decodedLength" "int" → the funcdef node, matched on name
##                                    plus a formal param whose type text
##                                    contains "int"
## Everything downstream is a pure function of that node plus the three entry
## fields this pipeline actually reads — `name`, `irSerialized`, `bmcSkippable`
## (admissibility.nim:81 is the sole `entry.*` read). `sourcePath` is a
## registry FACT, not a semantic input: nothing in the five measurements reads
## it, so labelling the entry "stew/base36.nim" loses no judgment. The rest of
## the real module — its other funcs, imports and size — is never read, so the
## fixture reproduces only the observed region.
##
## SUBJECT CORROBORATION (opt-in): set AXIOM_GOLDEN_SUBJECT_BASE36 to the real
## stew/base36.nim and the SAME measurement runs against it and must reach the
## SAME verdict, field for field. That is what makes the fixture substitution
## auditable rather than a silent narrowing. Either branch always prints which
## side ran, and a set-but-unreadable path is a counted FAIL, never a quiet
## pass.

import std/[unittest, strutils, os, sequtils]
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/axiom_pragmas
import core/parser_utils
import core/trusted/pnode_to_canon
import core/trusted/ast_to_ir
import verification/obligation/canonical_obligation_generator
import verification/obligation/obligation_types
import verification/obligation/obligation_ir
import verification/obligation/candidate_eligibility
import verification/obligation/verified_fragment
import verification/admissibility

const
  DecodedLengthName = "decodedLength"
  ParamTypeHint = "int"
    ## Disambiguates decodedLength from the module's other funcs: it is the
    ## one whose formal params carry an `int`-typed parameter.
  SubjectModulePath = "stew/base36.nim"
    ## Repo-relative module path — the shape `entry.sourcePath` carries in the
    ## real pipeline (ir_pipeline_runner.nim:116), not an absolute path.

  ## Minimal subject-shaped module — reproduced verbatim from nim-stew
  ## stew/base36.nim: `decodedLength`'s signature and body, plus the one type
  ## its signature names. Nothing else of the subject is read by the observer,
  ## so shrinking it cannot change the verdict.
  DecodedLengthFixture = """
type
  Base36* = object
  Base36Uc* = object
  Base36Lc* = object

  Base36Types* = Base36 | Base36Uc | Base36Lc

func decodedLength*(btype: typedesc[Base36Types], length: int): int =
  ## Return estimated length of decoded value of Base36 encoded value of length
  ## ``length``.
  return (length * 179) div 277
"""

type
  GoldenMeasurement = object
    ## The five pipeline verdicts plus the identity they were read off, so two
    ## subjects can be compared as a whole rather than verdict by coincidence.
    irName: string
    irSerializedLen: int
    genKind: string
    obligationIds: seq[string]
    obligationKinds: seq[ObligationKind]
    inFragment: bool
    eligibility: string
    frontierEligible: bool
    admissibility: string

proc measureGoldenPipeline(sourceText: string; m: var GoldenMeasurement): bool =
  ## Run the whole pipeline over one subject. Returns false when the subject
  ## does not yield a `decodedLength` funcdef — the caller turns that into a
  ## FAIL, so a subject the observer cannot read can never pass silently.
  let ast = parseStringAST(sourceText)
  if ast.isNil: return false
  let defNode = findFuncDefP(ast, DecodedLengthName, ParamTypeHint)
  if defNode.isNil: return false

  let canonNode = pnodeToCanon(defNode)
  let irFuncDef = axiomBodyCanon(canonNode)
  let irStr = serializeIRFuncDef(irFuncDef)

  # Mirrors the field set of synthesizeExternalEntry (external_ir_materializer.
  # nim:191-201). `sourcePath` is the repo-relative module path that proc assigns;
  # `isKernel` and `bmcSkippable` are pinned to the values this probe's recorded
  # verdict was measured at rather than derived from the IR the way that proc
  # derives them. Neither field is read by the five measurements below.
  let entry = RuntimeAxiomEntry(
    name: DecodedLengthName,
    irSerialized: irStr,
    smtSource: "",
    leanSource: "",
    sourcePath: SubjectModulePath,
    isKernel: true,
    irHash: "",
    effectKind: Pure,
    bmcSkippable: false,
    origin: soExternalSubject,
    expectedObligation: false)

  # isFrontierSelectionEligible scans the global registry, so the entry has to
  # be visible for the duration of the measurement and gone afterwards.
  let savedLen = runtimeAxiomRegistry.len
  runtimeAxiomRegistry.add(entry)
  try:
    let genResult = generateCanonicalObligations(irFuncDef, defaultScopePolicy())
    m = GoldenMeasurement(
      irName: irFuncDef.name,
      irSerializedLen: irStr.len,
      genKind: $genResult.kind,
      obligationIds: genResult.obligations.items.mapIt($it.kind & ":" & it.id),
      obligationKinds: genResult.obligations.items.mapIt(it.kind),
      inFragment: inVerifiedFragmentV1(entry, irFuncDef, genResult),
      eligibility: $classifyCandidateEligibility(entry, irFuncDef),
      frontierEligible: isFrontierSelectionEligible(DecodedLengthName),
      admissibility: $assessAdmissibility(entry, irFuncDef).decision)
  finally:
    runtimeAxiomRegistry.setLen(savedLen)
  true

proc echoMeasurement(label: string; m: GoldenMeasurement) =
  echo "  [", label, "]"
  echo "    irFuncDef.name: ", m.irName
  echo "    irSerialized len: ", m.irSerializedLen
  echo "    genResult.kind: ", m.genKind
  echo "    obligations [kind:id list]: ", m.obligationIds
  echo "    obligation kinds in allowlist: ",
       m.obligationKinds.allIt(it in VerifiedFragmentAllowlist)
  echo "    inVerifiedFragmentV1: ", m.inFragment
  echo "    classifyCandidateEligibility: ", m.eligibility
  echo "    isFrontierSelectionEligible: ", m.frontierEligible
  echo "    assessAdmissibility.decision: ", m.admissibility

suite "F3 probe — decodedLength golden eligibility measurement":

  test "golden pipeline measurements for decodedLength":
    var fixtureM: GoldenMeasurement
    let parsed = measureGoldenPipeline(DecodedLengthFixture, fixtureM)

    # The fixture verdict is the standalone judgment and it always runs.
    check parsed
    echoMeasurement("inline fixture", fixtureM)

    # Pin the verdicts the probe exists to measure. Without these the test
    # would report success for any subject the pipeline happened to accept,
    # which is the quiet-pass path (AGENTS.md §0.9).
    check fixtureM.irName == DecodedLengthName
    check fixtureM.irSerializedLen > 0
    check fixtureM.genKind == "ogrGenerated"
    check fixtureM.obligationIds.len > 0
    check fixtureM.obligationKinds.allIt(it in VerifiedFragmentAllowlist)
    check fixtureM.inFragment
    check fixtureM.eligibility == "elProofCandidate"
    check fixtureM.frontierEligible
    check fixtureM.admissibility == "ADMISSIBLE"

    # ── Subject corroboration (opt-in): the real nim-stew source ─────
    # Same entry fields, same assertions — only the subject text changes, so a
    # difference in any field below is the subject's doing and nothing else's.
    let subjectPath = getEnv("AXIOM_GOLDEN_SUBJECT_BASE36").strip

    if subjectPath.len == 0:
      echo "  INFO: subject corroboration NOT RUN — AXIOM_GOLDEN_SUBJECT_BASE36" &
           " unset; the inline fixture verdict above is the standalone judgment"
    else:
      check fileExists(subjectPath)
      # Read defensively: an unreadable path must land as counted check
      # failures that name the cause, not as an unhandled IOError that aborts
      # the run before the remaining comparisons report.
      let subjectText = if fileExists(subjectPath): subjectPath.readFile else: ""
      check subjectText.len > 0
      var subjectM: GoldenMeasurement
      check measureGoldenPipeline(subjectText, subjectM)
      echoMeasurement("subject " & subjectPath, subjectM)

      check subjectM.irName == fixtureM.irName
      check subjectM.irSerializedLen == fixtureM.irSerializedLen
      check subjectM.genKind == fixtureM.genKind
      check subjectM.obligationIds == fixtureM.obligationIds
      check subjectM.obligationKinds == fixtureM.obligationKinds
      check subjectM.inFragment == fixtureM.inFragment
      check subjectM.eligibility == fixtureM.eligibility
      check subjectM.frontierEligible == fixtureM.frontierEligible
      check subjectM.admissibility == fixtureM.admissibility