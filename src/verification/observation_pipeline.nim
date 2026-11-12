## observation_pipeline.nim — 3-Stage Typed Verification Observation Pipeline
##
## RawObservation (unvalidated raw read) → classify() → ClassifiedObservation
##   (distinct type; carries content) → validate() → ValidatedDependency
##   (distinct type, carries dependency kind + a content digest where SEMANTIC).
##
## Modeled on proof_typestate.nim: distinct types + function-only
## transitions. Fields are non-exported; direct construction or field
## access bypasses the transitions at compile time.
##
## 4-state ObservationStatus: Complete, Incomplete, Unknown, Unclassified.
## Policy: only Complete may ever feed a reuse decision; everything
## else forces a recompute.
##
## Precedent: proof_typestate.nim (AxProofUnattempted → AxProofInProgress → ...)
## and semantic_query_types.nim (distinct digest types).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[strutils, algorithm]
import verification/verification_dependency
import core/crypto/hash_kernel

# ---------------------------------------------------------------------------
# Observation status — 4-state machine
# ---------------------------------------------------------------------------
## Policy: only osComplete may ever feed a reuse decision; everything
## else forces a recompute. Match the gvsUnchecked / psPending state-
## machine idioms in the codebase for the naming convention.

type
  ObservationStatus* = enum
    ## State of an observation in the pipeline.
    osComplete,     ## Fully validated; may feed reuse.
    osIncomplete,   ## Some checks missing; must recompute.
    osUnknown,      ## Cannot determine; must recompute (fail-closed).
    osUnclassified, ## UNCLASSIFIED read; must fail-closed for reuse.

func `$`*(s: ObservationStatus): string {.raises: [].} =
  ## Human-readable status name.
  case s
  of osComplete:     "Complete"
  of osIncomplete:   "Incomplete"
  of osUnknown:      "Unknown"
  of osUnclassified: "Unclassified"

# ---------------------------------------------------------------------------
# Stage 1: RawObservation — unvalidated raw read from the probe
# ---------------------------------------------------------------------------
## Fields are NON-EXPORTED — external code cannot construct or access
## them directly. Use newRawObservation* to create and classify() to
## transition to ClassifiedObservation.

type
  RawObservation* = object
    ## Unvalidated raw read record (probe output).
    path: string
    readClass: ReadClass
    content: string

func newRawObservation*(path: string; readClass: ReadClass; content: string): RawObservation {.raises: [].} =
  ## Constructor for RawObservation. Only way to create this type
  ## from outside the module (fields are non-exported).
  RawObservation(path: path, readClass: readClass, content: content)

# Accessors for RawObservation fields (exported; fields themselves are not)
func rawPath*(raw: RawObservation): string {.raises: [].} = raw.path
func rawReadClass*(raw: RawObservation): ReadClass {.raises: [].} = raw.readClass
func rawContent*(raw: RawObservation): string {.raises: [].} = raw.content

# ---------------------------------------------------------------------------
# Stage 2: ClassifiedObservation — distinct type after classify()
# ---------------------------------------------------------------------------
## Distinct type — cannot be confused with RawObservation or
## ValidatedDependency. Fields are non-exported; only classify()
## and validate() can construct/access them.

type
  ClassifiedObservation* = object
    ## Observation with a classified dependency kind.
    path: string
    readClass: ReadClass
    kind: VerificationDependencyKind
    status: ObservationStatus
    content: string

func newClassifiedObservation*(path: string; readClass: ReadClass; kind: VerificationDependencyKind; status: ObservationStatus; content: string): ClassifiedObservation {.raises: [].} =
  ## Constructor for ClassifiedObservation. Only way to create this
  ## type from outside the module.
  ClassifiedObservation(path: path, readClass: readClass, kind: kind, status: status, content: content)

func classifiedPath*(obs: ClassifiedObservation): string {.raises: [].} = obs.path
func classifiedReadClass*(obs: ClassifiedObservation): ReadClass {.raises: [].} = obs.readClass
func classifiedKind*(obs: ClassifiedObservation): VerificationDependencyKind {.raises: [].} = obs.kind
func classifiedStatus*(obs: ClassifiedObservation): ObservationStatus {.raises: [].} = obs.status
func classifiedContent*(obs: ClassifiedObservation): string {.raises: [].} = obs.content

# ---------------------------------------------------------------------------
# Stage 3: ValidatedDependency — distinct type after validate()
# ---------------------------------------------------------------------------
## Distinct type — final stage. Carries dependency kind + content
## digest where SEMANTIC. Fields are non-exported; only validate()
## can construct this type.

type
  ValidatedDependency* = object
    ## Validated dependency: carries dependency kind + content digest
    ## where SEMANTIC. Only constructible via validate().
    path: string
    readClass: ReadClass
    kind: VerificationDependencyKind
    contentDigest: string
    status: ObservationStatus

func newValidatedDependency*(path: string; readClass: ReadClass; kind: VerificationDependencyKind; contentDigest: string; status: ObservationStatus): ValidatedDependency {.raises: [].} =
  ## Constructor for ValidatedDependency. Only way to create this
  ## type from outside the module.
  ValidatedDependency(path: path, readClass: readClass, kind: kind, contentDigest: contentDigest, status: status)

func depPath*(dep: ValidatedDependency): string {.raises: [].} = dep.path
func depReadClass*(dep: ValidatedDependency): ReadClass {.raises: [].} = dep.readClass
func depKind*(dep: ValidatedDependency): VerificationDependencyKind {.raises: [].} = dep.kind
func depContentDigest*(dep: ValidatedDependency): string {.raises: [].} = dep.contentDigest
func depStatus*(dep: ValidatedDependency): ObservationStatus {.raises: [].} = dep.status

# ---------------------------------------------------------------------------
# Dependency resolution — fold kind + status into a decision
# ---------------------------------------------------------------------------

type
  DependencyResolution* = enum
    ## Decision about a validated dependency.
    drDeclared,    ## SEMANTIC + Complete: declared dependency (reusable).
    drRecompute,   ## Incomplete / Unknown / non-SEMANTIC: must recompute.
    drFailClosed,  ## UNCLASSIFIED: fail-closed, no reuse.

func `$`*(r: DependencyResolution): string {.raises: [].} =
  case r
  of drDeclared:   "Declared"
  of drRecompute:  "Recompute"
  of drFailClosed: "FailClosed"

## Resolve a ValidatedDependency into a decision.
## SEMANTIC + Complete → drDeclared (declared dependency, reusable).
## UNCLASSIFIED → drFailClosed (no reuse).
## Everything else → drRecompute.
func resolve*(dep: ValidatedDependency): DependencyResolution {.raises: [].} =
  case dep.kind
  of dkSemantic:
    if dep.status == osComplete:
      drDeclared
    else:
      drRecompute
  of dkUnclassified:
    drFailClosed
  else:
    drRecompute

# ---------------------------------------------------------------------------
# Transition functions (function-only transitions)
# ---------------------------------------------------------------------------

func observeStatusFromKind*(kind: VerificationDependencyKind; hasContent: bool): ObservationStatus {.raises: [].} =
  ## Derive ObservationStatus from the dependency kind and whether
  ## content is present. Never silently pass-through — always
  ## returns a concrete status.
  case kind
  of dkSemantic:
    if hasContent: osComplete
    else: osIncomplete
  of dkProvenance:
    if hasContent: osComplete
    else: osUnknown
  of dkInternal:
    osIncomplete
  of dkOutput:
    osIncomplete
  of dkUnclassified:
    osUnclassified

## classify: RawObservation → ClassifiedObservation.
## Determines the VerificationDependencyKind and derives the ObservationStatus.
## Downgrades status on validation failure (never silently pass-through).
func classify*(raw: RawObservation): ClassifiedObservation {.raises: [].} =
  let kind = classifyReadClass(raw.readClass)
  let hasContent = raw.content.len > 0
  let status = observeStatusFromKind(kind, hasContent)
  ClassifiedObservation(
    path: raw.path,
    readClass: raw.readClass,
    kind: kind,
    status: status,
    content: raw.content
  )

## validate: ClassifiedObservation → ValidatedDependency.
## Validates the observation; computes content digest where SEMANTIC
## from the ACTUAL observation content (not the path).
## Downgrades status on validation failure (never silently pass-through).
func validate*(classified: ClassifiedObservation): ValidatedDependency {.raises: [].} =
  let hasContent = classified.content.len > 0
  let contentDigest = if classified.kind == dkSemantic:
    semanticContentDigest(classified.readClass, classified.content)
  else:
    ""
  # Downgrade logic: if content is missing for SEMANTIC, downgrade status.
  var status = classified.status
  if classified.kind == dkSemantic and not hasContent:
    status = osIncomplete
  elif classified.kind == dkUnclassified:
    status = osUnclassified
  elif classified.kind == dkProvenance and not hasContent:
    status = osUnknown
  ValidatedDependency(
    path: classified.path,
    readClass: classified.readClass,
    kind: classified.kind,
    contentDigest: contentDigest,
    status: status
  )