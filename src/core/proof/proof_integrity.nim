import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Unified deep-verification predicate with Set Membership (Phase 2 WS-A).
##
## `proof_integrity` is the unique deep-verification entry point that adds a
## Set Membership check (numerator gte denominator symbol coverage) on top of the
## 3-stage zero-trust logic in `certificate_verifier.nim`.
##
## Preservation of SSOT: the 3-stage verifier is injected via the `DeepVerifyFn`
## callback (DIP) — core never imports verification/. Its result is treated as
## authoritative (`dvcSuccess`); this module never duplicates the CAS fingerprint
## / kernel-empirical branch / status-whitelist logic.
##
## Degraded mode (documented): when `scope.kernelSymbols` is empty (lock missing
## or schema v1), Set Membership is skipped and the 3-stage result is returned as-is.

import std/json
import std/os
import core/types/certificate_types
import core/types/verification_tier
import core/trusted/axiom_pragmas
import core/trusted/evidence_calculus

type
  KernelScopeInfo* = object
    kernelSymbols*: seq[string]   # modulePath::funcName (lock v2/v3 kernel_symbols)
    kernelTotal*: int             # lock kernel_total (entire trusted kernel scope)
    vksTotal*: int     # lock vksTotal (proof-bearing; schema v3)
    kernelExemptSymbols*: seq[string]  # lock kernel_exempt_symbols (schema v3; proof-exempt)

  ## Deep-verification callback (DIP): the 3-stage zero-trust verifier is injected
  ## by the composition root (CLI layer) — core never imports verification/.
  ## Returns DeepVerificationCode so stage-4 Set Membership can compose with it.
  DeepVerifyFn* = proc(cert: JsonNode; certPath: string;
      entry: RuntimeAxiomEntry; projectRoot: string): DeepVerificationCode
      {.nimcall, raises: [].}

  ## VKD admission verdict — independent of the verification-layer DeepVerificationCode
  ## so admission semantics never couple to solver/verification result space.
  VkdAdmissionResult* = enum
    varAdmit             ## kernel ∧ ¬exempt ∧ isDeepVerified == dvcSuccess ∧ status == certGreen (→ VKD molecule)
    varReject            ## ordinary non-admissible state (no-cert / failure / incomplete)
    varScopeInconsistency  ## scope-contract violation — stronger than reject (e.g. provable ∧ obligations==∅)

  ## Explicit scope contract for cnaNoObligations classification. cnaNoObligations
  ## means "no safety/semantic obligation was derived by CHC", which is NOT
  ## automatically a scope inconsistency. Promotion to noObligationScopeMismatch
  ## requires an explicit `expectedObligation: true` contract on the proof-mode symbol.
  ## Defaults to `expectedObligation: false` → legitimate no-op (anti-theater §0.9:
  ## a CHC result alone must never overwrite scope policy).
  NoObligationClass* = enum
    noObligationLegitimate    ## expectedObligation := false — no unmet scope contract
    noObligationScopeMismatch ## expectedObligation := true but CHC derived zero obligations

proc classifyNoObligation*(expectedObligation: bool): NoObligationClass =
  if expectedObligation:
    noObligationScopeMismatch
  else:
    noObligationLegitimate

proc loadKernelScope*(lockPath: string; failClosed: bool = false): KernelScopeInfo {.raises: [CatchableError], axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Reads verification_scope.lock (schema v2/v3).
  ## When failClosed=false (default): returns empty scope on missing/corrupt lock
  ## (degraded mode). When failClosed=true: raises CatchableError on missing/corrupt
  ## or empty lock — the caller must supply a valid lock or handle the failure.
  ## Fail-closed invariant (I5): a corrupt or absent lock must not silently produce
  ## an empty scope that admits all symbols; it must be an explicit error path.
  result.kernelTotal = 0
  result.vksTotal = 0
  if not fileExists(lockPath):
    if failClosed:
      raise newException(CatchableError, "loadKernelScope fail-closed: lock file missing at '" & lockPath & "'")
    return result

  var node: JsonNode
  try:
    node = parseJson(readFile(lockPath))
  except CatchableError as e:
    if failClosed:
      raise newException(CatchableError, "loadKernelScope fail-closed: lock file unreadable/corrupt at '" & lockPath & "': " & e.msg)
    # Unreadable / corrupt lock -> degraded mode (empty scope)
    return result

  if node.isNil or node.kind != JObject:
    if failClosed:
      raise newException(CatchableError, "loadKernelScope fail-closed: lock file does not contain a JSON object at '" & lockPath & "'")
    return result
  result.kernelTotal = node.getOrDefault("kernel_total").getInt(0)
  result.vksTotal = node.getOrDefault("vksTotal").getInt(0)

  let symbols = node.getOrDefault("kernel_symbols")
  if symbols.isNil or symbols.kind != JArray:
    # Schema v1 (no kernel_symbols) -> empty scope -> degraded mode
    if failClosed:
      raise newException(CatchableError, "loadKernelScope fail-closed: lock file missing 'kernel_symbols' array at '" & lockPath & "'")
    return result
  for sym in symbols.elems:
    if sym.kind == JString and sym.getStr.len > 0:
      result.kernelSymbols.add(sym.getStr)
  let exempt = node.getOrDefault("kernel_exempt_symbols")
  if exempt != nil and exempt.kind == JArray:
    for sym in exempt.elems:
      if sym.kind == JString and sym.getStr.len > 0:
        result.kernelExemptSymbols.add(sym.getStr)
  # If kernelSymbols is empty after parsing a v2/v3 lock (all entries filtered or
  # empty strings), failClosed treats that as a corrupt/empty lock.
  if failClosed and result.kernelSymbols.len == 0:
    raise newException(CatchableError, "loadKernelScope fail-closed: lock file contains zero kernel_symbols at '" & lockPath & "'")

func symbolInKernelScope*(cert: JsonNode; scope: KernelScopeInfo): bool {.raises: [], axiomDecision.} =
  ## Builds `<modulePath>::<functionName>` and checks membership against
  ## scope.kernelSymbols. Returns false when either field is absent.
  if cert.isNil or cert.kind != JObject:
    return false
  let modulePath = cert.getOrDefault("modulePath").getStr("")
  let functionName = cert.getOrDefault("functionName").getStr("")
  if modulePath.len == 0 or functionName.len == 0:
    return false
  let key = modulePath & "::" & functionName
  for sym in scope.kernelSymbols:
    if sym == key:
      return true
  false

proc isDeepVerified*(cert: JsonNode; certPath: string;
    entry: RuntimeAxiomEntry; projectRoot: string;
    scope: KernelScopeInfo; verifier: DeepVerifyFn): DeepVerificationCode {.raises: [], axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Unified deep-verification predicate.
  ##
  ## Stages 1-3 (exactly mirror certificate_verifier.nim:10-45): CAS fingerprint,
  ## kernel/empirical branch, status whitelist — delegated to the injected
  ## `verifier` callback (DIP; see core/boundary/verification_interface.DeepVerifyFn).
  ##
  ## Stage 4 (NEW): Set Membership. For kernel certs, require
  ## `cert modulePath::functionName` to be a member of `scope.kernelSymbols`.
  ##   - If scope.kernelSymbols is non-empty (authoritative) and the symbol is NOT
  ##     in it -> `dvcNotInKernelScope`.
  ##   - If kernelSymbols is empty (lock unavailable/legacy) -> skip the check
  ##     (degraded mode) and return the 3-stage result unchanged.
  doAssert verifier != nil, "DeepVerifyFn callback must be wired (theater guard §0.9)"
  let base = verifier(cert, certPath, entry, projectRoot)
  if base != dvcSuccess:
    return base

  # Stage 4: Set Membership (kernel certs only, authoritative scope present).
  if entry.isKernel and scope.kernelSymbols.len > 0:
    if not symbolInKernelScope(cert, scope):
      return dvcNotInKernelScope

  base

proc isVkdAdmissible*(cert: JsonNode; entry: RuntimeAxiomEntry;
    scope: KernelScopeInfo; verifier: DeepVerifyFn): VkdAdmissionResult
    {.raises: [], axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## VKD admission SSOT — the single canonical predicate that answers whether a
  ## symbol contributes to the VKD molecule `|VKS ∩ certGreen|`.
  ##
  ## It composes the full `isDeepVerified` proof and:
  ##   - exempt kernel symbol (schema v3 kernel_exempt_symbols) → `scopeInconsistency`
  ##     (defense-in-depth; already excluded from candidate loops)
  ##   - `isDeepVerified == dvcSuccess` ∧ `status == certGreen` → `admit`
  ##   - otherwise → `reject`
  ##
  ## Scope-contract classification: a proof-mode (non-exempt) kernel symbol with
  ## `expectedObligation: true` that yields zero obligations in CHC is a scope
  ## inconsistency, NOT a legitimate no-op. Symbols with `expectedObligation: false`
  ## keep the default CHC no-op path, so we NEVER mechanically promote every
  ## cnaNoObligations (anti-theater §0.9).
  if entry.isKernel and scope.kernelExemptSymbols.len > 0:
    let modulePath = cert.getOrDefault("modulePath").getStr("")
    let functionName = cert.getOrDefault("functionName").getStr("")
    if modulePath.len > 0 and functionName.len > 0:
      let key = modulePath & "::" & functionName
      if key in scope.kernelExemptSymbols:
        return varScopeInconsistency
  if isDeepVerified(cert, "", entry, "", scope, verifier) == dvcSuccess:
    let ev = certificateEvidenceFromJson(cert)
    if admissibleEvidence(toEvidenceBundle(ev)):
      return varAdmit
  return varReject

{.pop.}
