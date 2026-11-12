import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## BaseRunIdentity — Base attestation identity layer (P8.3).
##
## Implements the identity/provenance separation contract:
##   - BaseSemanticIdentity is the SEMANTIC identity (what is being certified):
##     baseCommit, treeDigest, certificationMode, requiredWorkUnitCoverage.
##     Its identityDigest is computed over ONLY these semantic fields.
##   - BaseProvenance is PROVENANCE (how/when/where it ran):
##     runId, workflow, resultStatus, recordedAt, runnerId.
##     Provenance NEVER enters identityDigest.
##   - BaseRunIdentity aggregates both. isValid requires both
##     resultStatus == "success" AND requiredWorkUnitCoverage == "complete".
##
## Convention (execution-convention SSOT, identity.nim line ~15):
##   "All functions are pure and deterministic. Identity digests
##    exclude provenance (observedAt, timestamps, randomness)."
##   runId / timestamps / runner identifiers MUST NOT appear in identityDigest.
##
## Base-suitability rule (incremental_ci_contract.md §5.x):
##   BaseRunIdentity unavailable ⇒ V1 (incremental) forbidden ⇒ V2 (full certification).

import core/crypto/hash_kernel
import core/types/results
import std/[strutils, json]

# ---------------------------------------------------------------------------
# BaseSemanticIdentity — the semantic identity (what is being certified)
# ---------------------------------------------------------------------------

type
  BaseSemanticIdentity* = object
    baseCommit*: string
    treeDigest*: string
    certificationMode*: string
    requiredWorkUnitCoverage*: string
    identityDigest*: string

func computeBaseSemanticIdentityDigest*(
  baseCommit, treeDigest, certificationMode, requiredWorkUnitCoverage: string
): string {.raises: [].} =
  ## Deterministic identity digest over ONLY semantic fields.
  ## Reuses sha256Hex (core/crypto/hash_kernel) — same hash proc as
  ## canonical_cache.computeWorkUnitFingerprint and identity.nim.
  ## Provenance fields (runId, timestamps, runnerId) are NEVER included.
  sha256Hex(
    baseCommit & "|" &
    treeDigest & "|" &
    certificationMode & "|" &
    requiredWorkUnitCoverage
  )

func makeBaseSemanticIdentity*(
  baseCommit, treeDigest, certificationMode, requiredWorkUnitCoverage: string
): BaseSemanticIdentity {.raises: [].} =
  ## Construct a BaseSemanticIdentity with a reproducible identityDigest.
  BaseSemanticIdentity(
    baseCommit: baseCommit,
    treeDigest: treeDigest,
    certificationMode: certificationMode,
    requiredWorkUnitCoverage: requiredWorkUnitCoverage,
    identityDigest: computeBaseSemanticIdentityDigest(
      baseCommit, treeDigest, certificationMode, requiredWorkUnitCoverage
    )
  )

# ---------------------------------------------------------------------------
# BaseProvenance — provenance (how/when/where it ran)
# ---------------------------------------------------------------------------

type
  BaseProvenance* = object
    runId*: string
    workflow*: string
    resultStatus*: string
    recordedAt*: string
    runnerId*: string

func makeBaseProvenance*(
  runId, workflow, resultStatus, recordedAt, runnerId: string
): BaseProvenance {.raises: [].} =
  ## Construct a BaseProvenance. Provenance never influences identityDigest.
  BaseProvenance(
    runId: runId,
    workflow: workflow,
    resultStatus: resultStatus,
    recordedAt: recordedAt,
    runnerId: runnerId
  )

# ---------------------------------------------------------------------------
# BaseRunIdentity — aggregate + enforcement
# ---------------------------------------------------------------------------

type
  BaseRunIdentity* = object
    semanticIdentity*: BaseSemanticIdentity
    provenance*: BaseProvenance

func isValid*(base: BaseRunIdentity): bool {.raises: [].} =
  ## Base-suitability predicate: both semantic coverage AND run result
  ## must be satisfied. Otherwise V1 (incremental) is forbidden ⇒ V2.
  base.provenance.resultStatus == "success" and
    base.semanticIdentity.requiredWorkUnitCoverage == "complete"

func requireValidBaseRunIdentity*(
  base: BaseRunIdentity
): Result[void, string] {.raises: [].} =
  ## Enforcement point — callers (V1 path) MUST gate on this.
  ## Returns OK only when base.isValid; otherwise an error stating
  ## "BaseRunIdentity unavailable ⇒ V1 forbidden ⇒ V2" with the
  ## specific failing field.
  if base.provenance.resultStatus != "success":
    return err(
      "BaseRunIdentity unavailable ⇒ V1 forbidden ⇒ V2: " &
      "resultStatus=" & base.provenance.resultStatus
    )
  if base.semanticIdentity.requiredWorkUnitCoverage != "complete":
    return err(
      "BaseRunIdentity unavailable ⇒ V1 forbidden ⇒ V2: " &
      "requiredWorkUnitCoverage=" & base.semanticIdentity.requiredWorkUnitCoverage
    )
  Result[void, string](ok: true)
