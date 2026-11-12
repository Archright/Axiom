import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

import std/strutils

## Trust Authority Specification — the single source of truth (SSOT) for the
## I7 TrustCommit authority model (Wave7A).
##
## Purpose
##   I7 protects *authoritative trust-state transitions*, not individual file
##   writes. This module fixes the semantic axes that the I7-A (semantic
##   authority) and I7-B (persistence escape) gates enforce:
##
##     A = DeclaredAuthorityRoots     = { trust_commit.commitVerification }
##     C = ReverseReachable(A)        # TrustCommit callable closure (syntactic)
##     M = Inferred trust-relevant mutation functions
##
##   Invariants (all must hold for I7 GREEN; "0 findings" alone is insufficient):
##     I7-1  Durable-effect classification:  UnknownDurableEffects = {}
##     I7-2  Authority provenance safety:    M ⊆ C
##     I7-3  Authority-root declaration:     A = DeclaredAuthorityRoots,
##                                           C = ReverseReachable(A)
##     I7-4  Persistence escape isolation:   RawAuthoritativePersistence ⊆ C
##
##   Certificate definition:
##     persistence = Derived, canonicality = true,
##     decisionInfluence = TrustRelevant, sourceOfTruth = VerifiedClaim /
##     TrustCommit-derived state.
##
## Design notes
##   - The two axes (Persistence Authority, Decision Influence) are orthogonal:
##     an artifact can be Derived in persistence yet TrustRelevant in decision
##     influence (Certificate), or Authoritative in both (TrustCommit journal).
##   - Storage representation is modelled as a *projection* of the authority
##     model (path is a result, not a cause), so the I7-B escape detector does
##     not hardcode filesystem paths.

type
  PersistenceAuthority* = enum
    paNonAuthoritative  ## transient/sandbox: no durable trust authority
    paDerived           ## regenerable derived / cache artifact
    paAuthoritative     ## authoritative trust state

  DecisionInfluence* = enum
    diNone             ## never used as a trust-decision input
    diTrustRelevant    ## consumed as a trust-decision input

  DurableEffectClass* = enum
    decTransient    ## transient compiler / sandbox I/O (temp, disposable)
    decSandbox      ## sandbox-scoped I/O
    decCache        ## performance cache / CAS staging (regenerable)
    decDerived      ## derived canonical artifact (Certificate, stale area)
    decAuthoritative## TrustCommit durable trust state
    decUnknown      ## unclassified durable effect → I7-1 FAIL

  TrustAuthorityState* = enum
    stVerifiedClaim     ## primary authoritative state (deriveClaim output)
    stAttestation       ## verification evidence bundle
    stPromotionRecord   ## promotion transition record
    stJournal           ## TrustCommit durable journal (authoritative)
    stCertificate       ## derived canonical projection (TrustRelevant)

# ---------------------------------------------------------------------------
# A = DeclaredAuthorityRoots (I7-3)
# ---------------------------------------------------------------------------
## The single trust-mutation transaction root. All authoritative trust state
## transitions must be provenance-reachable from this root.
const declaredTrustAuthorityRoots*: seq[string] = @[
  "trust_commit.commitVerification"
]

# ---------------------------------------------------------------------------
# Authoritative state inventory (I7-2 classification)
# ---------------------------------------------------------------------------
const authoritativeTrustStates*: seq[TrustAuthorityState] = @[
  stVerifiedClaim,
  stAttestation,
  stPromotionRecord,
  stJournal,
]

## TrustRelevant-derived states — Derived in persistence but consumed as a
## trust-decision input. Excluded from I7-A (no persistence authority) but
## watched by I7-B (representation escape) and migration-targeted.
const trustRelevantDerivedStates*: seq[TrustAuthorityState] = @[
  stCertificate
]

# ---------------------------------------------------------------------------
# Persistence authority classification (I7-1 durable effect class)
# ---------------------------------------------------------------------------
func persistenceAuthorityOf*(state: TrustAuthorityState): PersistenceAuthority {.inline.} =
  case state
  of stVerifiedClaim, stAttestation, stPromotionRecord, stJournal:
    paAuthoritative
  of stCertificate:
    paDerived

func decisionInfluenceOf*(state: TrustAuthorityState): DecisionInfluence {.inline.} =
  case state
  of stCertificate:
    diTrustRelevant
  of stVerifiedClaim, stAttestation, stPromotionRecord, stJournal:
    diTrustRelevant
  # transient / cache / sandbox states are not part of this axis; they default
  # to diNone via their owning class (see durableEffectClassOf).

func durableEffectClassOf*(kind: string): DurableEffectClass {.inline.} =
  ## Map a named persistence-effect family onto its durable-effect class.
  ## `kind` is one of the closed-world classification labels produced by the
  ## I7 persistence-effect detector. Unknown labels fail closed (I7-1).
  case kind
  of "transient": decTransient
  of "sandbox":   decSandbox
  of "cache":     decCache
  of "derived":   decDerived
  of "authoritative": decAuthoritative
  else: decUnknown

func isAuthoritativeEffect*(c: DurableEffectClass): bool {.inline.} =
  c == decAuthoritative

func isTrustRelevantDerived*(c: DurableEffectClass): bool {.inline.} =
  c == decDerived

# ---------------------------------------------------------------------------
# Storage representation — a projection of the authority model (I7-B)
# ---------------------------------------------------------------------------
## Canonical storage representation roots. These are the *authoritative-state
## representations* the raw-escape detector must protect. Derived quarantine /
## stale areas are separate (not authoritative).
const authoritativeStorageRepresentations*: seq[string] = @[
  ## journal dir is authoritative (I3). Relative to a repo/base root.
  "data/trusted/journal",
]

const derivedStorageRepresentations*: seq[string] = @[
  ## derived canonical cert area + its quarantine/stale sub-area.
  "src/verification/certificates",
  "src/verification/certificates/stale",
  # runtime canonical store (data/trusted/certificates) is a derived
  # materialization of TrustCommit-authoritative state; the journal
  # remains the sole authoritative representation.
  "data/trusted/certificates",
]

func isAuthoritativeRepresentation*(path: string): bool {.inline.} =
  for r in authoritativeStorageRepresentations:
    if path.contains(r):
      return true
  false

func isDerivedRepresentation*(path: string): bool {.inline.} =
  for r in derivedStorageRepresentations:
    if path.contains(r):
      return true
  false

{.pop.}
