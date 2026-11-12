import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/json
import core/trusted/fingerprint_generator

## v3 certificate identity — single source of truth shared by writer and verifier
## (START-D). Both construct a V3IdentityState — the writer from authoritative
## in-memory evidence, the verifier from a deep-verify-validated certificate JSON
## — and project it through the SAME canonical function. Because the field set and
## order live in exactly one place, the two sides cannot drift apart (e.g. a future
## "12 vs 13 field" mismatch is structurally impossible).

type V3IdentityState* = object
  schemaVersion*: string
  modulePath*: string
  functionName*: string
  sourceHash*: string
  irHash*: string
  leanProposition*: string
  solverStatus*: string
  status*: string
  winningStrategy*: string
  inputHash*: string
  solverInputDigest*: string
  solverResultDigest*: string
  ## S2 rev.4: canonical evidence identity binding. Empty on non-evidence paths
  ## (behavior-preserving); bound when a CanonicalLeanEvidence backs the cert.
  evidenceId*: string = ""
  ## Phase 1B strict completeness contract (cert/claim identity extension).
  ## These three fields participate in the identity ONLY when
  ## `completenessContract == "strict-v1"`: strict-contract certificates carry a
  ## 16-field identity, every legacy certificate keeps its 13-field identity and
  ## its stored identityDigest stays valid. `compV3Identity` branches on the
  ## marker, so stripping the marker from a strict cert (or adding it to a
  ## legacy cert) breaks the identity recompute — fail-closed both ways.
  completenessContract*: string = ""
  completenessEvidenceKey*: string = ""
  completenessBindingDigest*: string = ""

const canonicalV3FieldKeys*: array[13, string] = [
  "schemaVersion", "modulePath", "functionName", "sourceHash", "irHash",
  "leanProposition", "solverStatus", "status", "winningStrategy",
  "inputHash", "solverInputDigest", "solverResultDigest", "evidenceId"
]

const CompletenessContractStrictV1* = "strict-v1"

func compV3Identity*(state: V3IdentityState): string =
  ## Canonical v3 identity projection (order-sensitive, joined with "\n" → SHA-256).
  ## THE single identity formula for v3 certificates — writer and verifier both
  ## route through this so the identity semantics are structurally unified.
  ## Phase 1B: strict-contract certs (completenessContract == "strict-v1")
  ## extend the projection with the completeness binding anchor fields; every
  ## other state projects the original 13 fields unchanged.
  let base = @[
    state.schemaVersion, state.modulePath, state.functionName, state.sourceHash,
    state.irHash, state.leanProposition, state.solverStatus, state.status,
    state.winningStrategy, state.inputHash, state.solverInputDigest,
    state.solverResultDigest, state.evidenceId
  ]
  if state.completenessContract == CompletenessContractStrictV1:
    computeCertificateIdentity(base & @[
      state.completenessContract, state.completenessEvidenceKey,
      state.completenessBindingDigest
    ])
  else:
    computeCertificateIdentity(base)

func v3IdentityFromJson*(cert: JsonNode): string =
  ## Verifier-side projection: reads the identity fields from a certificate
  ## JSON and projects them through the same canonical function. Call AFTER
  ## isDeepVerified has validated the values (sourceHash vs current source,
  ## status vs evidence) so a tampered JSON value cannot be self-blessed.
  ## Phase 1B: the completeness binding fields are read conditionally — the
  ## projection branch is decided by the cert's own completenessContract
  ## marker, so legacy certs (no marker) keep the 13-field identity.
  compV3Identity(V3IdentityState(
    schemaVersion: cert.getOrDefault("schemaVersion").getStr(""),
    modulePath: cert.getOrDefault("modulePath").getStr(""),
    functionName: cert.getOrDefault("functionName").getStr(""),
    sourceHash: cert.getOrDefault("sourceHash").getStr(""),
    irHash: cert.getOrDefault("irHash").getStr(""),
    leanProposition: cert.getOrDefault("leanProposition").getStr(""),
    solverStatus: cert.getOrDefault("solverStatus").getStr(""),
    status: cert.getOrDefault("status").getStr(""),
    winningStrategy: cert.getOrDefault("winningStrategy").getStr(""),
    inputHash: cert.getOrDefault("inputHash").getStr(""),
    solverInputDigest: cert.getOrDefault("solverInputDigest").getStr(""),
    solverResultDigest: cert.getOrDefault("solverResultDigest").getStr(""),
    evidenceId: cert.getOrDefault("evidenceId").getStr(""),
    completenessContract: cert.getOrDefault("completenessContract").getStr(""),
    completenessEvidenceKey: cert.getOrDefault("completenessEvidenceKey").getStr(""),
    completenessBindingDigest: cert.getOrDefault("completenessBindingDigest").getStr("")
  ))
{.pop.}
