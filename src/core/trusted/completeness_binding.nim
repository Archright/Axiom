import core/trusted/layer_declaration
import core/trusted/semantic_fact_types
import core/crypto/hash_kernel
import std/json
axiomLayer "trusted.core.completeness-binding"
{.push raises: [].}

## completeness_binding.nim — strict binding wrapper around CompletenessEvidence.
##
## The legacy 5-field CompletenessEvidence artifact (WP4-j.2 Phase D) carried no
## key equality, no re-hash and silent defaults on load: any bytes at the anchor
## path were accepted as the evidence for that anchor. This module defines the
## admission artifact that replaces it for canonical use:
##
##   - `schemaVersion` is a constant; loaders reject unknown versions.
##   - `evidenceKey` is the EXACT load anchor — a loader must refuse an artifact
##     whose stored key differs from the key it was asked for.
##   - `irDigest` records the materializer save-key flavor ③
##     (computeDeterministicCasKey(serializeIRFuncDef(preSynthesisFuncDef)));
##   - `irDigestCanonical` records flavor ② (computeIrDigest, canonicalized).
##     Both IR flavors are RECORDED for audit; the anchor of record is
##     `evidenceKey`. They are deliberately NOT cross-checked so the two-anchor
##     evidence search (pre-synthesis then current funcDef) stays expressible.
##   - `semanticProfileId` IS the single config identity
##     (SemanticProfileV1Hash). There is intentionally no separate configDigest:
##     a second config identity would fork the writer/verifier pair.
##   - `payload` embeds the 5 evidence fields BY VALUE (not a reference), so the
##     digest covers the evidence itself.
##   - `evidenceDigest` = sha256Hex over the canonical serialization of all
##     other fields (completenessBindingContentJson). A stored binding whose
##     recomputed digest differs is refused — no silent defaults, ever.

const CompletenessBindingSchemaVersion* = "completeness-binding-v1"

type
  CompletenessBinding* = object
    schemaVersion*: string          ## always CompletenessBindingSchemaVersion
    evidenceKey*: string            ## exact load anchor (artifact filename stem)
    irDigest*: string               ## flavor ③ materializer save key
    irDigestCanonical*: string      ## flavor ② canonicalized IR digest
    sourceIdentity*: string         ## subject source identity at capture time
    subjectModuleSha256*: string    ## sha256 of subject module bytes at capture
    semanticProfileId*: string      ## SemanticProfileV1Hash — single config identity
    toolchainFingerprint*: string   ## pinned toolchain fingerprint at capture
    payload*: CompletenessEvidence  ## embedded 5-field evidence (by value)
    evidenceDigest*: string         ## sha256 of canonical serialization of the rest

func completenessBindingContentJson*(b: CompletenessBinding): JsonNode {.raises: [].} =
  ## Canonical serialization of every field EXCEPT `evidenceDigest` — the exact
  ## preimage of `computeCompletenessBindingDigest`. Field order is fixed;
  ## strings are JSON-escaped, so no delimiter-collision ambiguity exists.
  result = newJObject()
  result["schemaVersion"] = %b.schemaVersion
  result["evidenceKey"] = %b.evidenceKey
  result["irDigest"] = %b.irDigest
  result["irDigestCanonical"] = %b.irDigestCanonical
  result["sourceIdentity"] = %b.sourceIdentity
  result["subjectModuleSha256"] = %b.subjectModuleSha256
  result["semanticProfileId"] = %b.semanticProfileId
  result["toolchainFingerprint"] = %b.toolchainFingerprint
  var payload = newJObject()
  payload["translationLossFree"] = %b.payload.translationLossFree
  payload["bindingUniverseComplete"] = %b.payload.bindingUniverseComplete
  payload["opaqueExpansionStatus"] = %b.payload.opaqueExpansionStatus
  payload["sourceBindingCount"] = %b.payload.sourceBindingCount
  payload["irBindingCount"] = %b.payload.irBindingCount
  result["payload"] = payload

func completenessBindingToJson*(b: CompletenessBinding): JsonNode {.raises: [].} =
  ## Full artifact JSON: content fields plus `evidenceDigest` last.
  result = completenessBindingContentJson(b)
  result["evidenceDigest"] = %b.evidenceDigest

func computeCompletenessBindingDigest*(b: CompletenessBinding): string {.raises: [].} =
  ## sha256Hex over the canonical serialization of all fields except
  ## `evidenceDigest`. Integrity only, not identity: recomputation on load
  ## detects any unaccompanied mutation of the stored artifact.
  sha256Hex($completenessBindingContentJson(b))

func makeCompletenessBinding*(evidenceKey, irDigest, irDigestCanonical,
    sourceIdentity, subjectModuleSha256, semanticProfileId,
    toolchainFingerprint: string; payload: CompletenessEvidence): CompletenessBinding {.
    raises: [].} =
  ## Construct a binding with `schemaVersion` pinned to the constant and
  ## `evidenceDigest` computed over the given content. The only sanctioned way
  ## to produce a savable binding.
  result = CompletenessBinding(
    schemaVersion: CompletenessBindingSchemaVersion,
    evidenceKey: evidenceKey,
    irDigest: irDigest,
    irDigestCanonical: irDigestCanonical,
    sourceIdentity: sourceIdentity,
    subjectModuleSha256: subjectModuleSha256,
    semanticProfileId: semanticProfileId,
    toolchainFingerprint: toolchainFingerprint,
    payload: payload,
    evidenceDigest: "")
  result.evidenceDigest = computeCompletenessBindingDigest(result)

# ---------------------------------------------------------------------------
# CompletenessBindingRef — the authenticated strict evidence identity
# ---------------------------------------------------------------------------
## What a strict-first reader carries out of a successful
## `loadCompletenessBinding`: the three values an evidence envelope (CLE) and
## the certificate writer need to name and re-verify the binding later.
##
##   - `evidenceKey` — the exact load anchor the binding was found under
##     ("" marks the LEGACY representation: no strict binding exists and the
##     record digest came from a legacy 5-field artifact).
##   - `evidenceDigest` — the strict `CompletenessBinding.evidenceDigest`
##     (sha256 over the binding content). Recomputable by any reader that can
##     load the binding artifact; this is the authenticated identity.
##   - `payloadDigest` — sha256 over `evidenceToJson(payload)`, the LEGACY
##     5-field serialization. This — NOT the strict evidenceDigest — is the
##     value bound into `ObligationSubjectBinding.completenessRecordDigest`,
##     so the bound-obligation representation is byte-compatible across the
##     legacy and strict generations.

type CompletenessBindingRef* = object
  evidenceKey*: string          ## strict load anchor; "" = legacy-only record
  evidenceDigest*: string       ## strict binding evidenceDigest
  payloadDigest*: string        ## sha256 of the legacy 5-field payload serialization

func composeCompletenessSourceIdentity*(subjectGitRef, subjectTreeMerkleRoot,
    subjectModuleSha256: string): string {.raises: [].} =
  ## The canonical `sourceIdentity` composite recorded in a
  ## CompletenessBinding and recomputed by its reader — the single definition
  ## both sides share (producer sites and `measureCompletenessRecordDigest`
  ## alike call this; no site composes the string by hand). Versioned
  ## domain-separated sha256 over the measured subject git ref, the subject
  ## tree merkle root and the subject module digest. Any unmeasurable
  ## component produces a composite that the capturing side refuses to save
  ## and the loading side cannot match — never a downgraded identity.
  sha256Hex("completeness-source-identity-v1|" & subjectGitRef & "|" &
    subjectTreeMerkleRoot & "|" & subjectModuleSha256)

{.pop.}
