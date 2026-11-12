import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/json
import verification/canonical_json
import verification/certificate_identity

## ─────────────────────────────────────────────────────────────────────────
## Canonical Certificate Contract — single promotion boundary
##
## This module declares the ONE contract that converts "verification success"
## into a canonical provenance-bearing certificate artifact. Every producer on
## the product path (cert_writer candidate, promotion, report, golden slice)
## MUST route serialization through `canonicalCertificateBytes` and identity
## through `compV3Identity`/`v3IdentityFromJson`.
##
## Design (avoids circular identity):
##   • The identity is a PROJECTION of the semantic payload — the 12 identity
##     fields in `V3IdentityState` — and is computed from those fields alone
##     (certificate_identity.nim). It does NOT include `identityDigest` itself,
##     so identity is not self-referential.
##   • The persisted artifact's canonical bytes are produced by the single
##     RFC 8785 serializer in canonical_json.nim. There is exactly one byte
##     representation per semantic payload, so byte identity follows semantic
##     identity (C1–C3 of "Canonical Certificate Promotion Contract v1").
##   • Idempotent promotion (C4) compares by canonical identity, not by raw
##     persisted bytes: two files whose payloads are semantically identical
##     (`compV3Identity` equal) are the SAME certificate even if their on-disk
##     bytes differ (e.g. a legacy trailing newline).
##
## This module deliberately does NOT redefine the identity field set — that
## lives in exactly one place (certificate_identity.nim) to avoid duplicate
## semantic state (AGENTS.md §1). It only binds serialization + identity into
## one importable contract.
## ─────────────────────────────────────────────────────────────────────────

const CanonicalCertificateSchemaVersion* = "axiom.certificate.v3"

func canonicalCertificateBytes*(payload: JsonNode): seq[byte] {.raises: [].} =
  ## THE single canonical byte representation of a certificate payload.
  ## RFC 8785 canonical JSON, no trailing newline, no insignificant whitespace.
  canonicalJsonBytes(payload)

func canonicalCertificateString*(payload: JsonNode): string {.raises: [].} =
  ## THE single canonical string representation (UTF-8, no trailing newline).
  canonicalJsonString(payload)

func canonicalCertificateIdentity*(
  schemaVersion, modulePath, functionName, sourceHash, irHash, leanProposition,
  solverStatus, status, winningStrategy, inputHash, solverInputDigest,
  solverResultDigest: string
): string {.raises: [].} =
  ## Canonical certificate identity projection — routes through the single
  ## identity function (certificate_identity.nim). Used by idempotent promotion
  ## (C4) to compare semantic identity, and by golden/reproducibility checks.
  compV3Identity(V3IdentityState(
    schemaVersion: schemaVersion,
    modulePath: modulePath,
    functionName: functionName,
    sourceHash: sourceHash,
    irHash: irHash,
    leanProposition: leanProposition,
    solverStatus: solverStatus,
    status: status,
    winningStrategy: winningStrategy,
    inputHash: inputHash,
    solverInputDigest: solverInputDigest,
    solverResultDigest: solverResultDigest
  ))

func sameCanonicalIdentity*(a, b: JsonNode): bool {.raises: [].} =
  ## C4 idempotency predicate: two certificate JSON documents are the SAME
  ## canonical certificate iff their canonical identities are equal. Used by
  ## `promoteToCanonical` to accept a second execution whose persisted bytes
  ## differ only cosmetically (e.g. trailing newline / field formatting).
  ## Both payloads are re-validated by the promotion aggregate gate before this
  ## is consulted, so a tampered field cannot be self-blessed.
  v3IdentityFromJson(a) == v3IdentityFromJson(b)
{.pop.}
