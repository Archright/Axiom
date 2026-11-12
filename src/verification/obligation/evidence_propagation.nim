import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Evidence Propagation Consistency — Phase C P0 pure verification.
##
## Validates that the observed axiom set flows end-to-end from the Lean
## kernel receipt through KAA CanonicalKaa.observedAxiomSet and
## CanonicalLeanEvidence to the certificate's axiomsUsed field without
## divergence.  All comparisons use canonical form (lexical sort + dedupe)
## so order differences never produce false negatives.
##
## Fail-closed: any inconsistency → false.  No exception swallowing, no
## always-pass stub logic.  Inconsistencies are real and must be audited.

import std/[algorithm, strutils]

# ---------------------------------------------------------------------------
# Canonicalization — mirrors KAA canonicalObservationSet (kernel_acceptance_authority.nim:62)
# ---------------------------------------------------------------------------
## The same sort+dedupe logic applied at the KAA boundary.  Using the
## identical algorithm here guarantees that two sets with the same
## semantic content produce the same canonical form regardless of
## whether they arrive via the receipt probe, the KAA accessor, or the
## certificate JSON field.

func canonicalizeObservedSet*(items: seq[string]): seq[string] {.raises: [].} =
  if items.len == 0:
    return @[]
  var sorted = items
  sorted.sort()
  result = @[sorted[0]]
  for i in 1 ..< sorted.len:
    if sorted[i] != sorted[i - 1]:
      result.add(sorted[i])

# ---------------------------------------------------------------------------
# Consistency check
# ---------------------------------------------------------------------------
## Returns true iff ALL of the following hold:
##
## 1. Canonical equivalence: receiptObserved, kaaObserved, and
##    certObserved all normalize to the same canonical sequence.
##    This catches re-derivation, reordering, or dedupe mismatches at
##    any point in the propagation chain.
##
## 2. KernelAccepted ↔ HasKaa coherence: when the Lean kernel
##    accepted the artifact (kernelAccepted==true), a genuine KAA
##    must exist (hasKaa==true).  A receipt from canonicalLeanKernelCheck
##    that exited 0 but failed to produce a KAA (malformed receipt,
##    missing structural fields) is a fail-closed inconsistency — the
##    acceptance event is recorded but the authority attestation is
##    missing, meaning the evidence chain is broken.
##
##    Conversely, hasKaa==true implies kernelAccepted==true: a KAA
##    can only be created from a receipt produced by a successful
##    canonical Lean invocation (bindReceipt rejects receipts from
##    non-canonical or failed executions).  If hasKaa==true but
##    kernelAccepted==false, the KAA was fabricated or the receipt
##    was tampered with.
##
## 3. Empty-set consistency: when all three observed sets are empty,
##    this is legitimate (the Lean kernel accepted a theorem with no
##    axioms, e.g. `theorem triv : True := trivial`).  The function
##    returns true in this case — an empty observed set is a valid
##    observation, not a contradiction.  The deep-verification sorry
##    gate (certificate_verifier.nim:89-105) handles empty axiomsUsed
##    as dvcNotCurrent (stale cert), not as a genuine integrity fault.

func evidencePropagationConsistent*(
  receiptObserved: seq[string];
  kaaObserved: seq[string];
  certObserved: seq[string];
  kernelAccepted: bool;
  hasKaa: bool
): bool {.raises: [].} =
  # --- Coherence guard: kernelAccepted and hasKaa must agree ---
  # kernelAccepted==true requires hasKaa==true (the acceptance event
  # must have produced an authority attestation).
  # hasKaa==true requires kernelAccepted==true (a KAA cannot exist
  # without a genuine kernel acceptance receipt).
  if kernelAccepted != hasKaa:
    return false

  # --- Canonical equivalence of all three observed sets ---
  let rCanon = canonicalizeObservedSet(receiptObserved)
  let kCanon = canonicalizeObservedSet(kaaObserved)
  let cCanon = canonicalizeObservedSet(certObserved)

  if rCanon.len != kCanon.len or rCanon.len != cCanon.len:
    return false

  for i in 0 ..< rCanon.len:
    if rCanon[i] != kCanon[i] or rCanon[i] != cCanon[i]:
      return false

  true

{.pop.}