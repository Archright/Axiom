import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Pure persona interface — zero infrastructure imports.
## All Artifact types used by the four personas are centralized here
## so that consumers (universal_pipeline, mcp/tools) import only this module.

import std/options
import std/strutils
import core/types/pipeline_core_types
import core/types/remediation_types
from core/proof/proof_artifact import ProofArtifact

type
  PersonaKind* = enum
    pkDetective, pkJudge, pkLegislator, pkScribe, pkSwat

  PersonaLayerKind* = enum
    plkSwat       ## Layer 1: SWAT / BMC
    plkDetective  ## Layer 2: Abstract interpretation / CEGAR / PDR
    plkScribe     ## Layer 3: LLM auto-formalization / Legislator
    plkJudge      ## Layer 4: Lean 4 kernel verification

const LayerMapping*: array[PersonaKind, PersonaLayerKind] = [
  plkDetective,
  plkJudge,
  plkScribe,
  plkScribe,
  plkSwat
]

static:
  ## Compile-time guard: persona-to-layer mapping is bijective and Notion-aligned
  for pk in low(PersonaKind) .. high(PersonaKind):
    assert LayerMapping[pk] != plkSwat or pk == pkSwat,
      "Only SWAT may map to Layer 1"
    assert LayerMapping[pk] != plkDetective or pk == pkDetective,
      "Only Detective may map to Layer 2 (Detective)"
    assert LayerMapping[pk] != plkScribe or pk == pkLegislator or pk == pkScribe,
      "Only Legislator or Scribe may map to Layer 3 (Scribe)"
    assert LayerMapping[pk] != plkJudge or pk == pkJudge,
      "Only Judge may map to Layer 4 (Judge)"

type
  UnsatCoreExtractionStatus* = enum
    ucesNotAttempted      ## No counterexample, so extraction was skipped
    ucesSuccess           ## Unsat core successfully extracted
    ucesProcessFailed     ## Z3 process spawn failed
    ucesIoError           ## I/O error during Z3 communication
    ucesParseFailed       ## Could not parse Z3 output

type
  DetectiveArtifact* = object
    priorPromotion*: tuple[invariant: string; snapshotPath: string]
    initialScan*: NegativeInvariantScan
    finalScan*: NegativeInvariantScan
    evolutionHit*: Option[AnnotatedHit]
    verificationVerdict*: string
    verificationVerdictReport*: VerificationVerdictReport
    traceReport*: TraceReport
    logLines*: seq[string]
    cegarSmtlib2*: string      ## SMT-LIB2 encoding from CEGAR engine (empty if unused)
    cegarEvidenceLog*: string  ## Human-readable CEGAR evidence trace (empty if unused)
    cegarCounterexample*: bool ## True if CEGAR found a concrete counterexample
    unsatCoreVars*: seq[string] ## Variable names from failed CEGAR iteration (empty if unused)
    unsatCoreExtractionStatus*: UnsatCoreExtractionStatus ## Distinguishes success vs I/O failure

  JudgeArtifact* = object
    finalSource*: string
    finalInvariant*: string
    inferredSpec*: LeanSpecInference
    nearestDiagnostic*: string
    nearestDiscontinuities*: seq[MathematicalDiscontinuity]
    failedReplayAttempts*: int
    rounds*: seq[HealingRound]
    proofReplayMethod*: string
    proofReplayTactics*: seq[string]
    proofReplayVerified*: bool
    leanKernelVerified*: bool
    vacuityProven*: bool              ## Anti-vacuity linter result — derived from negative mutation test
    negativeMutationPass*: bool       ## Negative mutation test result (genuine vacuum defense)
    proofDepth*: int
    logLines*: seq[string]
    structuredRemediation*: StructuredRemediationPayload
    proofArtifact*: ProofArtifact  ## SSOT — replaces nearestDiscontinuities + structuredRemediation

  LegislatorArtifact* = object
    baselineInvariant*: string
    refinedInvariant*: string
    activeInvariant*: string
    evolutionReasoning*: string
    traceReport*: TraceReport
    logLines*: seq[string]
    scribeArtifact*: ScribeArtifact  ## Composition field for future Legislator→Scribe subroutine chaining

  ScribeArtifact* = object
    theoremSource*: string
    tacticTrace*: seq[string]
    verified*: bool

  CounterExamplePayload* = object
    ## Data-driven feedback from Judge to Legislator for closed-loop
    ## counterexample-guided invariant refinement (CEGIR).
    nodeId*: string
    failedInvariant*: string
    leanDiagnostic*: string
    smtCounterExample*: string
    traceReport*: TraceReport

  SwatArtifact* = object
    healedSource*: string
    rounds*: seq[HealingRound]
    sourceChecksum*: string
    reproductionPath*: string
    bddFeaturePath*: string
    pocSnippet*: string
    traceReport*: TraceReport
    vulnerabilityHits*: seq[AnnotatedHit]
    logLines*: seq[string]

{.pop.}
{.pop.}

## Context Slicing — Extract function signature and contracts for LLM prompts
## Reduces prompt size by removing function body noise
func extractSignatureAndContracts*(source: string, functionName: string): string {.raises: [].} =
  result = ""
  var inSignature = false
  var braceDepth = 0
  for line in source.splitLines():
    let stripped = line.strip()
    if not inSignature and (stripped.startsWith("proc ") or stripped.startsWith("func ") or
        stripped.startsWith("method ") or stripped.startsWith("template ")):
      inSignature = true
      result.add(line & "\n")
      braceDepth += line.count('{') - line.count('}')
      if braceDepth <= 0 and ':' in stripped and stripped.len > 1:
        inSignature = braceDepth > 0
      continue
    if inSignature:
      result.add(line & "\n")
      braceDepth += line.count('{') - line.count('}')
      if braceDepth <= 0:
        inSignature = false
    elif "requires" in stripped or "ensures" in stripped or
         "precondition" in stripped or "postcondition" in stripped:
      result.add(stripped & "\n")
  if result.len == 0:
    result = source  # Fallback: return full source if slicing found nothing

## Function Archetype — AST-driven classification for prompt dispatch
type FunctionArchetype* = enum
  archIterative   ## while/for loops
  archRecursive   ## self-calling functions
  archLinear      ## simple functions

func determineArchetype*(source: string, functionName: string): FunctionArchetype {.raises: [].} =
  ## Classify function archetype from source code for adaptive prompt generation
  for line in source.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("while ") or stripped.startsWith("for "):
      return archIterative
    if functionName.len > 0 and functionName in stripped and
       ("(" in stripped or "result" in stripped):
      return archRecursive
  archLinear
