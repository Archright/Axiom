import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Verification Obligation IR — canonical obligation representation.
##
## This module defines the core obligation types that are backend-independent.
## It imports obligation_types.nim for the foundational enums and wrappers.
##
## Invariants:
## - ObligationGenerationResult.ogrGenerated always contains len >= 1
##   (enforced by makeGenerated constructor).
## - C4 identity is computed via computeObligationId in obligation_types.nim,
##   which uses a single canonicalizePredicate path and SHA-256.

import std/[sequtils, strutils, algorithm]
import core/crypto/hash_kernel
import core/trusted/axiom_ir
import verification/obligation/obligation_types
import verification/obligation/no_obligation_provenance

# ---------------------------------------------------------------------------
# VerificationObligation — canonical obligation with C4 identity
# ---------------------------------------------------------------------------

type
  VerificationObligation* = object
    id*: string                    ## C4 identity — deterministic hash
    kind*: ObligationKind          ## obligation category
    subject*: string               ## target symbol / relation
    assumptions*: string           ## canonical assumptions (string form)
    proposition*: IRExpr           ## typed semantic proposition (authoritative)
    predicate*: string             ## canonical string form = canonicalizePredicate(proposition)
    derivationRule*: string        ## rule that produced this obligation
    provenance*: string            ## reference to source / derivation trace
    assumptionOrigin*: AssumptionOrigin = aoUserDeclared
      ## Provenance class of the assumption channel (typeDerived /
      ## callerObligation / userDeclared). Part of C4 identity via
      ## computeObligationId — an assumption changing origin changes the
      ## obligation identity. Default preserves the legacy producer behavior:
      ## every obligation generated before the discriminator existed is
      ## aoUserDeclared.

# ---------------------------------------------------------------------------
# Canonical producer — typed proposition → derived string predicate + id
# ---------------------------------------------------------------------------

func makeVerificationObligation*(
  kind: ObligationKind,
  subject, assumptions, derivationRule, provenance: string,
  proposition: IRExpr,
  assumptionOrigin: AssumptionOrigin = aoUserDeclared
): VerificationObligation {.raises: [].} =
  ## Canonical producer: derives predicate from proposition and computes
  ## C4 identity.  predicate is ALWAYS canonicalizePredicate(proposition),
  ## ensuring I-1 (predicate = projection) and I-2 (id immutability).
  let pred = canonicalizePredicate(proposition)
  VerificationObligation(
    id: computeObligationId(subject, kind, assumptions, pred, derivationRule,
                            assumptionOrigin),
    kind: kind,
    subject: subject,
    assumptions: assumptions,
    proposition: proposition,
    predicate: pred,
    derivationRule: derivationRule,
    provenance: provenance,
    assumptionOrigin: assumptionOrigin
  )

# ---------------------------------------------------------------------------
# ObligationGenerationResult — 4-way variant (plan §1.1)
# ---------------------------------------------------------------------------

type
  ObligationGenerationResultKind* = enum
    ogrGenerated,
    ogrNoApplicableObligation,
    ogrUnsupported,
    ogrIllFormed

  ObligationGenerationResult* = object
    case kind*: ObligationGenerationResultKind
    of ogrGenerated:
      obligations*: LightNonEmptySeq[VerificationObligation]
        ## Generated obligations — always non-empty (len >= 1).
        ## The constructor makeGenerated enforces this invariant.
    of ogrNoApplicableObligation:
      provenance*: NoObligationProvenance
        ## Provenance explaining why no obligation applies.
        ## This is a "proven" classification — not an absence of analysis.
    of ogrUnsupported:
      unsupportedReason*: UnsupportedReason
        ## Semantic scope is out of the model (e.g. recursive heap).
        ## Backend failures must NOT use this variant — they use
        ## ProofTerminal.ptInconclusive via ObligationOutcome.
    of ogrIllFormed:
      illFormedReason*: IllFormedReason
        ## Semantic validation failure — mirrors semantic_validator layers.

# ---------------------------------------------------------------------------
# Constructors for each variant
# ---------------------------------------------------------------------------

func makeGenerated*(obligations: LightNonEmptySeq[VerificationObligation]):
    ObligationGenerationResult {.raises: [].} =
  ## Constructor that enforces non-empty invariant via doAssert + runtime check.
  doAssert obligations.len >= 1,
    "ObligationGenerationResult.ogrGenerated requires len >= 1 obligations"
  ObligationGenerationResult(kind: ogrGenerated, obligations: obligations)

func makeNoApplicable*(provenance: NoObligationProvenance):
    ObligationGenerationResult {.raises: [].} =
  ObligationGenerationResult(kind: ogrNoApplicableObligation, provenance: provenance)

func makeUnsupported*(reason: UnsupportedReason):
    ObligationGenerationResult {.raises: [].} =
  ObligationGenerationResult(kind: ogrUnsupported, unsupportedReason: reason)

func makeIllFormed*(reason: IllFormedReason):
    ObligationGenerationResult {.raises: [].} =
  ObligationGenerationResult(kind: ogrIllFormed, illFormedReason: reason)

# ---------------------------------------------------------------------------
# Obligation identity helpers
# ---------------------------------------------------------------------------

func computeId*(obl: VerificationObligation): string {.raises: [].} =
  ## Compute C4 identity for a single obligation using the canonical 6-tuple
  ## (plan 5-tuple + assumptionOrigin). Callers that recompute the tuple id
  ## from an obligation's fields MUST pass the obligation's own
  ## assumptionOrigin — the field-less recomputation silently assumes
  ## aoUserDeclared and diverges from obl.id for tagged assumptions.
  let assumptionsStr = obl.assumptions
  let predicateStr   = obl.predicate
  computeObligationId(obl.subject, obl.kind, assumptionsStr, predicateStr,
                      obl.derivationRule, obl.assumptionOrigin)

{.pop.}
