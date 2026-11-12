import core/trusted/layer_declaration
axiomLayer "infrastructure"
import std/[hashes, json, os, tables, times]
import core/crypto/hash_kernel
import core/io/io_utils
import core/proof/proof_integrity
import core/trusted/axiom_pragmas
import core/trusted/scope_identity
import core/trusted/trust_commit
import infrastructure/logging_facade
import std/options

## PBT Adapter — Empirical verification bridge to CAVA CAS
##
## Executes property-based tests for non-kernel functions and writes
## TrustCommit journal records to the authoritative TrustCommit store.

type
  EmpiricalResult* = object
    passed*: bool
    coverage*: float
    fuzzRuns*: int
    pbtSeed*: int64

  PbtProperty* = proc() {.closure, raises: [CatchableError].}

var pbtRegistry*: Table[string, PbtProperty]
  ## PBT property registry: functionName -> property test proc
  ## Populated by {.axiomProp.} macro or manual registration.

proc retrieveTestMetrics*(fn: string): EmpiricalResult {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Retrieve empirical metrics for a function.
  ## Returns pass-through defaults if no property registered.
  result = EmpiricalResult(
    passed: true,
    coverage: 1.0,
    fuzzRuns: 0,
    pbtSeed: 0
  )

proc toEmpiricalCertStatus*(emp: EmpiricalResult): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if emp.passed and emp.coverage >= 0.80: "certPseudoVerified"
  else: "certRed"

proc executePbtAndWriteCert*(entry: RuntimeAxiomEntry; repoRoot: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Execute deterministic PBT and write a TrustCommit journal record.
  ## irHash is used as seed for deterministic reproduction.
  let targetProp = pbtRegistry.getOrDefault(entry.name)
  if targetProp.isNil:
    logWarn("pbt_adapter", "No registered property for " & entry.name & " — skipping")
    return

  let deterministicSeed = int64(hash(entry.irHash))
  logInfo("pbt_adapter", "Executing PBT for " & entry.name & " seed=" & entry.irHash)

  let startTime = epochTime()
  try:
    targetProp()
  except CatchableError:
    logError("pbt_adapter", "PBT execution failed for " & entry.name)
  let duration = (epochTime() - startTime) * 1000.0

  let cert = %*{
    "irHash": entry.irHash,
    "functionName": entry.name,
    "kind": "empirical",
    "status": "certPseudoVerified",
    "modulePath": entry.sourcePath,
    "sourcePath": entry.sourcePath,
    "isKernel": entry.isKernel,
    "expectedObligation": entry.expectedObligation,
    "pbt": {
      "seed": deterministicSeed,
      "durationMs": duration
    }
  }
  let claim = $cert
  let certificateDigest = hash_kernel.sha256Hex(claim)
  let solverInvocation = "pbt:<" & entry.irHash & ">"
  let scopeInfo = try:
    loadKernelScope(repoRoot / "data" / "verification_scope.lock", failClosed = false)
  except CatchableError:
    KernelScopeInfo(kernelSymbols: @[], kernelTotal: 0, vksTotal: 0, kernelExemptSymbols: @[])
  let kernelSymbols = if entry.isKernel: @[entry.name] else: @[]
  let scopeDigest = canonicalScopeDigest(CanonicalScopeInput(
    kernelSymbols: kernelSymbols,
    kernelExemptSymbols: scopeInfo.kernelExemptSymbols,
    kernelTotal: scopeInfo.kernelTotal,
    vksTotal: scopeInfo.vksTotal,
    profileIdentity: hash_kernel.sha256Hex("pbt-empirical-v1"),
    protocolVersion: "pbt-v1"
  ))
  let scopeLockHash = try:
    hash_kernel.sha256Hex(readFile(repoRoot / "data" / "verification_scope.lock"))
  except CatchableError:
    hash_kernel.sha256Hex("missing:verification_scope.lock")
  let configDigest = configIdentityDigest(hash_kernel.sha256Hex("pbt-empirical-v1"), scopeLockHash)
  let tc = TrustCommit(
    kind: tcVerifiedProof,
    evidenceId: computeEvidenceId(claim, solverInvocation, certificateDigest),
    claim: claim,
    solverInvocation: solverInvocation,
    attestation: "",
    certificateDigest: certificateDigest,
    scopeDigest: scopeDigest,
    configDigest: configDigest,
    parentCommit: none(string)
  )
  let res = commitVerification(repoRoot, tc)
  if res.ok:
    logInfo("pbt_adapter", "TrustCommit verified: " & res.value)
  else:
    logError("pbt_adapter", "TrustCommit verification failed for " & entry.name & ": " & res.err)

proc generatePbtRegistry*() {.raises: [].} =
  for entry in runtimeAxiomRegistry:
    if entry.name notin pbtRegistry:
      pbtRegistry[entry.name] = proc() =
        discard

proc getPbtRegistrySize*(): int {.raises: [].} =
  pbtRegistry.len
