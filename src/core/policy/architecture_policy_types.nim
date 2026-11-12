import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Type definitions and constants for the architecture policy parser.
##
## Extracted from architecture_policy.nim to enable include→import migration.

import std/tables
import core/types/hubs/pragma_pattern_hub
export pragma_pattern_hub

type
  DryPolicy* = object
    functionCloneMinAstNodes*: int
    alphaEquivalence*: bool
    boilerplateNodeCountThreshold*: int

  LayerLimit* = object
    maxImports*: int
    maxExportedFunctions*: int

  SurfaceAreaPolicy* = object
    defaultMaxImports*: int
    defaultMaxExportedFunctions*: int
    maxFunctionLines*: int                        ## max lines per function body; 0 = disabled
    layerLimits*: Table[string, LayerLimit]
    moduleOverrides*: Table[string, LayerLimit]  ## per-module override for legitimate patterns

  ForbiddenCallPolicy* = object
    calleeName*: string
    ownerRole*: string
    allowedCallers*: seq[string]

  CanonicalComputation* = object
    owner*: string
    pattern*: string
    varType*: string

  InterfaceContract* = object
    file*: string
    requiredPragmas*: seq[string]
    allowedRaises*: seq[string]

  OpaqueType* = object
    constructorModule*: string
    consumerLayers*: seq[string]

  CohesionPolicy* = object
    maxLcom*: float
    minTcc*: float
    lcomOverrides*: Table[string, float]  ## per-module LCOM threshold override
    tccOverrides*: Table[string, float]   ## per-module TCC threshold override

  ArchitecturePolicy* = object
    version*: string
    layers*: Table[string, seq[string]]
    layerEdges*: Table[string, seq[string]]
    moduleRoles*: Table[string, seq[string]]
    ssotTypes*: Table[string, string]
    forbiddenCalls*: Table[string, seq[string]]
    forbiddenAssignments*: Table[string, seq[string]]
    allowedAssignmentOwners*: Table[string, seq[string]]
    dry*: DryPolicy
    surfaceArea*: SurfaceAreaPolicy
    canonicalComputations*: Table[string, CanonicalComputation]
    interfaces*: Table[string, InterfaceContract]
    opaqueTypes*: Table[string, OpaqueType]
    cohesion*: CohesionPolicy
    forbiddenCallPolicies*: Table[string, ForbiddenCallPolicy]
    forbiddenPragmaPatterns*: Table[string, ForbiddenPragmaPattern]
    externalPackagePrefixes*: seq[string]
    generatedModules*: Table[string, string]  ## modulePath → fingerprint
    memoryPolicyMarkers*: Table[string, string]  ## markerName → markerText
    impureProceduresWhitelist*: seq[string]

  ArchitecturePolicyParseResult* = object
    ok*: bool
    policy*: ArchitecturePolicy
    diagnostics*: seq[string]

const
  architecturePolicyPath* = "src/gate/architecture_policy.lock"
  expectedPolicyVersion* = "axiom.architecture-policy.v1"

{.pop.}
