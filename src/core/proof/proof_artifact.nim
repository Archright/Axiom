import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
## Proof artifact types — canonical output format for verification results.
## SSOT for proof verification output across the Axiom pipeline.
##
## JSON serialization via deriveJsonCodec (compile-time generated, zero overhead).
## Replaces hand-written jsonFromProofArtifact (removed — was dead code with zero callers).

import std/json
import core/codec/axiom_codec
import core/types/domain_types
import core/types/hubs/proof_hub
import core/diagnostics/refactoring_engine

export proof_hub

type
  Discontinuity* = object
    filePath*: string
    lineNumber*: int
    smtUnsatCoreVars*: seq[string]
    kind*: DiscontinuityKind
    description*: string

  ProofArtifactKind* = enum
    pakProven
    pakUnverifiable
    pakCounterExample
    pakTimedOut
    pakPreSieved

  ProofArtifact* = object
    nodeId*: string
    kind*: ProofArtifactKind
    discontinuities*: seq[Discontinuity]
    suggestedPatterns*: seq[string]
    refactoringTemplates*: seq[RefactoringTemplate]
    synergyMetrics*: SynergyMetrics
    provenLayer*: string
    asiScore*: float
    smtUnsatCoreVars*: seq[string]
    leanDiagnostic*: string
    elapsedMs*: int
    iterations*: int
    stagnationEscalated*: bool
    proofSummaryPath*: string
    proofArtifactPath*: string
    witnessTrace*: string

func emptySynergyMetrics*(): SynergyMetrics {.raises: [].} =
  SynergyMetrics(fFactor: 1.0, gFactor: 1.0, hFactor: 1.0, geometricMean: 1.0)

func emptyProofArtifact*(nodeId: string = ""): ProofArtifact {.raises: [].} =
  ProofArtifact(nodeId: nodeId, kind: pakProven, synergyMetrics: emptySynergyMetrics())

# --- deriveJsonCodec: compile-time generated JSON codecs ---
# Leaf types first, then composite types (dependency order)

# Enum codecs
deriveJsonCodec(DiscontinuityKind)
deriveJsonCodec(ProofArtifactKind)
deriveJsonCodec(RefactoringSignalKind)
deriveJsonCodec(RefactoringPatternKind)

# Object codecs (leaf → composite)
deriveJsonCodec(SynergyMetrics)
deriveJsonCodec(Discontinuity)
deriveJsonCodec(RefactoringTemplate)
deriveJsonCodec(ProofArtifact)

{.pop.}
